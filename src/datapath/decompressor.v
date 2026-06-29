// =============================================================================
// decompressor.v  –  Descompresor RVC (RISC-V Compressed Extension)
//
// Entregable 3 (Parte 2): Traduce instrucciones de 16 bits (Extensión C) a
// sus equivalentes de 32 bits en RV32I.
//
// ┌─────────────────────────────────────────────────────────────────────────┐
// │  INSTRUCCIONES SOPORTADAS (20 total)                                   │
// │                                                                         │
// │  Cuadrante 0 (op = 2'b00):  [NUEVO E3]                                 │
// │    1. c.lw    rd', off(rs1') → lw  rd', off(rs1')    (CL-type)         │
// │    2. c.sw    rs2', off(rs1')→ sw  rs2', off(rs1')   (CS-type)         │
// │                                                                         │
// │  Cuadrante 1 (op = 2'b01):                                             │
// │    3. c.addi   rd, imm       → addi rd, rd, imm       (CI-type)    E2  │
// │    4. c.jal    offset        → jal  x1, offset        (CJ-type) [NUEVO]│
// │    5. c.lui    rd, nzimm     → lui  rd, nzimm         (CI-type)    E2  │
// │    6. c.srli   rd', shamt    → srli rd', rd', shamt   (CB-type)    E2  │
// │    7. c.srai   rd', shamt    → srai rd', rd', shamt   (CB-type)    E2  │
// │    8. c.sub    rd', rs2'     → sub  rd', rd', rs2'    (CA-type)    E2  │
// │    9. c.xor    rd', rs2'     → xor  rd', rd', rs2'    (CA-type)    E2  │
// │   10. c.or     rd', rs2'     → or   rd', rd', rs2'    (CA-type)    E2  │
// │   11. c.and    rd', rs2'     → and  rd', rd', rs2'    (CA-type)    E2  │
// │   12. c.j      offset        → jal  x0, offset        (CJ-type) [NUEVO]│
// │   13. c.beqz   rs1', offset  → beq  rs1', x0, offset  (CB-type) [NUEVO]│
// │   14. c.bnez   rs1', offset  → bne  rs1', x0, offset  (CB-type) [NUEVO]│
// │                                                                         │
// │  Cuadrante 2 (op = 2'b10):                                             │
// │   15. c.slli   rd, shamt     → slli rd, rd, shamt     (CI-type)    E2  │
// │   16. c.lwsp   rd, off(sp)   → lw   rd, off(x2)       (CI-type) [NUEVO]│
// │   17. c.jr     rs1           → jalr x0, rs1, 0        (CR-type) [NUEVO]│
// │   18. c.jalr   rs1           → jalr x1, rs1, 0        (CR-type) [NUEVO]│
// │   19. c.add    rd, rs2       → add  rd, rd, rs2       (CR-type)    E2  │
// │   20. c.swsp   rs2, off(sp)  → sw   rs2, off(x2)      (CSS-type)[NUEVO]│
// └─────────────────────────────────────────────────────────────────────────┘
//
// Convención de registros comprimidos:
//   - Formatos CL/CS/CA/CB: registros de 3 bits que mapean a x8–x15:
//       reg_completo = {2'b01, reg_3bit}
//   - Formatos CI/CR/CJ/CSS: registros de 5 bits directos (x0–x31).
//
// Inmediatos por formato:
//   CL/CS : off[5:3]=instr[12:10], off[2]=instr[6], off[6]=instr[5]  (×4)
//   CI lwsp: off[5]=instr[12], off[4:2]=instr[6:4], off[7:6]=instr[3:2] (×4)
//   CSS   : off[5:2]=instr[12:9], off[7:6]=instr[8:7]                  (×4)
//   CB    : sext({instr[12],instr[6:5],instr[2],instr[11:10],instr[4:3],0})
//   CJ    : sext 12-bit scrambled (ver código)
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
  wire [3:0]  funct4 = instr16[15:12];   // Para c.jr/c.jalr/c.add (bit12 distingue)
  wire [1:0]  funct2 = instr16[6:5];     // Sub-sub-op para CA-type (sub/xor/or/and)

  // ---------------------------------------------------------------------------
  // Mapeo de registros
  // ---------------------------------------------------------------------------
  // Registros COMPLETOS (5 bits) – CI-type, CR-type, CSS-type, CJ-type
  wire [4:0]  rd  = instr16[11:7];   // Registro destino / fuente 1 (rd = rs1)
  wire [4:0]  rs2 = instr16[6:2];    // Registro fuente 2

  // Registros COMPRIMIDOS (3 bits → 5 bits) – CL/CS/CA/CB-type
  //   Bits [9:7] → rd'/rs1' (registros x8-x15)
  //   Bits [4:2] → rs2'     (registros x8-x15)
  wire [4:0]  rd_c  = {2'b01, instr16[9:7]};   // rd' / rs1'
  wire [4:0]  rs2_c = {2'b01, instr16[4:2]};   // rs2'

  // ---------------------------------------------------------------------------
  // Reconstrucción de inmediatos — E2 (existentes)
  // ---------------------------------------------------------------------------
  // c.addi: inmediato con signo de 6 bits → extensión a 12 bits
  //   Bits: [12|6:2] → imm[5|4:0], extensión de signo desde bit 5
  wire [11:0] imm_addi = {{6{instr16[12]}}, instr16[12], instr16[6:2]};

  // c.lui: inmediato con signo de 6 bits → extensión a 20 bits
  //   Bits: [12|6:2] → nzimm[17|16:12], extensión de signo desde bit 17
  wire [19:0] imm_lui = {{14{instr16[12]}}, instr16[12], instr16[6:2]};

  // c.slli/c.srli/c.srai: shift amount (sin signo, 5 bits)
  wire [4:0]  shamt = instr16[6:2];

  // ---------------------------------------------------------------------------
  // Reconstrucción de inmediatos — E3 (nuevos)
  // ---------------------------------------------------------------------------

  // CL/CS-type: c.lw y c.sw
  //   offset[5:3] = instr16[12:10]
  //   offset[2]   = instr16[6]
  //   offset[6]   = instr16[5]
  //   offset[1:0] = 2'b00  (alineación a word)
  //   Resultado: 7 bits unsigned, [6:0]
  wire [11:0] imm_lw;
  assign imm_lw = {5'b0, instr16[5], instr16[12:10], instr16[6], 2'b00};

  // Para c.sw S-type (necesitamos separar en [11:5] y [4:0]):
  // imm_lw sirve igual porque es el mismo offset

  // CI-type: c.lwsp
  //   offset[5]   = instr16[12]
  //   offset[4:2] = instr16[6:4]
  //   offset[7:6] = instr16[3:2]
  //   offset[1:0] = 2'b00
  //   Resultado: 8 bits unsigned (0..252), extendido a 12 bits
  wire [11:0] imm_lwsp;
  assign imm_lwsp = {4'b0, instr16[3:2], instr16[12], instr16[6:4], 2'b00};

  // CSS-type: c.swsp
  //   offset[5:2] = instr16[12:9]
  //   offset[7:6] = instr16[8:7]
  //   offset[1:0] = 2'b00
  //   Resultado: 8 bits unsigned (0..252)
  wire [11:0] imm_swsp;
  assign imm_swsp = {4'b0, instr16[8:7], instr16[12:9], 2'b00};

  // CB-type: c.beqz / c.bnez
  //   Inmediato con signo de 9 bits (múltiplo de 2), scrambled:
  //     imm[8]   = instr16[12]
  //     imm[4:3] = instr16[11:10]
  //     imm[7:6] = instr16[6:5]
  //     imm[2:1] = instr16[4:3]
  //     imm[5]   = instr16[2]
  //     imm[0]   = 1'b0  (siempre)
  //
  //   Para el formato B-type de 32 bits necesitamos:
  //     instr32[31]   = imm[12] (signo extendido = imm[8])
  //     instr32[30:25]= imm[10:5]
  //     instr32[11:8] = imm[4:1]
  //     instr32[7]    = imm[11]  (= imm[4:3] bit alto → imm[4:3][1] = instr16[11])
  //
  //   Reconstrucción del inmediato B-type [12:1] directamente:
  //     imm_cb[12]   = instr16[12]  (signo)
  //     imm_cb[11]   = instr16[11]  (bit 11 del B-type)  ← ¡ojo! en CB es imm[4:3][1]
  //     imm_cb[10]   = instr16[10]
  //     imm_cb[9]    = instr16[6]
  //     imm_cb[8]    = instr16[5]
  //     imm_cb[7]    = instr16[2]   (= imm[5] en el offset)
  //     imm_cb[6]    = instr16[12]  ← NO. Usemos el enfoque directo:
  //
  //   El offset CB de 9 bits con signo es:
  //     { instr16[12], instr16[6:5], instr16[2], instr16[11:10], instr16[4:3], 1'b0 }
  //     = { sext, imm[7:6], imm[5], imm[4:3], imm[2:1], 0 }
  //
  //   Extendido con signo a 13 bits para mapear a B-type 32b:
  wire [12:0] imm_cb;
  assign imm_cb = {{4{instr16[12]}},
                    instr16[12],    // imm[8]  → posición 8
                    instr16[6:5],   // imm[7:6]
                    instr16[2],     // imm[5]
                    instr16[11:10], // imm[4:3]
                    instr16[4:3],   // imm[2:1]
                    1'b0};          // imm[0]

  // CJ-type: c.j / c.jal
  //   Inmediato con signo de 12 bits (múltiplo de 2), muy scrambled:
  //     imm[11]  = instr16[12]  ← signo / bit más significativo
  //     imm[4]   = instr16[11]
  //     imm[9:8] = instr16[10:9]
  //     imm[10]  = instr16[8]
  //     imm[6]   = instr16[7]
  //     imm[7]   = instr16[6]
  //     imm[3:1] = instr16[5:3]
  //     imm[5]   = instr16[2]
  //     imm[0]   = 1'b0
  //
  //   Reconstruido como vector sign-extended de 21 bits [20:0]:
  //     [20:12] = extensión de signo (9 bits, = {9{imm[11]}} = {9{instr16[12]}})
  //     [11]    = imm[11] = instr16[12]   ← CRÍTICO: debe ser explícito
  //     [10]    = imm[10] = instr16[8]
  //     [9:8]   = imm[9:8] = instr16[10:9]
  //     [7]     = imm[7]  = instr16[6]
  //     [6]     = imm[6]  = instr16[7]
  //     [5]     = imm[5]  = instr16[2]
  //     [4]     = imm[4]  = instr16[11]
  //     [3:1]   = imm[3:1] = instr16[5:3]
  //     [0]     = 0
  wire [20:0] imm_cj;
  assign imm_cj = {{9{instr16[12]}},  // [20:12] extensión de signo
                    instr16[12],        // [11] = imm[11] (bit de signo del offset)
                    instr16[8],         // [10] = imm[10]
                    instr16[10:9],      // [9:8] = imm[9:8]
                    instr16[6],         // [7]  = imm[7]
                    instr16[7],         // [6]  = imm[6]
                    instr16[2],         // [5]  = imm[5]
                    instr16[11],        // [4]  = imm[4]
                    instr16[5:3],       // [3:1] = imm[3:1]
                    1'b0};              // [0]  = 0 (alineación a 2 bytes)

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
      // =======================================================================
      // CUADRANTE 0 (op = 2'b00)  [NUEVO E3]
      // Contiene: c.lw, c.sw
      // Ambas usan registros comprimidos x8-x15 (rd_c, rs2_c)
      // =======================================================================
      2'b00: begin
        case (funct3)
          // -------------------------------------------------------------------
          // c.lw rd', off(rs1')
          //   Codificación: [15:13]=010 [12:10]=off[5:3] [9:7]=rs1' [6]=off[2]
          //                 [5]=off[6]  [4:2]=rd'         [1:0]=00
          //   Expansión:    lw rd', sext(off)(rs1')
          //   Formato 32b:  {imm[11:0], rs1, 3'b010, rd, 7'b0000011}
          //   Nota: el offset es de 7 bits, múltiplo de 4, sin signo (positivo)
          // -------------------------------------------------------------------
          3'b010: begin
            dec_instr = {imm_lw, rd_c, 3'b010, rs2_c, 7'b0000011};
            dec_valid = 1'b1;
          end

          // -------------------------------------------------------------------
          // c.sw rs2', off(rs1')
          //   Codificación: [15:13]=110 [12:10]=off[5:3] [9:7]=rs1' [6]=off[2]
          //                 [5]=off[6]  [4:2]=rs2'         [1:0]=00
          //   Expansión:    sw rs2', sext(off)(rs1')
          //   Formato S-type: {imm[11:5], rs2, rs1, 3'b010, imm[4:0], 7'b0100011}
          //   Nota: imm_lw[11:5] son los 7 bits altos; imm_lw[4:0] los 5 bajos
          // -------------------------------------------------------------------
          3'b110: begin
            dec_instr = {imm_lw[11:5], rs2_c, rd_c, 3'b010, imm_lw[4:0], 7'b0100011};
            dec_valid = 1'b1;
          end

          // funct3 no reconocido en Q0 → NOP
          default: begin
            dec_instr = 32'h00000013;
            dec_valid = 1'b0;
          end
        endcase
      end

      // =======================================================================
      // CUADRANTE 1 (op = 2'b01)
      // Contiene: c.addi, c.jal[NUEVO], c.lui, c.srli, c.srai,
      //           c.sub, c.xor, c.or, c.and, c.j[NUEVO], c.beqz[NUEVO], c.bnez[NUEVO]
      // =======================================================================
      2'b01: begin
        case (funct3)
          // -----------------------------------------------------------------
          // c.addi rd, nzimm
          //   Codificación: [15:13]=000  [12]=imm[5]  [11:7]=rd  [6:2]=imm[4:0]  [1:0]=01
          //   Expansión:    addi rd, rd, sext(imm)
          // -----------------------------------------------------------------
          3'b000: begin
            dec_instr = {imm_addi, rd, 3'b000, rd, 7'b0010011};
            dec_valid = 1'b1;
          end

          // -----------------------------------------------------------------
          // c.jal offset  [NUEVO E3]
          //   Codificación: [15:13]=001  [12:2]=offset (CJ-type scrambled)  [1:0]=01
          //   Expansión:    jal x1, sext(offset)
          //   Formato J-type: {imm[20],imm[10:1],imm[11],imm[19:12], rd, 7'b1101111}
          //   rd = x1 (registro de retorno)
          //   Solo válido en RV32C (en RV64C este encoding es c.addiw)
          // -----------------------------------------------------------------
          3'b001: begin
            dec_instr = {imm_cj[20], imm_cj[10:1], imm_cj[11], imm_cj[19:12],
                         5'b00001, 7'b1101111};
            dec_valid = 1'b1;
          end

          // -----------------------------------------------------------------
          // c.lui rd, nzimm
          //   Codificación: [15:13]=011  [12]=nzimm[17]  [11:7]=rd  [6:2]=nzimm[16:12]
          //   Expansión:    lui rd, sext(nzimm)
          //   Restricción:  rd ≠ x0, rd ≠ x2 (x2 = sp → eso sería c.addi16sp)
          // -----------------------------------------------------------------
          3'b011: begin
            if (rd != 5'd0 && rd != 5'd2) begin
              dec_instr = {imm_lui, rd, 7'b0110111};
              dec_valid = 1'b1;
            end
          end

          // -----------------------------------------------------------------
          // funct3 = 100: Shifts y operaciones registro-registro (CA/CB-format)
          //   Selección por instr16[11:10]:
          //     2'b00 → c.srli    2'b01 → c.srai
          //     2'b11 → sub-ops seleccionadas por instr16[6:5] (funct2)
          // -----------------------------------------------------------------
          3'b100: begin
            case (instr16[11:10])
              // c.srli rd', shamt → srli rd', rd', shamt
              2'b00: begin
                if (instr16[12] == 1'b0) begin
                  dec_instr = {7'b0000000, shamt, rd_c, 3'b101, rd_c, 7'b0010011};
                  dec_valid = 1'b1;
                end
              end

              // c.srai rd', shamt → srai rd', rd', shamt
              2'b01: begin
                if (instr16[12] == 1'b0) begin
                  dec_instr = {7'b0100000, shamt, rd_c, 3'b101, rd_c, 7'b0010011};
                  dec_valid = 1'b1;
                end
              end

              // Operaciones CA-format: sub, xor, or, and
              2'b11: begin
                case (funct2)
                  2'b00: begin  // c.sub → sub rd', rd', rs2'
                    dec_instr = {7'b0100000, rs2_c, rd_c, 3'b000, rd_c, 7'b0110011};
                    dec_valid = 1'b1;
                  end
                  2'b01: begin  // c.xor → xor rd', rd', rs2'
                    dec_instr = {7'b0000000, rs2_c, rd_c, 3'b100, rd_c, 7'b0110011};
                    dec_valid = 1'b1;
                  end
                  2'b10: begin  // c.or  → or  rd', rd', rs2'
                    dec_instr = {7'b0000000, rs2_c, rd_c, 3'b110, rd_c, 7'b0110011};
                    dec_valid = 1'b1;
                  end
                  2'b11: begin  // c.and → and rd', rd', rs2'
                    dec_instr = {7'b0000000, rs2_c, rd_c, 3'b111, rd_c, 7'b0110011};
                    dec_valid = 1'b1;
                  end
                endcase
              end

              // 2'b10 = c.andi (no soportada) → NOP
              default: begin
                dec_instr = 32'h00000013;
                dec_valid = 1'b0;
              end
            endcase
          end

          // -----------------------------------------------------------------
          // c.j offset  [NUEVO E3]
          //   Codificación: [15:13]=101  [12:2]=offset (CJ-type scrambled)  [1:0]=01
          //   Expansión:    jal x0, sext(offset)   (salto incondicional sin retorno)
          //   Formato J-type: {imm[20],imm[10:1],imm[11],imm[19:12], rd, 7'b1101111}
          //   rd = x0 (descarta dirección de retorno)
          // -----------------------------------------------------------------
          3'b101: begin
            dec_instr = {imm_cj[20], imm_cj[10:1], imm_cj[11], imm_cj[19:12],
                         5'b00000, 7'b1101111};
            dec_valid = 1'b1;
          end

          // -----------------------------------------------------------------
          // c.beqz rs1', offset  [NUEVO E3]
          //   Codificación: [15:13]=110  [12]=off[8]  [11:10]=off[4:3]
          //                 [9:7]=rs1'   [6:5]=off[7:6]  [4:3]=off[2:1]
          //                 [2]=off[5]   [1:0]=01
          //   Expansión:    beq rs1', x0, sext(offset)
          //   Formato B-type: {imm[12],imm[10:5],rs2,rs1,funct3,imm[4:1],imm[11],opcode}
          //   rs2 = x0 (compara contra cero)
          // -----------------------------------------------------------------
          3'b110: begin
            dec_instr = {imm_cb[12], imm_cb[10:5],
                         5'b00000, rd_c, 3'b000,
                         imm_cb[4:1], imm_cb[11], 7'b1100011};
            dec_valid = 1'b1;
          end

          // -----------------------------------------------------------------
          // c.bnez rs1', offset  [NUEVO E3]
          //   Codificación: [15:13]=111  [12]=off[8]  [11:10]=off[4:3]
          //                 [9:7]=rs1'   [6:5]=off[7:6]  [4:3]=off[2:1]
          //                 [2]=off[5]   [1:0]=01
          //   Expansión:    bne rs1', x0, sext(offset)
          //   Solo cambia funct3: 3'b001 en lugar de 3'b000
          // -----------------------------------------------------------------
          3'b111: begin
            dec_instr = {imm_cb[12], imm_cb[10:5],
                         5'b00000, rd_c, 3'b001,
                         imm_cb[4:1], imm_cb[11], 7'b1100011};
            dec_valid = 1'b1;
          end

          // funct3 no reconocido en Q1 → NOP
          default: begin
            dec_instr = 32'h00000013;
            dec_valid = 1'b0;
          end
        endcase
      end

      // =======================================================================
      // CUADRANTE 2 (op = 2'b10)
      // Contiene: c.slli, c.lwsp[NUEVO], c.jr[NUEVO], c.jalr[NUEVO],
      //           c.add, c.swsp[NUEVO]
      // =======================================================================
      2'b10: begin
        case (funct3)
          // -----------------------------------------------------------------
          // c.slli rd, shamt
          //   Codificación: [15:13]=000  [12]=0  [11:7]=rd  [6:2]=shamt  [1:0]=10
          //   Expansión:    slli rd, rd, shamt
          // -----------------------------------------------------------------
          3'b000: begin
            if (instr16[12] == 1'b0) begin
              dec_instr = {7'b0000000, shamt, rd, 3'b001, rd, 7'b0010011};
              dec_valid = 1'b1;
            end
          end

          // -----------------------------------------------------------------
          // c.lwsp rd, off(sp)  [NUEVO E3]
          //   Codificación: [15:13]=010  [12]=off[5]  [11:7]=rd
          //                 [6:4]=off[4:2]  [3:2]=off[7:6]  [1:0]=10
          //   Expansión:    lw rd, sext(off)(x2)
          //   Formato I-type: {imm[11:0], rs1, 3'b010, rd, 7'b0000011}
          //   rs1 = x2 (sp)
          //   Restricción: rd ≠ x0 (si rd=0 es RESERVED en la spec)
          // -----------------------------------------------------------------
          3'b010: begin
            if (rd != 5'd0) begin
              dec_instr = {imm_lwsp, 5'd2, 3'b010, rd, 7'b0000011};
              dec_valid = 1'b1;
            end
          end

          // -----------------------------------------------------------------
          // c.jr / c.jalr / c.add (funct3=100)
          //   Distinción por funct4 (instr16[15:12]) y rs2 (instr16[6:2]):
          //
          //   funct4=1000 (bit12=0):
          //     rs2=0 → c.jr  : jalr x0, rs1, 0  (salto sin retorno)
          //     rs2≠0 → c.mv  : add  rd, x0, rs2  (NO implementado → NOP)
          //
          //   funct4=1001 (bit12=1):
          //     rs2=0 → c.jalr: jalr x1, rs1, 0  (salto con retorno a x1)
          //     rs2≠0 → c.add : add  rd, rd, rs2  (ya implementado en E2)
          // -----------------------------------------------------------------
          3'b100: begin
            if (funct4 == 4'b1000) begin
              if (rs2 == 5'b0 && rd != 5'b0) begin
                // c.jr rs1 → jalr x0, rs1, 0
                //   Formato I-type jalr: {imm[11:0], rs1, 3'b000, rd, 7'b1100111}
                //   imm=0, rd=x0
                dec_instr = {12'b0, rd, 3'b000, 5'b00000, 7'b1100111};
                dec_valid = 1'b1;
              end
              // rs2≠0: c.mv → add rd, x0, rs2 (no soportado, cae en NOP default)
            end else if (funct4 == 4'b1001) begin
              if (rs2 == 5'b0 && rd != 5'b0) begin
                // c.jalr rs1 → jalr x1, rs1, 0
                //   Igual que c.jr pero rd=x1 (guarda PC+2 en x1)
                dec_instr = {12'b0, rd, 3'b000, 5'b00001, 7'b1100111};
                dec_valid = 1'b1;
              end else if (rs2 != 5'b0 && rd != 5'b0) begin
                // c.add rd, rs2 → add rd, rd, rs2
                dec_instr = {7'b0000000, rs2, rd, 3'b000, rd, 7'b0110011};
                dec_valid = 1'b1;
              end
            end
          end

          // -----------------------------------------------------------------
          // c.swsp rs2, off(sp)  [NUEVO E3]
          //   Codificación: [15:13]=110  [12:9]=off[5:2]  [8:7]=off[7:6]
          //                 [6:2]=rs2    [1:0]=10
          //   Expansión:    sw rs2, sext(off)(x2)
          //   Formato S-type: {imm[11:5], rs2, rs1, 3'b010, imm[4:0], 7'b0100011}
          //   rs1 = x2 (sp)
          // -----------------------------------------------------------------
          3'b110: begin
            dec_instr = {imm_swsp[11:5], rs2, 5'd2, 3'b010, imm_swsp[4:0], 7'b0100011};
            dec_valid = 1'b1;
          end

          // funct3 no reconocido en Q2 → NOP
          default: begin
            dec_instr = 32'h00000013;
            dec_valid = 1'b0;
          end
        endcase
      end

      // =======================================================================
      // CUADRANTE 3 (op = 2'b11)
      // Instrucciones de 32 bits — nunca deben llegar aquí (el datapath
      // las detecta antes y NO pasa por el descompresor).
      // =======================================================================
      default: begin
        dec_instr = 32'h00000013;
        dec_valid = 1'b0;
      end
    endcase
  end

  assign instr32       = dec_instr;
  assign is_compressed = dec_valid;

endmodule
