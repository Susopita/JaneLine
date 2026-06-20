// =============================================================================
// regfile.v
// Register File RISC-V 32x32
// =============================================================================
module regfile(input  clk,
               input  we3,
               input  [ 4:0] a1, a2, a3,
               input  [31:0] wd3,
               output [31:0] rd1, rd2);

  reg [31:0] rf[31:0];

  // Write on negative edge
  always @(negedge clk) begin
    if (we3) rf[a3] <= wd3;
  end

  // Combinational read with internal bypass
  assign rd1 = (a1 != 0) ? ((we3 && (a1 == a3)) ? wd3 : rf[a1]) : 32'b0;
  assign rd2 = (a2 != 0) ? ((we3 && (a2 == a3)) ? wd3 : rf[a2]) : 32'b0;

endmodule