# # Toolchain prefix (adjust based on your Lab's installation)
# # RV_CC = riscv64-unknown-elf-gcc
# # CC = riscv64-none-elf-gcc
# # # RV_OBJCOPY = riscv64-unknown-elf-objcopy
# # OBJCOPY = riscv64-none-elf-objcopy

# # # extra -->
# # CROSS_COMPILE = riscv32-none-elf-
# # # <-- extra

# CC      = riscv-none-elf-gcc
# AR      = riscv-none-elf-ar
# OBJDUMP = riscv-none-elf-objdump
# OBJCOPY = riscv-none-elf-objcopy
# READELF = riscv-none-elf-readelf


# # # CFLAGS = -march=rv32i -mabi=ilp32 -nostdlib -Ttext 0x00000000
# # CFLAGS  = -march=rv32i -mabi=ilp32


# # extra -->
# # Change from -march=rv32i to -march=rv32im
# CFLAGS = -march=rv32im -mabi=ilp32 -ffreestanding -O0 -Wall
# # Add linker flags to use your link.ld script
# LDFLAGS = -nostdlib -T link.ld
# # <-- extra


# # # Architecture Flags
# # # -march=rv32im: Enables Shaurya's Multiply/Divide hardware [cite: 316]
# # CFLAGS  = -march=rv32im -mabi=ilp32 -ffreestanding -O2 -Wall
# # LDFLAGS = -nostdlib -T link.ld


# SRC_FIB      = code_fib.c
# SRC_ADDITION = code_addition.c
# SRC_FSW = filter_switch.c
# SRC_MMIO = hw_conv_mmio.c
# SRC_MULDIV = mul_div_test.c
# SRC_BLUR = sw_blur.c
# SRC_GAU_BLUR = sw_gaussian_blur.c


# # # extra -->
# # # Directories
# # SRC_DIR = src
# # HEX_DIR = hex
# # BIN_DIR = bin
# # # <-- extra

# TARGET   = code.elf

# # extra -->
# OUT_DIR = ./imem_dmem
# # <-- extra

# .PHONY: all clean

# # fib:
# # 	# 1. Compile C to ELF
# # 	$(RV_CC) $(CFLAGS) code_fib.c -o code.elf
# # 	# 2. Extract raw binary/hex
# # 	$(RV_OBJCOPY) -O verilog code.elf imem.hex
# # 	# 3. Move to simulation folder
# # 	cp imem.hex ../../hardware/cpu/tb/
# # 	@echo "Fibonacci hex generated and moved to simulation folder."

# fib: $(SRC_FIB)
# 	$(CC) -c  $(SRC_FIB) -o $(TARGET) $(CFLAGS)
# 	$(OBJCOPY) -O binary $(TARGET) ./imem_dmem/imem.bin
# 	$(OBJCOPY) -j .data -O binary $(TARGET) ./imem_dmem/dmem.bin
# 	$(OBJDUMP) -d $(TARGET) > ./imem_dmem/code.dis
# 	cd imem_dmem && python bin2hex.py

# 	@echo NEW STEP: Copy the results to the Hardware directory
# 	cp ./imem_dmem/imem.hex ../../hardware/cpu/imem.hex
# 	cp ./imem_dmem/dmem.hex ../../hardware/cpu/dmem.hex
# 	@echo "Hex files synchronized to Hardware directory!"


# addition: $(SRC_ADDITION)
# 	$(CC) -c  $(SRC_ADDITION) -o $(TARGET) $(CFLAGS)
# 	$(OBJCOPY) -O binary $(TARGET) ./imem_dmem/imem.bin
# 	$(OBJCOPY) -j .data -O binary $(TARGET) ./imem_dmem/dmem.bin
# 	$(OBJDUMP) -d $(TARGET) > ./imem_dmem/code.dis
# 	cd imem_dmem && python bin2hex.py

# 	@echo NEW STEP: Copy the results to the Hardware directory
# 	cp ./imem_dmem/imem.hex ../../hardware/cpu/imem.hex
# 	cp ./imem_dmem/dmem.hex ../../hardware/cpu/dmem.hex
# 	@echo "Hex files synchronized to Hardware directory!"


# filter_switch: $(SRC_FSW)
# 	$(CC) -c  $(SRC_FSW) -o $(TARGET) $(CFLAGS)
# 	$(OBJCOPY) -O binary $(TARGET) ./imem_dmem/imem.bin
# 	$(OBJCOPY) -j .data -O binary $(TARGET) ./imem_dmem/dmem.bin
# 	$(OBJDUMP) -d $(TARGET) > ./imem_dmem/code.dis
# 	cd imem_dmem && python bin2hex.py

# 	@echo NEW STEP: Copy the results to the Hardware directory
# 	cp ./imem_dmem/imem.hex ../../hardware/cpu/imem.hex
# 	cp ./imem_dmem/dmem.hex ../../hardware/cpu/dmem.hex
# 	@echo "Hex files synchronized to Hardware directory!"


# hw_conv_mmio: $(SRC_MMIO)
# 	$(CC) -c  $(SRC_MMIO) -o $(TARGET) $(CFLAGS)
# 	$(OBJCOPY) -O binary $(TARGET) ./imem_dmem/imem.bin
# 	$(OBJCOPY) -j .data -O binary $(TARGET) ./imem_dmem/dmem.bin
# 	$(OBJDUMP) -d $(TARGET) > ./imem_dmem/code.dis
# 	cd imem_dmem && python bin2hex.py

# 	@echo NEW STEP: Copy the results to the Hardware directory
# 	cp ./imem_dmem/imem.hex ../../hardware/cpu/imem.hex
# 	cp ./imem_dmem/dmem.hex ../../hardware/cpu/dmem.hex
# 	@echo "Hex files synchronized to Hardware directory!"


# mul_div_test: $(SRC_MULDIV)
# 	$(CC) -c  $(SRC_MULDIV) -o $(TARGET) $(CFLAGS)
# 	$(OBJCOPY) -O binary $(TARGET) ./imem_dmem/imem.bin
# 	$(OBJCOPY) -j .data -O binary $(TARGET) ./imem_dmem/dmem.bin
# 	$(OBJDUMP) -d $(TARGET) > ./imem_dmem/code.dis
# 	cd imem_dmem && python bin2hex.py

# 	@echo NEW STEP: Copy the results to the Hardware directory
# 	cp ./imem_dmem/imem.hex ../../hardware/cpu/imem.hex
# 	cp ./imem_dmem/dmem.hex ../../hardware/cpu/dmem.hex
# 	@echo "Hex files synchronized to Hardware directory!"


# sw_blur: $(SRC_BLUR)
# 	$(CC) -c  $(SRC_BLUR) -o $(TARGET) $(CFLAGS)
# 	$(OBJCOPY) -O binary $(TARGET) ./imem_dmem/imem.bin
# 	$(OBJCOPY) -j .data -O binary $(TARGET) ./imem_dmem/dmem.bin
# 	$(OBJDUMP) -d $(TARGET) > ./imem_dmem/code.dis
# 	cd imem_dmem && python bin2hex.py

# 	@echo NEW STEP: Copy the results to the Hardware directory
# 	cp ./imem_dmem/imem.hex ../../hardware/cpu/imem.hex
# 	cp ./imem_dmem/dmem.hex ../../hardware/cpu/dmem.hex
# 	@echo "Hex files synchronized to Hardware directory!"


# sw_gaussian_blur: $(SRC_GAU_BLUR)
# 	$(CC) -c $(CFLAGS) sw_gaussian_blur.c -o code.elf $(LDFLAGS)
# 	$(OBJCOPY) -O binary code.elf ./imem_dmem/imem.bin
# 	$(OBJCOPY) -j .data -j .bss -O binary code.elf ./imem_dmem/dmem.bin
# 	$(OBJDUMP) -d code.elf > ./imem_dmem/code.dis
# 	cd imem_dmem && python bin2hex.py

# 	@echo NEW STEP: Copy the results to the Hardware directory
# 	cp ./imem_dmem/imem.hex ../../hardware/cpu/imem.hex
# 	cp ./imem_dmem/dmem.hex ../../hardware/cpu/dmem.hex
# 	@echo "Hex files synchronized to Hardware directory!"


# # /////clean function
# clean:
# 	$(RM) $(TARGET) ./imem_dmem/imem.bin ./imem_dmem/imem.hex ./imem_dmem/dmem.bin ./imem_dmem/dmem.hex ./imem_dmem/code.dis

# Toolchain prefix (adjust based on your Lab's installation)
# RV_CC = riscv64-unknown-elf-gcc
# CC = riscv64-none-elf-gcc
# # RV_OBJCOPY = riscv64-unknown-elf-objcopy
# OBJCOPY = riscv64-none-elf-objcopy

# # extra -->
# CROSS_COMPILE = riscv32-none-elf-
# # <-- extra

CC      = riscv-none-elf-gcc
AR      = riscv-none-elf-ar
OBJDUMP = riscv-none-elf-objdump
OBJCOPY = riscv-none-elf-objcopy
READELF = riscv-none-elf-readelf


# # CFLAGS = -march=rv32i -mabi=ilp32 -nostdlib -Ttext 0x00000000
# CFLAGS  = -march=rv32i -mabi=ilp32


# extra -->
# Change from -march=rv32i to -march=rv32im
CFLAGS = -march=rv32im -mabi=ilp32 -ffreestanding -O1 -Wall
# Add linker flags to use your link.ld script
LDFLAGS = -nostdlib -T link.ld
# <-- extra


# # Architecture Flags
# # -march=rv32im: Enables Shaurya's Multiply/Divide hardware
# CFLAGS  = -march=rv32im -mabi=ilp32 -ffreestanding -O2 -Wall
# LDFLAGS = -nostdlib -T link.ld


SRC_FIB      = code_fib.c
SRC_ADDITION = code_addition.c
SRC_FSW = filter_switch.c
SRC_MMIO = hw_conv_mmio.c
SRC_SW_CONV  = sw_conv_mmio.c
SRC_UNIFIED  = unified_conv.c
SRC_MULDIV = mul_div_test.c


# # extra -->
# # Directories
# SRC_DIR = src
# HEX_DIR = hex
# BIN_DIR = bin
# # <-- extra

TARGET   = code.elf

# extra -->
OUT_DIR = ./imem_dmem
# <-- extra

.PHONY: all clean sw_conv hw_conv_mmio unified_conv

fib: $(SRC_FIB) start.S
	$(CC) $(CFLAGS) start.S $(SRC_FIB) -o $(TARGET) $(LDFLAGS)
	$(OBJCOPY) -O binary $(TARGET) ./imem_dmem/imem.bin
	$(OBJCOPY) -j .data -O binary $(TARGET) ./imem_dmem/dmem.bin
	$(OBJDUMP) -d $(TARGET) > ./imem_dmem/code.dis
	cd imem_dmem && python bin2hex.py
	@echo "NEW STEP: Copy the results to the Hardware directory"
	copy /Y .\imem_dmem\imem.hex ..\..\hardware\cpu\imem.hex
	copy /Y .\imem_dmem\dmem.hex ..\..\hardware\cpu\dmem.hex
	@echo "Hex files synchronized to Hardware directory!"


addition: $(SRC_ADDITION) start.S
	$(CC) $(CFLAGS) start.S $(SRC_ADDITION) -o $(TARGET) $(LDFLAGS)
	$(OBJCOPY) -O binary $(TARGET) ./imem_dmem/imem.bin
	$(OBJCOPY) -j .data -O binary $(TARGET) ./imem_dmem/dmem.bin
	$(OBJDUMP) -d $(TARGET) > ./imem_dmem/code.dis
	cd imem_dmem && python bin2hex.py
	@echo "NEW STEP: Copy the results to the Hardware directory"
	copy /Y .\imem_dmem\imem.hex ..\..\hardware\cpu\imem.hex
	copy /Y .\imem_dmem\dmem.hex ..\..\hardware\cpu\dmem.hex
	@echo "Hex files synchronized to Hardware directory!"


filter_switch: $(SRC_FSW) start.S
	$(CC) $(CFLAGS) start.S $(SRC_FSW) -o $(TARGET) $(LDFLAGS)
	$(OBJCOPY) -O binary $(TARGET) ./imem_dmem/imem.bin
	$(OBJCOPY) -j .data -O binary $(TARGET) ./imem_dmem/dmem.bin
	$(OBJDUMP) -d $(TARGET) > ./imem_dmem/code.dis
	cd imem_dmem && python bin2hex.py
	@echo "NEW STEP: Copy the results to the Hardware directory"
	copy /Y .\imem_dmem\imem.hex ..\..\hardware\cpu\imem.hex
	copy /Y .\imem_dmem\dmem.hex ..\..\hardware\cpu\dmem.hex
	@echo "Hex files synchronized to Hardware directory!"


hw_conv_mmio: $(SRC_MMIO) start.S
	$(CC) $(CFLAGS) start.S $(SRC_MMIO) -o $(TARGET) $(LDFLAGS)
	$(OBJCOPY) -O binary $(TARGET) ./imem_dmem/imem.bin
	$(OBJCOPY) -j .data -j .rodata -j .bss -O binary $(TARGET) .\imem_dmem\dmem.bin
	$(OBJDUMP) -d $(TARGET) > ./imem_dmem/code.dis
	cd imem_dmem && python bin2hex.py
	@echo "NEW STEP: Copy the results to the Hardware directory"
	copy /Y .\imem_dmem\imem.hex ..\..\hardware\cpu\imem.hex
	copy /Y .\imem_dmem\dmem.hex ..\..\hardware\cpu\dmem.hex
	@echo "Hex files synchronized to Hardware directory!"


mul_div_test: $(SRC_MULDIV) start.S
	$(CC) $(CFLAGS) start.S $(SRC_MULDIV) -o $(TARGET) $(LDFLAGS)
	$(OBJCOPY) -O binary $(TARGET) ./imem_dmem/imem.bin
	$(OBJCOPY) -j .data -O binary $(TARGET) ./imem_dmem/dmem.bin
	$(OBJDUMP) -d $(TARGET) > ./imem_dmem/code.dis
	cd imem_dmem && python bin2hex.py
	@echo "NEW STEP: Copy the results to the Hardware directory"
	copy /Y .\imem_dmem\imem.hex ..\..\hardware\cpu\imem.hex
	copy /Y .\imem_dmem\dmem.hex ..\..\hardware\cpu\dmem.hex
	@echo "Hex files synchronized to Hardware directory!"


sw_conv: $(SRC_SW_CONV) start.S
	@echo ">>> Building UNIFIED Software Convolution Daemon (all 6 filters)"
	$(CC) $(CFLAGS) start.S $(SRC_SW_CONV) -o $(TARGET) $(LDFLAGS)
	$(OBJCOPY) -O binary $(TARGET) ./imem_dmem/imem.bin
	$(OBJCOPY) -j .data -j .rodata -j .bss -O binary $(TARGET) .\imem_dmem\dmem.bin
	$(OBJDUMP) -d $(TARGET) > ./imem_dmem/code.dis
	cd imem_dmem && python bin2hex.py
	@echo "NEW STEP: Copy the results to the Hardware directory"
	copy /Y .\imem_dmem\imem.hex ..\..\hardware\cpu\imem.hex
	copy /Y .\imem_dmem\dmem.hex ..\..\hardware\cpu\dmem.hex
	@echo "=== SW firmware ready! Use updatemem or re-flash via Vivado ==="

unified_conv: $(SRC_UNIFIED) start.S
	@echo ">>> Building GOD MODE Unified Firmware (HW + SW loops)"
	$(CC) $(CFLAGS) start.S $(SRC_UNIFIED) -o $(TARGET) $(LDFLAGS)
	$(OBJCOPY) -O binary $(TARGET) ./imem_dmem/imem.bin
	$(OBJCOPY) -j .data -j .rodata -j .bss -O binary $(TARGET) .\imem_dmem\dmem.bin
	$(OBJDUMP) -d $(TARGET) > ./imem_dmem/code.dis
	cd imem_dmem && python bin2hex.py
	@echo "NEW STEP: Copy the results to the Hardware directory"
	copy /Y .\imem_dmem\imem.hex ..\..\hardware\cpu\imem.hex
	copy /Y .\imem_dmem\dmem.hex ..\..\hardware\cpu\dmem.hex
	@echo "=== GOD MODE firmware ready! ==="

test_bram_out: test_bram_out.c start.S
	@echo ">>> Building BRAM_OUT Write Path Diagnostic"
	$(CC) $(CFLAGS) start.S test_bram_out.c -o $(TARGET) $(LDFLAGS)
	$(OBJCOPY) -O binary $(TARGET) ./imem_dmem/imem.bin
	$(OBJCOPY) -j .data -j .rodata -j .bss -O binary $(TARGET) .\imem_dmem\dmem.bin
	$(OBJDUMP) -d $(TARGET) > ./imem_dmem/code.dis
	cd imem_dmem && python bin2hex.py
	@echo "NEW STEP: Copy the results to the Hardware directory"
	copy /Y .\imem_dmem\imem.hex ..\..\hardware\cpu\imem.hex
	copy /Y .\imem_dmem\dmem.hex ..\..\hardware\cpu\dmem.hex
	@echo "=== Test firmware ready! Flash and run with fpga_coprocessor_ui ==="



# /////clean function
clean:
	-del /F /Q $(TARGET) .\imem_dmem\imem.bin .\imem_dmem\imem.hex .\imem_dmem\dmem.bin .\imem_dmem\dmem.hex .\imem_dmem\code.dis
