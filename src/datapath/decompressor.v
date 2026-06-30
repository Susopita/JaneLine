// =============================================================================
// decompressor.v  –  Descompresor RVC (RISC-V Compressed Extension)
//
// Entregable 3: Traduce instrucciones de 16 bits (Extensión C) a sus
// equivalentes de 32 bits en RV32I.
//
// ┌─────────────────────────────────────────────────────────────────────┐
// │  INSTRUCCIONES SOPORTADAS (20)                                      │
// │                                                                     │
// │  Cuadrante 0 (op = 2'b00):                                          │
// │    1. c.lw     rd', imm(rs1') → lw   rd', imm(rs1')    (CL-type)    │
// │    2. c.sw     rs2', imm(rs1')→ sw   rs2', imm(rs1')   (CS-type)    │
// │                                                                     │
// │  Cuadrante 1 (op = 2'b01):                                          │
// │    3. c.addi   rd, imm       → addi rd, rd, imm        (CI-type)    │
// │    4. c.jal    imm           → jal  x1, imm            (CJ-type)    │
// │    5. c.lui    rd, nzimm     → lui  rd, nzimm          (CI-type)    │
// │    6. c.srli   rd', shamt    → srli rd', rd', shamt    (CB-type)    │
// │    7. c.srai   rd', shamt    → srai rd', rd', shamt    (CB-type)    │
// │    8. c.sub    rd', rs2'     → sub  rd', rd', rs2'     (CA-type)    │
// │    9. c.xor    rd', rs2'     → xor  rd', rd', rs2'     (CA-type)    │
// │   10. c.or     rd', rs2'     → or   rd', rd', rs2'     (CA-type)    │
// │   11. c.and    rd', rs2'     → and  rd', rd', rs2'     (CA-type)    │
// │   12. c.j      imm           → jal  x0, imm            (CJ-type)    │
// │   13. c.beqz   rs1', imm     → beq  rs1', x0, imm      (CB-type)    │
// │   14. c.bnez   rs1', imm     → bne  rs1', x0, imm      (CB-type)    │
// │                                                                     │
// │  Cuadrante 2 (op = 2'b10):                                          │
// │   15. c.slli   rd, shamt     → slli rd, rd, shamt      (CI-type)    │
// │   16. c.lwsp   rd, imm(sp)   → lw   rd, imm(x2)        (CI-type)    │
// │   17. c.jr     rs1           → jalr x0, rs1, 0         (CR-type)    │
// │   18. c.add    rd, rs2       → add  rd, rd, rs2        (CR-type)    │
// │   19. c.jalr   rs1           → jalr x1, rs1, 0         (CR-type)    │
// │   20. c.swsp   rs2, imm(sp)  → sw   rs2, imm(x2)       (CSS-type)   │
// └─────────────────────────────────────────────────────────────────────┘
//
// Convención de registros comprimidos:
//   - Los formatos CA/CB/CL/CS usan registros de 3 bits (instr[9:7] e instr[4:2])
//     que mapean al rango x8–x15: reg_completo = {2'b01, reg_3bit}
//   - Los formatos CI/CR/CSS usan registros de 5 bits (instr[11:7], instr[6:2])
//     que mapean directamente a x0–x31.
//
// Instrucciones NO soportadas:
//   - c.mv, c.andi, c.addi16sp, c.addi4spn
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
  wire [3:0]  funct4 = instr16[15:12];   // Para c.add, c.jr, c.jalr
  wire [1:0]  funct2 = instr16[6:5];     // Sub-sub-op para CA-type (sub/xor/or/and)

  // ---------------------------------------------------------------------------
  // Mapeo de registros
  // ---------------------------------------------------------------------------
  // Registros COMPLETOS (5 bits) – usados por CI-type, CR-type, CSS-type
  wire [4:0]  rd  = instr16[11:7];   // Registro destino / fuente 1 (rd = rs1)
  wire [4:0]  rs2 = instr16[6:2];    // Registro fuente 2

  // Registros COMPRIMIDOS (3 bits → 5 bits) – usados por CA-type, CB-type, CL-type, CS-type
  //   Bits [9:7] → rd'/rs1' (registros x8-x15)
  //   Bits [4:2] → rs2'     (registros x8-x15)
  wire [4:0]  rd_c  = {2'b01, instr16[9:7]};   // rd' / rs1'
  wire [4:0]  rs2_c = {2'b01, instr16[4:2]};   // rs2'

  // ---------------------------------------------------------------------------
  // Reconstrucción de inmediatos
  // ---------------------------------------------------------------------------
  // c.addi: inmediato con signo de 6 bits → extensión a 12 bits
  //   Bits: [12|6:2] → imm[5|4:0]
  wire [11:0] imm_addi = {{6{instr16[12]}}, instr16[12], instr16[6:2]};

  // c.lui: inmediato con signo de 6 bits → extensión a 20 bits
  //   Bits: [12|6:2] → nzimm[17|16:12]
  wire [19:0] imm_lui = {{14{instr16[12]}}, instr16[12], instr16[6:2]};

  // c.slli/c.srli/c.srai: shift amount (sin signo, 5 bits)
  wire [4:0]  shamt = instr16[6:2];

  // c.lw / c.sw: offset sin signo de 7 bits (múltiplo de 4) → extensión a 12 bits
  //   Orden de bits en instr16: [5]=imm[6], [12:10]=imm[5:3], [6]=imm[2]
  wire [11:0] imm_lw_sw = {5'b00000, instr16[5], instr16[12:10], instr16[6], 2'b00};

  // c.lwsp: offset sin signo de 8 bits (múltiplo de 4) → extensión a 12 bits
  //   Orden de bits en instr16: [3:2]=imm[7:6], [12]=imm[5], [6:4]=imm[4:2]
  wire [11:0] imm_lwsp = {4'b0000, instr16[3:2], instr16[12], instr16[6:4], 2'b00};

  // c.swsp: offset sin signo de 8 bits (múltiplo de 4) → extensión a 12 bits
  //   Orden de bits en instr16: [8:7]=imm[7:6], [12:9]=imm[5:2]
  wire [11:0] imm_swsp = {4'b0000, instr16[8:7], instr16[12:9], 2'b00};

  // c.beqz / c.bnez: offset con signo de 9 bits (múltiplo de 2) → representamos bits [12:1] en 12 bits
  //   Orden de bits en instr16: [12]=imm[8], [6:5]=imm[7:6], [2]=imm[5], [11:10]=imm[4:3], [4:3]=imm[2:1]
  wire [11:0] imm_b = {{4{instr16[12]}}, instr16[12], instr16[6:5], instr16[2], instr16[11:10], instr16[4:3]};

  // c.j / c.jal: offset con signo de 12 bits (múltiplo de 2) → representamos bits [20:1] en 20 bits
  //   Orden de bits en instr16: [12]=imm[11], [8]=imm[10], [10:9]=imm[9:8], [6]=imm[7], [7]=imm[6], [2]=imm[5], [11]=imm[4], [5:3]=imm[3:1]
  wire [19:0] imm_j = {{9{instr16[12]}}, instr16[12], instr16[8], instr16[10:9], instr16[6], instr16[7], instr16[2], instr16[11], instr16[5:3]};

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
      // CUADRANTE 0 (op = 2'b00)
      // Contiene: c.lw, c.sw
      // =====================================================================
      2'b00: begin
        case (funct3)
          // -----------------------------------------------------------------
          // c.lw rd', imm(rs1')
          //   Expansión: lw rd', imm(rs1')
          //   Formato 32b I-type: {imm[11:0], rs1, 3'b010, rd, 7'b0000011}
          // -----------------------------------------------------------------
          3'b010: begin
            dec_instr = {imm_lw_sw, rd_c, 3'b010, rs2_c, 7'b0000011};
            dec_valid = 1'b1;
          end

          // -----------------------------------------------------------------
          // c.sw rs2', imm(rs1')
          //   Expansión: sw rs2', imm(rs1')
          //   Formato 32b S-type: {imm[11:5], rs2, rs1, 3'b010, imm[4:0], 7'b0100011}
          // -----------------------------------------------------------------
          3'b110: begin
            dec_instr = {imm_lw_sw[11:5], rs2_c, rd_c, 3'b010, imm_lw_sw[4:0], 7'b0100011};
            dec_valid = 1'b1;
          end

          default: begin
            dec_instr = 32'h00000013;
            dec_valid = 1'b0;
          end
        endcase
      end

      // =====================================================================
      // CUADRANTE 1 (op = 2'b01)
      // Contiene: c.addi, c.jal, c.lui, c.srli, c.srai, c.sub, c.xor, c.or, c.and, c.j, c.beqz, c.bnez
      // =====================================================================
      2'b01: begin
        case (funct3)
          // -----------------------------------------------------------------
          // c.addi rd, nzimm
          //   Expansión: addi rd, rd, sext(imm)
          // -----------------------------------------------------------------
          3'b000: begin
            dec_instr = {imm_addi, rd, 3'b000, rd, 7'b0010011};
            dec_valid = 1'b1;
          end

          // -----------------------------------------------------------------
          // c.jal imm (RV32C only)
          //   Expansión: jal x1, imm
          //   Formato 32b J-type: {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'b1101111}
          // -----------------------------------------------------------------
          3'b001: begin
            dec_instr = {imm_j[19], imm_j[9:0], imm_j[10], imm_j[18:11], 5'd1, 7'b1101111};
            dec_valid = 1'b1;
          end

          // -----------------------------------------------------------------
          // c.lui rd, nzimm
          //   Expansión: lui rd, sext(nzimm)
          // -----------------------------------------------------------------
          3'b011: begin
            if (rd != 5'd0 && rd != 5'd2) begin
              dec_instr = {imm_lui, rd, 7'b0110111};
              dec_valid = 1'b1;
            end
          end

          // -----------------------------------------------------------------
          // funct3 = 100: Shifts y operaciones registro-registro (CA-format)
          // -----------------------------------------------------------------
          3'b100: begin
            case (instr16[11:10])
              // c.srli rd', shamt
              2'b00: begin
                if (instr16[12] == 1'b0) begin
                  dec_instr = {7'b0000000, shamt, rd_c, 3'b101, rd_c, 7'b0010011};
                  dec_valid = 1'b1;
                end
              end

              // c.srai rd', shamt
              2'b01: begin
                if (instr16[12] == 1'b0) begin
                  dec_instr = {7'b0100000, shamt, rd_c, 3'b101, rd_c, 7'b0010011};
                  dec_valid = 1'b1;
                end
              end

              // Operaciones registro-registro (CA-format)
              2'b11: begin
                case (funct2)
                  // c.sub rd', rs2'
                  2'b00: begin
                    dec_instr = {7'b0100000, rs2_c, rd_c, 3'b000, rd_c, 7'b0110011};
                    dec_valid = 1'b1;
                  end
                  // c.xor rd', rs2'
                  2'b01: begin
                    dec_instr = {7'b0000000, rs2_c, rd_c, 3'b100, rd_c, 7'b0110011};
                    dec_valid = 1'b1;
                  end
                  // c.or rd', rs2'
                  2'b10: begin
                    dec_instr = {7'b0000000, rs2_c, rd_c, 3'b110, rd_c, 7'b0110011};
                    dec_valid = 1'b1;
                  end
                  // c.and rd', rs2'
                  2'b11: begin
                    dec_instr = {7'b0000000, rs2_c, rd_c, 3'b111, rd_c, 7'b0110011};
                    dec_valid = 1'b1;
                  end
                endcase
              end
              default: begin
                dec_instr = 32'h00000013;
                dec_valid = 1'b0;
              end
            endcase
          end

          // -----------------------------------------------------------------
          // c.j imm
          //   Expansión: jal x0, imm
          //   Formato 32b J-type: {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'b1101111}
          // -----------------------------------------------------------------
          3'b101: begin
            dec_instr = {imm_j[19], imm_j[9:0], imm_j[10], imm_j[18:11], 5'd0, 7'b1101111};
            dec_valid = 1'b1;
          end

          // -----------------------------------------------------------------
          // c.beqz rs1', imm
          //   Expansión: beq rs1', x0, imm
          //   Formato 32b B-type: {imm[12], imm[10:5], rs2, rs1, 3'b000, imm[4:1], imm[11], 7'b1100011}
          // -----------------------------------------------------------------
          3'b110: begin
            dec_instr = {imm_b[11], imm_b[9:4], 5'd0, rd_c, 3'b000, imm_b[3:0], imm_b[10], 7'b1100011};
            dec_valid = 1'b1;
          end

          // -----------------------------------------------------------------
          // c.bnez rs1', imm
          //   Expansión: bne rs1', x0, imm
          // -----------------------------------------------------------------
          3'b111: begin
            dec_instr = {imm_b[11], imm_b[9:4], 5'd0, rd_c, 3'b001, imm_b[3:0], imm_b[10], 7'b1100011};
            dec_valid = 1'b1;
          end

          default: begin
            dec_instr = 32'h00000013;
            dec_valid = 1'b0;
          end
        endcase
      end

      // =====================================================================
      // CUADRANTE 2 (op = 2'b10)
      // Contiene: c.slli, c.lwsp, c.jr, c.add, c.jalr, c.swsp
      // =====================================================================
      2'b10: begin
        case (funct3)
          // -----------------------------------------------------------------
          // c.slli rd, shamt
          //   Expansión: slli rd, rd, shamt
          // -----------------------------------------------------------------
          3'b000: begin
            if (instr16[12] == 1'b0) begin
              dec_instr = {7'b0000000, shamt, rd, 3'b001, rd, 7'b0010011};
              dec_valid = 1'b1;
            end
          end

          // -----------------------------------------------------------------
          // c.lwsp rd, imm(sp)
          //   Expansión: lw rd, imm(x2)
          //   Restricción: rd ≠ x0
          // -----------------------------------------------------------------
          3'b010: begin
            if (rd != 5'd0) begin
              dec_instr = {imm_lwsp, 5'd2, 3'b010, rd, 7'b0000011};
              dec_valid = 1'b1;
            end
          end

          // -----------------------------------------------------------------
          // c.jr rs1 / c.jalr rs1 / c.add rd, rs2
          //   Diferenciados por el bit 12 y rs2
          // -----------------------------------------------------------------
          3'b100: begin
            if (instr16[12] == 1'b0 && rd != 5'd0 && rs2 == 5'd0) begin
              // c.jr rs1 → jalr x0, rs1, 0
              dec_instr = {12'b0, rd, 3'b000, 5'd0, 7'b1100111};
              dec_valid = 1'b1;
            end
            else if (instr16[12] == 1'b1 && rd != 5'd0 && rs2 == 5'd0) begin
              // c.jalr rs1 → jalr x1, rs1, 0
              dec_instr = {12'b0, rd, 3'b000, 5'd1, 7'b1100111};
              dec_valid = 1'b1;
            end
            else if (instr16[12] == 1'b1 && rd != 5'd0 && rs2 != 5'd0) begin
              // c.add rd, rs2 → add rd, rd, rs2
              dec_instr = {7'b0000000, rs2, rd, 3'b000, rd, 7'b0110011};
              dec_valid = 1'b1;
            end
            // c.mv (bit12=0, rs2!=0) no está soportada
          end

          // -----------------------------------------------------------------
          // c.swsp rs2, imm(sp)
          //   Expansión: sw rs2, imm(x2)
          // -----------------------------------------------------------------
          3'b110: begin
            dec_instr = {imm_swsp[11:5], rs2, 5'd2, 3'b010, imm_swsp[4:0], 7'b0100011};
            dec_valid = 1'b1;
          end

          default: begin
            dec_instr = 32'h00000013;
            dec_valid = 1'b0;
          end
        endcase
      end

      // =====================================================================
      // CUADRANTE 3 (op = 2'b11)
      // Instrucciones de 32 bits (nunca llegan aquí)
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
