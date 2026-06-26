// aludec.v -- Decodificador de la ALU RISC-V 32-bit
//
// ALUOp:
//   00 -> ADD  (lw, sw, jalr)
//   01 -> SUB  (branches)
//   10 -> segun funct3 (R-type / I-type ALU)
//   11 -> OR con a=0 (LUI: result = b)
//
// ShiftArith: 1 si sra/srai (funct3=101 y funct7b5=1)

module aludec(
    input        opb5,
    input  [2:0] funct3,
    input        funct7b5,
    input  [1:0] ALUOp,
    output [2:0] ALUControl,
    output       ShiftArith
);

  wire RtypeSub = funct7b5 & opb5;
  assign ShiftArith = (funct3 == 3'b101) & funct7b5;

  reg [2:0] ALUControl_reg;
  assign ALUControl = ALUControl_reg;

  always @* case (ALUOp)
    2'b00:   ALUControl_reg = 3'b000; // ADD
    2'b01:   ALUControl_reg = 3'b001; // SUB
    2'b11:   ALUControl_reg = 3'b011; // OR (LUI)
    default: case (funct3)
      3'b000:  ALUControl_reg = RtypeSub ? 3'b001 : 3'b000;
      3'b001:  ALUControl_reg = 3'b110; // sll/slli
      3'b010:  ALUControl_reg = 3'b101; // slt/slti
      3'b011:  ALUControl_reg = 3'b101; // sltu
      3'b100:  ALUControl_reg = 3'b100; // xor/xori
      3'b101:  ALUControl_reg = 3'b111; // srl/sra, srli/srai
      3'b110:  ALUControl_reg = 3'b011; // or/ori
      3'b111:  ALUControl_reg = 3'b010; // and/andi
      default: ALUControl_reg = 3'b000;
    endcase
  endcase

endmodule