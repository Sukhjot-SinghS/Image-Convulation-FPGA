/* unified_conv_mmio.c - God Mode Firmware
   Combines HW DSP dispatch and SW CPU convolution into one 4KB firmware.
*/
#include <stdint.h>

#define HW_KERNEL_BASE  ((volatile uint32_t*)0x80000000)
#define HW_CMD_START    (*(volatile uint32_t*)0x80000024)
#define HW_STATUS_DONE  (*(volatile uint32_t*)0x80000028)
#define HW_NORM_EN      (*(volatile uint32_t*)0x80000030)
#define SW_DONE_REG     (*(volatile uint32_t*)0x80000034)
#define HW_IMG_READY    ((volatile uint32_t*)0x80000038)
#define HW_FILTER_ID    (*(volatile uint32_t*)0x8000003C)
#define BENCHMARK_FLAG  (*(volatile uint32_t*)0x00000F00)

#define BRAM_IN_BASE   ((volatile uint8_t*)0xC0000000)
#define BRAM_OUT_BASE  ((volatile uint8_t*)0xC0010000)

static const int8_t KERNELS[6][9] = {
    { 1,  2,  1,  2,  4,  2,  1,  2,  1},  /* 0: Gaussian Blur */
    {-1,  0,  1, -2,  0,  2, -1,  0,  1},  /* 1: Sobel X       */
    {-1, -2, -1,  0,  0,  0,  1,  2,  1},  /* 2: Sobel Y       */
    { 0, -1,  0, -1,  5, -1,  0, -1,  0},  /* 3: Sharpen       */
    {-1, -1, -1, -1,  8, -1, -1, -1, -1},  /* 4: Edge Detect   */
    { 0,  0,  0,  0,  1,  0,  0,  0,  0},  /* 5: Identity      */
};
static const uint8_t IS_BLUR[6] = {1, 0, 0, 0, 0, 0};

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

static inline uint8_t read_pixel(int idx) {
    volatile uint8_t *addr = &BRAM_IN_BASE[idx];
    (void)(*addr);
    return *addr;
}

int main(void) {
    while (1) {
        POLL_DOORBELL(HW_IMG_READY);

        uint32_t raw_id = HW_FILTER_ID;
        uint8_t is_sw = (raw_id >= 16);
        uint8_t fid = is_sw ? (raw_id - 16) : raw_id;
        if (fid > 5) fid = 0;

        if (!is_sw) {
            // --- HARDWARE DISPATCH ---
            HW_NORM_EN = IS_BLUR[fid];
            for (int i = 0; i < 9; i++) {
                HW_KERNEL_BASE[i] = (uint32_t)KERNELS[fid][i];
            }
            BENCHMARK_FLAG = 0x11111111;
            HW_CMD_START = 1;
            HW_CMD_START = 0;
            POLL_DOORBELL(&HW_STATUS_DONE);
            BENCHMARK_FLAG = 0x99999999;
        } else {
            // --- SOFTWARE CONVOLUTION ---
            const int8_t *k = KERNELS[fid];
            uint8_t blur = IS_BLUR[fid];
            
            BENCHMARK_FLAG = 0x11111111;

            for (int c = 0; c < 128; c++) {
                __asm__ volatile("nop"); /* Shield loop */
                BRAM_OUT_BASE[c] = 0;
                BRAM_OUT_BASE[127 * 128 + c] = 0;
            }
            for (int r = 1; r < 127; r++) {
                __asm__ volatile("nop"); /* Shield loop */
                BRAM_OUT_BASE[r * 128] = 0;
                BRAM_OUT_BASE[r * 128 + 127] = 0;
            }

            for (int r = 1; r < 127; r++) {
                __asm__ volatile("nop");
                for (int c = 1; c < 127; c++) {
                    __asm__ volatile("nop");
                    int32_t sum = 0;
                    sum += (int32_t)read_pixel((r-1)*128 + (c-1)) * k[0];
                    sum += (int32_t)read_pixel((r-1)*128 + (c  )) * k[1];
                    sum += (int32_t)read_pixel((r-1)*128 + (c+1)) * k[2];
                    sum += (int32_t)read_pixel((r  )*128 + (c-1)) * k[3];
                    sum += (int32_t)read_pixel((r  )*128 + (c  )) * k[4];
                    sum += (int32_t)read_pixel((r  )*128 + (c+1)) * k[5];
                    sum += (int32_t)read_pixel((r+1)*128 + (c-1)) * k[6];
                    sum += (int32_t)read_pixel((r+1)*128 + (c  )) * k[7];
                    sum += (int32_t)read_pixel((r+1)*128 + (c+1)) * k[8];

                    if (blur) {
                        sum = sum >> 4;
                    } else {
                        if (sum < 0) sum = -sum;
                    }
                    if (sum > 255) sum = 255;
                    if (sum < 0)   sum = 0;

                    BRAM_OUT_BASE[r * 128 + c] = (uint8_t)sum;
                }
            }
            BENCHMARK_FLAG = 0x99999999;
        }

        SW_DONE_REG = 1;

        __asm__ volatile (
            "li t0, 5000\n\t"
            "1:\n\t"
            "nop\n\t"
            "addi t0, t0, -1\n\t"
            "bnez t0, 1b\n\t"
            ::: "t0"
        );
    }
    return 0;
}
