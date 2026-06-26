// riscvsingle.v -- Top-level: procesador RISC-V 32-bit pipelined

module riscvsingle(
    input         clk, reset,
    output [31:0] PC,
    input  [31:0] Instr,
    output        MemWrite,
    output [31:0] DataAdr,
    output [31:0] WriteData,
    input  [31:0] ReadData
);

  wire [6:0] OpD;
  wire [2:0] Funct3D;
  wire       Funct7b5D;
  wire [2:0] ImmSrc;

  wire       ALUSrcE;
  wire [2:0] ALUControlE;
  wire [1:0] ResultSrcE;
  wire       MemWriteE, RegWriteE, JumpE, BranchE;
  wire       JalrE, ShiftArithE;

  wire       ZeroE, NegE, PCSrcE;

  wire       MemWriteM, RegWriteM;
  wire [1:0] ResultSrcM;

  wire       RegWriteW;
  wire [1:0] ResultSrcW;

  wire [4:0] Rs1D_w, Rs2D_w;
  wire [4:0] Rs1E_w, Rs2E_w;
  wire [4:0] RdE_w, RdM_w, RdW_w;

  wire [1:0] ForwardAE_w, ForwardBE_w;
  wire       StallF_w, StallD_w, FlushD_w, FlushE_w;

  controller c(
    .clk         (clk),
    .reset       (reset),
    .FlushE      (FlushE_w),
    .OpD         (OpD),
    .Funct3D     (Funct3D),
    .Funct7b5D   (Funct7b5D),
    .ImmSrc      (ImmSrc),
    .ALUSrcE     (ALUSrcE),
    .ALUControlE (ALUControlE),
    .ResultSrcE  (ResultSrcE),
    .MemWriteE   (MemWriteE),
    .RegWriteE   (RegWriteE),
    .JumpE       (JumpE),
    .BranchE     (BranchE),
    .JalrE       (JalrE),
    .ShiftArithE (ShiftArithE),
    .MemWriteM   (MemWriteM),
    .RegWriteM   (RegWriteM),
    .ResultSrcM  (ResultSrcM),
    .RegWriteW   (RegWriteW),
    .ResultSrcW  (ResultSrcW),
    .ZeroE       (ZeroE),
    .NegE        (NegE),
    .PCSrcE      (PCSrcE)
  );

  hazard_unit hu(
    .Rs1D        (Rs1D_w),
    .Rs2D        (Rs2D_w),
    .Rs1E        (Rs1E_w),
    .Rs2E        (Rs2E_w),
    .RdE         (RdE_w),
    .ResultSrcE0 (ResultSrcE[0]),
    .PCSrcE      (PCSrcE),
    .RdM         (RdM_w),
    .RegWriteM   (RegWriteM),
    .RdW         (RdW_w),
    .RegWriteW   (RegWriteW),
    .ForwardAE   (ForwardAE_w),
    .ForwardBE   (ForwardBE_w),
    .StallF      (StallF_w),
    .StallD      (StallD_w),
    .FlushD      (FlushD_w),
    .FlushE      (FlushE_w)
  );

  datapath dp(
    .clk           (clk),
    .reset         (reset),
    .ImmSrc        (ImmSrc),
    .ALUSrcE       (ALUSrcE),
    .ALUControlE   (ALUControlE),
    .ResultSrcE    (ResultSrcE),
    .JumpE         (JumpE),
    .BranchE       (BranchE),
    .JalrE         (JalrE),
    .ShiftArithE   (ShiftArithE),
    .MemWriteM     (MemWriteM),
    .RegWriteM     (RegWriteM),
    .ResultSrcM    (ResultSrcM),
    .RegWriteW     (RegWriteW),
    .ResultSrcW    (ResultSrcW),
    .PCF           (PC),
    .InstrF        (Instr),
    .OpD           (OpD),
    .Funct3D       (Funct3D),
    .Funct7b5D     (Funct7b5D),
    .ZeroE         (ZeroE),
    .NegE          (NegE),
    .PCSrcE        (PCSrcE),
    .ALUResultM    (DataAdr),
    .WriteDataM    (WriteData),
    .MemWriteM_out (MemWrite),
    .ReadDataM     (ReadData),
    .Rs1D          (Rs1D_w),
    .Rs2D          (Rs2D_w),
    .Rs1E          (Rs1E_w),
    .Rs2E          (Rs2E_w),
    .RdE           (RdE_w),
    .RdM           (RdM_w),
    .RdW           (RdW_w),
    .StallF        (StallF_w),
    .StallD        (StallD_w),
    .FlushD        (FlushD_w),
    .FlushE        (FlushE_w),
    .ForwardAE     (ForwardAE_w),
    .ForwardBE     (ForwardBE_w)
  );

endmodule
