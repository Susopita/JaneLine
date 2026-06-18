// =============================================================================
// maindec.v  –  Decodificador Principal RISC-V 32-bit
// Fase B: ISA completo.
//
// Señales de control generadas (13 bits total):
//   RegWrite : escribe en el register file
//   ImmSrc   : [2:0] tipo de inmediato (3 bits para cubrir U-type)
//              000 = I-type   001 = S-type   010 = B-type
//              011 = J-type   100 = U-type
//   ALUSrc   : 0 = Rs2, 1 = ImmExt
//   MemWrite : escribe en la memoria de datos
//   ResultSrc: [1:0] selector del mux de WB
//              00 = ALUResult  01 = ReadData  10 = PC+4  11 = ImmExt(LUI)
//   Branch   : instrucción de salto condicional (B-type)
//   ALUOp    : [1:0] guía al aludec
//              00 = ADD  01 = SUB  10 = usa funct3/funct7  11 = pasa-b (LUI)
//   Jump     : salto incondicional (jal o jalr)
//   JalrSrc  : 1 = jalr (PCTarget = Rs1+Imm), 0 = jal (PCTarget = PC+Imm)
//
// Total bits del vector "controls":
//   RegWrite(1) + ImmSrc(3) + ALUSrc(1) + MemWrite(1) +
//   ResultSrc(2) + Branch(1) + ALUOp(2) + Jump(1) + JalrSrc(1) = 13 bits
// =============================================================================
module maindec(
    input  [6:0] op,
    output        RegWrite,
    output [2:0]  ImmSrc,      // AMPLIADO a 3 bits (antes era 2)
    output        ALUSrc,
    output        MemWrite,
    output [1:0]  ResultSrc,
    output        Branch,
    output [1:0]  ALUOp,
    output        Jump,
    output        JalrSrc      // NUEVO: 1 = jalr (target = Rs1+Imm)
);

  reg [12:0] controls;

  // Desempaquetado del vector de control
  assign {RegWrite, ImmSrc, ALUSrc, MemWrite,
          ResultSrc, Branch, ALUOp, Jump, JalrSrc} = controls;

  always @* case (op)
    // -------------------------------------------------------------------------
    // Formato del vector (13 bits):
    // RegWrite_ImmSrc(3b)_ALUSrc_MemWrite_ResultSrc(2b)_Branch_ALUOp(2b)_Jump_JalrSrc
    // -------------------------------------------------------------------------

    // lw: load word — I-type
    //   RegWrite=1, ImmSrc=000(I), ALUSrc=1, MemWrite=0,
    //   ResultSrc=01(ReadData), Branch=0, ALUOp=00(ADD), Jump=0, JalrSrc=0
    7'b0000011: controls = 13'b1_000_1_0_01_0_00_0_0;

    // sw: store word — S-type
    //   RegWrite=0, ImmSrc=001(S), ALUSrc=1, MemWrite=1,
    //   ResultSrc=00, Branch=0, ALUOp=00(ADD), Jump=0, JalrSrc=0
    7'b0100011: controls = 13'b0_001_1_1_00_0_00_0_0;

    // R-type: add, sub, sll, xor, srl, sra, or, and
    //   RegWrite=1, ImmSrc=xxx(no importa), ALUSrc=0, MemWrite=0,
    //   ResultSrc=00, Branch=0, ALUOp=10(funct), Jump=0, JalrSrc=0
    7'b0110011: controls = 13'b1_000_0_0_00_0_10_0_0;

    // B-type: beq, bne, blt, bge (funct3 resuelve cuál en EX)
    //   RegWrite=0, ImmSrc=010(B), ALUSrc=0, MemWrite=0,
    //   ResultSrc=00, Branch=1, ALUOp=01(SUB), Jump=0, JalrSrc=0
    7'b1100011: controls = 13'b0_010_0_0_00_1_01_0_0;

    // I-type ALU: addi, slli, xori, srli, srai, ori, andi
    //   RegWrite=1, ImmSrc=000(I), ALUSrc=1, MemWrite=0,
    //   ResultSrc=00, Branch=0, ALUOp=10(funct), Jump=0, JalrSrc=0
    7'b0010011: controls = 13'b1_000_1_0_00_0_10_0_0;

    // jal: Jump and Link — J-type
    //   RegWrite=1, ImmSrc=011(J), ALUSrc=0, MemWrite=0,
    //   ResultSrc=10(PC+4 va a Rd), Branch=0, ALUOp=00, Jump=1, JalrSrc=0
    7'b1101111: controls = 13'b1_011_0_0_10_0_00_1_0;

    // jalr: Jump and Link Register — I-type
    //   RegWrite=1, ImmSrc=000(I), ALUSrc=1, MemWrite=0,
    //   ResultSrc=10(PC+4 va a Rd), Branch=0, ALUOp=00(ADD), Jump=1, JalrSrc=1
    //   El PC target = Rs1 + ImmExt (lo resuelve el datapath usando JalrSrcE)
    7'b1100111: controls = 13'b1_000_1_0_10_0_00_1_1;

    // lui: Load Upper Immediate — U-type
    //   RegWrite=1, ImmSrc=100(U), ALUSrc=1, MemWrite=0,
    //   ResultSrc=11(ImmExt directo a WB), Branch=0, ALUOp=11(pasa-b), Jump=0, JalrSrc=0
    //   El inmediato U-type ya viene con los 12 bits bajos en cero desde extend.v
    7'b0110111: controls = 13'b1_100_1_0_11_0_11_0_0;

    default:    controls = 13'b0_000_0_0_00_0_00_0_0; // NOP: RegWrite=0, no mem, no branch
  endcase

endmodule