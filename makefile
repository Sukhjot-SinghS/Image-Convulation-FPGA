# ======================================================================
# MASTER SoC MAKEFILE
# Run all software compilation and hardware simulations from here!
# ======================================================================

# Define your exact folder paths
HW_DIR = hardware/cpu
SW_DIR = software/mem_generator

# List of all your test programs
PROGRAMS = fib addition filter_switch hw_conv_mmio mul_div_test sw_conv unified_conv

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
	@echo "   make hw_conv_mmio    - HW DSP convolution daemon (all filters)"
	@echo "   make sw_conv         - SW CPU convolution daemon (all filters)"
	@echo "   make unified_conv    - GOD MODE: HW + SW in one firmware (use this!)"
	@echo "   make mul_div_test"
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