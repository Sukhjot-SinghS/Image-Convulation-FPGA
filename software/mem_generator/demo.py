# demo.py - UART Image Transfer and Visualization
# Author: Abhirup Paul

import serial
import numpy as np
import matplotlib.pyplot as plt
import time

# ── CONFIG ────────────────────────────────────────────────────────────────────
COM_PORT      = 'COM4'
BAUD_RATE     = 115200
IMG_PATH      = 'grayscale.jpg'

IMG_W, IMG_H  = 128, 128
OUT_W, OUT_H  = 126, 126
IMG_BYTES     = IMG_W * IMG_H          # 16384
OUT_BYTES     = OUT_W * OUT_H          # 15876

# How long to wait after sending image before polling for output.
# Breakdown at 25 MHz:
#   UART RX of 16384 bytes @ 115200 baud  ≈ 1.4 s
#   CPU delay loop (50M iters, ~4 cyc ea) ≈ 8.0 s
#   Gaussian blur 126×126 × 9 reads       ≈ 0.5 s
#   FSM TRANSMIT of 15876 bytes @ 115200  ≈ 1.4 s
# Total: ~11 s — use 15 s margin
WAIT_AFTER_SEND = 15  # seconds

# Timeout for the actual serial.read() call
READ_TIMEOUT    = 30  # seconds
# ─────────────────────────────────────────────────────────────────────────────


def load_image():
    try:
        img = plt.imread(IMG_PATH)
        # plt.imread returns float [0,1] for JPEG — convert to uint8
        if img.dtype != np.uint8:
            img = (img * 255).astype(np.uint8)
        # If RGB, convert to grayscale
        if img.ndim == 3:
            img = (0.299 * img[:,:,0] +
                   0.587 * img[:,:,1] +
                   0.114 * img[:,:,2]).astype(np.uint8)
        # Resize to 128×128 if needed
        if img.shape != (IMG_H, IMG_W):
            print(f"  Resizing from {img.shape} → ({IMG_H},{IMG_W})")
            from PIL import Image as PILImage
            img = np.array(PILImage.fromarray(img).resize((IMG_W, IMG_H)))
        print(f"  Image loaded: shape={img.shape}, dtype={img.dtype}, "
              f"min={img.min()}, max={img.max()}")
        return img
    except Exception as e:
        print(f"  Could not load {IMG_PATH} ({e}), using synthetic gradient.")
        return np.linspace(0, 255, IMG_BYTES).reshape(IMG_H, IMG_W).astype(np.uint8)


def run_demo():
    # ── 1. Open serial port ───────────────────────────────────────────────────
    print(f"[1] Opening {COM_PORT} @ {BAUD_RATE} baud...")
    try:
        ser = serial.Serial(COM_PORT, BAUD_RATE, timeout=READ_TIMEOUT)
        ser.reset_input_buffer()   # flush any stale bytes from FPGA
        ser.reset_output_buffer()
        print("    Connected OK.")
    except Exception as e:
        print(f"    ERROR: {e}")
        return

    # ── 2. Load image ─────────────────────────────────────────────────────────
    print(f"[2] Loading image...")
    img = load_image()
    raw_bytes = img.tobytes()
    assert len(raw_bytes) == IMG_BYTES, f"Expected {IMG_BYTES} bytes, got {len(raw_bytes)}"

    # ── 3. Send image to FPGA ─────────────────────────────────────────────────
    # At 115200 baud with 10 bits/byte, sending 16384 bytes takes ~1.43 s.
    # Make sure your FPGA is RESET and sitting in WAIT_IMAGE before you run this.
    print(f"[3] Sending {IMG_BYTES} bytes to FPGA (takes ~1.4 s at 115200)...")
    t0 = time.time()
    ser.write(raw_bytes)
    ser.flush()   # block until OS buffer is drained to the UART hardware
    elapsed = time.time() - t0
    print(f"    Done sending in {elapsed:.2f} s.")

    # ── 4. Wait for CPU to finish ─────────────────────────────────────────────
    # The FSM will start transmitting once the CPU finishes processing and sends sw_done.
    # We rely on ser.read(OUT_BYTES) with its 30 second timeout to block and patiently wait.
    print(f"[4] Waiting for CPU to process and FSM to TX (up to 30s timeout)...")

    # ── 5. Receive output ─────────────────────────────────────────────────────
    print(f"    Reading {OUT_BYTES} bytes...")

    t0 = time.time()
    raw_data = ser.read(OUT_BYTES)
    elapsed = time.time() - t0

    print(f"    Received {len(raw_data)} / {OUT_BYTES} bytes in {elapsed:.2f} s.")

    # ── Diagnostic: show first few bytes ──────────────────────────────────────
    if len(raw_data) > 0:
        preview = list(raw_data[:16])
        print(f"    First 16 bytes: {preview}")
    else:
        print("    NO BYTES received. Check:")
        print("      a) Did you press RESET on the FPGA before running this script?")
        print("      b) Is CLKS_PER_BIT in top_fsm correct for your CPU clock?")
        print("         At 25 MHz:  CLKS_PER_BIT = 25000000/115200 ≈ 217  ✓")
        print("         At 100 MHz: CLKS_PER_BIT = 100000000/115200 ≈ 868")
        print("      c) Is the TX pin wired to the correct PMOD/USB-UART pin in XDC?")
        ser.close()
        return

    if len(raw_data) < OUT_BYTES:
        print(f"    WARNING: Only got {len(raw_data)} bytes (expected {OUT_BYTES}).")
        print(f"    Partial data — padding with zeros for display.")
        raw_data = raw_data + bytes(OUT_BYTES - len(raw_data))

    # ── 6. Visualise ──────────────────────────────────────────────────────────
    processed_img = np.frombuffer(raw_data, dtype=np.uint8).reshape(OUT_H, OUT_W)
    print(f"[6] Output stats: min={processed_img.min()}, max={processed_img.max()}, "
          f"mean={processed_img.mean():.1f}")

    if processed_img.max() == 0:
        print("    WARNING: all-zero output — BRAM_OUT was never written.")
        print("    Check that SW_DONE fires and BRAM_OUT is mapped correctly.")

    plt.figure(figsize=(10, 5))
    plt.subplot(1, 2, 1)
    plt.title(f"Original ({IMG_W}×{IMG_H})")
    plt.imshow(img, cmap='gray', vmin=0, vmax=255)
    plt.axis('off')

    plt.subplot(1, 2, 2)
    plt.title(f"SW Gaussian Blur Output ({OUT_W}×{OUT_H})")
    plt.imshow(processed_img, cmap='gray', vmin=0, vmax=255)
    plt.axis('off')

    plt.tight_layout()
    plt.savefig('output_result.png', dpi=150)
    print("    Saved output_result.png")
    plt.show()

    ser.close()
    print("[Done]")


if __name__ == "__main__":
    run_demo()