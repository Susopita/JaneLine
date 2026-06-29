// =============================================================================
// controller.v  –  Unidad de Control Pipelined RISC-V 32-bit
// Fase B: ISA completo.
//   Cambios respecto a Fase A:
//     - ImmSrc ampliado a 3 bits (U-type para LUI)
//     - Nuevas señales de control: JalrE (jalr), ShiftArithE (sra/srai)
//     - PCSrcE ahora resuelve beq, bne, blt, bge usando Funct3E y los flags
//       Zero y Neg de la ALU
//     - Funct3D se registra en el registro ID/EX para usarse en EX
//     - ResultSrc de 2 bits soporta LUI (ResultSrc=11 → pasa ImmExt directo)
// Sin Hazard Unit todavía.
// =============================================================================
module controller(
    input  clk, reset,

    // Señales de la Hazard Unit
    input        FlushE,   // 1 → limpia el registro ID/EX (inserta burbuja NOP en EX)

    // -------------------------------------------------------------------------
    // Entradas desde la etapa ID (campos de la instrucción decodificada)
    // -------------------------------------------------------------------------
    input  [6:0] OpD,
    input  [2:0] Funct3D,
    input        Funct7b5D,

    // -------------------------------------------------------------------------
    // Salida combinacional hacia el datapath (etapa ID)
    // -------------------------------------------------------------------------
    output [2:0] ImmSrc,     // AMPLIADO a 3 bits

    // -------------------------------------------------------------------------
    // Señales de control para la etapa EX (post-registro ID/EX)
    // -------------------------------------------------------------------------
    output       ALUSrcE,
    output [2:0] ALUControlE,
    output [1:0] ResultSrcE,
    output       MemWriteE,
    output       RegWriteE,
    output       JumpE,
    output       BranchE,
    output       JalrE,        // NUEVO: 1 = jalr (PC target = Rs1+Imm)
    output       ShiftArithE,  // NUEVO: 1 = corrimiento aritmético (sra/srai)

    // -------------------------------------------------------------------------
    // Señales de control para la etapa MEM (post-registro EX/MEM)
    // -------------------------------------------------------------------------
    output       MemWriteM,
    output       RegWriteM,
    output [1:0] ResultSrcM,

    // -------------------------------------------------------------------------
    // Señales de control para la etapa WB (post-registro MEM/WB)
    // -------------------------------------------------------------------------
    output       RegWriteW,
    output [1:0] ResultSrcW,

    // -------------------------------------------------------------------------
    // Flags de la ALU (etapa EX) para resolver branches
    // -------------------------------------------------------------------------
    input        ZeroE,    // result == 0  (beq, bne)
    input        NegE,     // result[31]   (blt, bge)
    output       PCSrcE    // 1 → tomar salto
);

  // ---------------------------------------------------------------------------
  // Etapa ID – Decodificación combinacional
  // ---------------------------------------------------------------------------
  wire [2:0] ImmSrcD;
  wire [1:0] ALUOpD;
  wire       BranchD, JumpD, JalrSrcD, ALUSrcD, MemWriteD, RegWriteD;
  wire [1:0] ResultSrcD;
  wire [2:0] ALUControlD;
  wire       ShiftArithD;

  // Decodificador principal
  maindec md(
    .op        (OpD),
    .ResultSrc (ResultSrcD),
    .MemWrite  (MemWriteD),
    .Branch    (BranchD),
    .ALUSrc    (ALUSrcD),
    .RegWrite  (RegWriteD),
    .Jump      (JumpD),
    .JalrSrc   (JalrSrcD),   // NUEVO
    .ImmSrc    (ImmSrcD),
    .ALUOp     (ALUOpD)
  );

  // Decodificador ALU
  aludec ad(
    .opb5       (OpD[5]),
    .funct3     (Funct3D),
    .funct7b5   (Funct7b5D),
    .ALUOp      (ALUOpD),
    .ALUControl (ALUControlD),
    .ShiftArith (ShiftArithD)  // NUEVO
  );

  // ImmSrc es combinacional (etapa ID, no se registra para llegar al extensor)
  assign ImmSrc = ImmSrcD;

  // ---------------------------------------------------------------------------
  // Registro ID / EX
  // Propaga todas las señales de control hacia la etapa EX.
  // Incluye Funct3 para resolver el tipo de branch en EX.
  // ---------------------------------------------------------------------------
  reg        ALUSrcE_r, MemWriteE_r, RegWriteE_r, JumpE_r, BranchE_r;
  reg        JalrE_r, ShiftArithE_r;  // NUEVO
  reg [1:0]  ResultSrcE_r;
  reg [2:0]  ALUControlE_r;
  reg [2:0]  Funct3E_r;               // NUEVO: para resolver beq/bne/blt/bge en EX

  always @(posedge clk or posedge reset) begin
    if (reset || FlushE) begin
      // Reset normal O flush por salto/stall: inserta burbuja (NOP) en la etapa EX
      ALUSrcE_r     <= 1'b0;
      MemWriteE_r   <= 1'b0;
      RegWriteE_r   <= 1'b0;
      JumpE_r       <= 1'b0;
      BranchE_r     <= 1'b0;
      JalrE_r       <= 1'b0;
      ShiftArithE_r <= 1'b0;
      ResultSrcE_r  <= 2'b0;
      ALUControlE_r <= 3'b0;
      Funct3E_r     <= 3'b0;
    end else begin
      ALUSrcE_r     <= ALUSrcD;
      MemWriteE_r   <= MemWriteD;
      RegWriteE_r   <= RegWriteD;
      JumpE_r       <= JumpD;
      BranchE_r     <= BranchD;
      JalrE_r       <= JalrSrcD;
      ShiftArithE_r <= ShiftArithD;
      ResultSrcE_r  <= ResultSrcD;
      ALUControlE_r <= ALUControlD;
      Funct3E_r     <= Funct3D;
    end
  end

  assign ALUSrcE    = ALUSrcE_r;
  assign MemWriteE  = MemWriteE_r;
  assign RegWriteE  = RegWriteE_r;
  assign JumpE      = JumpE_r;
  assign BranchE    = BranchE_r;
  assign JalrE      = JalrE_r;
  assign ShiftArithE = ShiftArithE_r;
  assign ResultSrcE = ResultSrcE_r;
  assign ALUControlE = ALUControlE_r;

  // ---------------------------------------------------------------------------
  // Resolución de branch en la etapa EX
  //
  // La ALU realiza Rs1E - Rs2E (SUB) para todas las instrucciones B-type.
  // El funct3 determina la condición:
  //   000 (beq) : toma si resultado == 0        → ZeroE
  //   001 (bne) : toma si resultado != 0        → ~ZeroE
  //   100 (blt) : toma si resultado  < 0 (signed) → NegE
  //   101 (bge) : toma si resultado >= 0 (signed) → ~NegE
  //
  // Jump incondicional: jal siempre toma; jalr también (JumpE=1).
  // ---------------------------------------------------------------------------
  wire BranchTakenE;
  assign BranchTakenE =
      BranchE & (
        (Funct3E_r == 3'b000 &  ZeroE) |   // beq
        (Funct3E_r == 3'b001 & ~ZeroE) |   // bne
        (Funct3E_r == 3'b100 &  NegE)  |   // blt  (signed)
        (Funct3E_r == 3'b101 & ~NegE)      // bge  (signed)
      );

  assign PCSrcE = BranchTakenE | JumpE;

  // ---------------------------------------------------------------------------
  // Registro EX / MEM
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
