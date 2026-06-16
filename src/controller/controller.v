module controller(
                  input clk, reset,
                  input  [6:0] OpD,
                  input  [2:0] funct3D,
                  input        funct7b5D,
                  output [1:0] ImmSrc,
                  output       ALUSrcE,
                  output [2:0] ALUControlE,
                  output [1:0] ResultSrcE,
                  output       MemWriteE,
                  output       RegWriteE,
                  output       JumpE,
                  output       BranchE,
                  
                  output       MemWriteM,
                  output       RegWriteM,
                  output [1:0] ResultSrcM,
                  
                  output       RegWriteW,
                  output [1:0] ResultSrcW,
    
                  input        ZeroE,
                  output       PCSrcE);
  
  wire [1:0] ALUOpD;
  wire       BranchD, JumpD, ALUSrcD, MemWriteD, RegWriteD;
  wire [1:0] ResultSrcD;
  wire [2:0] ALUControlD;
  
  maindec md(
    .op(OpD), 
    .ResultSrc(ResultSrcD), 
    .MemWrite(MemWriteD), 
    .Branch(BranchD),
    .ALUSrc(ALUSrcD), 
    .RegWrite(RegWriteD), 
    .Jump(JumpD), 
    .ImmSrc(ImmSrcD), 
    .ALUOp(ALUOpD)
  ); 

  aludec  ad(
    .opb5(OpD[5]), 
    .funct3(funct3D), 
    .funct7b5(funct7b5D), 
    .ALUOp(ALUOpD), 
    .ALUControl(ALUControlD)
  ); 
  
  reg        ALUSrcE_r, MemWriteE_r, RegWriteE_r, JumpE_r, BranchE_r;
  reg [1:0]  ResultSrcE_r;
  reg [2:0]  ALUControlE_r;
 
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      ALUSrcE_r    <= 1'b0;
      MemWriteE_r  <= 1'b0;
      RegWriteE_r  <= 1'b0;
      JumpE_r      <= 1'b0;
      BranchE_r    <= 1'b0;
      ResultSrcE_r <= 2'b0;
      ALUControlE_r <= 3'b0;
    end else begin
      ALUSrcE_r    <= ALUSrcD;
      MemWriteE_r  <= MemWriteD;
      RegWriteE_r  <= RegWriteD;
      JumpE_r      <= JumpD;
      BranchE_r    <= BranchD;
      ResultSrcE_r <= ResultSrcD;
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
  
  assign PCSrcE = (BranchE & ZeroE) | JumpE;
  
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
