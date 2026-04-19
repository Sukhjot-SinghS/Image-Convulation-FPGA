/*
 * sw_blur.c  —  Software Box Blur (Average by 9)
 * Bare-metal version for Custom RISC-V CPU
 */

 #include <stdint.h>

 #define IMG_W     128
 #define IMG_H     128
 #define OUT_W     126
 #define OUT_H     126
 
 /* BRAM pixel access via MMIO */
 #define BRAM_IN_BASE   ((volatile uint8_t*)0xC0000000)
 #define BRAM_OUT_BASE  ((volatile uint8_t*)0xC0010000)
 
 /* Benchmark and Hardware Doorbell */
 #define BENCHMARK_FLAG (*(volatile uint32_t*)0x00000F00)
 #define SW_DONE_REG    (*(volatile uint32_t*)0x80000034)
 
 /* Safe 1-cycle latency BRAM read macro */
 static inline uint8_t read_pixel(int row, int col) {
     volatile uint8_t *addr = &BRAM_IN_BASE[row * IMG_W + col];
     (void)(*addr);          /* first access — latches address */
     return *addr;           /* second access — reads stable data */
 }
 
 /* BRAM write macro */
 static inline void write_pixel(int row, int col, uint8_t val) {
     BRAM_OUT_BASE[(row - 1) * OUT_W + (col - 1)] = val;
 }
 
 volatile int dummy_counter;
 
 int main(void) {
     // 1. The Un-killable Delay Loop (Wait for Python GUI)
     for (int i = 0; i < 50000000; i++) {
         dummy_counter = i;
     }
     
     /* ── START TIMER ────────────────────────────────────────── */
     BENCHMARK_FLAG = 0x11111111;
 
     /*
      * 3x3 Box Blur (Smoothing)
      * Sums all 9 pixels in the neighborhood and divides by 9.
      * Uses the hardware DIV instruction in the RISC-V ALU.
      */
     for (int r = 1; r < IMG_H - 1; r++) {
         for (int c = 1; c < IMG_W - 1; c++) {
             
             uint32_t sum = 0;
 
             // 3x3 Neighborhood Sum
             for (int i = -1; i <= 1; i++) {
                 for (int j = -1; j <= 1; j++) {
                     sum += (uint32_t)read_pixel(r + i, c + j);
                 }
             }
 
             // Average (Divide by 9)
             uint8_t result = (uint8_t)(sum / 9);
 
             write_pixel(r, c, result);
         }
     }
 
     /* ── STOP TIMER ─────────────────────────────────────────── */
     BENCHMARK_FLAG = 0x99999999;
 
     /* ── SIGNAL DONE → top_fsm goes to TRANSMIT ─────────────── */
     SW_DONE_REG = 1;
 
     /* Halt CPU */
     while (1) {}
     return 0;
 }