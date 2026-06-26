// datapath.v -- RISC-V 32-bit Pipelined Datapath
//
// Entregable 2: soporte para instrucciones comprimidas (Extension C).
//   - Descompresor insertado en IF, antes del registro IF/ID.
//   - PC variable: +2 para comprimidas, +4 para estandar.
//   - PCPlus4 renombrado a PCPlusInc en todo el pipeline.

module datapath(
    input  clk, reset,

    // Control (ID)
    input  [2:0] ImmSrc,

    // Control (EX)
    input        ALUSrcE,
    input  [2:0] ALUControlE,
    input  [1:0] ResultSrcE,
    input        JumpE,
    input        BranchE,
    input        JalrE,
    input        ShiftArithE,

    // Control (MEM)
    input        MemWriteM,
    input        RegWriteM,
    input  [1:0] ResultSrcM,

    // Control (WB)
    input        RegWriteW,
    input  [1:0] ResultSrcW,

    // Instruction Memory (IF)
    output [31:0] PCF,
    input  [31:0] InstrF,

    // Campos de instruccion -> controller (ID)
    output [6:0] OpD,
    output [2:0] Funct3D,
    output       Funct7b5D,

    // Flags ALU -> controller (EX)
    output       ZeroE,
    output       NegE,

    // Seleccion de PC
    input        PCSrcE,

    // Data Memory (MEM)
    output [31:0] ALUResultM,
    output [31:0] WriteDataM,
    output        MemWriteM_out,
    input  [31:0] ReadDataM,

    // Hazard Unit (outputs)
    output [4:0] Rs1D,
    output [4:0] Rs2D,
    output [4:0] Rs1E,
    output [4:0] Rs2E,
    output [4:0] RdE,
    output [4:0] RdM,
    output [4:0] RdW,

    // Hazard Unit (inputs)
    input        StallF,
    input        StallD,
    input        FlushD,
    input        FlushE,
    input  [1:0] ForwardAE,
    input  [1:0] ForwardBE
);

  localparam WIDTH = 32;

  // ===========================================================================
  // IF
  // ===========================================================================
  wire [31:0] PCNextF;
  wire [31:0] PCPlusIncF;
  wire [31:0] PCTargetE;

  // Deteccion: bits[1:0] != 11 => instruccion comprimida
  wire is_compressed_f = (InstrF[1:0] != 2'b11);

  // Descompresor
  wire [31:0] instr_expanded;
  wire        decomp_valid;

  decompressor decomp(
    .instr16       (InstrF[15:0]),
    .instr32       (instr_expanded),
    .is_compressed (decomp_valid)
  );

  // Selecciona instruccion expandida o estandar
  wire [31:0] InstrF_final = is_compressed_f ? instr_expanded : InstrF;

  reg [31:0] PCF_r;
  assign PCF = PCF_r;

  always @(posedge clk or posedge reset) begin
    if (reset)        PCF_r <= 32'b0;
    else if (~StallF) PCF_r <= PCNextF;
  end

  // Incremento variable: +2 si comprimida, +4 si estandar
  wire [31:0] pc_increment = is_compressed_f ? 32'd2 : 32'd4;

  adder pcaddinc(
    .a (PCF),
    .b (pc_increment),
    .y (PCPlusIncF)
  );

  mux2 #(WIDTH) pcmux(
    .d0 (PCPlusIncF),
    .d1 (PCTargetE),
    .s  (PCSrcE),
    .y  (PCNextF)
  );

  // ===========================================================================
  // Registro IF/ID
  // ===========================================================================
  reg [31:0] InstrD;
  reg [31:0] PCD;
  reg [31:0] PCPlusIncD;

  always @(posedge clk or posedge reset) begin
    if (reset || FlushD) begin
      InstrD     <= 32'b0;
      PCD        <= 32'b0;
      PCPlusIncD <= 32'b0;
    end else if (~StallD) begin
      InstrD     <= InstrF_final; // instruccion ya expandida
      PCD        <= PCF;
      PCPlusIncD <= PCPlusIncF;
    end
  end

  assign OpD       = InstrD[6:0];
  assign Funct3D   = InstrD[14:12];
  assign Funct7b5D = InstrD[30];

  // ===========================================================================
  // ID
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

  extend ext(
    .instr   (InstrD[31:7]),
    .immsrc  (ImmSrc),
    .immext  (ImmExtD)
  );

  // ===========================================================================
  // Registro ID/EX
  // ===========================================================================
  reg [31:0] RD1E_r, RD2E_r, ImmExtE_r, PCE_r, PCPlusIncE_r;
  reg [4:0]  RdE_r, Rs1E_r, Rs2E_r;

  always @(posedge clk or posedge reset) begin
    if (reset || FlushE) begin
      RD1E_r       <= 32'b0;
      RD2E_r       <= 32'b0;
      ImmExtE_r    <= 32'b0;
      PCE_r        <= 32'b0;
      PCPlusIncE_r <= 32'b0;
      RdE_r        <= 5'b0;
      Rs1E_r       <= 5'b0;
      Rs2E_r       <= 5'b0;
    end else begin
      RD1E_r       <= RD1D;
      RD2E_r       <= RD2D;
      ImmExtE_r    <= ImmExtD;
      PCE_r        <= PCD;
      PCPlusIncE_r <= PCPlusIncD;
      RdE_r        <= InstrD[11:7];
      Rs1E_r       <= InstrD[19:15];
      Rs2E_r       <= InstrD[24:20];
    end
  end

  wire [31:0] RD1E, RD2E, ImmExtE, PCE, PCPlusIncE;
  assign RD1E       = RD1E_r;
  assign RD2E       = RD2E_r;
  assign ImmExtE    = ImmExtE_r;
  assign PCE        = PCE_r;
  assign PCPlusIncE = PCPlusIncE_r;

  assign Rs1D = InstrD[19:15];
  assign Rs2D = InstrD[24:20];
  assign Rs1E = Rs1E_r;
  assign Rs2E = Rs2E_r;
  assign RdE  = RdE_r;

  // ===========================================================================
  // EX
  // ===========================================================================

  // Mux base del sumador de branch: PC (jal) o Rs1 (jalr)
  wire [31:0] SrcAE_branch;
  mux2 #(WIDTH) srcamux_branch(
    .d0 (PCE),
    .d1 (RD1E),
    .s  (JalrE),
    .y  (SrcAE_branch)
  );

  // Forwarding B
  wire [31:0] WriteDataE;
  mux3 #(WIDTH) forwardbmux(
    .d0 (RD2E),
    .d1 (ResultW),
    .d2 (ALUResultM),
    .s  (ForwardBE),
    .y  (WriteDataE)
  );

  wire [31:0] SrcBE;
  mux2 #(WIDTH) srcbmux(
    .d0 (WriteDataE),
    .d1 (ImmExtE),
    .s  (ALUSrcE),
    .y  (SrcBE)
  );

  wire [31:0] ALUResultE;

  // Forwarding A
  wire [31:0] SrcAE;
  mux3 #(WIDTH) forwardamux(
    .d0 (RD1E),
    .d1 (ResultW),
    .d2 (ALUResultM),
    .s  (ForwardAE),
    .y  (SrcAE)
  );

  alu alu(
    .a          (SrcAE),
    .b          (SrcBE),
    .alucontrol (ALUControlE),
    .ShiftArith (ShiftArithE),
    .result     (ALUResultE),
    .zero       (ZeroE),
    .neg        (NegE)
  );

  adder pcaddbranch(
    .a (SrcAE_branch),
    .b (ImmExtE),
    .y (PCTargetE)
  );

  // ===========================================================================
  // Registro EX/MEM
  // ===========================================================================
  reg [31:0] ALUResultM_r, WriteDataM_r, PCPlusIncM_r, ImmExtM_r;
  reg [4:0]  RdM_r;

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      ALUResultM_r <= 32'b0;
      WriteDataM_r <= 32'b0;
      PCPlusIncM_r <= 32'b0;
      ImmExtM_r    <= 32'b0;
      RdM_r        <= 5'b0;
    end else begin
      ALUResultM_r <= ALUResultE;
      WriteDataM_r <= WriteDataE;
      PCPlusIncM_r <= PCPlusIncE;
      ImmExtM_r    <= ImmExtE;
      RdM_r        <= RdE_r;
    end
  end

  assign ALUResultM    = ALUResultM_r;
  assign WriteDataM    = WriteDataM_r;
  assign MemWriteM_out = MemWriteM;
  assign RdM           = RdM_r;

  // ===========================================================================
  // Registro MEM/WB
  // ===========================================================================
  reg [31:0] ALUResultW_r, ReadDataW_r, PCPlusIncW_r, ImmExtW_r;
  reg [4:0]  RdW_r;

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      ALUResultW_r <= 32'b0;
      ReadDataW_r  <= 32'b0;
      PCPlusIncW_r <= 32'b0;
      ImmExtW_r    <= 32'b0;
      RdW_r        <= 5'b0;
    end else begin
      ALUResultW_r <= ALUResultM_r;
      ReadDataW_r  <= ReadDataM;
      PCPlusIncW_r <= PCPlusIncM_r;
      ImmExtW_r    <= ImmExtM_r;
      RdW_r        <= RdM_r;
    end
  end

  assign RdW     = RdW_r;
  assign RdW_int = RdW_r;

  // ===========================================================================
  // WB
  //   00 = ALUResult  01 = ReadData  10 = PC+Inc  11 = ImmExt (lui)
  // ===========================================================================
  mux4 #(WIDTH) resultmux(
    .d0 (ALUResultW_r),
    .d1 (ReadDataW_r),
    .d2 (PCPlusIncW_r),
    .d3 (ImmExtW_r),
    .s  (ResultSrcW),
    .y  (ResultW)
  );

endmodule
