# demo.py - UART Image Transfer and Visualization
# Author: Abhirup Paul

import serial
import numpy as np
import matplotlib.pyplot as plt
import time

def run_demo():
    # 1. Setup Serial Communication
    # On Windows 11, check Device Manager for the correct COM port (e.g., 'COM3')
    # Use 115200 baud rate to match standard UART implementations
    try:
        ser = serial.Serial('COM4', 115200, timeout=20)
        print("Connected to Nexys A7 on COM4")
    except Exception as e:
        print(f"Error connecting: {e}")
        return

    # 2. Load and Prepare Image
    # The line_buffer is parameterized for 128x128 
    img_path = 'grayscale.jpg' # As seen in your repo structure
    try:
        # If your test image is 64x64, we must pad it or resize it to 128x128 
        # to match the hardware IMG_W/IMG_H parameters [cite: 229]
        img = plt.imread(img_path)
        if img.shape != (128, 128):
            print("Warning: Resizing image to 128x128 to match hardware line_buffer")
            from PIL import Image
            img = np.array(Image.fromarray(img).resize((128, 128)))
    except:
        # Fallback: Generate a synthetic 128x128 gradient if file is missing
        img = np.linspace(0, 255, 128*128).reshape(128, 128).astype(np.uint8)

    # 3. Send Image Data
    print("Sending 16,384 bytes to FPGA...")
    ser.write(img.tobytes())
    
    # Give the FPGA a moment to process (100MHz is fast, but UART is the bottleneck)
    time.sleep(5)

    # 4. Receive Processed Data
    # The conv_engine produces 126x126 valid pixels [cite: 76, 228]
    expected_bytes = 126 * 126
    print(f"Waiting for {expected_bytes} processed bytes...")
    
    raw_data = ser.read(expected_bytes)
    
    if len(raw_data) == expected_bytes:
        processed_img = np.frombuffer(raw_data, dtype=np.uint8).reshape(126, 126)
        print("Processing Complete.")

        # 5. Visualization
        plt.figure(figsize=(10, 5))
        
        plt.subplot(1, 2, 1)
        plt.title("Original (128x128)")
        plt.imshow(img, cmap='gray')
        
        plt.subplot(1, 2, 2)
        plt.title("Hardware Output (126x126)")
        plt.imshow(processed_img, cmap='gray')
        
        plt.show()
    else:
        print(f"Timeout: Only received {len(raw_data)} bytes.")

    ser.close()

if __name__ == "__main__":
    run_demo()