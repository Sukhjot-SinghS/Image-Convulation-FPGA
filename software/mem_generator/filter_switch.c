#include <stdint.h>

// ==========================================
// MMIO HARDWARE ADDRESSES (From Satish's Decoder)
// ==========================================
// Using uint32_t pointers ensures the C compiler automatically steps 
// by 4 bytes (matching Satish's '>> 2' logic in Verilog)
#define HW_KERNEL_BASE  ((volatile uint32_t*)0x80000000)

#define HW_CMD_START    (*(volatile uint32_t*)0x80000024)
#define HW_STATUS_DONE  (*(volatile uint32_t*)0x80000028)
#define HW_NORM_EN      (*(volatile uint32_t*)0x80000030)

// ==========================================
// KERNEL MENU
// ==========================================
volatile int8_t sobel_x_pos[9] = {-1,  0,  1, 
                                  -2,  0,  2, 
                                  -1,  0,  1};

volatile int8_t sobel_x_neg[9] = { 1,  0, -1, 
                                   2,  0, -2, 
                                   1,  0, -1};

// Gaussian sum is 16, requires norm_en = 1
volatile int8_t gaussian_blur[9] = { 1,  2,  1, 
                                     2,  4,  2, 
                                     1,  2,  1};

// ==========================================
// HARDWARE DRIVER
// ==========================================
void load_kernel_and_start(volatile int8_t kernel[9], uint32_t norm_enable) {
    
    // 1. Write the normalization flag (1 for Gaussian, 0 for Sobel)
    HW_NORM_EN = norm_enable;

    // 2. Write the 9 weights. HW_KERNEL_BASE[i] automatically writes 
    // to 0x80000000, 0x80000004, 0x80000008...
    for (int i = 0; i < 9; i++) {
        // Cast the 8-bit weight to 32-bit to safely cross the CPU data bus
        HW_KERNEL_BASE[i] = (uint32_t)kernel[i];
    }

    // 3. Pulse the Start command
    HW_CMD_START = 1;
    // Satish's decoder requires the CPU to clear the start bit manually
    HW_CMD_START = 0; 

    // 4. Wait for the hardware to finish
    while (HW_STATUS_DONE == 0) {
        // CPU waits here
    }
}

int main() {
    // Test 1: Gaussian Blur (Needs normalization!)
    load_kernel_and_start(gaussian_blur, 1);

    /* // To test Sobel instead, uncomment one of these:
    // load_kernel_and_start(sobel_x_pos, 0);
    // load_kernel_and_start(sobel_x_neg, 0);
    */

    while(1) {}
    return 0;
}