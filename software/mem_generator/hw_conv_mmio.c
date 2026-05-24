#include <stdint.h>

// Hardware Accelerator MMIO Addresses
#define HW_KERNEL_BASE  ((volatile uint32_t*)0x80000000)
#define HW_CMD_START    (*(volatile uint32_t*)0x80000024)
#define HW_STATUS_DONE  (*(volatile uint32_t*)0x80000028)
#define HW_NORM_EN      (*(volatile uint32_t*)0x80000030)
#define SW_DONE_REG     (*(volatile uint32_t*)0x80000034)
#define HW_IMG_READY_ADDR ((volatile uint32_t*)0x80000038)
#define HW_FILTER_ID    (*(volatile uint32_t*)0x8000003C)
#define BENCHMARK_FLAG  (*(volatile uint32_t*)0x00000F00)

static const int8_t KERNELS[6][9] = {
    { 1,  2,  1,  2,  4,  2,  1,  2,  1},  /* 0: Gaussian   */
    {-1,  0,  1, -2,  0,  2, -1,  0,  1},  /* 1: Sobel X    */
    {-1, -2, -1,  0,  0,  0,  1,  2,  1},  /* 2: Sobel Y    */
    { 0, -1,  0, -1,  5, -1,  0, -1,  0},  /* 3: Sharpen    */
    {-1, -1, -1, -1,  8, -1, -1, -1, -1},  /* 4: Edge       */
    { 0,  0,  0,  0,  1,  0,  0,  0,  0},  /* 5: Identity (debug passthrough) */
};
static const uint8_t NORM_EN_TABLE[6] = {1, 0, 0, 0, 0, 0};

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
    while(1) {
        // 1. PERFECT SYNC: Safely wait for UART load completion
        POLL_DOORBELL(HW_IMG_READY_ADDR);

        // 2. Initialize Hardware Parameters — select filter via runtime ID
        uint32_t fid = HW_FILTER_ID;
        if (fid > 5) fid = 0;
        HW_NORM_EN = NORM_EN_TABLE[fid];

        for (int i = 0; i < 9; i++) {
            HW_KERNEL_BASE[i] = (uint32_t)KERNELS[fid][i];
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

        // 7. START UART TRANSMISSION
        SW_DONE_REG = 1;

        // Debounce: let the UART controller deassert img_ready before looping
        __asm__ volatile (
            "li t0, 5000\n\t"
            "1:\n\t"
            "addi t0, t0, -1\n\t"
            "bnez t0, 1b\n\t"
            ::: "t0"
        );
    }
    return 0;
}