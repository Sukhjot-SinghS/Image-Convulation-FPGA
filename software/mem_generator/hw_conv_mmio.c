#include <stdint.h>

#define HW_KERNEL_BASE  ((volatile uint32_t*)0x80000000)
#define HW_CMD_START    (*(volatile uint32_t*)0x80000024)
#define HW_STATUS_DONE  (*(volatile uint32_t*)0x80000028)
#define HW_NORM_EN      (*(volatile uint32_t*)0x80000030)

// Vivado Waveform Stopwatch Trigger
#define BENCHMARK_FLAG (*(volatile uint32_t*)0x00000F00) 

volatile int8_t gaussian_blur[9] = { 1,  2,  1, 
                                     2,  4,  2, 
                                     1,  2,  1};

int main() {
    // 1. Initialize Hardware Parameters
    HW_NORM_EN = 1; // Enable division by 16
    
    for (int i = 0; i < 9; i++) {
        HW_KERNEL_BASE[i] = (uint32_t)gaussian_blur[i];
    }

    // ==========================================
    // 2. START TIMER FLAG
    // ==========================================
    BENCHMARK_FLAG = 0x11111111; 

    // 3. Trigger Hardware Accelerator
    HW_CMD_START = 1;
    HW_CMD_START = 0; 

    // 4. Poll Status
    while (HW_STATUS_DONE == 0) {
        // CPU yields while Soumik's accelerator crunches the pixels
    }

    // ==========================================
    // 5. STOP TIMER FLAG
    // ==========================================
    BENCHMARK_FLAG = 0x99999999; 

    // Safely halt CPU
    while(1) {}
    return 0;
}