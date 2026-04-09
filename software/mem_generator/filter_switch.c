#include <stdint.h>

void load_kernel_and_start(int8_t kernel[9]);

int8_t sobel_x[9] = {-1, 0, 1, -2, 0, 2, -1, 0, 1};
int8_t box_blur[9] = {1, 1, 1, 1, 1, 1, 1, 1, 1};

int main() {
    // Example: Triggering the Hardware Sobel Filter
    load_kernel_and_start(sobel_x);

    // Trap the CPU at the end!
    while(1) {
        // Infinite loop to prevent simulation crash
    }
    return 0;
}