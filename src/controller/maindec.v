// =============================================================================
// maindec.v
// Main Decoder for RISC-V 32-bit Processor
// =============================================================================
module maindec(
    input  [6:0] op,
    output        RegWrite,
    output [2:0]  ImmSrc,
    output        ALUSrc,
    output        MemWrite,
    output [1:0]  ResultSrc,
    output        Branch,
    output [1:0]  ALUOp,
    output        Jump,
    output        JalrSrc
);

  reg [12:0] controls;

  // Control signals unpacking
  assign {RegWrite, ImmSrc, ALUSrc, MemWrite,
          ResultSrc, Branch, ALUOp, Jump, JalrSrc} = controls;

  always @* case (op)
    // -------------------------------------------------------------------------
    // Vector format (13 bits):
    // RegWrite_ImmSrc(3)_ALUSrc_MemWrite_ResultSrc(2)_Branch_ALUOp(2)_Jump_JalrSrc
    // -------------------------------------------------------------------------
    7'b0000011: controls = 13'b1_000_1_0_01_0_00_0_0; // lw
    7'b0100011: controls = 13'b0_001_1_1_00_0_00_0_0; // sw
    7'b0110011: controls = 13'b1_000_0_0_00_0_10_0_0; // R-type
    7'b1100011: controls = 13'b0_010_0_0_00_1_01_0_0; // B-type
    7'b0010011: controls = 13'b1_000_1_0_00_0_10_0_0; // I-type ALU
    7'b1101111: controls = 13'b1_011_0_0_10_0_00_1_0; // jal
    7'b1100111: controls = 13'b1_000_1_0_10_0_00_1_1; // jalr
    7'b0110111: controls = 13'b1_100_1_0_11_0_11_0_0; // lui

    default:    controls = 13'b0_000_0_0_00_0_00_0_0; // NOP
  endcase

endmodule