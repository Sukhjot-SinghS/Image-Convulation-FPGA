/*
 * test_bram_out.c — BRAM_OUT Write Path Diagnostic
 *
 * Fills BRAM_OUT with a gradient pattern WITHOUT reading BRAM_IN.
 * If the GUI shows the gradient, the write path works.
 * If the GUI shows black, the write path is broken.
 */

#include <stdint.h>

#define SW_DONE_REG       (*(volatile uint32_t*)0x80000034)
#define HW_IMG_READY_ADDR ((volatile uint32_t*)0x80000038)
#define BENCHMARK_FLAG    (*(volatile uint32_t*)0x00000F00)

#define BRAM_OUT_BASE  ((volatile uint8_t*)0xC0010000)

#define IMG_W  128
#define IMG_H  128

/* Pipeline-safe polling macro */
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

int main(void)
{
    while (1) {
        /* 1. Wait for image to arrive (we don't use it, but need the handshake) */
        POLL_DOORBELL(HW_IMG_READY_ADDR);

        /* 2. Start benchmark */
        BENCHMARK_FLAG = 0x11111111;

        /* 3. Fill BRAM_OUT with a simple gradient pattern */
        /*    Row r, col c → pixel = (r + c) & 0xFF        */
        /*    This creates a diagonal gradient pattern.     */
        for (int r = 0; r < IMG_H; r++) {
            for (int c = 0; c < IMG_W; c++) {
                uint8_t val = (uint8_t)((r + c) & 0xFF);
                BRAM_OUT_BASE[r * IMG_W + c] = val;
            }
        }

        /* 4. Stop benchmark */
        BENCHMARK_FLAG = 0x99999999;

        /* 5. Signal FSM: done → TRANSMIT */
        SW_DONE_REG = 1;

        /* 6. Debounce */
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
