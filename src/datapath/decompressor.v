// =============================================================================
// decompressor.v  -  RVC (RISC-V Compressed) Instruction Decompressor
// Mapea las instrucciones de 16 bits de la extensión C a sus equivalentes de 32 bits.
// =============================================================================
module decompressor (
    input  [15:0] instr_c,   // Instrucción comprimida de 16 bits
    output [31:0] instr_32,  // Instrucción expandida de 32 bits
    output        is_valid   // Flag de indicación de decodificación exitosa
);

  wire [1:0]  op       = instr_c[1:0];
  wire [2:0]  funct3   = instr_c[15:13];
  wire [3:0]  funct4   = instr_c[15:12];
  wire [5:0]  funct6   = instr_c[15:10];
  wire [1:0]  funct2   = instr_c[6:5];
  
  wire [4:0]  rd       = instr_c[11:7];
  wire [4:0]  rs2      = instr_c[6:2];

  // Mapeo de registros de 3 bits (x8-x15) para formatos CA, CB, CS
  wire [4:0]  rd_c     = {2'b01, instr_c[9:7]};
  wire [4:0]  rs2_c    = {2'b01, instr_c[4:2]};

  // Immediates
  wire [11:0] imm_addi = {{6{instr_c[12]}}, instr_c[12], instr_c[6:2]};
  wire [19:0] imm_lui  = {{14{instr_c[12]}}, instr_c[12], instr_c[6:2]};
  wire [4:0]  shamt    = instr_c[6:2]; // Para RV32C, shamt[5] (instr_c[12]) debe ser 0

  reg [31:0] dec_instr;
  reg        dec_valid;

  always @(*) begin
    dec_instr = 32'h00000013; // Por defecto: NOP (addi x0, x0, 0)
    dec_valid = 1'b0;

    case (op)
      2'b01: begin // Quadrant 1
        case (funct3)
          3'b000: begin // c.addi -> addi rd, rd, imm
            dec_instr = {imm_addi, rd, 3'b000, rd, 7'b0010011};
            dec_valid = 1'b1;
          end
          
          3'b011: begin // c.lui -> lui rd, imm (rd != 0, rd != 2)
            if (rd != 5'd0 && rd != 5'd2) begin
              dec_instr = {imm_lui, rd, 7'b0110111};
              dec_valid = 1'b1;
            end
          end
          
          3'b100: begin // shifts y CA format (c.sub, c.xor, c.or, c.and)
            case (instr_c[11:10])
              2'b00: begin // c.srli -> srli rd', rd', shamt
                if (instr_c[12] == 1'b0) begin // Para RV32C, shamt[5] = 0
                  dec_instr = {7'b0000000, shamt, rd_c, 3'b101, rd_c, 7'b0010011};
                  dec_valid = 1'b1;
                end
              end
              
              2'b01: begin // c.srai -> srai rd', rd', shamt
                if (instr_c[12] == 1'b0) begin // Para RV32C, shamt[5] = 0
                  dec_instr = {7'b0100000, shamt, rd_c, 3'b101, rd_c, 7'b0010011};
                  dec_valid = 1'b1;
                end
              end
              
              2'b11: begin // CA Format
                case (funct2)
                  2'b00: begin // c.sub -> sub rd', rd', rs2'
                    dec_instr = {7'b0100000, rs2_c, rd_c, 3'b000, rd_c, 7'b0110011};
                    dec_valid = 1'b1;
                  end
                  2'b01: begin // c.xor -> xor rd', rd', rs2'
                    dec_instr = {7'b0000000, rs2_c, rd_c, 3'b100, rd_c, 7'b0110011};
                    dec_valid = 1'b1;
                  end
                  2'b10: begin // c.or -> or rd', rd', rs2'
                    dec_instr = {7'b0000000, rs2_c, rd_c, 3'b110, rd_c, 7'b0110011};
                    dec_valid = 1'b1;
                  end
                  2'b11: begin // c.and -> and rd', rd', rs2'
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
          
          default: begin
            dec_instr = 32'h00000013;
            dec_valid = 1'b0;
          end
        endcase
      end

      2'b10: begin // Quadrant 2
        case (funct3)
          3'b000: begin // c.slli -> slli rd, rd, shamt
            if (instr_c[12] == 1'b0) begin // Para RV32C, shamt[5] = 0
              dec_instr = {7'b0000000, shamt, rd, 3'b001, rd, 7'b0010011};
              dec_valid = 1'b1;
            end
          end
          
          3'b100: begin // c.add -> add rd, rd, rs2 (rd != 0, rs2 != 0)
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

  assign instr_32 = dec_instr;
  assign is_valid = dec_valid;

endmodule
