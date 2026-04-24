#include <stdint.h>

// Hardware Accelerator MMIO Addresses
#define HW_KERNEL_BASE  ((volatile uint32_t*)0x80000000)
#define HW_CMD_START    (*(volatile uint32_t*)0x80000024)
#define HW_STATUS_DONE  (*(volatile uint32_t*)0x80000028)
#define HW_NORM_EN      (*(volatile uint32_t*)0x80000030)
#define SW_DONE_REG     (*(volatile uint32_t*)0x80000034)
#define HW_IMG_READY_ADDR ((volatile uint32_t*)0x80000038)
#define BENCHMARK_FLAG  (*(volatile uint32_t*)0x00000F00) 

volatile int8_t gaussian_blur[9] = { 1,  2,  1, 
                                     2,  4,  2, 
                                     1,  2,  1};

// EXTREME PIPELINE SHIELD POLL MACRO
// Your RISC-V pipeline inherently executes 2 instructions AFTER a branch is taken (No branch flush!)
// If we use C loops, it executes the upcoming initialization code which corrupts the loop's own pointers!
// This pure-assembly macro forces `nop`s into the delay slots so the processor safely spins!
#define POLL_DOORBELL(addr) \
    __asm__ volatile ( \
        "1:\n\t" \
        "lw zero, 0(%0)\n\t" \
        "lw t0, 0(%0)\n\t" \
        "beqz t0, 1b\n\t" \
        "nop\n\t" \
        "nop\n\t" \
        : : "r" (addr) : "t0", "memory" \
    )

int main() {
    // 1. PERFECT SYNC: Safely wait for UART load completion
    POLL_DOORBELL(HW_IMG_READY_ADDR);

    // 2. Initialize Hardware Parameters
    HW_NORM_EN = 1; // Enable normalization (divide by 8)
    
    for (int i = 0; i < 9; i++) {
        HW_KERNEL_BASE[i] = (uint32_t)gaussian_blur[i];
    }

    // 3. START TIMER FLAG
    BENCHMARK_FLAG = 0x11111111; 

    // 4. Trigger Hardware Accelerator
    HW_CMD_START = 1;
    HW_CMD_START = 0; 

    // 5. PERFECT SYNC: Safely wait for execution completion
    POLL_DOORBELL(&HW_STATUS_DONE);

    // 6. STOP TIMER FLAG
    BENCHMARK_FLAG = 0x99999999; 

    // Windows OS PySerial Buffer Fix: Pause CPU so Python can transition
    // its GUI state seamlessly into blocking serial.read(15880) without the USB
    // driver overflowing its 4KB/8KB buffers from a 100% duty cycle blast.
    __asm__ volatile (
        "li t0, 50000\n\t"
        "1:\n\t"
        "addi t0, t0, -1\n\t"
        "bnez t0, 1b\n\t"
        ::: "t0"
    );

    // 7. START UART TRANSMISSION
    SW_DONE_REG = 1;

    // Safely halt CPU
    while(1) {}
    return 0;
}
