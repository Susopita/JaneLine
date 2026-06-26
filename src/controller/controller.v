// controller.v -- Unidad de control pipelined RISC-V 32-bit

module controller(
    input  clk, reset,
    input        FlushE,

    // Etapa ID
    input  [6:0] OpD,
    input  [2:0] Funct3D,
    input        Funct7b5D,
    output [2:0] ImmSrc,

    // Etapa EX
    output       ALUSrcE,
    output [2:0] ALUControlE,
    output [1:0] ResultSrcE,
    output       MemWriteE,
    output       RegWriteE,
    output       JumpE,
    output       BranchE,
    output       JalrE,
    output       ShiftArithE,

    // Etapa MEM
    output       MemWriteM,
    output       RegWriteM,
    output [1:0] ResultSrcM,

    // Etapa WB
    output       RegWriteW,
    output [1:0] ResultSrcW,

    // Flags ALU para resolver branches
    input        ZeroE,
    input        NegE,
    output       PCSrcE
);

  wire [2:0] ImmSrcD;
  wire [1:0] ALUOpD;
  wire       BranchD, JumpD, JalrSrcD, ALUSrcD, MemWriteD, RegWriteD;
  wire [1:0] ResultSrcD;
  wire [2:0] ALUControlD;
  wire       ShiftArithD;

  maindec md(
    .op        (OpD),
    .ResultSrc (ResultSrcD),
    .MemWrite  (MemWriteD),
    .Branch    (BranchD),
    .ALUSrc    (ALUSrcD),
    .RegWrite  (RegWriteD),
    .Jump      (JumpD),
    .JalrSrc   (JalrSrcD),
    .ImmSrc    (ImmSrcD),
    .ALUOp     (ALUOpD)
  );

  aludec ad(
    .opb5       (OpD[5]),
    .funct3     (Funct3D),
    .funct7b5   (Funct7b5D),
    .ALUOp      (ALUOpD),
    .ALUControl (ALUControlD),
    .ShiftArith (ShiftArithD)
  );

  assign ImmSrc = ImmSrcD;

  // ---------------------------------------------------------------------------
  // Registro ID/EX
  // ---------------------------------------------------------------------------
  reg        ALUSrcE_r, MemWriteE_r, RegWriteE_r, JumpE_r, BranchE_r;
  reg        JalrE_r, ShiftArithE_r;
  reg [1:0]  ResultSrcE_r;
  reg [2:0]  ALUControlE_r;
  reg [2:0]  Funct3E_r;

  always @(posedge clk or posedge reset) begin
    if (reset || FlushE) begin
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
  // Resolucion de branch en EX
  //   beq: ZeroE=1  |  bne: ZeroE=0  |  blt: NegE=1  |  bge: NegE=0
  // ---------------------------------------------------------------------------
  wire BranchTakenE;
  assign BranchTakenE =
      BranchE & (
        (Funct3E_r == 3'b000 &  ZeroE) |
        (Funct3E_r == 3'b001 & ~ZeroE) |
        (Funct3E_r == 3'b100 &  NegE)  |
        (Funct3E_r == 3'b101 & ~NegE)
      );

  assign PCSrcE = BranchTakenE | JumpE;

  // ---------------------------------------------------------------------------
  // Registro EX/MEM
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
  // Registro MEM/WB
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
