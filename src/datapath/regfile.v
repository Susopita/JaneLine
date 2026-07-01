// regfile.v  –  Register File RISC-V 32x32
module regfile(input  clk,
               input  we3,
               input  [ 4:0] a1, a2, a3,
               input  [31:0] wd3,
               output [31:0] rd1, rd2);

  reg [31:0] rf[31:0];

  // Escritura en flanco NEGATIVO: el dato de WB llega estable antes de la
  // lectura combinacional que ocurre después del flanco positivo de ID.
  always @(negedge clk) begin
    if (we3) rf[a3] <= wd3;
  end

  // Lecturas combinacionales con bypass interno:
  // Si se lee y escribe el mismo registro no-cero en el mismo ciclo,
  // se adelanta el dato de escritura directamente.
  assign rd1 = (a1 != 0) ? ((we3 && (a1 == a3)) ? wd3 : rf[a1]) : 32'b0;
  assign rd2 = (a2 != 0) ? ((we3 && (a2 == a3)) ? wd3 : rf[a2]) : 32'b0;

endmodule