# Constraints template for RISC-V physical implementation on FPGA (e.g., Basys 3 / Artix-7)

# Clock signal (100 MHz)
set_property -dict { PACKAGE_PIN W5   IOSTANDARD LVCMOS33 } [get_ports clk]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk]

# Reset Button (active high)
set_property -dict { PACKAGE_PIN U18   IOSTANDARD LVCMOS33 } [get_ports reset]

# Outputs (example of mapping WriteData, DataAdr, MemWrite to LEDs/peripherals)
# set_property -dict { PACKAGE_PIN U16   IOSTANDARD LVCMOS33 } [get_ports {WriteData[0]}]
# set_property -dict { PACKAGE_PIN E19   IOSTANDARD LVCMOS33 } [get_ports {WriteData[1]}]
# set_property -dict { PACKAGE_PIN L1    IOSTANDARD LVCMOS33 } [get_ports MemWrite]
