module dmem(input  clk, we,
            input  [31:0] a, wd,
            output [31:0] rd);
  
  reg [31:0] RAM[0:127]; 

  assign rd = RAM[a[31:2]]; // word aligned

  always @(posedge clk) begin 
    if (we) RAM[a[31:2]] <= wd; 
  end
endmodule