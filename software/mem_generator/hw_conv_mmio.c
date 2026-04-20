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
#define HW_IMG_READY   (*(volatile uint32_t*)0x80000038)

volatile int8_t gaussian_blur[9] = { 1,  2,  1, 
                                     2,  4,  2, 
                                     1,  2,  1};

volatile int dummy_counter;

int main() {
    // 1. SMART POLLING LOOP (Wait for Python GUI UART TX)
    // The previous 50M iteration assembly loop took exactly 8 seconds.
    // If the GUI wasn't started within that 8 seconds, the CPU would fire HW_CMD_START
    // before the UART FSM was ready, causing a permanent deadlock at HW_STATUS_DONE.
    // NOW, the hardware explicitly tells us when the image is fully buffered in BRAM!
    while (HW_IMG_READY == 0) {
        dummy_counter = 1; // Yield until GUI finishes sending 16KB image
    }

    // 2. Initialize Hardware Parameters
    HW_NORM_EN = 1; // Enable division by 16
    
    for (int i = 0; i < 9; i++) {
        HW_KERNEL_BASE[i] = (uint32_t)gaussian_blur[i];
    }

    // ==========================================
    // 3. START TIMER FLAG
    // ==========================================
    BENCHMARK_FLAG = 0x11111111; 

    // 4. Trigger Hardware Accelerator
    HW_CMD_START = 1;
    HW_CMD_START = 0; 

    // 5. Poll Status
    while (HW_STATUS_DONE == 0) {
        // CPU yields while Soumik's accelerator crunches the pixels
    }

    // ==========================================
    // 6. STOP TIMER FLAG
    // ==========================================
    BENCHMARK_FLAG = 0x99999999; 

    // ==========================================
    // 7. START UART TRANSMISSION
    // ==========================================
    SW_DONE_REG = 1;

    // Safely halt CPU
    while(1) {}
    return 0;
}