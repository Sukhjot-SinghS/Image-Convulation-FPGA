// /**
//  * sw_blur.c
//  * Author: Abhirup Paul
//  * Purpose: Software-only Box Blur (Smoothing) baseline.
//  */

// #include <stdint.h>

// #define WIDTH  128
// #define HEIGHT 128

// void box_blur(volatile uint8_t input[HEIGHT][WIDTH], volatile uint8_t output[HEIGHT-2][WIDTH-2]) {
//     for (int r = 1; r < HEIGHT - 1; r++) {
//         for (int c = 1; c < WIDTH - 1; c++) {
//             volatile uint32_t sum = 0;

//             // 3x3 Neighborhood Sum
//             for (int i = -1; i <= 1; i++) {
//                 for (int j = -1; j <= 1; j++) {
//                     sum += input[r + i][c + j];
//                 }
//             }

//             // Average (Divide by 9)
//             // Note: On your RISC-V core, this uses Shaurya's DIV hardware!
//             output[r - 1][c - 1] = (uint8_t)(sum / 9);
//         }
//     }
// }

// int main() {
//     volatile uint8_t image_in[HEIGHT][WIDTH];
//     volatile uint8_t image_out[HEIGHT-2][WIDTH-2];

//     box_blur(image_in, image_out);
//     return 0;
// }












// #include <stdint.h>

// #define IMG_W 32
// #define IMG_H 32

// // Allocate arrays in Data Memory
// uint8_t image_in[IMG_H][IMG_W];
// uint8_t image_out[IMG_H][IMG_W];

// // A dummy pointer in Data Memory to act as our "Stopwatch Trigger"
// // Address 0x00000F00 is near the end of your 4KB memory, making it easy to spot!
// #define BENCHMARK_FLAG (*(volatile uint32_t*)0x00000F00) 

// int main() {
//     // 1. Initialize dummy image data
//     for (int y = 0; y < IMG_H; y++) {
//         for (int x = 0; x < IMG_W; x++) {
//             image_in[y][x] = (uint8_t)((x + y) * 4);
//         }
//     }

//     // ==========================================
//     // 2. START TIMER FLAG
//     // ==========================================
//     BENCHMARK_FLAG = 0x11111111; 

//     // 3. Perform 3x3 Box Blur (Pure Software)
//     for (int y = 1; y < IMG_H - 1; y++) {
//         for (int x = 1; x < IMG_W - 1; x++) {
            
//             uint32_t sum = 0;
            
//             // Accumulate the 3x3 window
//             sum += image_in[y-1][x-1]; sum += image_in[y-1][x]; sum += image_in[y-1][x+1];
//             sum += image_in[y][x-1];   sum += image_in[y][x];   sum += image_in[y][x+1];
//             sum += image_in[y+1][x-1]; sum += image_in[y+1][x]; sum += image_in[y+1][x+1];

//             // Divide by 9 for average
//             image_out[y][x] = (uint8_t)(sum / 9);
//         }
//     }

//     // ==========================================
//     // 4. STOP TIMER FLAG
//     // ==========================================
//     BENCHMARK_FLAG = 0x99999999; 

//     // Safely halt the processor
//     while(1) {}
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

int main() {
    // 1. Initialize dummy image data
    for (int y = 0; y < IMG_H; y++) {
        for (int x = 0; x < IMG_W; x++) {
            image_in[y][x] = (uint8_t)((x + y) * 4);
        }
    }

    // ==========================================
    // 2. START TIMER FLAG
    // ==========================================
    BENCHMARK_FLAG = 0x11111111; 

    // 3. Perform 3x3 Gaussian Blur (Kernel sum = 16)
    for (int y = 1; y < IMG_H - 1; y++) {
        for (int x = 1; x < IMG_W - 1; x++) {
            
            uint32_t sum = 0;
            
            // Gaussian Kernel Weights:
            // 1  2  1
            // 2  4  2
            // 1  2  1
            sum += (1 * image_in[y-1][x-1]) + (2 * image_in[y-1][x]) + (1 * image_in[y-1][x+1]);
            sum += (2 * image_in[y][x-1])   + (4 * image_in[y][x])   + (2 * image_in[y][x+1]);
            sum += (1 * image_in[y+1][x-1]) + (2 * image_in[y+1][x]) + (1 * image_in[y+1][x+1]);

            // Divide by 16 using a fast 4-bit right shift!
            image_out[y][x] = (uint8_t)(sum >> 4);
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

    while(1) {}
    return 0;
}