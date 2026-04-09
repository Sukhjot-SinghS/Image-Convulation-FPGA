/**
 * sw_blur.c
 * Author: Abhirup Paul
 * Purpose: Software-only Box Blur (Smoothing) baseline.
 */

#include <stdint.h>

#define WIDTH  128
#define HEIGHT 128

void box_blur(uint8_t input[HEIGHT][WIDTH], uint8_t output[HEIGHT-2][WIDTH-2]) {
    for (int r = 1; r < HEIGHT - 1; r++) {
        for (int c = 1; c < WIDTH - 1; c++) {
            uint32_t sum = 0;

            // 3x3 Neighborhood Sum
            for (int i = -1; i <= 1; i++) {
                for (int j = -1; j <= 1; j++) {
                    sum += input[r + i][c + j];
                }
            }

            // Average (Divide by 9)
            // Note: On your RISC-V core, this uses Shaurya's DIV hardware!
            output[r - 1][c - 1] = (uint8_t)(sum / 9);
        }
    }
}

int main() {
    static uint8_t image_in[HEIGHT][WIDTH];
    static uint8_t image_out[HEIGHT-2][WIDTH-2];

    box_blur(image_in, image_out);
    return 0;
}