// aludec.v - Decodificador de la ALU RISC-V 32-bit
module aludec(
    input        opb5,       // op[5]: distingue R-type (1) de I-type (0)
    input  [2:0] funct3,
    input        funct7b5,
    input  [1:0] ALUOp,
    output [2:0] ALUControl,
    output       ShiftArith  // 1 → operación de corrimiento aritmético (sra)
);

  wire RtypeSub;
  assign RtypeSub = funct7b5 & opb5;
  assign ShiftArith = (funct3 == 3'b101) & funct7b5;

  reg [2:0] ALUControl_reg;
  assign ALUControl = ALUControl_reg;

  always @* case (ALUOp)
    2'b00:   ALUControl_reg = 3'b000; // ADD (lw, sw, jalr)
    2'b01:   ALUControl_reg = 3'b001; // SUB (branches)
    2'b11:   ALUControl_reg = 3'b011; // OR (LUI/JALR pasa b)
    default: case (funct3)
      3'b000:  ALUControl_reg = RtypeSub ? 3'b001 : 3'b000; // sub / add,addi
      3'b001:  ALUControl_reg = 3'b110;                      // sll, slli
      3'b010:  ALUControl_reg = 3'b101;                      // slt, slti
      3'b011:  ALUControl_reg = 3'b101;                      // sltu (approx slt)
      3'b100:  ALUControl_reg = 3'b100;                      // xor, xori
      3'b101:  ALUControl_reg = 3'b111;                      // srl/sra, srli/srai
      3'b110:  ALUControl_reg = 3'b011;                      // or, ori
      3'b111:  ALUControl_reg = 3'b010;                      // and, andi
      default: ALUControl_reg = 3'b000;                      // desconocido: ADD (no X)
    endcase
  endcase

endmodule