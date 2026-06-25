module imem(input  [31:0] a,
            output [31:0] rd);
  
  reg [31:0] RAM[0:127]; 
  reg [1023:0] mem_file;

  initial begin
      if ($value$plusargs("mem_file=%s", mem_file)) begin
          $display("Loading instruction memory from: %0s", mem_file);
          $readmemh(mem_file, RAM);
      end else begin
          $display("Loading default instruction memory (prog4_flushing.mem)");
          $readmemh("prog4_flushing.mem", RAM);
      end
  end

  // Soporte para lectura alineada a half-word (16 bits)
  // Si a[1] == 1, la dirección no está alineada a palabra (32 bits),
  // por lo que concatenamos la mitad superior del offset actual con la mitad inferior del offset+1.
  assign rd = a[1] ? { ((a[31:2] < 127) ? RAM[a[31:2] + 1][15:0] : 16'b0), RAM[a[31:2]][31:16] } : RAM[a[31:2]];
endmodule