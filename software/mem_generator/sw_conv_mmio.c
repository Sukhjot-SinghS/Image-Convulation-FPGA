#include <stdint.h>

// Hardware Accelerator MMIO Addresses
#define HW_IMG_READY_ADDR ((volatile uint32_t*)0x80000038)
#define HW_FILTER_ID    (*(volatile uint32_t*)0x8000003C)
#define SW_DONE_REG     (*(volatile uint32_t*)0x80000034)
#define BENCHMARK_FLAG  (*(volatile uint32_t*)0x00000F00)

#define BRAM_IN_BASE   ((volatile uint8_t*)0xC0000000)
#define BRAM_OUT_BASE  ((volatile uint8_t*)0xC0010000)

static const int8_t KERNELS[6][9] = {
    { 1,  2,  1,  2,  4,  2,  1,  2,  1},  /* 0: Gaussian   */
    {-1,  0,  1, -2,  0,  2, -1,  0,  1},  /* 1: Sobel X    */
    {-1, -2, -1,  0,  0,  0,  1,  2,  1},  /* 2: Sobel Y    */
    { 0, -1,  0, -1,  5, -1,  0, -1,  0},  /* 3: Sharpen    */
    {-1, -1, -1, -1,  8, -1, -1, -1, -1},  /* 4: Edge       */
    { 0,  0,  0,  0,  1,  0,  0,  0,  0},  /* 5: Identity   */
};
static const uint8_t NORM_EN_TABLE[6] = {1, 0, 0, 0, 0, 0};

// PIPELINE SHIELD POLL MACRO — double-read to beat BRAM latency
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

// POST-STORE shield: prevents branch_stall from suppressing mem_write on the
// instruction that just wrote to BRAM_OUT.  pipeline.v gates mem_write with
// !branch_stall, so any store that shares the WB stage with a taken branch
// is silently dropped.  Two nops push the store out of the danger window.
#define STORE_SHIELD() __asm__ volatile("nop\nnop\n" ::: "memory")

static inline uint8_t read_pixel(int idx) {
    volatile uint8_t *addr = &BRAM_IN_BASE[idx];
    (void)(*addr);   /* dummy read — feeds address to BRAM one cycle early */
    return *addr;    /* real read — BRAM output is now valid                */
}

int main() {
    while(1) {
        // 1. Wait for UART to finish loading the image
        POLL_DOORBELL(HW_IMG_READY_ADDR);

        // 2. Read filter ID — strip the GUI's SW sentinel bit (filter_id | 16)
        uint32_t fid = HW_FILTER_ID;
        if (fid >= 16) fid = fid - 16;
        if (fid > 5)   fid = 0;

        const int8_t *k    = KERNELS[fid];
        uint8_t       blur = NORM_EN_TABLE[fid];

        // 3. Start benchmark timer
        BENCHMARK_FLAG = 0x11111111;

        // 4. Zero the border — top and bottom rows
        for (int c = 0; c < 128; c++) {
            __asm__ volatile("nop");          /* pre-store branch shield  */
            BRAM_OUT_BASE[c]             = 0;
            STORE_SHIELD();                   /* post-store branch shield */
            BRAM_OUT_BASE[127 * 128 + c] = 0;
            STORE_SHIELD();
        }
        // Zero left and right columns
        for (int r = 1; r < 127; r++) {
            __asm__ volatile("nop");
            BRAM_OUT_BASE[r * 128]       = 0;
            STORE_SHIELD();
            BRAM_OUT_BASE[r * 128 + 127] = 0;
            STORE_SHIELD();
        }

        // 5. Software convolution — 126×126 inner pixels
        for (int r = 1; r < 127; r++) {
            __asm__ volatile("nop");          /* shield outer-loop branch */
            for (int c = 1; c < 127; c++) {
                __asm__ volatile("nop");      /* shield inner-loop branch */

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
                STORE_SHIELD();               /* post-store branch shield */
            }
        }

        // 6. Stop benchmark timer
        BENCHMARK_FLAG = 0x99999999;

        // 7. Signal GUI that SW convolution is done → triggers UART TX
        SW_DONE_REG = 1;

        // 8. Debounce: let img_ready deassert before looping back
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
