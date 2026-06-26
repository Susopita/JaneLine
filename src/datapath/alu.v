// alu.v -- ALU RISC-V 32-bit
//
// ALUControl:
//   000=ADD  001=SUB  010=AND  011=OR  100=XOR  101=SLT  110=SLL  111=SRL/SRA
//
// ShiftArith: distingue SRA (1) de SRL (0)
// Flags: zero=(result==0), neg=result[31]

module alu(
    input  [31:0] a, b,
    input  [2:0]  alucontrol,
    input         ShiftArith,
    output [31:0] result,
    output        zero,
    output        neg
);

  wire [31:0] condinvb = alucontrol[0] ? ~b : b;
  wire [31:0] sum      = a + condinvb + {31'b0, alucontrol[0]};
  wire        isAddSub = (~alucontrol[2] & ~alucontrol[1]) |
                         (~alucontrol[1] &  alucontrol[0]);
  wire        v = ~(alucontrol[0] ^ a[31] ^ b[31]) & (a[31] ^ sum[31]) & isAddSub;

  reg [31:0] result_reg;
  assign result = result_reg;

  always @* case (alucontrol)
    3'b000:  result_reg = sum;
    3'b001:  result_reg = sum;
    3'b010:  result_reg = a & b;
    3'b011:  result_reg = a | b;
    3'b100:  result_reg = a ^ b;
    3'b101:  result_reg = {{31{1'b0}}, (sum[31] ^ v)};    // SLT
    3'b110:  result_reg = a << b[4:0];
    3'b111:  result_reg = ShiftArith
               ? ($signed(a) >>> b[4:0])
               : (a >> b[4:0]);
    default: result_reg = 32'b0;
  endcase

  assign zero = (result == 32'b0);
  assign neg  = result[31];

endmodule