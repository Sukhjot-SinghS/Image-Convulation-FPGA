CC      = riscv-none-elf-gcc
AR      = riscv-none-elf-ar
OBJDUMP = riscv-none-elf-objdump
OBJCOPY = riscv-none-elf-objcopy
READELF = riscv-none-elf-readelf


CFLAGS = -march=rv32im -mabi=ilp32 -ffreestanding -O1 -Wall
# Add linker flags to use your link.ld script
LDFLAGS = -nostdlib -T link.ld


SRC_FIB      = code_fib.c
SRC_ADDITION = code_addition.c
SRC_FSW = filter_switch.c
SRC_MMIO = hw_conv_mmio.c
SRC_MULDIV = mul_div_test.c
SRC_BLUR = sw_blur.c
SRC_GAU_BLUR = sw_gaussian_blur.c
SRC_SOBEL = sw_sobel.c
SRC_MASTER = sw_master.c


TARGET   = code.elf
OUT_DIR  = ./imem_dmem

.PHONY: all clean

fib: $(SRC_FIB) start.S
	$(CC) $(CFLAGS) start.S $(SRC_FIB) -o $(TARGET) $(LDFLAGS)
	$(OBJCOPY) -O binary $(TARGET) ./imem_dmem/imem.bin
	$(OBJCOPY) -j .data -O binary $(TARGET) ./imem_dmem/dmem.bin
	$(OBJDUMP) -d $(TARGET) > ./imem_dmem/code.dis
	cd imem_dmem && python bin2hex.py
	@echo "NEW STEP: Copy the results to the Hardware directory"
	cp ./imem_dmem/imem.hex ../../hardware/cpu/imem.hex
	cp ./imem_dmem/dmem.hex ../../hardware/cpu/dmem.hex
	@echo "Hex files synchronized to Hardware directory!"


addition: $(SRC_ADDITION) start.S
	$(CC) $(CFLAGS) start.S $(SRC_ADDITION) -o $(TARGET) $(LDFLAGS)
	$(OBJCOPY) -O binary $(TARGET) ./imem_dmem/imem.bin
	$(OBJCOPY) -j .data -O binary $(TARGET) ./imem_dmem/dmem.bin
	$(OBJDUMP) -d $(TARGET) > ./imem_dmem/code.dis
	cd imem_dmem && python bin2hex.py
	@echo "NEW STEP: Copy the results to the Hardware directory"
	cp ./imem_dmem/imem.hex ../../hardware/cpu/imem.hex
	cp ./imem_dmem/dmem.hex ../../hardware/cpu/dmem.hex
	@echo "Hex files synchronized to Hardware directory!"


filter_switch: $(SRC_FSW) start.S
	$(CC) $(CFLAGS) start.S $(SRC_FSW) -o $(TARGET) $(LDFLAGS)
	$(OBJCOPY) -O binary $(TARGET) ./imem_dmem/imem.bin
	$(OBJCOPY) -j .data -O binary $(TARGET) ./imem_dmem/dmem.bin
	$(OBJDUMP) -d $(TARGET) > ./imem_dmem/code.dis
	cd imem_dmem && python bin2hex.py
	@echo "NEW STEP: Copy the results to the Hardware directory"
	cp ./imem_dmem/imem.hex ../../hardware/cpu/imem.hex
	cp ./imem_dmem/dmem.hex ../../hardware/cpu/dmem.hex
	@echo "Hex files synchronized to Hardware directory!"


hw_conv_mmio: $(SRC_MMIO) start.S
	$(CC) $(CFLAGS) start.S $(SRC_MMIO) -o $(TARGET) $(LDFLAGS)
	$(OBJCOPY) -O binary $(TARGET) ./imem_dmem/imem.bin
	$(OBJCOPY) -j .data -j .bss -O binary $(TARGET) ./imem_dmem/dmem.bin
	$(OBJDUMP) -d $(TARGET) > ./imem_dmem/code.dis
	cd imem_dmem && python bin2hex.py
	@echo "NEW STEP: Copy the results to the Hardware directory"
	cp ./imem_dmem/imem.hex ../../hardware/cpu/imem.hex
	cp ./imem_dmem/dmem.hex ../../hardware/cpu/dmem.hex
	@echo "Hex files synchronized to Hardware directory!"


mul_div_test: $(SRC_MULDIV) start.S
	$(CC) $(CFLAGS) start.S $(SRC_MULDIV) -o $(TARGET) $(LDFLAGS)
	$(OBJCOPY) -O binary $(TARGET) ./imem_dmem/imem.bin
	$(OBJCOPY) -j .data -O binary $(TARGET) ./imem_dmem/dmem.bin
	$(OBJDUMP) -d $(TARGET) > ./imem_dmem/code.dis
	cd imem_dmem && python bin2hex.py
	@echo "NEW STEP: Copy the results to the Hardware directory"
	cp ./imem_dmem/imem.hex ../../hardware/cpu/imem.hex
	cp ./imem_dmem/dmem.hex ../../hardware/cpu/dmem.hex
	@echo "Hex files synchronized to Hardware directory!"


sw_blur: $(SRC_BLUR) start.S
	$(CC) $(CFLAGS) start.S $(SRC_BLUR) -o $(TARGET) $(LDFLAGS)
	$(OBJCOPY) -O binary $(TARGET) ./imem_dmem/imem.bin
	$(OBJCOPY) -j .data -O binary $(TARGET) ./imem_dmem/dmem.bin
	$(OBJDUMP) -d $(TARGET) > ./imem_dmem/code.dis
	cd imem_dmem && python bin2hex.py
	@echo "NEW STEP: Copy the results to the Hardware directory"
	cp ./imem_dmem/imem.hex ../../hardware/cpu/imem.hex
	cp ./imem_dmem/dmem.hex ../../hardware/cpu/dmem.hex
	@echo "Hex files synchronized to Hardware directory!"


sw_gaussian_blur: $(SRC_GAU_BLUR) start.S
	$(CC) $(CFLAGS) start.S $(SRC_GAU_BLUR) -o $(TARGET) $(LDFLAGS)
	$(OBJCOPY) -O binary $(TARGET) ./imem_dmem/imem.bin
	$(OBJCOPY) -j .data -j .bss -O binary $(TARGET) ./imem_dmem/dmem.bin
	$(OBJDUMP) -d $(TARGET) > ./imem_dmem/code.dis
	cd imem_dmem && python bin2hex.py
	@echo "NEW STEP: Copy the results to the Hardware directory"
	cp ./imem_dmem/imem.hex ../../hardware/cpu/imem.hex
	cp ./imem_dmem/dmem.hex ../../hardware/cpu/dmem.hex
	@echo "Hex files synchronized to Hardware directory!"


sw_sobel: $(SRC_SOBEL) start.S
	$(CC) $(CFLAGS) start.S $(SRC_SOBEL) -o $(TARGET) $(LDFLAGS)
	$(OBJCOPY) -O binary $(TARGET) ./imem_dmem/imem.bin
	$(OBJCOPY) -j .data -j .bss -O binary $(TARGET) ./imem_dmem/dmem.bin
	$(OBJDUMP) -d $(TARGET) > ./imem_dmem/code.dis
	cd imem_dmem && python bin2hex.py
	@echo "NEW STEP: Copy the results to the Hardware directory"
	cp ./imem_dmem/imem.hex ../../hardware/cpu/imem.hex
	cp ./imem_dmem/dmem.hex ../../hardware/cpu/dmem.hex
	@echo "Hex files synchronized to Hardware directory!"


sw_master: $(SRC_MASTER) start.S
	$(CC) $(CFLAGS) start.S $(SRC_MASTER) -o $(TARGET) $(LDFLAGS)
	$(OBJCOPY) -O binary $(TARGET) ./imem_dmem/imem.bin
	$(OBJCOPY) -j .data -j .bss -O binary $(TARGET) ./imem_dmem/dmem.bin
	$(OBJDUMP) -d $(TARGET) > ./imem_dmem/code.dis
	cd imem_dmem && python bin2hex.py
	@echo "NEW STEP: Copy the results to the Hardware directory"
	cp ./imem_dmem/imem.hex ../../hardware/cpu/imem.hex
	cp ./imem_dmem/dmem.hex ../../hardware/cpu/dmem.hex
	@echo "Hex files synchronized to Hardware directory!"


clean:
	$(RM) $(TARGET) ./imem_dmem/imem.bin ./imem_dmem/imem.hex ./imem_dmem/dmem.bin ./imem_dmem/dmem.hex ./imem_dmem/code.dis
