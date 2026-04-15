/*
 * sw_sobel.c  —  Software Gaussian Blur (3x3, kernel sum=16)
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
 
 /*
  * Read a pixel from img_bram_in.
  * BRAM has 1-cycle latency — we do a dummy read first to latch the address,
  * then read again. Because our pipeline has a load-use stall this works
  * correctly: the second read sees the stable registered output.
  */
 static inline uint8_t read_pixel(int row, int col)
 {
     volatile uint8_t *addr = &BRAM_IN_BASE[row * IMG_W + col];
     (void)(*addr);          /* first access — latches address into BRAM register */
     return *addr;           /* second access — data is now stable */
 }
 
 /*
  * Write a result pixel into img_bram_out.
  * Output pixel index = (row-1)*OUT_W + (col-1)
  * because we skip the border row/col.
  */
 static inline void write_pixel(int row, int col, uint8_t val)
 {
     BRAM_OUT_BASE[(row - 1) * OUT_W + (col - 1)] = val;
 }
 
 int main(void)
 {
     /* ── START TIMER ────────────────────────────────────────── */
     for(volatile int delay = 0; delay < 50000000; delay++);
     BENCHMARK_FLAG = 0x11111111;
 
     /*
      * 3×3 Gaussian blur kernel:
      *   1  2  1
      *   2  4  2
      *   1  2  1   (sum = 16, divide by shifting right 4)
      *
      * We skip the outer border (row 0, row 127, col 0, col 127).
      * Valid output rows: 1..126  →  126 rows
      * Valid output cols: 1..126  →  126 cols
      */
     int row, col;
     for (row = 1; row < IMG_H - 1; row++) {
         for (col = 1; col < IMG_W - 1; col++) {
 
             uint32_t sum =
                 (uint32_t)read_pixel(row-1, col-1)       +
                 (uint32_t)read_pixel(row-1, col  ) * 2u  +
                 (uint32_t)read_pixel(row-1, col+1)       +
                 (uint32_t)read_pixel(row,   col-1) * 2u  +
                 (uint32_t)read_pixel(row,   col  ) * 4u  +
                 (uint32_t)read_pixel(row,   col+1) * 2u  +
                 (uint32_t)read_pixel(row+1, col-1)       +
                 (uint32_t)read_pixel(row+1, col  ) * 2u  +
                 (uint32_t)read_pixel(row+1, col+1);
 
             /* divide by 16 */
             uint8_t result = (uint8_t)(sum >> 4);
 
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