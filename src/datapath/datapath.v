module datapath(input  clk, reset,

                input [1:0] ImmSrc, 
                input       ALUSrcE,
                input [2:0] ALUControlE,
                input [1:0] ResultSrcE,
                input       JumpE,
                input       BranchE,
 
    // Señales de control para MEM
                input       MemWriteM,
                input       RegWriteM,
                input [1:0] ResultSrcM,
 
    // Señales de control para WB
                input       RegWriteW,
                input[1:0]  ResultSrcW,
    // Salidas al exterior
                output [31:0] PCF, // PC actual → instruction memory
                input [31:0] InstrF,    // instrucción leída de imem
    // El controller necesita estos campos para decodificar en ID
                output [6:0] OpD,
                output [2:0] Funct3D,
                output       Funct7b5D,
    // Interfaz con data memory (etapa MEM)
                output [31:0] ALUResultM,    // dirección
                output [31:0] WriteDataM,    // dato a escribir
                output        MemWriteM_out, // write enable hacia dmem
                input[31:0]   ReadDataM,     // dato leído de dmem
    // Branch/jump
                output        PCSrcE        // PC mux select (branch/jump tomado)
    );
  
  localparam WIDTH = 32; // Define a local parameter for bus width
  
  //Fetch (IF)
  wire [31:0] PCNextF, PCPlus4F, PCTargetE; 
  //wire        PCSrcE;
  
  // next PC logic
  flopr #(WIDTH) pcreg(
    .clk(clk), 
    .reset(reset), 
    .d(PCNext), 
    .q(PC)
  ); 
  
  adder       pcadd4(
    .a(PC), 
    .b({WIDTH{1'b0}} + 4), // Using WIDTH parameter for constant 4
    .y(PCPlus4)
  ); 


  mux2 #(WIDTH)  pcmux(
    .d0(PCPlus4), 
    .d1(PCTarget), 
    .s(PCSrc), 
    .y(PCNext)
  ); 
 
    reg [31:0] InstrD, PCD, PCPlus4D;
//  wire [31:0] ImmExt; 
//  wire [31:0] SrcA, SrcB; 
//  wire [31:0] Result; 

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            InstrD   <= 32'b0;
            PCD      <= 32'b0;
            PCPlus4D <= 32'b0;
        end else begin
            InstrD   <= InstrF;
            PCD      <= PCF;
            PCPlus4D <= PCPlus4F;
        end
    end
    
    assign OpD       = InstrD[6:0];
    assign Funct3D   = InstrD[14:12];
    assign Funct7b5D = InstrD[30];
    
    
    wire [31:0] RD1D, RD2D, ImmExtD;
    wire [31:0] ResultW;  // dato de WB
    wire [4:0]   RdW;  
  
  // register file logic
  regfile     rf(
    .clk(clk), 
    .we3(RegWrite), 
    .a1(InstrD[19:15]), 
    .a2(InstrD[24:20]), 
    .a3(RdW), 
    .wd3(Result), 
    .rd1(RD1D), 
    .rd2(RD2D)
  ); 

  extend      ext(
    .instr(InstrD[31:7]), 
    .immsrc(ImmSrc), 
    .immext(ImmExtD)
  ); 


    reg [31:0] RD1E, RD2E, ImmExtE, PCE, PCPlus4E;
    reg [4:0]   RdE;
 
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
      RdE      <= InstrD[11:7];
    end
  end
  
  wire [31:0] SrcBE, ALUResultE;
  wire         ZeroE;



  // ALU logic
  mux2 #(WIDTH)  srcbmux(
    .d0(RD2E), 
    .d1(ImmExtE), 
    .s(ALUSrcE), 
    .y(SrcBE)
  ); 

  alu         alu(
    .a(RD1E), 
    .b(SrcBE), 
    .alucontrol(ALUControlE), 
    .result(ALUResultE), 
    .zero(ZeroE)
  ); 
  
  adder       pcaddbranch(
    .a(PCE), 
    .b(ImmExtE), 
    .y(PCTargetE)
  ); 
  
  assign PCSrcE = (BranchE & ZeroE) | JumpE;
  
  reg [31:0] ALUResultM_r, WriteDataM_r, PCPlus4M_r;
  reg [4:0]   RdM_r;
  
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      ALUResultM_r <= 32'b0;
      WriteDataM_r <= 32'b0;
      PCPlus4M_r   <= 32'b0;
      RdM_r        <= 5'b0;
    end else begin
      ALUResultM_r <= ALUResultE;
      WriteDataM_r <= RD2E;
      PCPlus4M_r   <= PCPlus4E;
      RdM_r        <= RdE;
    end
  end
 
  assign ALUResultM   = ALUResultM_r;
  assign WriteDataM   = WriteDataM_r;
  assign MemWriteM_out = MemWriteM;
  
  
  
  reg [31:0] ALUResultW_r, ReadDataW_r, PCPlus4W_r;
  reg [4:0]   RdW_r;
 
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
 
  assign RdW = RdW_r;
  
  
  

  mux3 #(WIDTH)  resultmux(
    .d0(ALUResultW_r), 
    .d1(ReadDataW_r), 
    .d2(PCPlus4W_r), 
    .s(ResultSrcW), 
    .y(ResultW)
  ); 
endmodule
