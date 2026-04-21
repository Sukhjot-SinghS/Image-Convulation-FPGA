#include <stdint.h>

// Hardware Accelerator MMIO Addresses
#define HW_KERNEL_BASE  ((volatile uint32_t*)0x80000000)
#define HW_CMD_START    (*(volatile uint32_t*)0x80000024)
#define HW_STATUS_DONE  (*(volatile uint32_t*)0x80000028)
#define HW_NORM_EN      (*(volatile uint32_t*)0x80000030)

// Vivado Waveform Stopwatch Trigger
#define BENCHMARK_FLAG (*(volatile uint32_t*)0x00000F00) 

// UART Transmission Trigger (Sukhjot's MMIO Bridge)
#define SW_DONE_REG    (*(volatile uint32_t*)0x80000034)

volatile int8_t gaussian_blur[9] = { 1,  2,  1, 
                                     2,  4,  2, 
                                     1,  2,  1};

#define HW_IMG_READY_ADDR ((volatile uint32_t*)0x80000038)

// Helper for 1-cycle latency safe MMIO polling with NOPs to prevent hazard stall bugs
static inline uint32_t read_mmio(volatile uint32_t *addr) {
    uint32_t val;
    __asm__ volatile (
        "lw zero, 0(%1)\n\t"    // Dummy read
        "lw %0, 0(%1)\n\t"      // Actual read
        "nop\n\t"               // Prevent hazard stall on branch eval
        "nop\n\t"
        : "=r" (val)
        : "r" (addr)
    );
    return val;
}

int main() {
    // 1. PERFECT SYNC: Poll the top_fsm until it says the Image is 100% loaded via UART
    while (read_mmio(HW_IMG_READY_ADDR) == 0) {
        // CPU gracefully spins here infinitely until you hit "send" in Python!
    }

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

    // 5. PERFECT SYNC: Wait exclusively just for the convolution HW to finish
    while (read_mmio(&HW_STATUS_DONE) == 0) {
        // Wait purely based on the hardware completing processing
    }

    // 6. STOP TIMER FLAG
    BENCHMARK_FLAG = 0x99999999; 

    // 7. START UART TRANSMISSION
    SW_DONE_REG = 1;

    // Safely halt CPU
    while(1) {}
    return 0;
}