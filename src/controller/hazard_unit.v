// hazard_unit.v - Unidad de Riesgos (Hazard Unit)
// Funciones: Forwarding, Stalling, Flushing
module hazard_unit(
    // -------------------------------------------------------------------------
    // Entradas desde la etapa ID
    // -------------------------------------------------------------------------
    input [4:0] Rs1D,           // Registro fuente 1 en etapa Decode
    input [4:0] Rs2D,           // Registro fuente 2 en etapa Decode

    // -------------------------------------------------------------------------
    // Entradas desde la etapa EX
    // -------------------------------------------------------------------------
    input [4:0] Rs1E,           // Registro fuente 1 en etapa Execute
    input [4:0] Rs2E,           // Registro fuente 2 en etapa Execute
    input [4:0] RdE,            // Registro destino en etapa Execute
    input       ResultSrcE0,    // Bit LSB de ResultSrc: =1 si la instrucción en EX es un load
    input       PCSrcE,         // =1 si un salto/branch fue tomado en EX

    // -------------------------------------------------------------------------
    // Entradas desde la etapa MEM
    // -------------------------------------------------------------------------
    input [4:0] RdM,            // Registro destino en etapa Memory
    input       RegWriteM,      // =1 si la instrucción en MEM va a escribir en el RF

    // -------------------------------------------------------------------------
    // Entradas desde la etapa WB
    // -------------------------------------------------------------------------
    input [4:0] RdW,            // Registro destino en etapa Writeback
    input       RegWriteW,      // =1 si la instrucción en WB va a escribir en el RF

    // -------------------------------------------------------------------------
    // Salidas de Forwarding (selección del multiplexor de adelantamiento)
    //   2'b00 → sin adelantamiento  (usa el valor normal del registro)
    //   2'b01 → adelanta desde WB   (ResultW)
    //   2'b10 → adelanta desde MEM  (ALUResultM)
    // -------------------------------------------------------------------------
    output reg [1:0] ForwardAE, // Selección de adelantamiento para entrada A de la ALU
    output reg [1:0] ForwardBE, // Selección de adelantamiento para entrada B de la ALU

    // -------------------------------------------------------------------------
    // Salidas de Stall (congelan los registros del pipeline)
    // -------------------------------------------------------------------------
    output StallF,              // Congela el registro PC (etapa IF no avanza)
    output StallD,              // Congela el registro IF/ID (etapa ID no avanza)

    // -------------------------------------------------------------------------
    // Salidas de Flush (insertan burbujas = NOP en los registros del pipeline)
    // -------------------------------------------------------------------------
    output FlushD,              // Limpia el registro IF/ID  (borra la instrucción en ID)
    output FlushE               // Limpia el registro ID/EX  (borra la instrucción en EX)
);

// Toggle: -DDISABLE_HAZARD_UNIT para pruebas sin hazards
`ifndef DISABLE_HAZARD_UNIT

  // 1. FORWARDING (Data Hazards RAW)
  always @(*) begin

    // --- Forwarding para la entrada A de la ALU (Rs1E) ---
    if      (RegWriteM & (RdM != 5'b0) & (RdM == Rs1E))
      ForwardAE = 2'b10;   // Adelanta desde MEM (resultado más reciente)
    else if (RegWriteW & (RdW != 5'b0) & (RdW == Rs1E))
      ForwardAE = 2'b01;   // Adelanta desde WB
    else
      ForwardAE = 2'b00;   // Sin adelantamiento: usa el valor del register file

    // --- Forwarding para la entrada B de la ALU (Rs2E) ---
    if      (RegWriteM & (RdM != 5'b0) & (RdM == Rs2E))
      ForwardBE = 2'b10;   // Adelanta desde MEM (resultado más reciente)
    else if (RegWriteW & (RdW != 5'b0) & (RdW == Rs2E))
      ForwardBE = 2'b01;   // Adelanta desde WB
    else
      ForwardBE = 2'b00;   // Sin adelantamiento: usa el valor del register file

  end

  // 2. STALLING (Load-Use Hazard)
  wire lwStall;
  assign lwStall = ResultSrcE0 & ((RdE == Rs1D) | (RdE == Rs2D));

  // Acciones del stall:
  //   - StallF: el PC no avanza → IF vuelve a buscar la misma instrucción
  //   - StallD: el registro IF/ID no se actualiza → ID re-decodifica la misma instrucción
  //   - FlushE: el registro ID/EX se pone a cero → se inserta un NOP (burbuja) en EX
  assign StallF = lwStall;
  assign StallD = lwStall;

  // 3. FLUSHING (Control Hazards)

  // FlushD: descarta la instrucción actualmente en la etapa ID
  //   (la que entró erróneamente mientras se calculaba el target del salto)
  assign FlushD = PCSrcE;

  // FlushE: descarta la instrucción actualmente en la etapa EX
  //   - Por un salto tomado (PCSrcE): la instrucción en EX es la errónea
  //   - Por un Load-Use stall (lwStall): se inserta una burbuja forzada
  assign FlushE = PCSrcE | lwStall;

`else
  // HAZARD UNIT DESACTIVADA
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
