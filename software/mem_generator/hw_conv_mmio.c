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

int main() {
    // ============================================================
    // 1. FIXED DELAY — Wait for image to load via UART
    //    Identical approach to the WORKING sw_gaussian_blur.c
    //    50,000,000 iterations × ~4 cycles = ~8 seconds at 25 MHz
    // ============================================================
    __asm__ volatile (
        "li t0, 50000000\n\t"
        "1:\n\t"
        "addi t0, t0, -1\n\t"
        "bnez t0, 1b\n\t"
        ::: "t0"
    );

    // ============================================================
    // 2. Initialize Hardware Parameters
    // ============================================================
    HW_NORM_EN = 1; // Enable normalization (divide by 8)
    
    for (int i = 0; i < 9; i++) {
        HW_KERNEL_BASE[i] = (uint32_t)gaussian_blur[i];
    }

    // ============================================================
    // 3. START TIMER FLAG
    // ============================================================
    BENCHMARK_FLAG = 0x11111111; 

    // ============================================================
    // 4. Trigger Hardware Accelerator
    // ============================================================
    HW_CMD_START = 1;
    HW_CMD_START = 0; 

    // ============================================================
    // 5. FIXED DELAY — Wait for convolution to finish
    //    The hardware convolution takes ~33,000 clk_slow cycles
    //    (126 rows × ~260 cycles/row). We wait 5,000,000 iterations
    //    (~20M clk_slow cycles = ~0.8s) which is massive overkill.
    // ============================================================
    __asm__ volatile (
        "li t0, 5000000\n\t"
        "1:\n\t"
        "addi t0, t0, -1\n\t"
        "bnez t0, 1b\n\t"
        ::: "t0"
    );

    // ============================================================
    // 6. STOP TIMER FLAG
    // ============================================================
    BENCHMARK_FLAG = 0x99999999; 

    // ============================================================
    // 7. START UART TRANSMISSION
    //    SW_DONE tells top_fsm to go from WAIT_START → TRANSMIT
    //    (or if the FSM already reached TRANSMIT via DRAIN, this
    //    is just a harmless 1-cycle pulse that gets ignored)
    // ============================================================
    SW_DONE_REG = 1;

    // Safely halt CPU
    while(1) {}
    return 0;
}