// alu.v - Unidad Aritmético-Lógica RISC-V 32-bit
module alu(
    input  [31:0] a, b,
    input  [2:0]  alucontrol,
    input         ShiftArith,  // 1 → sra/srai (aritmético), 0 → srl/srli (lógico)
    output [31:0] result,
    output        zero,        // result == 0
    output        neg          // result[31] (bit de signo, para blt/bge)
);

  // ADD/SUB compartido
  wire [31:0] condinvb;   // b o ~b según si es resta
  wire [31:0] sum;        // resultado de la suma/resta
  wire        isAddSub;   // 1 si la operación es add o sub
  wire        v;          // overflow con signo (para SLT)

  assign condinvb = alucontrol[0] ? ~b : b;
  assign sum      = a + condinvb + {31'b0, alucontrol[0]};
  assign isAddSub = (~alucontrol[2] & ~alucontrol[1]) |
                    (~alucontrol[1] &  alucontrol[0]);

  // Overflow con signo: ocurre cuando los signos de los operandos son iguales
  // pero el signo del resultado difiere
  assign v = ~(alucontrol[0] ^ a[31] ^ b[31]) & (a[31] ^ sum[31]) & isAddSub;

  // Selección del resultado
  reg [31:0] result_reg;
  assign result = result_reg;

  always @* case (alucontrol)
    3'b000:  result_reg = sum;                          // ADD  (add, addi, lw, sw)
    3'b001:  result_reg = sum;                          // SUB  (sub, branches)
    3'b010:  result_reg = a & b;                        // AND  (and, andi)
    3'b011:  result_reg = a | b;                        // OR   (or, ori)
    3'b100:  result_reg = a ^ b;                        // XOR  (xor, xori)
    3'b101:  result_reg = {{31{1'b0}}, (sum[31] ^ v)};  // SLT  (slt, slti): 1 si a < b (signed)
    3'b110:  result_reg = a << b[4:0];                  // SLL  (sll, slli)
    3'b111:  result_reg = ShiftArith                    // SRL/SRA:
               ? ($signed(a) >>> b[4:0])                //   sra/srai (aritmético, extiende signo)
               : (a >> b[4:0]);                         //   srl/srli (lógico, rellena con 0)
    default: result_reg = 32'b0;  // ALUControl desconocido: resultado 0 (no X)
  endcase

  // Flags de salida
  assign zero = (result == 32'b0);   // beq/bne usan este flag
  assign neg  = result[31];          // blt/bge usan este flag (resultado de SUB)

endmodule