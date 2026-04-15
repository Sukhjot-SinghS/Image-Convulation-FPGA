// ==============================================================================
// sw_sobel.c
// Bare-metal Sobel Edge Detection for custom RISC-V CPU.
// Reads 128x128 from BRAM_IN, computes 3x3 Sobel, writes 126x126 to BRAM_OUT.
// ==============================================================================

// Memory Mapped Pointers directly to the Hardware BRAMs
volatile unsigned char *bram_in  = (volatile unsigned char *)0xC0000000;
volatile unsigned char *bram_out = (volatile unsigned char *)0xC0010000;
volatile int *sw_done_reg        = (volatile int *)0x80000034;

int main() {
    int y, x;
    int p00, p01, p02;
    int p10, p11, p12;
    int p20, p21, p22;
    int sumX, sumY, magnitude;
    int out_idx;

    // Loop through the image, skipping the 1-pixel outer border
    // Input is 128x128, Output becomes 126x126
    for (y = 1; y < 127; y++) {
        for (x = 1; x < 127; x++) {
            
            // ------------------------------------------------
            // 1. Fetch 3x3 Window directly from BRAM_IN
            // ------------------------------------------------
            p00 = bram_in[(y - 1) * 128 + (x - 1)];
            p01 = bram_in[(y - 1) * 128 + (x)];
            p02 = bram_in[(y - 1) * 128 + (x + 1)];

            p10 = bram_in[(y) * 128 + (x - 1)];
            p11 = bram_in[(y) * 128 + (x)];
            p12 = bram_in[(y) * 128 + (x + 1)];

            p20 = bram_in[(y + 1) * 128 + (x - 1)];
            p21 = bram_in[(y + 1) * 128 + (x)];
            p22 = bram_in[(y + 1) * 128 + (x + 1)];

            // ------------------------------------------------
            // 2. Compute Sobel Gx (Horizontal edges)
            // ------------------------------------------------
            // Kernel: 
            // -1  0  1
            // -2  0  2
            // -1  0  1
            sumX = (p00 * -1) + (p02 * 1) +
                   (p10 * -2) + (p12 * 2) +
                   (p20 * -1) + (p22 * 1);

            // ------------------------------------------------
            // 3. Compute Sobel Gy (Vertical edges)
            // ------------------------------------------------
            // Kernel:
            // -1 -2 -1
            //  0  0  0
            //  1  2  1
            sumY = (p00 * -1) + (p01 * -2) + (p02 * -1) +
                   (p20 * 1) + (p21 * 2) + (p22 * 1);

            // ------------------------------------------------
            // 4. Absolute Magnitude & Clamping
            // ------------------------------------------------
            // Bare-metal absolute value (no math.h needed)
            if (sumX < 0) sumX = -sumX;
            if (sumY < 0) sumY = -sumY;

            magnitude = sumX + sumY;

            // Clamp to maximum 8-bit pixel value
            if (magnitude > 255) {
                magnitude = 255;
            }

            // ------------------------------------------------
            // 5. TIGHT PACKING: Write to BRAM_OUT
            // ------------------------------------------------
            // We map the (1..126) coordinate down to a (0..125) flat array
            out_idx = (y - 1) * 126 + (x - 1);
            bram_out[out_idx] = (unsigned char)magnitude;
        }
    }

    // ------------------------------------------------
    // 6. Ring the Doorbell
    // ------------------------------------------------
    // Tells top_fsm to switch to TRANSMIT state
    *sw_done_reg = 1;

    // Halt the CPU
    while(1);
    return 0;
}