// =============================================================================
// imem.v  –  Memoria de Instrucciones (Read-Only, para simulación)
//
// Soporte para instrucciones de 16 bits (Extensión C):
//   La memoria está organizada en palabras de 32 bits, pero el PC puede
//   apuntar a direcciones no alineadas a 4 bytes (alineadas a 2 bytes).
//
//   Caso 1: PC[1] == 0 (dirección alineada a palabra)
//     → La instrucción completa está en una sola palabra de RAM.
//     → rd = RAM[PC[31:2]]
//
//     Memoria:      |  word N  |
//     Bits:         [31:16] [15:0]
//                      ↑ posible 16b   ↑ posible 16b
//                   También puede ser una instrucción de 32b completa.
//
//   Caso 2: PC[1] == 1 (dirección alineada a half-word, NO a palabra)
//     → La instrucción cruza la frontera entre dos palabras consecutivas.
//     → Los 16 bits inferiores vienen de la mitad SUPERIOR de la palabra actual.
//     → Los 16 bits superiores vienen de la mitad INFERIOR de la palabra siguiente.
//     → rd = { RAM[word+1][15:0], RAM[word][31:16] }
//
//     Memoria:      |  word N  |  word N+1  |
//     Bits:         [31:16] [15:0] [31:16] [15:0]
//                      ↑ bits bajos del fetch   ↑ bits altos del fetch
// =============================================================================
module imem(input  [31:0] a,
            output [31:0] rd);

  reg [31:0] RAM[0:127];
  reg [1023:0] mem_file;

  initial begin
      if ($value$plusargs("mem_file=%s", mem_file)) begin
          $display("Loading instruction memory from: %0s", mem_file);
          $readmemh(mem_file, RAM);
      end else begin
          $display("Loading default instruction memory (prog5_compressed.mem)");
          $readmemh("prog5_compressed.mem", RAM);
      end
  end

  // -------------------------------------------------------------------------
  // Lectura con alineación a half-word
  //   a[31:2] = índice de palabra (word offset)
  //   a[1]    = selector de half-word:
  //     0 → lectura alineada (una sola palabra)
  //     1 → lectura cruzada  (mitad superior actual + mitad inferior siguiente)
  //
  // Protección de frontera: si el índice actual es el último (127), no se
  // accede a la palabra siguiente (se rellena con ceros).
  // -------------------------------------------------------------------------
  assign rd = a[1]
    ? { ((a[31:2] < 127) ? RAM[a[31:2] + 1][15:0] : 16'b0), RAM[a[31:2]][31:16] }
    : RAM[a[31:2]];

endmodule