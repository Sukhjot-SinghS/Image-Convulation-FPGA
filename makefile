# ======================================================================
# MASTER SoC MAKEFILE
# Run all software compilation and hardware simulations from here!
# ======================================================================

# Define your exact folder paths
HW_DIR = hardware/cpu
SW_DIR = software/mem_generator

# List of all your test programs
PROGRAMS = fib addition filter_switch hw_conv_mmio mul_div_test sw_blur sw_gaussian_blur sw_sobel sw_master

.PHONY: help clean $(PROGRAMS)

help:
	@echo "==========================================================="
	@echo " FPGA SoC Master Controller"
	@echo "==========================================================="
	@echo " Usage: make <program_name>"
	@echo ""
	@echo " Available programs:"
	@echo "   make fib"
	@echo "   make addition"
	@echo "   make filter_switch"
	@echo "   make hw_conv_mmio"
	@echo "   make mul_div_test"
	@echo "   make sw_blur"
	@echo "   make sw_gaussian_blur"
	@echo "   make sw_sobel"
	@echo "   make sw_master"
	@echo ""
	@echo " Utilities:"
	@echo "   make clean    - Wipes all compiled files and simulation logs"
	@echo "==========================================================="

# The Magic Route: This passes whatever you typed down to the Hardware Makefile
$(PROGRAMS):
	@echo ">>> 1. INITIALIZING MASTER BUILD FOR: $@"
	@$(MAKE) -C $(HW_DIR) $@

clean:
	@echo ">>> Wiping Software Directory..."
	@$(MAKE) -C $(SW_DIR) clean
	@echo ">>> Wiping Hardware Directory..."
	@$(MAKE) -C $(HW_DIR) clean
	@echo ">>> Project completely cleaned!"