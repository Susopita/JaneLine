// =============================================================================
// datapath.v
// RISC-V 32-bit Pipelined Datapath
// =============================================================================
module datapath(
    input  clk, reset,

    // -------------------------------------------------------------------------
    // Control signals from controller
    // -------------------------------------------------------------------------
    // ID Stage
    input  [2:0] ImmSrc,

    // EX Stage
    input        ALUSrcE,
    input  [2:0] ALUControlE,
    input  [1:0] ResultSrcE,
    input        JumpE,
    input        BranchE,
    input        JalrE,        // NUEVO: 1=jalr (SrcAE = Rs1E), 0=jal (SrcAE = PCE)
    input        ShiftArithE,  // NUEVO: 1=sra/srai (corrimiento aritmético)

    // MEM Stage
    input        MemWriteM,
    input        RegWriteM,
    input  [1:0] ResultSrcM,

    // WB Stage
    input        RegWriteW,
    input  [1:0] ResultSrcW,

    // -------------------------------------------------------------------------
    // Instruction Memory (IF)
    // -------------------------------------------------------------------------
    output [31:0] PCF,
    input  [31:0] InstrF,

    // -------------------------------------------------------------------------
    // Decoded instruction fields -> controller (ID)
    // -------------------------------------------------------------------------
    output [6:0] OpD,
    output [2:0] Funct3D,
    output       Funct7b5D,

    // -------------------------------------------------------------------------
    // ALU Flags -> controller (EX)
    // -------------------------------------------------------------------------
    output       ZeroE,
    output       NegE,

    // -------------------------------------------------------------------------
    // PC selection (EX)
    // -------------------------------------------------------------------------
    input        PCSrcE,

    // -------------------------------------------------------------------------
    // Data Memory (MEM)
    // -------------------------------------------------------------------------
    output [31:0] ALUResultM,
    output [31:0] WriteDataM,
    output        MemWriteM_out,
    input  [31:0] ReadDataM,

    // -------------------------------------------------------------------------
    // Hazard Unit Outputs
    // -------------------------------------------------------------------------
    output [4:0] Rs1D,
    output [4:0] Rs2D,
    output [4:0] Rs1E,
    output [4:0] Rs2E,
    output [4:0] RdE,
    output [4:0] RdM,
    output [4:0] RdW,

    // -------------------------------------------------------------------------
    // Hazard Unit Inputs
    // -------------------------------------------------------------------------
    input        StallF,
    input        StallD,
    input        FlushD,
    input        FlushE,
    input  [1:0] ForwardAE,
    input  [1:0] ForwardBE
);

  localparam WIDTH = 32;

  // ===========================================================================
  // IF Stage
  // ===========================================================================
  wire [31:0] PCNextF;
  wire [31:0] PCPlus4F;
  wire [31:0] PCTargetE;  // PC destino (calculado en EX)

  // PC register with stall
  reg [31:0] PCF_r;
  assign PCF = PCF_r;

  always @(posedge clk or posedge reset) begin
    if (reset)        PCF_r <= 32'b0;
    else if (~StallF) PCF_r <= PCNextF;

  end

  adder pcadd4(
    .a (PCF),
    .b (32'd4),
    .y (PCPlus4F)
  );

  // PC multiplexer
  mux2 #(WIDTH) pcmux(
    .d0 (PCPlus4F),
    .d1 (PCTargetE),
    .s  (PCSrcE),
    .y  (PCNextF)
  );

  // ===========================================================================
  // IF / ID Pipeline Register
  // ===========================================================================
  reg [31:0] InstrD;
  reg [31:0] PCD;
  reg [31:0] PCPlus4D;

  always @(posedge clk or posedge reset) begin
    if (reset || FlushD) begin
      InstrD   <= 32'b0;
      PCD      <= 32'b0;
      PCPlus4D <= 32'b0;
    end else if (~StallD) begin
      InstrD   <= InstrF;
      PCD      <= PCF;
      PCPlus4D <= PCPlus4F;
    end
  end

  assign OpD       = InstrD[6:0];
  assign Funct3D   = InstrD[14:12];
  assign Funct7b5D = InstrD[30];

  // ===========================================================================
  // ID Stage
  // ===========================================================================
  wire [31:0] RD1D, RD2D, ImmExtD;
  wire [4:0] RdD = InstrD[11:7];


  wire [31:0] ResultW;
  wire [4:0]  RdW_int;

  regfile rf(
    .clk (clk),
    .we3 (RegWriteW),
    .a1  (InstrD[19:15]),
    .a2  (InstrD[24:20]),
    .a3  (RdW_int),
    .wd3 (ResultW),
    .rd1 (RD1D),
    .rd2 (RD2D)
  );

  // Extensor de inmediatos (ImmSrc ahora es de 3 bits)
  extend ext(
    .instr   (InstrD[31:7]),
    .immsrc  (ImmSrc),
    .immext  (ImmExtD)
  );

  // ===========================================================================
  // ID / EX Pipeline Register
  // ===========================================================================
  reg [31:0] RD1E_r, RD2E_r, ImmExtE_r, PCE_r, PCPlus4E_r;
  reg [4:0]  RdE_r;
  reg [4:0]  Rs1E_r;
  reg [4:0]  Rs2E_r;

  always @(posedge clk or posedge reset) begin
    if (reset || FlushE) begin
      RD1E_r     <= 32'b0;
      RD2E_r     <= 32'b0;
      ImmExtE_r  <= 32'b0;
      PCE_r      <= 32'b0;
      PCPlus4E_r <= 32'b0;
      RdE_r      <= 5'b0;
      Rs1E_r     <= 5'b0;
      Rs2E_r     <= 5'b0;
    end else begin
      RD1E_r     <= RD1D;
      RD2E_r     <= RD2D;
      ImmExtE_r  <= ImmExtD;
      PCE_r      <= PCD;
      PCPlus4E_r <= PCPlus4D;
      RdE_r      <= InstrD[11:7];
      Rs1E_r     <= InstrD[19:15];
      Rs2E_r     <= InstrD[24:20];
    end
  end

  // Alias legibles
  wire [31:0] RD1E, RD2E, ImmExtE, PCE, PCPlus4E;
  assign RD1E     = RD1E_r;
  assign RD2E     = RD2E_r;
  assign ImmExtE  = ImmExtE_r;
  assign PCE      = PCE_r;
  assign PCPlus4E = PCPlus4E_r;

  // Outputs de hazard
  assign Rs1D = InstrD[19:15];
  assign Rs2D = InstrD[24:20];
  assign Rs1E = Rs1E_r;
  assign Rs2E = Rs2E_r;
  assign RdE  = RdE_r;

  // ===========================================================================
  // EX Stage
  // ===========================================================================

  // -------------------------------------------------------------------------
  // Mux SrcAE for branch/jump target calculation
  // -------------------------------------------------------------------------
  wire [31:0] SrcAE_branch;
  mux2 #(WIDTH) srcamux_branch(
    .d0 (PCE),    // jal: PC + ImmExt
    .d1 (RD1E),   // jalr: Rs1 + ImmExt
    .s  (JalrE),
    .y  (SrcAE_branch)
  );

  // -------------------------------------------------------------------------
  // ForwardBE Mux
  // -------------------------------------------------------------------------
  wire [31:0] WriteDataE;
  mux3 #(WIDTH) forwardbmux(
    .d0 (RD2E),
    .d1 (ResultW),
    .d2 (ALUResultM),
    .s  (ForwardBE),
    .y  (WriteDataE)
  );

  // -------------------------------------------------------------------------
  // SrcBE Mux
  // -------------------------------------------------------------------------
  wire [31:0] SrcBE;
  mux2 #(WIDTH) srcbmux(
    .d0 (WriteDataE),
    .d1 (ImmExtE),
    .s  (ALUSrcE),
    .y  (SrcBE)
  );

  // -------------------------------------------------------------------------
  // Main ALU
  // -------------------------------------------------------------------------
  wire [31:0] ALUResultE;

  // -------------------------------------------------------------------------
  // ForwardAE Mux
  // -------------------------------------------------------------------------
  wire [31:0] SrcAE;
  mux3 #(WIDTH) forwardamux(
    .d0 (RD1E),
    .d1 (ResultW),
    .d2 (ALUResultM),
    .s  (ForwardAE),
    .y  (SrcAE)
  );

  alu alu(
    .a          (SrcAE),       // Conectado al wire SrcAE para facilitar waveforms
    .b          (SrcBE),
    .alucontrol (ALUControlE),
    .ShiftArith (ShiftArithE), // NUEVO
    .result     (ALUResultE),
    .zero       (ZeroE),       // exportado al controller
    .neg        (NegE)         // NUEVO: exportado al controller para blt/bge
  );

  // -------------------------------------------------------------------------
  // PCTarget Adder
  // -------------------------------------------------------------------------
  adder pcaddbranch(
    .a (SrcAE_branch),
    .b (ImmExtE),
    .y (PCTargetE)
  );

  // ===========================================================================
  // EX / MEM Pipeline Register
  // ===========================================================================
  reg [31:0] ALUResultM_r, WriteDataM_r, PCPlus4M_r, ImmExtM_r;
  reg [4:0]  RdM_r;

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      ALUResultM_r <= 32'b0;
      WriteDataM_r <= 32'b0;
      PCPlus4M_r   <= 32'b0;
      ImmExtM_r    <= 32'b0;
      RdM_r        <= 5'b0;
    end else begin
      ALUResultM_r <= ALUResultE;
      WriteDataM_r <= WriteDataE;   // Usa WriteDataE (con forwarding) para 'sw'
      PCPlus4M_r   <= PCPlus4E;
      ImmExtM_r    <= ImmExtE;    // NUEVO: para LUI
      RdM_r        <= RdE_r;
    end
  end

  assign ALUResultM    = ALUResultM_r;
  assign WriteDataM    = WriteDataM_r;
  assign MemWriteM_out = MemWriteM;
  assign RdM           = RdM_r;

  // ===========================================================================
  // MEM Stage
  // ===========================================================================

  // ===========================================================================
  // MEM / WB Pipeline Register
  // ===========================================================================
  reg [31:0] ALUResultW_r, ReadDataW_r, PCPlus4W_r, ImmExtW_r;
  reg [4:0]  RdW_r;

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      ALUResultW_r <= 32'b0;
      ReadDataW_r  <= 32'b0;
      PCPlus4W_r   <= 32'b0;
      ImmExtW_r    <= 32'b0;
      RdW_r        <= 5'b0;
    end else begin
      ALUResultW_r <= ALUResultM_r;
      ReadDataW_r  <= ReadDataM;
      PCPlus4W_r   <= PCPlus4M_r;
      ImmExtW_r    <= ImmExtM_r;   // NUEVO: para LUI
      RdW_r        <= RdM_r;
    end
  end

  assign RdW     = RdW_r;
  assign RdW_int = RdW_r;   // alias para conectar al register file

  // ===========================================================================
  // WB Stage
  // ===========================================================================
  mux4 #(WIDTH) resultmux(
    .d0 (ALUResultW_r),
    .d1 (ReadDataW_r),
    .d2 (PCPlus4W_r),
    .d3 (ImmExtW_r),    // NUEVO: para LUI
    .s  (ResultSrcW),
    .y  (ResultW)
  );

endmodule
