#include <stdint.h>

// Mandated Hardware Memory Map
volatile int32_t* const KERNEL_BASE = (int32_t*)0x80000000;
volatile int32_t* const HW_START    = (int32_t*)0x80000028;
volatile int32_t* const HW_STATUS   = (int32_t*)0x8000002C;

void load_kernel_and_start(int8_t kernel[9]) {
    // 1. Load the 9 weights into MMIO registers
    for(int i = 0; i < 9; i++) {
        KERNEL_BASE[i] = (int32_t)kernel[i];
    }

    // 2. Fire the Start Signal
    *HW_START = 1;

    // 3. The Polling Loop (Mandatory volatile check)
    // Wait until HW_STATUS becomes 1 (Done)
    while (*HW_STATUS == 0) {
        // CPU spins here until Soumik's engine finishes
    }
    
    // 4. Reset start signal per Satish's bridge requirement
    *HW_START = 0; 
}