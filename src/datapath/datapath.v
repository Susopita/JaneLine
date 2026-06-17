// =============================================================================
// datapath.v  –  RISC-V 32-bit  Pipelined Datapath
// Paso 1: Registro IF/ID introducido (sin hazards).
//
// División de responsabilidades con el controller:
//   - Este módulo genera ZeroE (flag de la ALU) y lo exporta al controller.
//   - El controller calcula PCSrcE = (BranchE & ZeroE) | JumpE y lo devuelve.
//   - Así se evita duplicar la lógica y tener múltiples drivers.
// =============================================================================
module datapath(
    input  clk, reset,

    // -------------------------------------------------------------------------
    // Señales de control desde el controller
    // -------------------------------------------------------------------------
    // Etapa ID (combinacional, no pasa por registro)
    input  [1:0] ImmSrc,

    // Etapa EX (vienen del registro ID/EX del controller)
    input        ALUSrcE,
    input  [2:0] ALUControlE,
    input  [1:0] ResultSrcE,
    input        JumpE,
    input        BranchE,

    // Etapa MEM (vienen del registro EX/MEM del controller)
    input        MemWriteM,
    input        RegWriteM,
    input  [1:0] ResultSrcM,

    // Etapa WB (vienen del registro MEM/WB del controller)
    input        RegWriteW,
    input  [1:0] ResultSrcW,

    // -------------------------------------------------------------------------
    // Interfaz con la Instruction Memory (etapa IF)
    // -------------------------------------------------------------------------
    output [31:0] PCF,      // PC actual → instruction memory
    input  [31:0] InstrF,   // instrucción leída de imem

    // -------------------------------------------------------------------------
    // Campos de la instrucción decodificada → controller (etapa ID)
    // -------------------------------------------------------------------------
    output [6:0] OpD,
    output [2:0] Funct3D,
    output       Funct7b5D,

    // -------------------------------------------------------------------------
    // Flag de la ALU → controller para resolver branch (etapa EX)
    // -------------------------------------------------------------------------
    output       ZeroE,     // resultado == 0 (usado para beq/bne)

    // -------------------------------------------------------------------------
    // Selección del PC: el controller lo calcula y lo devuelve aquí
    // -------------------------------------------------------------------------
    input        PCSrcE,    // 1 → salto tomado (PCTargetE), 0 → PC+4

    // -------------------------------------------------------------------------
    // Interfaz con la Data Memory (etapa MEM)
    // -------------------------------------------------------------------------
    output [31:0] ALUResultM,     // dirección de memoria
    output [31:0] WriteDataM,     // dato a escribir en memoria
    output        MemWriteM_out,  // write-enable hacia dmem
    input  [31:0] ReadDataM       // dato leído de dmem
);

  localparam WIDTH = 32;

  // ===========================================================================
  // ETAPA IF – Instruction Fetch
  // ===========================================================================
  wire [31:0] PCNextF;    // siguiente valor del PC
  wire [31:0] PCPlus4F;   // PC + 4
  wire [31:0] PCTargetE;  // PC de destino del branch/jump (calculado en EX)

  // Registro de estado del PC
  flopr #(WIDTH) pcreg(
    .clk   (clk),
    .reset (reset),
    .d     (PCNextF),
    .q     (PCF)
  );

  // Sumador PC + 4
  adder pcadd4(
    .a (PCF),
    .b (32'd4),
    .y (PCPlus4F)
  );

  // Multiplexor para el siguiente PC:
  //   PCSrcE = 0 → ejecución normal (PC + 4)
  //   PCSrcE = 1 → salto tomado (PCTargetE calculado en EX)
  mux2 #(WIDTH) pcmux(
    .d0 (PCPlus4F),
    .d1 (PCTargetE),
    .s  (PCSrcE),
    .y  (PCNextF)
  );

  // ===========================================================================
  // REGISTRO INTERMEDIO  IF / ID  (Paso 1)
  //
  // Guarda los valores de la etapa IF para que estén disponibles en ID
  // al siguiente ciclo de reloj.
  //
  // Contenido según Harris & Harris (Fig. 7.52):
  //   - Instr  : instrucción leída de la memoria de instrucciones
  //   - PC     : dirección de la instrucción (necesario para branches en EX)
  //   - PCPlus4: PC + 4 (necesario para JAL en WB)
  //
  // Sin stall ni flush: se agregan en pasos posteriores (Hazard Unit).
  // ===========================================================================
  reg [31:0] InstrD;    // instrucción en la etapa ID
  reg [31:0] PCD;       // PC de la instrucción en ID
  reg [31:0] PCPlus4D;  // PC+4 de la instrucción en ID

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      // En reset, insertar NOP (instrucción nula) para que la etapa ID
      // no decodifique basura.
      InstrD   <= 32'b0;
      PCD      <= 32'b0;
      PCPlus4D <= 32'b0;
    end else begin
      // Capturar valores de la etapa IF en el flanco positivo
      InstrD   <= InstrF;    // instrucción de imem
      PCD      <= PCF;       // PC de esa instrucción
      PCPlus4D <= PCPlus4F;  // PC + 4 para uso en WB (JAL)
    end
  end

  // Campos extraídos de la instrucción decodificada (combinacional desde InstrD)
  assign OpD       = InstrD[6:0];   // opcode [6:0]
  assign Funct3D   = InstrD[14:12]; // funct3
  assign Funct7b5D = InstrD[30];    // bit 5 de funct7

  // ===========================================================================
  // ETAPA ID – Instruction Decode
  // ===========================================================================
  wire [31:0] RD1D, RD2D, ImmExtD;

  // Señales de write-back para cerrar el loop del pipeline
  wire [31:0] ResultW;  // dato a escribir en el register file (desde WB)
  wire [4:0]  RdW;      // registro destino de WB

  // Register File:
  //   Lecturas: RS1 = InstrD[19:15], RS2 = InstrD[24:20]  (etapa ID)
  //   Escritura: RdW, ResultW  (etapa WB, flanco negativo según teoría)
  regfile rf(
    .clk (clk),
    .we3 (RegWriteW),        // habilitación de escritura
    .a1  (InstrD[19:15]),    // Rs1
    .a2  (InstrD[24:20]),    // Rs2
    .a3  (RdW),              // Rd de WB
    .wd3 (ResultW),          // dato de WB
    .rd1 (RD1D),
    .rd2 (RD2D)
  );

  // Extensor de inmediatos (combinacional, controlado por ImmSrc del controller)
  extend ext(
    .instr   (InstrD[31:7]),
    .immsrc  (ImmSrc),
    .immext  (ImmExtD)
  );

  // ===========================================================================
  // REGISTRO INTERMEDIO  ID / EX
  // Propaga operandos y registro destino hacia la etapa EX.
  // Las señales de control viajan en un registro análogo dentro del controller.
  // ===========================================================================
  reg [31:0] RD1E, RD2E, ImmExtE, PCE, PCPlus4E;
  reg [4:0]  RdE;

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      RD1E     <= 32'b0;
      RD2E     <= 32'b0;
      ImmExtE  <= 32'b0;
      PCE      <= 32'b0;
      PCPlus4E <= 32'b0;
      RdE      <= 5'b0;
    end else begin
      RD1E     <= RD1D;
      RD2E     <= RD2D;
      ImmExtE  <= ImmExtD;
      PCE      <= PCD;
      PCPlus4E <= PCPlus4D;
      RdE      <= InstrD[11:7];   // Rd (registro destino)
    end
  end

  // ===========================================================================
  // ETAPA EX – Execute
  // ===========================================================================
  wire [31:0] SrcBE, ALUResultE;

  // Multiplexor SrcB: elige entre Rs2 (registro) e ImmExt (inmediato)
  mux2 #(WIDTH) srcbmux(
    .d0 (RD2E),
    .d1 (ImmExtE),
    .s  (ALUSrcE),
    .y  (SrcBE)
  );

  // ALU principal
  alu alu(
    .a          (RD1E),
    .b          (SrcBE),
    .alucontrol (ALUControlE),
    .result     (ALUResultE),
    .zero       (ZeroE)         // ZeroE va al controller para resolver branch
  );

  // Sumador para calcular la dirección destino del branch/jump:
  //   PCTargetE = PCE + ImmExtE
  adder pcaddbranch(
    .a (PCE),
    .b (ImmExtE),
    .y (PCTargetE)
  );
  // NOTA: PCSrcE = (BranchE & ZeroE) | JumpE  se calcula en controller.v
  //       para evitar drivers múltiples. El resultado se recibe como input.

  // ===========================================================================
  // REGISTRO INTERMEDIO  EX / MEM
  // ===========================================================================
  reg [31:0] ALUResultM_r, WriteDataM_r, PCPlus4M_r;
  reg [4:0]  RdM_r;

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      ALUResultM_r <= 32'b0;
      WriteDataM_r <= 32'b0;
      PCPlus4M_r   <= 32'b0;
      RdM_r        <= 5'b0;
    end else begin
      ALUResultM_r <= ALUResultE;
      WriteDataM_r <= RD2E;       // dato a escribir en memoria (Rs2)
      PCPlus4M_r   <= PCPlus4E;
      RdM_r        <= RdE;
    end
  end

  // Puertos de salida hacia la data memory
  assign ALUResultM    = ALUResultM_r;
  assign WriteDataM    = WriteDataM_r;
  assign MemWriteM_out = MemWriteM;   // pasa directamente desde el controller

  // ===========================================================================
  // ETAPA MEM – Memory Access
  // (La memoria de datos es externa; la interfaz ya está en los puertos)
  // ===========================================================================

  // ===========================================================================
  // REGISTRO INTERMEDIO  MEM / WB
  // ===========================================================================
  reg [31:0] ALUResultW_r, ReadDataW_r, PCPlus4W_r;
  reg [4:0]  RdW_r;

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      ALUResultW_r <= 32'b0;
      ReadDataW_r  <= 32'b0;
      PCPlus4W_r   <= 32'b0;
      RdW_r        <= 5'b0;
    end else begin
      ALUResultW_r <= ALUResultM_r;
      ReadDataW_r  <= ReadDataM;
      PCPlus4W_r   <= PCPlus4M_r;
      RdW_r        <= RdM_r;
    end
  end

  // Registro destino de WB (alimenta al register file en ID)
  assign RdW = RdW_r;

  // ===========================================================================
  // ETAPA WB – Write Back
  // Multiplexor que elige el dato a escribir en el register file:
  //   ResultSrcW = 2'b00 → ALUResult  (R-type, I-type ALU)
  //   ResultSrcW = 2'b01 → ReadData   (lw)
  //   ResultSrcW = 2'b10 → PC + 4     (jal, jalr)
  // ===========================================================================
  mux3 #(WIDTH) resultmux(
    .d0 (ALUResultW_r),
    .d1 (ReadDataW_r),
    .d2 (PCPlus4W_r),
    .s  (ResultSrcW),
    .y  (ResultW)
  );

endmodule
