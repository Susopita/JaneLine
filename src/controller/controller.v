// =============================================================================
// controller.v  –  Unidad de Control Pipelined RISC-V 32-bit
// Paso 1: agrega el sufijo de etapa a todas las señales.
//         - Etapa ID : decodificación combinacional (maindec + aludec)
//         - Registro ID/EX : propaga señales de control hacia EX
//         - Registro EX/MEM: propaga señales hacia MEM
//         - Registro MEM/WB: propaga señales hacia WB
// Sin hazard unit todavía (se agrega en pasos posteriores).
// =============================================================================
module controller(
    input  clk, reset,

    // -------------------------------------------------------------------------
    // Entradas desde la etapa ID (campos de la instrucción decodificada)
    // -------------------------------------------------------------------------
    input  [6:0] OpD,
    input  [2:0] funct3D,
    input        funct7b5D,

    // -------------------------------------------------------------------------
    // Salida combinacional hacia el datapath (etapa ID)
    // ImmSrc no pasa por un registro: el extensor de inmediatos necesita
    // el tipo de inmediato en la misma etapa ID, de forma combinacional.
    // -------------------------------------------------------------------------
    output [1:0] ImmSrc,

    // -------------------------------------------------------------------------
    // Señales de control para la etapa EX (después del registro ID/EX)
    // -------------------------------------------------------------------------
    output       ALUSrcE,
    output [2:0] ALUControlE,
    output [1:0] ResultSrcE,
    output       MemWriteE,
    output       RegWriteE,
    output       JumpE,
    output       BranchE,

    // -------------------------------------------------------------------------
    // Señales de control para la etapa MEM (después del registro EX/MEM)
    // -------------------------------------------------------------------------
    output       MemWriteM,
    output       RegWriteM,
    output [1:0] ResultSrcM,

    // -------------------------------------------------------------------------
    // Señales de control para la etapa WB (después del registro MEM/WB)
    // -------------------------------------------------------------------------
    output       RegWriteW,
    output [1:0] ResultSrcW,

    // -------------------------------------------------------------------------
    // Señal Zero desde la ALU (etapa EX) para resolver branches
    // -------------------------------------------------------------------------
    input        ZeroE,
    output       PCSrcE
);

  // ---------------------------------------------------------------------------
  // Etapa ID – Decodificación combinacional
  // ---------------------------------------------------------------------------
  wire [1:0] ALUOpD;
  wire       BranchD, JumpD, ALUSrcD, MemWriteD, RegWriteD;
  wire [1:0] ResultSrcD;
  wire [2:0] ALUControlD;
  wire [1:0] ImmSrcD;   // wire local para ImmSrc (etapa ID)

  // Decodificador principal: genera señales de control a partir del opcode
  maindec md(
    .op        (OpD),
    .ResultSrc (ResultSrcD),
    .MemWrite  (MemWriteD),
    .Branch    (BranchD),
    .ALUSrc    (ALUSrcD),
    .RegWrite  (RegWriteD),
    .Jump      (JumpD),
    .ImmSrc    (ImmSrcD),
    .ALUOp     (ALUOpD)
  );

  // Decodificador ALU: genera ALUControl a partir de funct3/funct7 y ALUOp
  aludec ad(
    .opb5      (OpD[5]),
    .funct3    (funct3D),
    .funct7b5  (funct7b5D),
    .ALUOp     (ALUOpD),
    .ALUControl(ALUControlD)
  );

  // ImmSrc se pasa directamente al datapath (combinacional, no se registra)
  assign ImmSrc = ImmSrcD;

  // ---------------------------------------------------------------------------
  // Registro ID / EX
  // Propaga todas las señales de control que necesitan las etapas EX, MEM y WB
  // ---------------------------------------------------------------------------
  reg        ALUSrcE_r, MemWriteE_r, RegWriteE_r, JumpE_r, BranchE_r;
  reg [1:0]  ResultSrcE_r;
  reg [2:0]  ALUControlE_r;

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      ALUSrcE_r     <= 1'b0;
      MemWriteE_r   <= 1'b0;
      RegWriteE_r   <= 1'b0;
      JumpE_r       <= 1'b0;
      BranchE_r     <= 1'b0;
      ResultSrcE_r  <= 2'b0;
      ALUControlE_r <= 3'b0;
    end else begin
      ALUSrcE_r     <= ALUSrcD;
      MemWriteE_r   <= MemWriteD;
      RegWriteE_r   <= RegWriteD;
      JumpE_r       <= JumpD;
      BranchE_r     <= BranchD;
      ResultSrcE_r  <= ResultSrcD;
      ALUControlE_r <= ALUControlD;
    end
  end

  assign ALUSrcE    = ALUSrcE_r;
  assign MemWriteE  = MemWriteE_r;
  assign RegWriteE  = RegWriteE_r;
  assign JumpE      = JumpE_r;
  assign BranchE    = BranchE_r;
  assign ResultSrcE = ResultSrcE_r;
  assign ALUControlE = ALUControlE_r;

  // Resolución de branch/jump (combinacional en EX)
  assign PCSrcE = (BranchE & ZeroE) | JumpE;

  // ---------------------------------------------------------------------------
  // Registro EX / MEM
  // Propaga las señales de control que necesitan las etapas MEM y WB
  // ---------------------------------------------------------------------------
  reg        MemWriteM_r, RegWriteM_r;
  reg [1:0]  ResultSrcM_r;

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      MemWriteM_r  <= 1'b0;
      RegWriteM_r  <= 1'b0;
      ResultSrcM_r <= 2'b0;
    end else begin
      MemWriteM_r  <= MemWriteE_r;
      RegWriteM_r  <= RegWriteE_r;
      ResultSrcM_r <= ResultSrcE_r;
    end
  end

  assign MemWriteM  = MemWriteM_r;
  assign RegWriteM  = RegWriteM_r;
  assign ResultSrcM = ResultSrcM_r;

  // ---------------------------------------------------------------------------
  // Registro MEM / WB
  // Propaga las señales de control que necesita la etapa WB
  // ---------------------------------------------------------------------------
  reg        RegWriteW_r;
  reg [1:0]  ResultSrcW_r;

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      RegWriteW_r  <= 1'b0;
      ResultSrcW_r <= 2'b0;
    end else begin
      RegWriteW_r  <= RegWriteM_r;
      ResultSrcW_r <= ResultSrcM_r;
    end
  end

  assign RegWriteW  = RegWriteW_r;
  assign ResultSrcW = ResultSrcW_r;

endmodule
