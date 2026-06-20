// =============================================================================
// alu.v
// ALU for RISC-V 32-bit Processor
// =============================================================================
module alu(
    input  [31:0] a, b,
    input  [2:0]  alucontrol,
    input         ShiftArith,
    output [31:0] result,
    output        zero,
    output        neg
);

  // -------------------------------------------------------------------------
  // Shared ADD/SUB infrastructure
  // -------------------------------------------------------------------------
  wire [31:0] condinvb;
  wire [31:0] sum;
  wire        isAddSub;
  wire        v;

  assign condinvb = alucontrol[0] ? ~b : b;
  assign sum      = a + condinvb + {31'b0, alucontrol[0]};
  assign isAddSub = (~alucontrol[2] & ~alucontrol[1]) |
                    (~alucontrol[1] &  alucontrol[0]);

  // Signed overflow
  assign v = ~(alucontrol[0] ^ a[31] ^ b[31]) & (a[31] ^ sum[31]) & isAddSub;

  // -------------------------------------------------------------------------
  // Result selection
  // -------------------------------------------------------------------------
  reg [31:0] result_reg;
  assign result = result_reg;

  always @* case (alucontrol)
    3'b000:  result_reg = sum;
    3'b001:  result_reg = sum;
    3'b010:  result_reg = a & b;
    3'b011:  result_reg = a | b;
    3'b100:  result_reg = a ^ b;
    3'b101:  result_reg = {{31{1'b0}}, (sum[31] ^ v)};
    3'b110:  result_reg = a << b[4:0];
    3'b111:  result_reg = ShiftArith ? ($signed(a) >>> b[4:0]) : (a >> b[4:0]);
    default: result_reg = 32'b0;
  endcase

  // -------------------------------------------------------------------------
  // Output Flags
  // -------------------------------------------------------------------------
  assign zero = (result == 32'b0);
  assign neg  = result[31];

endmodule