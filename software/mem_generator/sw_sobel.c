/*
 * sw_sobel.c  —  Software Sobel Edge Detection (3x3)
 *
 * Memory map (from top_fsm.v BRAM hijack logic):
 *   Read  pixel from img_bram_in  → load  from 0xC000_0000 + pixel_index
 *   Write pixel to  img_bram_out  → store to  0xC001_0000 + pixel_index
 *
 * Image:  128 × 128 input  → pixel index = row*128 + col  (0..16383)
 * Output: 126 × 126        → pixel index = (row-1)*126 + (col-1)  (0..15875)
 *
 * Benchmark flags (Vivado waveform stopwatch):
 *   0x0000_0F00 → write 0x11111111 to START timer
 *   0x0000_0F00 → write 0x99999999 to STOP  timer
 *
 * SW_DONE doorbell:
 *   0x8000_0034 → write 1  →  top_fsm transitions WAIT_START → TRANSMIT
 */

#include <stdint.h>

#define IMG_W     128
#define IMG_H     128
#define OUT_W     126   /* IMG_W - 2, border pixels skipped */
#define OUT_H     126   /* IMG_H - 2, border pixels skipped */

/* BRAM pixel access via MMIO */
#define BRAM_IN_BASE   ((volatile uint8_t*)0xC0000000)
#define BRAM_OUT_BASE  ((volatile uint8_t*)0xC0010000)

/* Benchmark stopwatch */
#define BENCHMARK_FLAG (*(volatile uint32_t*)0x00000F00)

/* Software done doorbell → triggers top_fsm TRANSMIT */
#define SW_DONE_REG    (*(volatile uint32_t*)0x80000034)
#define HW_IMG_READY_ADDR ((volatile uint32_t*)0x80000038)

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

/*
 * Read a pixel from img_bram_in.
 * BRAM has 1-cycle latency — dummy read first to latch address,
 * then read again for stable data.
 */
static inline uint8_t read_pixel(int row, int col)
{
    volatile uint8_t *addr = &BRAM_IN_BASE[row * IMG_W + col];
    (void)(*addr);
    return *addr;
}

/*
 * Write a result pixel into img_bram_out.
 * Output pixel index = (row-1)*OUT_W + (col-1)
 */
static inline void write_pixel(int row, int col, uint8_t val)
{
    BRAM_OUT_BASE[(row - 1) * OUT_W + (col - 1)] = val;
}

volatile int dummy_counter;

int main(void)
{
    /* Wait for Python GUI to finish sending image */
    POLL_DOORBELL(HW_IMG_READY_ADDR);

    /* ── START TIMER ────────────────────────────────────────── */
    BENCHMARK_FLAG = 0x11111111;

    /*
     * 3×3 Sobel edge detection:
     *
     *   Gx = [-1  0  1]    Gy = [-1 -2 -1]
     *        [-2  0  2]         [ 0  0  0]
     *        [-1  0  1]         [ 1  2  1]
     *
     * Magnitude ≈ |Gx| + |Gy|  (avoids sqrt, safe on RV32IM)
     * Clamped to 0–255.
     */
    int row, col;
    for (row = 1; row < IMG_H - 1; row++) {
        for (col = 1; col < IMG_W - 1; col++) {

            int32_t gx =
                -(int32_t)read_pixel(row-1, col-1) + (int32_t)read_pixel(row-1, col+1)
                - 2*(int32_t)read_pixel(row,   col-1) + 2*(int32_t)read_pixel(row,   col+1)
                - (int32_t)read_pixel(row+1, col-1) + (int32_t)read_pixel(row+1, col+1);

            int32_t gy =
                -(int32_t)read_pixel(row-1, col-1) - 2*(int32_t)read_pixel(row-1, col) - (int32_t)read_pixel(row-1, col+1)
                + (int32_t)read_pixel(row+1, col-1) + 2*(int32_t)read_pixel(row+1, col) + (int32_t)read_pixel(row+1, col+1);

            int32_t mag = (gx < 0 ? -gx : gx) + (gy < 0 ? -gy : gy);
            uint8_t result = (mag > 255) ? 255 : (uint8_t)mag;

            write_pixel(row, col, result);
        }
    }

    /* ── STOP TIMER ─────────────────────────────────────────── */
    BENCHMARK_FLAG = 0x99999999;

    /* ── SIGNAL DONE → top_fsm goes to TRANSMIT ─────────────── */
    SW_DONE_REG = 1;

    /* Halt */
    while (1) {}
    return 0;
}
