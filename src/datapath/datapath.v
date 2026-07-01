// datapath.v  –  RISC-V 32-bit  Pipelined Datapath
module datapath(
    input  clk, reset,
  // Señales de control desde el controller
    // Etapa ID (combinacional, no pasa por registro)
    input  [2:0] ImmSrc,    // AMPLIADO a 3 bits (U-type)

    // Etapa EX (vienen del registro ID/EX del controller)
    input        ALUSrcE,
    input  [2:0] ALUControlE,
    input  [1:0] ResultSrcE,
    input        JumpE,
    input        BranchE,
    input        JalrE,        // 1=jalr (SrcAE = Rs1E), 0=jal (SrcAE = PCE)
    input        ShiftArithE,  // 1=sra/srai (corrimiento aritmético)

    // Etapa MEM (vienen del registro EX/MEM del controller)
    input        MemWriteM,
    input        RegWriteM,
    input  [1:0] ResultSrcM,

    // Etapa WB (vienen del registro MEM/WB del controller)
    input        RegWriteW,
    input  [1:0] ResultSrcW,
  // Interfaz con la Instruction Memory (etapa IF)
    output [31:0] PCF,      // PC actual → instruction memory
    input  [31:0] InstrF,   // instrucción leída de imem (puede ser 16b en bits [15:0])
  // Campos de la instrucción decodificada → controller (etapa ID)
    output [6:0] OpD,
    output [2:0] Funct3D,
    output       Funct7b5D,
  // Flags de la ALU → controller para resolver branches (etapa EX)
    output       ZeroE,  // result == 0  (beq/bne)
    output       NegE,   // result[31]   (blt/bge)
  // Selección del PC (calculado en el controller)
    input        PCSrcE,    // 1 → salto tomado (PCTargetE), 0 → PC+Inc
  // Interfaz con la Data Memory (etapa MEM)
    output [31:0] ALUResultM,
    output [31:0] WriteDataM,
    output        MemWriteM_out,
    input  [31:0] ReadDataM,
  // Outputs para la Hazard Unit
    output [4:0] Rs1D,
    output [4:0] Rs2D,
    output [4:0] Rs1E,
    output [4:0] Rs2E,
    output [4:0] RdE,
    output [4:0] RdM,
    output [4:0] RdW,
  // Entradas desde la Hazard Unit
    input        StallF,       // 1 → congela el PC (IF no avanza)
    input        StallD,       // 1 → congela el registro IF/ID (ID no avanza)
    input        FlushD,       // 1 → limpia el registro IF/ID (burbuja en ID)
    input        FlushE,       // 1 → limpia el registro ID/EX (burbuja en EX)
    input  [1:0] ForwardAE,    // 00=RF 01=WB 10=MEM (forwarding entrada A de ALU)
    input  [1:0] ForwardBE     // 00=RF 01=WB 10=MEM (forwarding entrada B de ALU)
);

  localparam WIDTH = 32;
  // ETAPA IF – Instruction Fetch
  wire [31:0] PCNextF;
  wire [31:0] PCPlusIncF;    // ← RENOMBRADO: antes PCPlus4F
  wire [31:0] PCTargetE;     // PC destino (calculado en EX)
  // [NUEVO] Detección de instrucción comprimida
  wire is_compressed_f = (InstrF[1:0] != 2'b11);
  // [NUEVO] Instanciación del Descompresor
  wire [31:0] instr_expanded;
  wire        decomp_valid;

  decompressor decomp(
    .instr16       (InstrF[15:0]),
    .instr32       (instr_expanded),
    .is_compressed (decomp_valid)
  );
  // [NUEVO] Mux de selección de instrucción: comprimida vs. estándar
  wire [31:0] InstrF_final = is_compressed_f ? instr_expanded : InstrF;
  // Registro del PC con soporte para Stall
  reg [31:0] PCF_r;
  assign PCF = PCF_r;

  always @(posedge clk or posedge reset) begin
    if (reset)        PCF_r <= 32'b0;
    else if (~StallF) PCF_r <= PCNextF;  // Solo avanza si no hay stall
  end
  // [MODIFICADO] Sumador del PC con incremento variable
  wire [31:0] pc_increment = is_compressed_f ? 32'd2 : 32'd4;

  adder pcaddinc(
    .a (PCF),
    .b (pc_increment),
    .y (PCPlusIncF)
  );

  // PCSrcE=0 → ejecución normal (PC+Inc); PCSrcE=1 → salto tomado
  mux2 #(WIDTH) pcmux(
    .d0 (PCPlusIncF),
    .d1 (PCTargetE),
    .s  (PCSrcE),
    .y  (PCNextF)
  );
  // REGISTRO INTERMEDIO  IF / ID
  reg [31:0] InstrD;
  reg [31:0] PCD;
  reg [31:0] PCPlusIncD;   // ← RENOMBRADO: antes PCPlus4D

  always @(posedge clk or posedge reset) begin
    if (reset || FlushD) begin
      // Reset normal O flush por salto tomado: inserta burbuja (NOP) en ID
      InstrD     <= 32'b0;
      PCD        <= 32'b0;
      PCPlusIncD <= 32'b0;
    end else if (~StallD) begin
      // Solo avanza si no hay stall de Load-Use
      InstrD     <= InstrF_final;   // ← MODIFICADO: usa instrucción expandida
      PCD        <= PCF;
      PCPlusIncD <= PCPlusIncF;     // ← RENOMBRADO
    end
    // Si StallD=1 y no FlushD: registros retienen sus valores (pipeline congelado)
  end

  assign OpD       = InstrD[6:0];
  assign Funct3D   = InstrD[14:12];
  assign Funct7b5D = InstrD[30];
  // ETAPA ID – Instruction Decode
  wire [31:0] RD1D, RD2D, ImmExtD;
  wire [4:0] RdD = InstrD[11:7];


  // Señales de write-back para cerrar el loop del pipeline
  wire [31:0] ResultW;
  wire [4:0]  RdW_int;   // wire interno; también sale como output RdW

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
  // REGISTRO INTERMEDIO  ID / EX
  reg [31:0] RD1E_r, RD2E_r, ImmExtE_r, PCE_r, PCPlusIncE_r;
  reg [4:0]  RdE_r;
  reg [4:0]  Rs1E_r;
  reg [4:0]  Rs2E_r;

  always @(posedge clk or posedge reset) begin
    if (reset || FlushE) begin
      // Reset normal O flush: inserta burbuja (NOP) en EX
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
      PCPlusIncE_r <= PCPlusIncD;   // ← RENOMBRADO
      RdE_r        <= InstrD[11:7];
      Rs1E_r       <= InstrD[19:15];
      Rs2E_r       <= InstrD[24:20];
    end
  end

  // Alias legibles
  wire [31:0] RD1E, RD2E, ImmExtE, PCE, PCPlusIncE;
  assign RD1E       = RD1E_r;
  assign RD2E       = RD2E_r;
  assign ImmExtE    = ImmExtE_r;
  assign PCE        = PCE_r;
  assign PCPlusIncE = PCPlusIncE_r;  // ← RENOMBRADO

  // Outputs de hazard
  assign Rs1D = InstrD[19:15];
  assign Rs2D = InstrD[24:20];
  assign Rs1E = Rs1E_r;
  assign Rs2E = Rs2E_r;
  assign RdE  = RdE_r;
  // ETAPA EX – Execute
  // Mux SrcAE: entrada A del sumador de branch/jump target
  wire [31:0] SrcAE_branch;
  mux2 #(WIDTH) srcamux_branch(
    .d0 (PCE),
    .d1 (RD1E),
    .s  (JalrE),
    .y  (SrcAE_branch)
  );
  // Mux de Forwarding para la entrada B de la ALU (Rs2) – ForwardBE
  wire [31:0] WriteDataE;
  mux3 #(WIDTH) forwardbmux(
    .d0 (RD2E),
    .d1 (ResultW),
    .d2 (ALUResultM),
    .s  (ForwardBE),
    .y  (WriteDataE)
  );
  // Mux SrcBE: entrada B de la ALU
  wire [31:0] SrcBE;
  mux2 #(WIDTH) srcbmux(
    .d0 (WriteDataE),
    .d1 (ImmExtE),
    .s  (ALUSrcE),
    .y  (SrcBE)
  );
  // ALU principal
  wire [31:0] ALUResultE;
  // Mux de Forwarding para la entrada A de la ALU (Rs1) – ForwardAE
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
  // Sumador de PCTarget para branch/jump
  adder pcaddbranch(
    .a (SrcAE_branch),
    .b (ImmExtE),
    .y (PCTargetE)
  );
  // REGISTRO INTERMEDIO  EX / MEM
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
      WriteDataM_r <= WriteDataE;     // Usa WriteDataE (con forwarding) para 'sw'
      PCPlusIncM_r <= PCPlusIncE;     // ← RENOMBRADO
      ImmExtM_r    <= ImmExtE;
      RdM_r        <= RdE_r;
    end
  end

  assign ALUResultM    = ALUResultM_r;
  assign WriteDataM    = WriteDataM_r;
  assign MemWriteM_out = MemWriteM;
  assign RdM           = RdM_r;
  // ETAPA MEM – Memory Access (interfaz externa)
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
      PCPlusIncW_r <= PCPlusIncM_r;   // ← RENOMBRADO
      ImmExtW_r    <= ImmExtM_r;
      RdW_r        <= RdM_r;
    end
  end

  assign RdW     = RdW_r;
  assign RdW_int = RdW_r;   // alias para conectar al register file
  // ETAPA WB – Write Back
  mux4 #(WIDTH) resultmux(
    .d0 (ALUResultW_r),
    .d1 (ReadDataW_r),
    .d2 (PCPlusIncW_r),   // ← RENOMBRADO: ahora guarda PC+2 o PC+4 correcto
    .d3 (ImmExtW_r),
    .s  (ResultSrcW),
    .y  (ResultW)
  );

endmodule
