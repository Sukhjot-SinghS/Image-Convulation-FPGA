# Makefile for UART Section Verification

# Variables
SIM_SNAPSHOT = uart_sim
VCD_FILE = uart_test.vcd
TOP_TB_MODULE = tb_uart

all: simulate

simulate:
	@echo "=== STEP 1: Compiling UART Verilog Files ==="
	xvlog uart_rx.v uart_tx.v uart_to_bram_ctrl.v top_uart.v tb_uart.v
	
	@echo "=== STEP 2: Elaborating Testbench ==="
	xelab -top $(TOP_TB_MODULE) -snapshot $(SIM_SNAPSHOT) -debug typical
	
	@echo "=== STEP 3: Running Simulation ==="
	xsim $(SIM_SNAPSHOT) -R
	
	@echo "=== STEP 4: Launching GTKWave ==="
	gtkwave $(VCD_FILE) &

clean:
	@echo "Cleaning up simulation files..."
	rm -rf xsim.dir/ .Xil/
	rm -f *.log *.jou *.pb *.vcd