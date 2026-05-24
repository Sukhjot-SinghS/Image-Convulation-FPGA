#include <iostream>
#include <vector>
#include <cmath>
#include <chrono>
#include <algorithm>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

int main(int argc, char* argv[]) {
#ifdef _WIN32
    _setmode(_fileno(stdin), _O_BINARY);
    _setmode(_fileno(stdout), _O_BINARY);
#endif

    // We expect N as an optional argument, default to 128.
    int n = 128;
    if (argc > 1) {
        n = std::atoi(argv[1]);
    }

    // Read the filter_id byte
    int filter_id = std::cin.get();
    if (filter_id == EOF) {
        std::cerr << "Error: No input data." << std::endl;
        return 1;
    }

    // Read N*N image bytes
    int img_size = n * n;
    std::vector<uint8_t> img(img_size);
    std::cin.read(reinterpret_cast<char*>(img.data()), img_size);

    if (std::cin.gcount() != img_size) {
        std::cerr << "Error: Not enough image bytes received." << std::endl;
        return 1;
    }

    std::vector<uint8_t> out(img_size, 0);

    // Filter definitions
    int kernel[3][3] = {0};
    int kernel_y[3][3] = {0}; // Used only for combined Sobel (fallback)
    int div = 1;
    bool is_combined_sobel = false;

    if (filter_id == 0) { // Gaussian Blur
        kernel[0][0] = 1; kernel[0][1] = 2; kernel[0][2] = 1;
        kernel[1][0] = 2; kernel[1][1] = 4; kernel[1][2] = 2;
        kernel[2][0] = 1; kernel[2][1] = 2; kernel[2][2] = 1;
        div = 16;
    } else if (filter_id == 1) { // Sobel X
        kernel[0][0] = -1; kernel[0][1] = 0; kernel[0][2] = 1;
        kernel[1][0] = -2; kernel[1][1] = 0; kernel[1][2] = 2;
        kernel[2][0] = -1; kernel[2][1] = 0; kernel[2][2] = 1;
    } else if (filter_id == 2) { // Sobel Y
        kernel[0][0] = -1; kernel[0][1] = -2; kernel[0][2] = -1;
        kernel[1][0] =  0; kernel[1][1] =  0; kernel[1][2] =  0;
        kernel[2][0] =  1; kernel[2][1] =  2; kernel[2][2] =  1;
    } else if (filter_id == 3) { // Sharpen
        kernel[0][0] =  0; kernel[0][1] = -1; kernel[0][2] =  0;
        kernel[1][0] = -1; kernel[1][1] =  5; kernel[1][2] = -1;
        kernel[2][0] =  0; kernel[2][1] = -1; kernel[2][2] =  0;
    } else if (filter_id == 4) { // Edge Detect
        kernel[0][0] = -1; kernel[0][1] = -1; kernel[0][2] = -1;
        kernel[1][0] = -1; kernel[1][1] =  8; kernel[1][2] = -1;
        kernel[2][0] = -1; kernel[2][1] = -1; kernel[2][2] = -1;
    } else if (filter_id == 5) { // Identity
        kernel[0][0] = 0; kernel[0][1] = 0; kernel[0][2] = 0;
        kernel[1][0] = 0; kernel[1][1] = 1; kernel[1][2] = 0;
        kernel[2][0] = 0; kernel[2][1] = 0; kernel[2][2] = 0;
    } else {
        // Fallback: Combined Sobel Magnitude
        is_combined_sobel = true;
        kernel[0][0] = -1; kernel[0][1] = 0; kernel[0][2] = 1;
        kernel[1][0] = -2; kernel[1][1] = 0; kernel[1][2] = 2;
        kernel[2][0] = -1; kernel[2][1] = 0; kernel[2][2] = 1;

        kernel_y[0][0] = -1; kernel_y[0][1] = -2; kernel_y[0][2] = -1;
        kernel_y[1][0] =  0; kernel_y[1][1] =  0; kernel_y[1][2] =  0;
        kernel_y[2][0] =  1; kernel_y[2][1] =  2; kernel_y[2][2] =  1;
    }

    // Start chronometer
    auto start = std::chrono::high_resolution_clock::now();

    for (int y = 0; y < n; ++y) {
        for (int x = 0; x < n; ++x) {
            int acc = 0;
            int acc_y = 0;

            for (int ky = -1; ky <= 1; ++ky) {
                for (int kx = -1; kx <= 1; ++kx) {
                    int py = y + ky;
                    int px = x + kx;

                    // Zero padding condition
                    if (py >= 0 && py < n && px >= 0 && px < n) {
                        int pixel = img[py * n + px];
                        acc += pixel * kernel[ky + 1][kx + 1];
                        if (is_combined_sobel) {
                            acc_y += pixel * kernel_y[ky + 1][kx + 1];
                        }
                    }
                }
            }

            int mag = 0;
            if (is_combined_sobel) {
                mag = static_cast<int>(std::round(std::sqrt(acc * acc + acc_y * acc_y)));
            } else {
                mag = acc / div;
                // Abs for Sobel X/Y/Edge if needed, but hardware might just clip or abs.
                // Usually Sobel X/Y are absolute valued or just clipped. We'll take absolute value.
                if (filter_id == 1 || filter_id == 2 || filter_id == 4) {
                    mag = std::abs(mag);
                }
            }

            if (mag > 255) mag = 255;
            if (mag < 0) mag = 0;

            out[y * n + x] = static_cast<uint8_t>(mag);
        }
    }

    // Stop chronometer
    auto end = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double, std::milli> duration = end - start;

    // Write processed image to stdout
    std::cout.write(reinterpret_cast<const char*>(out.data()), img_size);
    std::cout.flush();

    // Write time to stderr
    std::cerr << duration.count() << std::endl;

    return 0;
}
