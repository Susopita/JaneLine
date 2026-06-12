module testbench;
  reg          clk;
  reg          reset;
  wire [31:0]  WriteData;
  wire [31:0]  DataAdr;
  wire         MemWrite;
  
  // configurable expectations
  reg [31:0] expected_addr;
  reg [31:0] expected_data;
  integer    max_cycles;
  integer    cycle_count;
  reg        allow_all_writes;

  // instantiate device to be tested
  top dut(
    .clk(clk), 
    .reset(reset), 
    .WriteData(WriteData), 
    .DataAdr(DataAdr), 
    .MemWrite(MemWrite)
  );

  // initialize test
  initial begin
    $dumpfile("sim.vcd");
    $dumpvars(0, testbench);
    
    // load simulation arguments
    if (!$value$plusargs("expected_addr=%d", expected_addr)) expected_addr = 100;
    if (!$value$plusargs("expected_data=%d", expected_data)) expected_data = 25;
    if (!$value$plusargs("max_cycles=%d", max_cycles)) max_cycles = 1000;
    if (!$value$plusargs("allow_all_writes=%d", allow_all_writes)) allow_all_writes = 0;
    cycle_count = 0;

    $display("Test configurations:");
    $display(" - expected_addr   = %0d", expected_addr);
    $display(" - expected_data   = %0d", expected_data);
    $display(" - max_cycles      = %0d", max_cycles);
    $display(" - allow_all_write = %0b", allow_all_writes);

    reset = 1; # 22;
    reset = 0;
  end

  // generate clock to sequence tests
  always begin
    clk = 1;
    # 5; clk = 0; # 5;
  end

  // cycle counter and timeout check
  always @(posedge clk) begin
    if (!reset) begin
      cycle_count = cycle_count + 1;
      if (cycle_count >= max_cycles) begin
        $display("Simulation timeout after %0d cycles", max_cycles);
        $finish;
      end
    end
  end

  // check results
  always @(negedge clk) begin
    if (MemWrite) begin
      if (DataAdr === expected_addr & WriteData === expected_data) begin
        $display("Simulation succeeded at cycle %0d (Addr: %0d, Data: %0d)", cycle_count, DataAdr, WriteData);
        $finish;
      end else if (!allow_all_writes & DataAdr !== 96) begin
        $display("Simulation failed at cycle %0d (Addr: %0d, Data: %0d, expected %0d => %0d)", cycle_count, DataAdr, WriteData, expected_addr, expected_data);
        $finish;
      end
    end
  end
endmodule