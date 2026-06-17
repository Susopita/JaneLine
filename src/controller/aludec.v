// =============================================================================
// aludec.v  –  Decodificador de la ALU RISC-V 32-bit
// Fase B: soporte completo del ISA.
//
// ALUOp encoding (viene de maindec):
//   2'b00 → suma (lw, sw, jalr: calculan dirección con ADD)
//   2'b01 → resta (branches: comparan operandos con SUB)
//   2'b10 → R-type o I-type ALU (usa funct3 y funct7b5)
//   2'b11 → LUI / JALR resultado = b (inmediato) — no usa ALU, solo pasa b
//
// Tabla funct3 para ALUOp=10 (R-type/I-type ALU):
//   000 → ADD/SUB (distingue sub si R-type y funct7b5=1)
//   001 → SLL
//   010 → SLT
//   011 → SLTU (tratado como SLT por ahora; sltu no está en el ISA pedido)
//   100 → XOR
//   101 → SRL (funct7b5=0) / SRA (funct7b5=1)
//   110 → OR
//   111 → AND
//
// ShiftArith: 1 si la instrucción es sra/srai (funct7b5=1 y funct3=101)
// =============================================================================
module aludec(
    input        opb5,       // op[5]: distingue R-type (1) de I-type (0)
    input  [2:0] funct3,
    input        funct7b5,
    input  [1:0] ALUOp,
    output [2:0] ALUControl,
    output       ShiftArith  // NUEVO: 1 → operación de corrimiento aritmético (sra)
);

  wire RtypeSub;
  // Sub solo si es R-type (opb5=1) y funct7b5=1
  assign RtypeSub = funct7b5 & opb5;

  // ShiftArith: sra o srai → funct3=101 y funct7b5=1 (para I-type srai opb5=0)
  assign ShiftArith = (funct3 == 3'b101) & funct7b5;

  reg [2:0] ALUControl_reg;
  assign ALUControl = ALUControl_reg;

  always @* case (ALUOp)
    // -------------------------------------------------------------------------
    // Suma pura: lw, sw usan ADD para calcular dirección efectiva
    // jalr también usa ADD para calcular Rs1 + imm
    // -------------------------------------------------------------------------
    2'b00:   ALUControl_reg = 3'b000; // ADD

    // -------------------------------------------------------------------------
    // Resta pura: branches B-type comparan con SUB (funct3 resuelve en EX)
    // -------------------------------------------------------------------------
    2'b01:   ALUControl_reg = 3'b001; // SUB

    // -------------------------------------------------------------------------
    // Instrucciones que no necesitan ALU (LUI): el valor de b pasa directo.
    // Reutilizamos OR con a=0 (SrcAE=0) para pasar b; el mux de SrcAE se
    // maneja en el datapath con la señal LuiE.
    // -------------------------------------------------------------------------
    2'b11:   ALUControl_reg = 3'b011; // OR (LUI lo usa con SrcAE=0 → result=b)

    // -------------------------------------------------------------------------
    // R-type / I-type ALU: decodifica por funct3
    // -------------------------------------------------------------------------
    default: case (funct3)
      3'b000:  ALUControl_reg = RtypeSub ? 3'b001 : 3'b000; // sub / add,addi
      3'b001:  ALUControl_reg = 3'b110;                      // sll, slli
      3'b010:  ALUControl_reg = 3'b101;                      // slt, slti
      3'b011:  ALUControl_reg = 3'b101;                      // sltu (approx slt)
      3'b100:  ALUControl_reg = 3'b100;                      // xor, xori
      3'b101:  ALUControl_reg = 3'b111;                      // srl/sra, srli/srai
      3'b110:  ALUControl_reg = 3'b011;                      // or, ori
      3'b111:  ALUControl_reg = 3'b010;                      // and, andi
    endcase
  endcase

endmodule