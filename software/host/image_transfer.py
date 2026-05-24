import serial
import time
import sys
import os
import argparse
import numpy as np
from PIL import Image
import matplotlib.pyplot as plt

def main():
    parser = argparse.ArgumentParser(description="Host Driver for RISC-V Image Convolution Coprocessor")
    parser.add_argument("--image", type=str, required=True, help="Path to input image (will be resized/converted to grayscale 128x128)")
    parser.add_argument("--port", type=str, default="COM3", help="Serial port (e.g. COM3 or /dev/ttyUSB0)")
    parser.add_argument("--baud", type=int, default=115200, help="Baud rate (default: 115200)")
    
    args = parser.parse_args()

    if not os.path.exists(args.image):
        print(f"Error: Image '{args.image}' not found.")
        sys.exit(1)

    print("=========================================")
    print(" 🚀 RISC-V Coprocessor Host Script")
    print("=========================================")

    # 1. Image Pre-processing
    print(f"[*] Loading and preprocessing image: {args.image}")
    try:
        # Convert to grayscale and resize to exactly 128x128 as expected by hardware
        img = Image.open(args.image).convert('L').resize((128, 128))
    except Exception as e:
        print(f"Error processing image: {e}")
        sys.exit(1)

    # Convert to flat raw bytes 
    img_data = np.array(img, dtype=np.uint8)
    raw_bytes_out = img_data.tobytes()

    print(f"    - Dimensions: {img.size}")
    print(f"    - File Size: {len(raw_bytes_out)} bytes")

    # 2. UART Connection setup
    print(f"\n[*] Connecting to FPGA on {args.port} at {args.baud} baud...")
    try:
        ser = serial.Serial(args.port, args.baud, timeout=10)
    except Exception as e:
        print(f"Error opening serial port {args.port}: {e}")
        print("Tip: Check device manager to see if your Nexys A7 is connected and which COM port it uses.")
        sys.exit(1)

    # 3. Transmit Image to FPGA Wait_IMAGE state
    print("\n[*] Sending Filter ID (0) + 16,384 bytes to the FPGA...")
    start_time = time.time()
    
    # Send 1 byte for WAIT_FILTER_ID state, then the image
    ser.write(bytes([0])) 
    ser.write(raw_bytes_out)
    ser.flush()  # Wait until transmission completes
    
    tx_time = time.time() - start_time
    print(f"    - TX Complete in {tx_time:.2f} seconds")
    
    # The FPGA CPU now takes over, writes the starts signal to MMIO, wait for MAC pipeline, 
    # and then UART TX starts streaming the 126x126 output back.
    print("\n[*] Hardware processing...")
    print("[*] Waiting for 15,876 bytes of processed output...")
    
    # 4. Receive Processed output
    expected_rx_bytes = 126 * 126
    start_rx_time = time.time()
    
    # Read the expected amount of bytes (blocking up to timeout)
    raw_rx_bytes = ser.read(expected_rx_bytes)
    
    rx_time = time.time() - start_rx_time
    
    ser.close()

    if len(raw_rx_bytes) != expected_rx_bytes:
        print(f"\n[!] ERROR: Timeout! Only received {len(raw_rx_bytes)} out of {expected_rx_bytes} bytes.")
        sys.exit(1)

    print(f"    - RX Complete in {rx_time:.2f} seconds")

    # 5. Display & Save
    print("\n[*] Reconstructing output image...")
    # Reshape the flat bytes array back into a 126x126 2D matrix
    processed_img_data = np.frombuffer(raw_rx_bytes, dtype=np.uint8).reshape((126, 126))

    # Save output to disk
    output_filename = "hardware_output.png"
    Image.fromarray(processed_img_data).save(output_filename)
    print(f"[*] Processed image saved to {output_filename}")

    # Plot Side-by-side using matplotlib
    fig, axes = plt.subplots(1, 2, figsize=(10, 5))
    
    axes[0].set_title("Original (128x128)")
    axes[0].imshow(img_data, cmap='gray', vmin=0, vmax=255)
    axes[0].axis('off')

    axes[1].set_title("FPGA Output (126x126)")
    axes[1].imshow(processed_img_data, cmap='gray', vmin=0, vmax=255)
    axes[1].axis('off')

    plt.tight_layout()
    plt.show()

if __name__ == "__main__":
    main()
