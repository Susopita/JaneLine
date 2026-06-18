# Makefile para la Simulación del Procesador RISC-V
# Autogenerado por Antigravity

# Herramientas
IVERILOG = iverilog
VVP      = vvp
GTKWAVE  = gtkwave

# Directorios
SRC_DIR  = src
SIM_DIR  = sim
FPGA_DIR = fpga
BUILD_DIR = build

# Archivos de diseño (RTL)
SRCS = $(SRC_DIR)/riscvsingle.v \
       $(SRC_DIR)/controller/controller.v \
       $(SRC_DIR)/controller/maindec.v \
       $(SRC_DIR)/controller/aludec.v \
       $(SRC_DIR)/datapath/datapath.v \
       $(SRC_DIR)/datapath/alu.v \
       $(SRC_DIR)/datapath/regfile.v \
       $(SRC_DIR)/datapath/extend.v \
       $(SRC_DIR)/common/adder.v \
       $(SRC_DIR)/common/flopr.v \
       $(SRC_DIR)/common/mux2.v \
       $(SRC_DIR)/common/mux3.v \
       $(SRC_DIR)/common/mux4.v

# Archivos de simulación e integración
SIM_SRCS = $(SIM_DIR)/testbench.v \
           $(SIM_DIR)/imem.v \
           $(SIM_DIR)/dmem.v \
           $(FPGA_DIR)/top.v

# Archivos de salida
SIM_OUT  = $(BUILD_DIR)/sim.out
VCD_FILE = sim/sim.vcd

.PHONY: all run compile wave clean directories run-test run-all-tests

# Regla por defecto: compilar y ejecutar
all: run

# Crear directorio de compilación
directories:
	mkdir -p $(BUILD_DIR)

# Compilación con iverilog
compile: directories
	$(IVERILOG) -o $(SIM_OUT) -I $(SRC_DIR) -I $(SIM_DIR) -I $(FPGA_DIR) $(SRCS) $(SIM_SRCS)

# Parámetros por defecto para pruebas individuales
TEST_DIR ?= tests
TEST ?= riscvtest.mem
ADDR ?= 100
DATA ?= 25
ALLOW_ALL ?= 0
MAX_CYCLES ?= 1000

# Ejecución de la simulación por defecto (retrocompatibilidad)
run: compile
	cd sim && $(VVP) ../$(SIM_OUT)

# Ejecutar un caso de prueba individual.
# Ejemplo: make run-test TEST=prog1_isa.mem ADDR=100 DATA=25
run-test: compile
	cd sim && $(VVP) ../$(SIM_OUT) +mem_file=$(TEST_DIR)/$(TEST) +expected_addr=$(ADDR) +expected_data=$(DATA) +allow_all_writes=$(ALLOW_ALL) +max_cycles=$(MAX_CYCLES)

# Ejecutar todas las pruebas ordenadamente
run-all-tests: compile
	@echo "=================================================="
	@echo "Iniciando suite de pruebas para procesador RISC-V..."
	@echo "=================================================="
	@echo ""
	@echo "[TEST 1/5] Programa (1): ISA sin dependencias"
	@cd sim && $(VVP) ../$(SIM_OUT) +mem_file=tests/prog1_isa.mem +expected_addr=100 +expected_data=25 +allow_all_writes=0
	@echo "--------------------------------------------------"
	@echo "[TEST 2/5] Programa (2): Forwarding"
	@cd sim && $(VVP) ../$(SIM_OUT) +mem_file=tests/prog2_forwarding.mem +expected_addr=100 +expected_data=25 +allow_all_writes=1
	@echo "--------------------------------------------------"
	@echo "[TEST 3/5] Programa (3): Stalling"
	@cd sim && $(VVP) ../$(SIM_OUT) +mem_file=tests/prog3_stalling.mem +expected_addr=100 +expected_data=25 +allow_all_writes=1
	@echo "--------------------------------------------------"
	@echo "[TEST 4/5] Programa (4): Flushing"
	@cd sim && $(VVP) ../$(SIM_OUT) +mem_file=tests/prog4_flushing.mem +expected_addr=100 +expected_data=25 +allow_all_writes=1
	@echo "--------------------------------------------------"
	@echo "[TEST 5/5] Programa completo (Todos los anteriores)"
	@cd sim && $(VVP) ../$(SIM_OUT) +mem_file=tests/prog_all.mem +expected_addr=100 +expected_data=25 +allow_all_writes=1
	@echo "=================================================="
	@echo "Suite de simulaciones finalizada."
	@echo "=================================================="

# Visualización de ondas con gtkwave
wave: run
	$(GTKWAVE) $(VCD_FILE)

# Limpieza de archivos temporales
clean:
	rm -rf $(BUILD_DIR)
	rm -f $(VCD_FILE)
