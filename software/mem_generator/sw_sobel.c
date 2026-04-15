// /**
//  * sw_sobel.c
//  * Author: Abhirup Paul
//  * Purpose: Software-only Sobel Edge Detection baseline.
//  */

// #include <stdint.h>
// #include <stdlib.h>

// #define WIDTH  128
// #define HEIGHT 128

// // Sobel Kernels
// volatile int8_t Gx[3][3] = {{-1, 0, 1}, {-2, 0, 2}, {-1, 0, 1}};
// volatile int8_t Gy[3][3] = {{ 1, 2, 1}, { 0, 0, 0}, {-1,-2,-1}};

// void sobel_filter(volatile uint8_t input[HEIGHT][WIDTH], volatile uint8_t output[HEIGHT-2][WIDTH-2]) {
//     for (int r = 1; r < HEIGHT - 1; r++) {
//         for (int c = 1; c < WIDTH - 1; c++) {
//             volatile int16_t sumX = 0;
//             volatile int16_t sumY = 0;

//             // 3x3 Convolution
//             for (int i = -1; i <= 1; i++) {
//                 for (int j = -1; j <= 1; j++) {
//                     volatile uint8_t pixel = input[r + i][c + j];
//                     sumX += pixel * Gx[i + 1][j + 1];
//                     sumY += pixel * Gy[i + 1][j + 1];
//                 }
//             }

//             // Magnitude approximation: |G| = |Gx| + |Gy|
//             volatile int16_t total = (sumX < 0 ? -sumX : sumX) + (sumY < 0 ? -sumY : sumY);
            
//             // Clamp to 0-255 (Matches Soumik's conv_engine logic) 
//             if (total > 255) total = 255;
//             output[r - 1][c - 1] = (uint8_t)total;
//         }
//     }
// }

// int main() {
//     // Initializing with {0} ensures these are placed in the .data section
//     // if your Makefile doesn't use the -j .bss flag yet.
//     static volatile uint8_t image_in[HEIGHT][WIDTH] = {0};
//     static volatile uint8_t image_out[HEIGHT-2][WIDTH-2] = {0};

//     sobel_filter(image_in, image_out);

//     // CRITICAL: Infinite trap to prevent the CPU from fetching 
//     // invalid instructions after main() returns.
//     while(1) {
//         // CPU parks here safely
//     }

//     return 0;
// }

















#include <stdint.h>

#define IMG_W 32
#define IMG_H 32

uint8_t image_in[IMG_H][IMG_W];
uint8_t image_out[IMG_H][IMG_W];

// Vivado Waveform Stopwatch Trigger
#define BENCHMARK_FLAG (*(volatile uint32_t*)0x00000F00) 

// UART Transmission Trigger (Sukhjot's MMIO Bridge)
#define SW_DONE_REG    (*(volatile uint32_t*)0x80000034)

// Simple absolute value function
int32_t abs_val(int32_t x) {
    return (x < 0) ? -x : x;
}

int main() {
    // 1. Initialize dummy image data (a hard edge in the middle)
    for (int y = 0; y < IMG_H; y++) {
        for (int x = 0; x < IMG_W; x++) {
            image_in[y][x] = (x > 15) ? 255 : 0;
        }
    }

    // ==========================================
    // 2. START TIMER FLAG
    // ==========================================
    BENCHMARK_FLAG = 0x11111111; 

    // 3. Perform Sobel Edge Detection
    for (int y = 1; y < IMG_H - 1; y++) {
        for (int x = 1; x < IMG_W - 1; x++) {
            
            int32_t gx = 
                (-1 * image_in[y-1][x-1]) + (1 * image_in[y-1][x+1]) +
                (-2 * image_in[y][x-1])   + (2 * image_in[y][x+1]) +
                (-1 * image_in[y+1][x-1]) + (1 * image_in[y+1][x+1]);

            int32_t gy = 
                (-1 * image_in[y-1][x-1]) + (-2 * image_in[y-1][x]) + (-1 * image_in[y-1][x+1]) +
                (1 * image_in[y+1][x-1])  + (2 * image_in[y+1][x])  + (1 * image_in[y+1][x+1]);

            int32_t mag = abs_val(gx) + abs_val(gy);

            if (mag > 255) mag = 255;

            image_out[y][x] = (uint8_t)mag;
        }
    }

    // ==========================================
    // 4. STOP TIMER FLAG
    // ==========================================
    BENCHMARK_FLAG = 0x99999999; 

    // ==========================================
    // 5. START UART TRANSMISSION
    // ==========================================
    SW_DONE_REG = 1;

    // Safely halt the processor
    while(1) {}
    return 0;
}