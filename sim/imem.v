// imem.v - Memoria de Instrucciones (simulación)
// Soporta instrucciones comprimidas (alineación a half-word).
module imem(input  [31:0] a,
            output [31:0] rd);

  reg [31:0] RAM[0:127];
  reg [1023:0] mem_file;

  initial begin
      if ($value$plusargs("mem_file=%s", mem_file)) begin
          $display("Loading instruction memory from: %0s", mem_file);
          $readmemh(mem_file, RAM);
      end else begin
          $display("Loading default instruction memory (prog6_fibonacci_32b.mem)");
          $readmemh("prog6_fibonacci_32b.mem", RAM);
      end
  end

  // Lectura con alineación a half-word (protege frontera de word)
  assign rd = a[1]
    ? { ((a[31:2] < 127) ? RAM[a[31:2] + 1][15:0] : 16'b0), RAM[a[31:2]][31:16] }
    : RAM[a[31:2]];

endmodule