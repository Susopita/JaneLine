// =============================================================================
// riscvsingle.v  –  Top-level: Procesador RISC-V 32-bit Pipelined
// Paso 1: conecta Controller y Datapath.
//         El registro IF/ID ya está dentro del datapath.
//
// Flujo de ZeroE / PCSrcE:
//   Datapath genera ZeroE (flag de ALU, etapa EX)
//   Controller recibe ZeroE y calcula PCSrcE = (BranchE & ZeroE) | JumpE
//   Datapath recibe PCSrcE para seleccionar el siguiente PC
// =============================================================================
module riscvsingle(
    input         clk, reset,

    // Interfaz con la Instruction Memory (etapa IF)
    output [31:0] PC,        // PC actual → dirección de imem
    input  [31:0] Instr,     // instrucción leída de imem

    // Interfaz con la Data Memory (etapa MEM)
    output        MemWrite,  // write-enable de dmem
    output [31:0] DataAdr,   // dirección de dmem
    output [31:0] WriteData, // dato a escribir en dmem
    input  [31:0] ReadData   // dato leído de dmem
);

  // ---------------------------------------------------------------------------
  // Wires internos entre Controller y Datapath
  // ---------------------------------------------------------------------------

  // Etapa ID: campos de la instrucción decodificada → controller
  wire [6:0] OpD;
  wire [2:0] Funct3D;
  wire       Funct7b5D;

  // Etapa ID: ImmSrc (combinacional controller → datapath)
  wire [1:0] ImmSrc;

  // Etapa EX: señales de control controller → datapath
  wire       ALUSrcE;
  wire [2:0] ALUControlE;
  wire [1:0] ResultSrcE;
  wire       MemWriteE;       // necesario para hazard unit (Paso 5)
  wire       RegWriteE;       // necesario para hazard unit (Paso 5)
  wire       JumpE;
  wire       BranchE;

  // Etapa EX: ZeroE datapath → controller (flag de la ALU)
  wire       ZeroE;

  // Etapa EX: PCSrcE controller → datapath (selección del siguiente PC)
  wire       PCSrcE;

  // Etapa MEM: señales de control
  wire       MemWriteM;
  wire       RegWriteM;
  wire [1:0] ResultSrcM;

  // Etapa WB: señales de control
  wire       RegWriteW;
  wire [1:0] ResultSrcW;

  // ---------------------------------------------------------------------------
  // Paso 2: Wires de hazard (conectados al datapath, usados en Paso 5)
  // Estos buses de números de registro serán la entrada del Hazard Unit.
  // ---------------------------------------------------------------------------
  wire [4:0] Rs1D_w, Rs2D_w;   // Rs1/Rs2 en etapa ID
  wire [4:0] Rs1E_w, Rs2E_w;   // Rs1/Rs2 en etapa EX
  wire [4:0] RdE_w;             // Rd en EX
  wire [4:0] RdM_w;             // Rd en MEM
  wire [4:0] RdW_w;             // Rd en WB (también conectado al regfile via datapath)

  // ---------------------------------------------------------------------------
  // Instancia del Controller (unidad de control pipelined)
  // ---------------------------------------------------------------------------
  controller c(
    .clk         (clk),
    .reset       (reset),
    // Entradas: campos de instrucción (etapa ID)
    .OpD         (OpD),
    .funct3D     (Funct3D),
    .funct7b5D   (Funct7b5D),
    // Salida combinacional hacia extensor de inmediatos
    .ImmSrc      (ImmSrc),
    // Señales de control para EX (post-registro ID/EX)
    .ALUSrcE     (ALUSrcE),
    .ALUControlE (ALUControlE),
    .ResultSrcE  (ResultSrcE),
    .MemWriteE   (MemWriteE),           // usada internamente en el controller
    .RegWriteE   (RegWriteE),           // usada internamente en el controller
    .JumpE       (JumpE),
    .BranchE     (BranchE),
    // Señales de control para MEM (post-registro EX/MEM)
    .MemWriteM   (MemWriteM),
    .RegWriteM   (RegWriteM),
    .ResultSrcM  (ResultSrcM),
    // Señales de control para WB (post-registro MEM/WB)
    .RegWriteW   (RegWriteW),
    .ResultSrcW  (ResultSrcW),
    // ZeroE del datapath → controller calcula PCSrcE
    .ZeroE       (ZeroE),
    .PCSrcE      (PCSrcE)
  );

  // ---------------------------------------------------------------------------
  // Instancia del Datapath pipelined
  // ---------------------------------------------------------------------------
  datapath dp(
    .clk           (clk),
    .reset         (reset),
    // Señales de control desde el controller
    .ImmSrc        (ImmSrc),
    .ALUSrcE       (ALUSrcE),
    .ALUControlE   (ALUControlE),
    .ResultSrcE    (ResultSrcE),
    .JumpE         (JumpE),
    .BranchE       (BranchE),
    .MemWriteM     (MemWriteM),
    .RegWriteM     (RegWriteM),
    .ResultSrcM    (ResultSrcM),
    .RegWriteW     (RegWriteW),
    .ResultSrcW    (ResultSrcW),
    // Instruction Memory (etapa IF)
    .PCF           (PC),
    .InstrF        (Instr),
    // Campos decodificados → controller (etapa ID)
    .OpD           (OpD),
    .Funct3D       (Funct3D),
    .Funct7b5D     (Funct7b5D),
    // Flag ALU → controller (etapa EX)
    .ZeroE         (ZeroE),
    // Selección de PC ← controller (etapa EX)
    .PCSrcE        (PCSrcE),
    // Data Memory (etapa MEM)
    .ALUResultM    (DataAdr),
    .WriteDataM    (WriteData),
    .MemWriteM_out (MemWrite),
    .ReadDataM     (ReadData),
    // Paso 2: Outputs de hazard → se enrutarán al Hazard Unit en Paso 5
    .Rs1D          (Rs1D_w),
    .Rs2D          (Rs2D_w),
    .Rs1E          (Rs1E_w),
    .Rs2E          (Rs2E_w),
    .RdE           (RdE_w),
    .RdM           (RdM_w),
    .RdW           (RdW_w)
  );

endmodule
