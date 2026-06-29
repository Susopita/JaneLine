// mux4.v – Multiplexor 4 entradas parametrizable
// Usado en la etapa WB para seleccionar entre:
//   d0 = ALUResult, d1 = ReadData, d2 = PC+4, d3 = ImmExt (LUI)
module mux4 #(parameter WIDTH = 8)
             (input  [WIDTH-1:0] d0, d1, d2, d3,
              input  [1:0]       s,
              output [WIDTH-1:0] y);

  assign y = s[1] ? (s[0] ? d3 : d2)
                  : (s[0] ? d1 : d0);

endmodule
