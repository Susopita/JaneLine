// hazard_unit.v -- Unidad de riesgos RISC-V pipelined
//
// Maneja: forwarding (RAW), stalling (load-use), flushing (saltos tomados).
// Compilar con -DDISABLE_HAZARD_UNIT para desactivar en pruebas unitarias.

module hazard_unit(
    input [4:0] Rs1D,
    input [4:0] Rs2D,
    input [4:0] Rs1E,
    input [4:0] Rs2E,
    input [4:0] RdE,
    input       ResultSrcE0,
    input       PCSrcE,
    input [4:0] RdM,
    input       RegWriteM,
    input [4:0] RdW,
    input       RegWriteW,

    output reg [1:0] ForwardAE,
    output reg [1:0] ForwardBE,

    output StallF,
    output StallD,
    output FlushD,
    output FlushE
);

`ifndef DISABLE_HAZARD_UNIT

  // Forwarding: MEM tiene prioridad sobre WB
  always @(*) begin
    if      (RegWriteM & (RdM != 5'b0) & (RdM == Rs1E)) ForwardAE = 2'b10;
    else if (RegWriteW & (RdW != 5'b0) & (RdW == Rs1E)) ForwardAE = 2'b01;
    else                                                  ForwardAE = 2'b00;

    if      (RegWriteM & (RdM != 5'b0) & (RdM == Rs2E)) ForwardBE = 2'b10;
    else if (RegWriteW & (RdW != 5'b0) & (RdW == Rs2E)) ForwardBE = 2'b01;
    else                                                  ForwardBE = 2'b00;
  end

  // Stall por load-use
  wire lwStall = ResultSrcE0 & ((RdE == Rs1D) | (RdE == Rs2D));
  assign StallF = lwStall;
  assign StallD = lwStall;

  // Flush por salto tomado (o stall forzado)
  assign FlushD = PCSrcE;
  assign FlushE = PCSrcE | lwStall;

`else
  // Modo prueba: sin hazards
  always @(*) begin
    ForwardAE = 2'b00;
    ForwardBE = 2'b00;
  end
  assign StallF = 1'b0;
  assign StallD = 1'b0;
  assign FlushD = 1'b0;
  assign FlushE = 1'b0;
`endif

endmodule
