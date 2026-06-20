module hazard_unit(
    input [4:0] Rs1D, Rs2D,
    input [4:0] Rs1E, Rs2E, RdE,
    input       ResultSrcE0,
    input       PCSrcE,
    input [4:0] RdM,
    input       RegWriteM,
    input [4:0] RdW,
    input       RegWriteW,
    output reg [1:0] ForwardAE, ForwardBE,
    output StallF, StallD,
    output FlushD, FlushE
);

  // Forwarding logic
  always @(*) begin
    if      (RegWriteM & (RdM != 5'b0) & (RdM == Rs1E)) ForwardAE = 2'b10;
    else if (RegWriteW & (RdW != 5'b0) & (RdW == Rs1E)) ForwardAE = 2'b01;
    else                                                ForwardAE = 2'b00;

    if      (RegWriteM & (RdM != 5'b0) & (RdM == Rs2E)) ForwardBE = 2'b10;
    else if (RegWriteW & (RdW != 5'b0) & (RdW == Rs2E)) ForwardBE = 2'b01;
    else                                                ForwardBE = 2'b00;
  end

  // Stalling logic (Load-Use)
  wire lwStall;
  assign lwStall = ResultSrcE0 & ((RdE == Rs1D) | (RdE == Rs2D));

  assign StallF = lwStall;
  assign StallD = lwStall;

  // Flushing logic (Control Hazards)
  assign FlushD = PCSrcE;
  assign FlushE = PCSrcE | lwStall;

endmodule
