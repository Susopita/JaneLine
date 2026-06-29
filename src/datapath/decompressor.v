// =============================================================================
// decompressor.v  –  Descompresor RVC (RISC-V Compressed Extension)
//
// Entregable 2: Traduce instrucciones de 16 bits (Extensión C) a sus
// equivalentes de 32 bits en RV32I.
//
// ┌─────────────────────────────────────────────────────────────────────┐
// │  INSTRUCCIONES SOPORTADAS (10)                                     │
// │                                                                     │
// │  Cuadrante 1 (op = 2'b01):                                         │
// │    1. c.addi   rd, imm       → addi rd, rd, imm       (CI-type)    │
// │    2. c.lui    rd, nzimm     → lui  rd, nzimm          (CI-type)    │
// │    3. c.srli   rd', shamt    → srli rd', rd', shamt    (CB-type)    │
// │    4. c.srai   rd', shamt    → srai rd', rd', shamt    (CB-type)    │
// │    5. c.sub    rd', rs2'     → sub  rd', rd', rs2'     (CA-type)    │
// │    6. c.xor    rd', rs2'     → xor  rd', rd', rs2'     (CA-type)    │
// │    7. c.or     rd', rs2'     → or   rd', rd', rs2'     (CA-type)    │
// │    8. c.and    rd', rs2'     → and  rd', rd', rs2'     (CA-type)    │
// │                                                                     │
// │  Cuadrante 2 (op = 2'b10):                                         │
// │    9. c.slli   rd, shamt     → slli rd, rd, shamt      (CI-type)    │
// │   10. c.add    rd, rs2       → add  rd, rd, rs2        (CR-type)    │
// └─────────────────────────────────────────────────────────────────────┘
//
// Convención de registros comprimidos:
//   - Los formatos CA/CB usan registros de 3 bits (instr[9:7] e instr[4:2])
//     que mapean al rango x8–x15: reg_completo = {2'b01, reg_3bit}
//   - Los formatos CI/CR usan registros de 5 bits (instr[11:7], instr[6:2])
//     que mapean directamente a x0–x31.
//
// Instrucciones NO soportadas en este entregable:
//   - Loads/Stores  : c.lw, c.sw, c.lwsp, c.swsp
//   - Branches/Jumps: c.beqz, c.bnez, c.j, c.jal, c.jr, c.jalr
//   - Otros         : c.mv, c.andi, c.addi16sp, c.addi4spn
//   → Cualquier instrucción no reconocida produce un NOP (addi x0, x0, 0).
// =============================================================================
module decompressor (
    input  [15:0] instr16,      // Instrucción comprimida de 16 bits
    output [31:0] instr32,      // Instrucción expandida de 32 bits
    output        is_compressed  // 1 = se decodificó exitosamente una instr. comprimida
);

  // ---------------------------------------------------------------------------
  // Campos comunes extraídos de la instrucción de 16 bits
  // ---------------------------------------------------------------------------
  wire [1:0]  op     = instr16[1:0];     // Cuadrante (00, 01, 10)
  wire [2:0]  funct3 = instr16[15:13];   // Sub-operación dentro del cuadrante
  wire [3:0]  funct4 = instr16[15:12];   // Para c.add (Q2, funct3=100, bit12=1)
  wire [1:0]  funct2 = instr16[6:5];     // Sub-sub-op para CA-type (sub/xor/or/and)

  // ---------------------------------------------------------------------------
  // Mapeo de registros
  // ---------------------------------------------------------------------------
  // Registros COMPLETOS (5 bits) – usados por CI-type y CR-type
  wire [4:0]  rd  = instr16[11:7];   // Registro destino / fuente 1 (rd = rs1)
  wire [4:0]  rs2 = instr16[6:2];    // Registro fuente 2

  // Registros COMPRIMIDOS (3 bits → 5 bits) – usados por CA-type y CB-type
  //   Bits [9:7] → rd'/rs1' (registros x8-x15)
  //   Bits [4:2] → rs2'     (registros x8-x15)
  wire [4:0]  rd_c  = {2'b01, instr16[9:7]};   // rd' / rs1'
  wire [4:0]  rs2_c = {2'b01, instr16[4:2]};   // rs2'

  // ---------------------------------------------------------------------------
  // Reconstrucción de inmediatos
  // ---------------------------------------------------------------------------
  // c.addi: inmediato con signo de 6 bits → extensión a 12 bits
  //   Bits: [12|6:2] → imm[5|4:0], con extensión de signo desde bit 5
  wire [11:0] imm_addi = {{6{instr16[12]}}, instr16[12], instr16[6:2]};

  // c.lui: inmediato con signo de 6 bits → extensión a 20 bits
  //   Bits: [12|6:2] → nzimm[17|16:12], con extensión de signo desde bit 17
  wire [19:0] imm_lui = {{14{instr16[12]}}, instr16[12], instr16[6:2]};

  // c.slli/c.srli/c.srai: shift amount (sin signo, 5 bits)
  //   En RV32C, el bit instr16[12] (shamt[5]) DEBE ser 0
  wire [4:0]  shamt = instr16[6:2];

  // ---------------------------------------------------------------------------
  // Lógica de decodificación combinacional
  // ---------------------------------------------------------------------------
  reg [31:0] dec_instr;
  reg        dec_valid;

  always @(*) begin
    // Default: NOP (addi x0, x0, 0) y marcado como no válido
    dec_instr = 32'h00000013;
    dec_valid = 1'b0;

    case (op)
      // =====================================================================
      // CUADRANTE 1 (op = 2'b01)
      // Contiene: c.addi, c.lui, c.srli, c.srai, c.sub, c.xor, c.or, c.and
      // =====================================================================
      2'b01: begin
        case (funct3)
          // -----------------------------------------------------------------
          // c.addi rd, nzimm
          //   Codificación: [15:13]=000  [12]=imm[5]  [11:7]=rd  [6:2]=imm[4:0]  [1:0]=01
          //   Expansión:    addi rd, rd, sext(imm)
          //   Formato 32b:  {imm[11:0], rs1, 3'b000, rd, 7'b0010011}
          //   Nota: c.nop es c.addi x0, 0 (caso especial, produce NOP natural)
          // -----------------------------------------------------------------
          3'b000: begin
            dec_instr = {imm_addi, rd, 3'b000, rd, 7'b0010011};
            dec_valid = 1'b1;
          end

          // -----------------------------------------------------------------
          // c.lui rd, nzimm
          //   Codificación: [15:13]=011  [12]=nzimm[17]  [11:7]=rd  [6:2]=nzimm[16:12]  [1:0]=01
          //   Expansión:    lui rd, sext(nzimm)
          //   Formato 32b:  {imm[19:0], rd, 7'b0110111}
          //   Restricción:  rd ≠ x0, rd ≠ x2 (x2 = sp, eso sería c.addi16sp)
          // -----------------------------------------------------------------
          3'b011: begin
            if (rd != 5'd0 && rd != 5'd2) begin
              dec_instr = {imm_lui, rd, 7'b0110111};
              dec_valid = 1'b1;
            end
          end

          // -----------------------------------------------------------------
          // funct3 = 100: Shifts y operaciones registro-registro (CA-format)
          //   Selección por instr16[11:10]:
          //     2'b00 → c.srli    2'b01 → c.srai
          //     2'b11 → sub-ops seleccionadas por instr16[6:5] (funct2)
          // -----------------------------------------------------------------
          3'b100: begin
            case (instr16[11:10])
              // -------------------------------------------------------------
              // c.srli rd', shamt
              //   Codificación: [15:13]=100  [12]=0  [11:10]=00  [9:7]=rd'  [6:2]=shamt  [1:0]=01
              //   Expansión:    srli rd', rd', shamt
              //   Formato 32b:  {7'b0000000, shamt, rs1, 3'b101, rd, 7'b0010011}
              // -------------------------------------------------------------
              2'b00: begin
                if (instr16[12] == 1'b0) begin  // RV32C: shamt[5] debe ser 0
                  dec_instr = {7'b0000000, shamt, rd_c, 3'b101, rd_c, 7'b0010011};
                  dec_valid = 1'b1;
                end
              end

              // -------------------------------------------------------------
              // c.srai rd', shamt
              //   Codificación: [15:13]=100  [12]=0  [11:10]=01  [9:7]=rd'  [6:2]=shamt  [1:0]=01
              //   Expansión:    srai rd', rd', shamt
              //   Formato 32b:  {7'b0100000, shamt, rs1, 3'b101, rd, 7'b0010011}
              //   Nota: funct7=0100000 distingue srai de srli
              // -------------------------------------------------------------
              2'b01: begin
                if (instr16[12] == 1'b0) begin  // RV32C: shamt[5] debe ser 0
                  dec_instr = {7'b0100000, shamt, rd_c, 3'b101, rd_c, 7'b0010011};
                  dec_valid = 1'b1;
                end
              end

              // -------------------------------------------------------------
              // Operaciones registro-registro (CA-format)
              //   Codificación común: [15:10]=100011  [9:7]=rd'/rs1'  [6:5]=funct2  [4:2]=rs2'  [1:0]=01
              //   funct2 selecciona la operación:
              //     00 → c.sub    01 → c.xor    10 → c.or    11 → c.and
              // -------------------------------------------------------------
              2'b11: begin
                case (funct2)
                  // c.sub rd', rs2' → sub rd', rd', rs2'
                  //   Formato 32b: {7'b0100000, rs2, rs1, 3'b000, rd, 7'b0110011}
                  2'b00: begin
                    dec_instr = {7'b0100000, rs2_c, rd_c, 3'b000, rd_c, 7'b0110011};
                    dec_valid = 1'b1;
                  end

                  // c.xor rd', rs2' → xor rd', rd', rs2'
                  //   Formato 32b: {7'b0000000, rs2, rs1, 3'b100, rd, 7'b0110011}
                  2'b01: begin
                    dec_instr = {7'b0000000, rs2_c, rd_c, 3'b100, rd_c, 7'b0110011};
                    dec_valid = 1'b1;
                  end

                  // c.or rd', rs2' → or rd', rd', rs2'
                  //   Formato 32b: {7'b0000000, rs2, rs1, 3'b110, rd, 7'b0110011}
                  2'b10: begin
                    dec_instr = {7'b0000000, rs2_c, rd_c, 3'b110, rd_c, 7'b0110011};
                    dec_valid = 1'b1;
                  end

                  // c.and rd', rs2' → and rd', rd', rs2'
                  //   Formato 32b: {7'b0000000, rs2, rs1, 3'b111, rd, 7'b0110011}
                  2'b11: begin
                    dec_instr = {7'b0000000, rs2_c, rd_c, 3'b111, rd_c, 7'b0110011};
                    dec_valid = 1'b1;
                  end
                endcase
              end

              // 2'b10 = c.andi (NO soportada en E2) → NOP
              default: begin
                dec_instr = 32'h00000013;
                dec_valid = 1'b0;
              end
            endcase
          end

          // funct3 no reconocido en Q1 → NOP
          default: begin
            dec_instr = 32'h00000013;
            dec_valid = 1'b0;
          end
        endcase
      end

      // =====================================================================
      // CUADRANTE 2 (op = 2'b10)
      // Contiene: c.slli, c.add
      // =====================================================================
      2'b10: begin
        case (funct3)
          // -----------------------------------------------------------------
          // c.slli rd, shamt
          //   Codificación: [15:13]=000  [12]=0  [11:7]=rd  [6:2]=shamt  [1:0]=10
          //   Expansión:    slli rd, rd, shamt
          //   Formato 32b:  {7'b0000000, shamt, rs1, 3'b001, rd, 7'b0010011}
          //   Restricción:  rd ≠ x0 (HINT si rd=0, lo ignoramos como NOP)
          // -----------------------------------------------------------------
          3'b000: begin
            if (instr16[12] == 1'b0) begin  // RV32C: shamt[5] debe ser 0
              dec_instr = {7'b0000000, shamt, rd, 3'b001, rd, 7'b0010011};
              dec_valid = 1'b1;
            end
          end

          // -----------------------------------------------------------------
          // c.add rd, rs2
          //   Codificación: [15:12]=1001  [11:7]=rd  [6:2]=rs2  [1:0]=10
          //   Expansión:    add rd, rd, rs2
          //   Formato 32b:  {7'b0000000, rs2, rs1, 3'b000, rd, 7'b0110011}
          //   Restricción:  rd ≠ x0, rs2 ≠ x0
          //   Nota: bit12=1 distingue c.add (funct4=1001) de c.mv (funct4=1000)
          //         c.mv NO está soportada en este entregable.
          // -----------------------------------------------------------------
          3'b100: begin
            if (funct4 == 4'b1001 && rd != 5'd0 && rs2 != 5'd0) begin
              dec_instr = {7'b0000000, rs2, rd, 3'b000, rd, 7'b0110011};
              dec_valid = 1'b1;
            end
          end

          // funct3 no reconocido en Q2 → NOP
          default: begin
            dec_instr = 32'h00000013;
            dec_valid = 1'b0;
          end
        endcase
      end

      // =====================================================================
      // CUADRANTE 0 (op = 2'b00) y CUADRANTE 3 (op = 2'b11)
      // Q0: c.lw, c.sw (NO soportadas en E2)
      // Q3: Instrucciones de 32 bits (nunca llegan aquí)
      // =====================================================================
      default: begin
        dec_instr = 32'h00000013;
        dec_valid = 1'b0;
      end
    endcase
  end

  assign instr32       = dec_instr;
  assign is_compressed = dec_valid;

endmodule
