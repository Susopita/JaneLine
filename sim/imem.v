// imem.v -- Memoria de instrucciones (solo lectura)
//
// Soporte para instrucciones comprimidas de 16 bits:
//   a[1]=0 -> lectura alineada a palabra (caso normal)
//   a[1]=1 -> lectura cruzada: mitad superior de la palabra actual
//             concatenada con mitad inferior de la siguiente.

module imem(input  [31:0] a,
            output [31:0] rd);

  reg [31:0] RAM[0:127];
  reg [1023:0] mem_file;

  initial begin
      if ($value$plusargs("MEM_FILE=%s", mem_file))
          $readmemh(mem_file, RAM);
      else begin
          $display("ERROR: No se especifico MEM_FILE");
          $finish;
      end
  end

  assign rd = a[1]
    ? { ((a[31:2] < 127) ? RAM[a[31:2] + 1][15:0] : 16'b0), RAM[a[31:2]][31:16] }
    : RAM[a[31:2]];

endmodule