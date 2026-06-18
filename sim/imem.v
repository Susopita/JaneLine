module imem(input  [31:0] a,
            output [31:0] rd);
  
  reg [31:0] RAM[0:127]; 
  reg [1023:0] mem_file;

  initial begin
      if ($value$plusargs("mem_file=%s", mem_file)) begin
          $display("Loading instruction memory from: %0s", mem_file);
          $readmemh(mem_file, RAM);
      end else begin
          $display("Loading default instruction memory (prog1_isa.mem)");
          $readmemh("C:/My Things/UTEC/26-1/Arch/Proyecto2/JaneLine/sim/tests/prog1_isa.mem", RAM);
      end
  end

  assign rd = RAM[a[31:2]]; // word aligned
endmodule