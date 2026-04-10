/**
 * sw_sobel.c
 * Author: Abhirup Paul
 * Purpose: Software-only Sobel Edge Detection baseline.
 */

#include <stdint.h>
#include <stdlib.h>

#define WIDTH  128
#define HEIGHT 128

// Sobel Kernels
volatile int8_t Gx[3][3] = {{-1, 0, 1}, {-2, 0, 2}, {-1, 0, 1}};
volatile int8_t Gy[3][3] = {{ 1, 2, 1}, { 0, 0, 0}, {-1,-2,-1}};

void sobel_filter(volatile uint8_t input[HEIGHT][WIDTH], volatile uint8_t output[HEIGHT-2][WIDTH-2]) {
    for (int r = 1; r < HEIGHT - 1; r++) {
        for (int c = 1; c < WIDTH - 1; c++) {
            volatile int16_t sumX = 0;
            volatile int16_t sumY = 0;

            // 3x3 Convolution
            for (int i = -1; i <= 1; i++) {
                for (int j = -1; j <= 1; j++) {
                    volatile uint8_t pixel = input[r + i][c + j];
                    sumX += pixel * Gx[i + 1][j + 1];
                    sumY += pixel * Gy[i + 1][j + 1];
                }
            }

            // Magnitude approximation: |G| = |Gx| + |Gy|
            volatile int16_t total = (sumX < 0 ? -sumX : sumX) + (sumY < 0 ? -sumY : sumY);
            
            // Clamp to 0-255 (Matches Soumik's conv_engine logic) 
            if (total > 255) total = 255;
            output[r - 1][c - 1] = (uint8_t)total;
        }
    }
}

int main() {
    // Initializing with {0} ensures these are placed in the .data section
    // if your Makefile doesn't use the -j .bss flag yet.
    static volatile uint8_t image_in[HEIGHT][WIDTH] = {0};
    static volatile uint8_t image_out[HEIGHT-2][WIDTH-2] = {0};

    sobel_filter(image_in, image_out);

    // CRITICAL: Infinite trap to prevent the CPU from fetching 
    // invalid instructions after main() returns.
    while(1) {
        // CPU parks here safely
    }

    return 0;
}