// extend.v  –  Extensor de Inmediatos RISC-V 32-bit
module extend(
    input  [31:7] instr,
    input  [2:0]  immsrc,    // AMPLIADO a 3 bits (antes era 2)
    output [31:0] immext
);

  reg [31:0] immext_reg;
  assign immext = immext_reg;

  always @* case (immsrc)
    // I-type: lw, I-type ALU, jalr
    3'b000: immext_reg = {{20{instr[31]}}, instr[31:20]};

    // S-type: sw
    3'b001: immext_reg = {{20{instr[31]}}, instr[31:25], instr[11:7]};

    // B-type: beq, bne, blt, bge
    3'b010: immext_reg = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};

    // J-type: jal
    3'b011: immext_reg = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};

    // U-type: lui
    //   Los bits [31:12] de la instrucción van a los bits [31:12] del resultado.
    //   Los 12 bits bajos se rellenan con ceros (ya en el formato de la instrucción).
    3'b100: immext_reg = {instr[31:12], 12'b0};

    default: immext_reg = 32'b0;  // ImmSrc desconocido: salida 0 (no X)
  endcase

endmodule