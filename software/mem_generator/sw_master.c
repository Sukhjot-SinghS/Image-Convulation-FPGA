/*
 * sw_master.c
 * Final C Workload for Verified Hardware
 * * Uses a compile-time switch to select the active filter.
 */

#include <stdint.h>

// ==========================================
// MMIO ADDRESSES (Matching mmio_decoder.v)
// ==========================================
#define HW_KERNEL_BASE  ((volatile uint32_t*)0x80000000)
#define HW_CMD_START    (*(volatile uint32_t*)0x80000024)
#define HW_STATUS_DONE  (*(volatile uint32_t*)0x80000028)
#define HW_NORM_EN      (*(volatile uint32_t*)0x80000030)

// Benchmark Stopwatch (Snooped by top_fpga.v)
#define BENCHMARK_FLAG  (*(volatile uint32_t*)0x00000F00)

// ==========================================
// FILTER SELECTION (Compile-Time Switch)
// ==========================================
// Change this value to test different filters on the hardware:
// 0 = Gaussian Blur
// 1 = Sobel X Edge Detection
// 2 = Sobel Y Edge Detection
volatile uint32_t ACTIVE_FILTER = 0;

// ==========================================
// KERNEL DEFINITIONS
// ==========================================
volatile int8_t gaussian_blur[9] = { 1,  2,  1, 
                                     2,  4,  2, 
                                     1,  2,  1};

volatile int8_t sobel_x[9]       = {-1,  0,  1, 
                                    -2,  0,  2, 
                                    -1,  0,  1};

volatile int8_t sobel_y[9]       = { 1,  2,  1, 
                                     0,  0,  0, 
                                    -1, -2, -1};

// ==========================================
// HARDWARE DRIVER
// ==========================================
void load_and_run(volatile int8_t kernel[9], uint32_t norm_enable) {
    
    // 1. Write the normalization flag (1 for blur, 0 for edges)
    HW_NORM_EN = norm_enable;

    // 2. Load the kernel weights into the accelerator
    for (int i = 0; i < 9; i++) {
        HW_KERNEL_BASE[i] = (uint32_t)kernel[i];
    }

    // 3. Pulse Start command
    HW_CMD_START = 1;
    HW_CMD_START = 0; 

    // 4. Wait for hardware to finish
    while (HW_STATUS_DONE == 0) {
        // Yield CPU while convolution engine runs
    }
}

volatile int dummy_counter;

int main(void) {
    // 1. Delay Loop: Wait for Python GUI to finish transmitting the image
    //    over UART to the BRAM. (50M iterations ~ 15 sec)
    for (int i = 0; i < 50000000; i++) {
        dummy_counter = i;
    }
    
    // 2. Start Hardware Cycle Timer
    BENCHMARK_FLAG = 0x11111111;

    // 3. Route to the correct hardware algorithm
    if (ACTIVE_FILTER == 0) {
        load_and_run(gaussian_blur, 1);
    } else if (ACTIVE_FILTER == 1) {
        load_and_run(sobel_x, 0);
    } else {
        load_and_run(sobel_y, 0);
    }

    // 4. Stop Hardware Cycle Timer
    BENCHMARK_FLAG = 0x99999999;

    // 5. Halt.
    // top_fsm.v automatically notices the hardware is done,
    // transitions to TRANSMIT, and streams the BRAM data back to GUI.
    while(1) {}
    
    return 0;
}