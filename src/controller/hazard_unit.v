// =============================================================================
// hazard_unit.v  –  Unidad de Riesgos (Hazard Unit)
// Procesador RISC-V 32-bit Pipelined – Harris & Harris
//
// Responsabilidades:
//   1. FORWARDING  : Detecta dependencias RAW y adelanta datos desde las
//                   etapas MEM o WB hacia las entradas de la ALU en EX,
//                   evitando tener que detener el pipeline innecesariamente.
//
//   2. STALLING    : Detecta el riesgo Load-Use (una instrucción lw seguida
//                   de una instrucción que usa su resultado en el ciclo
//                   siguiente). Detiene IF e ID por un ciclo e inserta
//                   una burbuja en EX.
//
//   3. FLUSHING    : Detecta saltos tomados (branches y jumps). Descarta
//                   las instrucciones que entraron erróneamente a las
//                   etapas IF e ID insertando burbujas en D y en E.
//
// Toda la lógica es COMBINACIONAL (sin registros internos).
// =============================================================================
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

  // ===========================================================================
  // 1. FORWARDING – Adelantamiento de datos (Data Hazards RAW)
  //
  // Previene que la ALU lea un valor desactualizado del register file cuando
  // una instrucción posterior necesita el resultado de una instrucción que aún
  // no ha llegado a la etapa WB.
  //
  // Prioridad: MEM (más reciente) tiene precedencia sobre WB (más antigua).
  // ===========================================================================
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

  // ===========================================================================
  // 2. STALLING – Detección del riesgo Load-Use
  //
  // Cuando una instrucción 'lw' está en la etapa EX y la instrucción siguiente
  // (en ID) necesita el dato que aún está siendo leído de memoria, el forwarding
  // no es suficiente. Es necesario detener el pipeline 1 ciclo e insertar una
  // burbuja en EX.
  //
  // Condición: la instrucción en EX es un load (ResultSrcE0=1) y su registro
  // destino (RdE) coincide con alguno de los registros fuente de la instrucción
  // en ID (Rs1D o Rs2D). Se excluye x0 porque escribir en x0 no tiene efecto.
  // ===========================================================================
  wire lwStall;
  assign lwStall = ResultSrcE0 & ((RdE == Rs1D) | (RdE == Rs2D));

  // Acciones del stall:
  //   - StallF: el PC no avanza → IF vuelve a buscar la misma instrucción
  //   - StallD: el registro IF/ID no se actualiza → ID re-decodifica la misma instrucción
  //   - FlushE: el registro ID/EX se pone a cero → se inserta un NOP (burbuja) en EX
  assign StallF = lwStall;
  assign StallD = lwStall;

  // ===========================================================================
  // 3. FLUSHING – Limpieza por saltos tomados (Control Hazards)
  //
  // El procesador asume que los saltos no se toman (predict-not-taken). Cuando
  // un branch o jump SÍ se toma (PCSrcE=1 en la etapa EX), las instrucciones
  // que entraron erróneamente a IF e ID deben descartarse.
  //
  // Si ocurre un Load-Use stall simultáneamente con un salto tomado, FlushE
  // sigue siendo 1 (el OR garantiza esto), lo que tiene sentido porque tanto
  // el stall como el flush quieren insertar un NOP en EX.
  // ===========================================================================

  // FlushD: descarta la instrucción actualmente en la etapa ID
  //   (la que entró erróneamente mientras se calculaba el target del salto)
  assign FlushD = PCSrcE;

  // FlushE: descarta la instrucción actualmente en la etapa EX
  //   - Por un salto tomado (PCSrcE): la instrucción en EX es la errónea
  //   - Por un Load-Use stall (lwStall): se inserta una burbuja forzada
  assign FlushE = PCSrcE | lwStall;

endmodule
