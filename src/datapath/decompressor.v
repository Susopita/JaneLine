// decompressor.v -- Traduce instrucciones RVC (16 bits) a RV32I (32 bits)
//
// Instrucciones soportadas:
//   Q1: c.addi, c.lui, c.srli, c.srai, c.sub, c.xor, c.or, c.and
//   Q2: c.slli, c.add
//
// Registros comprimidos (CA/CB): 3 bits -> x8-x15 ({2'b01, reg3b})
// Instrucciones no reconocidas producen NOP (addi x0, x0, 0).

module decompressor (
    input  [15:0] instr16,
    output [31:0] instr32,
    output        is_compressed
);

  wire [1:0]  op     = instr16[1:0];
  wire [2:0]  funct3 = instr16[15:13];
  wire [3:0]  funct4 = instr16[15:12];
  wire [1:0]  funct2 = instr16[6:5];

  wire [4:0]  rd    = instr16[11:7];
  wire [4:0]  rs2   = instr16[6:2];
  wire [4:0]  rd_c  = {2'b01, instr16[9:7]};
  wire [4:0]  rs2_c = {2'b01, instr16[4:2]};

  // inmediatos
  wire [11:0] imm_addi = {{6{instr16[12]}}, instr16[12], instr16[6:2]};
  wire [19:0] imm_lui  = {{14{instr16[12]}}, instr16[12], instr16[6:2]};
  wire [4:0]  shamt    = instr16[6:2];

  reg [31:0] dec_instr;
  reg        dec_valid;

  always @(*) begin
    dec_instr = 32'h00000013; // NOP por defecto
    dec_valid = 1'b0;

    case (op)
      // -----------------------------------------------------------------------
      // Cuadrante 1
      // -----------------------------------------------------------------------
      2'b01: begin
        case (funct3)
          // c.addi rd, imm  ->  addi rd, rd, sext(imm)
          3'b000: begin
            dec_instr = {imm_addi, rd, 3'b000, rd, 7'b0010011};
            dec_valid = 1'b1;
          end

          // c.lui rd, nzimm  ->  lui rd, sext(nzimm)  (rd != x0, x2)
          3'b011: begin
            if (rd != 5'd0 && rd != 5'd2) begin
              dec_instr = {imm_lui, rd, 7'b0110111};
              dec_valid = 1'b1;
            end
          end

          // Shifts y ops registro-registro
          3'b100: begin
            case (instr16[11:10])
              // c.srli rd', shamt  ->  srli rd', rd', shamt
              2'b00: begin
                if (instr16[12] == 1'b0) begin
                  dec_instr = {7'b0000000, shamt, rd_c, 3'b101, rd_c, 7'b0010011};
                  dec_valid = 1'b1;
                end
              end

              // c.srai rd', shamt  ->  srai rd', rd', shamt
              2'b01: begin
                if (instr16[12] == 1'b0) begin
                  dec_instr = {7'b0100000, shamt, rd_c, 3'b101, rd_c, 7'b0010011};
                  dec_valid = 1'b1;
                end
              end

              // c.sub / c.xor / c.or / c.and  (CA-format, funct2)
              2'b11: begin
                case (funct2)
                  2'b00: dec_instr = {7'b0100000, rs2_c, rd_c, 3'b000, rd_c, 7'b0110011}; // sub
                  2'b01: dec_instr = {7'b0000000, rs2_c, rd_c, 3'b100, rd_c, 7'b0110011}; // xor
                  2'b10: dec_instr = {7'b0000000, rs2_c, rd_c, 3'b110, rd_c, 7'b0110011}; // or
                  2'b11: dec_instr = {7'b0000000, rs2_c, rd_c, 3'b111, rd_c, 7'b0110011}; // and
                endcase
                dec_valid = 1'b1;
              end

              default: begin
                dec_instr = 32'h00000013;
                dec_valid = 1'b0;
              end
            endcase
          end

          default: begin
            dec_instr = 32'h00000013;
            dec_valid = 1'b0;
          end
        endcase
      end

      // -----------------------------------------------------------------------
      // Cuadrante 2
      // -----------------------------------------------------------------------
      2'b10: begin
        case (funct3)
          // c.slli rd, shamt  ->  slli rd, rd, shamt
          3'b000: begin
            if (instr16[12] == 1'b0) begin
              dec_instr = {7'b0000000, shamt, rd, 3'b001, rd, 7'b0010011};
              dec_valid = 1'b1;
            end
          end

          // c.add rd, rs2  ->  add rd, rd, rs2  (bit12=1 distingue de c.mv)
          3'b100: begin
            if (funct4 == 4'b1001 && rd != 5'd0 && rs2 != 5'd0) begin
              dec_instr = {7'b0000000, rs2, rd, 3'b000, rd, 7'b0110011};
              dec_valid = 1'b1;
            end
          end

          default: begin
            dec_instr = 32'h00000013;
            dec_valid = 1'b0;
          end
        endcase
      end

      default: begin
        dec_instr = 32'h00000013;
        dec_valid = 1'b0;
      end
    endcase
  end

  assign instr32       = dec_instr;
  assign is_compressed = dec_valid;

endmodule
