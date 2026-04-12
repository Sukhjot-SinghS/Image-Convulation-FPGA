





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