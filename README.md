<div align="center">
  <img src="assets/icon.png" alt="GIC Logo" width="200" />
  
  # GIC — Grayscale Image Convolution FPGA Coprocessor
  
  **A hardware-software co-design project extending a pipelined RISC-V CPU with a custom DSP convolution accelerator — achieving a 75× architectural speedup over pure software on the same silicon clock.**

  [![Platform](https://img.shields.io/badge/Platform-Nexys%20A7--100T-blue.svg)](#)
  [![ISA](https://img.shields.io/badge/ISA-RV32IM-orange.svg)](#)
  [![Clock](https://img.shields.io/badge/Clock-25%20MHz-green.svg)](#)
  [![Speedup](https://img.shields.io/badge/Speedup-75%C3%97-critical.svg)](#)
  
</div>

---

## ⚡ The Problem: Software Convolution is Painfully Slow

Image convolution is the backbone of virtually every computer vision pipeline — blurring, sharpening, edge detection, and feature extraction all boil down to the same operation: sliding a small kernel over every pixel and computing a weighted sum of the neighborhood.

On a general-purpose CPU, that sounds simple. In practice, it's brutal.

A naïve 3×3 convolution over a 128×128 grayscale image requires 9 multiply-accumulate operations per pixel, repeated for all 16,384 pixels. On our in-house 3-stage RV32I soft-core running at 25 MHz, that translates to roughly **150 cycles per pixel** — a total of 2.4 million cycles, or about **98 milliseconds per frame**.

> 98 ms per frame = ~10 FPS. For a 128×128 image. At 25 MHz. 

Real-time video processing requires ~33 ms per frame. Software-only falls more than 3× short before we even consider larger images or more complex filters.

The root cause is architectural: a scalar in-order pipeline must fetch, decode, execute, and retire every single multiply and accumulate instruction sequentially. There is no parallelism. The hardware sits idle waiting for data dependencies to resolve. The CPU was never designed for this kind of workload.

**We needed a better answer.**

---

## 🛠️ The Solution: Build the Hardware That Fits the Problem

Rather than squeezing performance from the general-purpose CPU, we designed a dedicated hardware datapath that does exactly one thing — but does it extremely fast.

The system we built is a two-tier hardware-software co-processor, running entirely on the **Digilent Nexys A7-100T FPGA** (Xilinx Artix-7 XC7A100T):

```text
┌─────────────────────────────────────────────────────────────────┐
│                      Nexys A7 FPGA                              │
│                                                                 │
│  ┌─────────────────┐    MMIO Bus     ┌──────────────────────┐   │
│  │  3-Stage RV32IM │ ◄────────────► │  9-MAC Convolution   │   │
│  │  Pipeline CPU   │  0x80000000    │    Coprocessor        │   │
│  │                 │                │                       │   │
│  │  IF/ID → EX     │                │  Kernel Regfile (k0-  │   │
│  │       → WB      │                │  k8) → Line Buffer →  │   │
│  │                 │                │  DSP MAC Array        │   │
│  └────────┬────────┘                └──────────┬───────────┘   │
│           │ IMEM/DMEM                           │ Image BRAM    │
│      Block RAM                           Block RAM (In/Out)     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │ UART 115200 baud
                    ┌─────────▼──────────┐
                    │   PC Host GUI      │
                    │  (Filter.exe /     │
                    │  fpga_coprocessor_ │
                    │  ui.py)            │
                    └────────────────────┘
```

### Phase 1 — Extending the CPU: RV32M
The base RV32I core had no multiply or divide instructions. Software convolution kernels that needed integer multiply had to emulate it with repeated additions — a massive cycle cost.

We extended the pipeline with a full RV32M implementation inside `rv32m_alu.v`:

* **`MUL / MULH / MULHSU / MULHU`** — all four multiply variants, resolved in **1 clock cycle** by Vivado inferring a DSP48E1 hard multiply block. No hand-instantiation needed.
* **`DIV / DIVU / REM / REMU`** — all four divide variants, implemented as a **32-cycle iterative restoring-division FSM**. The `alu_busy_o` signal stalls the pipeline while division runs.

The hazard unit was extended to compose two stall sources: `pipe_stall = stall_read | div_busy`. Both sources are correctly ORed — if either condition holds, the pipeline freezes and no instruction advances.

### Phase 2 — The Convolution Coprocessor
The coprocessor is a parallel MAC engine mapped into the CPU's address space at `0x80000000`. The CPU programs it like a peripheral:

1. Write 9 kernel coefficients into MMIO registers `k0–k8`
2. Write 1 to the `START` register at `0x80000028`
3. Poll the `STATUS` register at `0x8000002C` until it reads 1

Meanwhile, the hardware runs independently:

| Module | Role |
| :--- | :--- |
| `kernel_regfile.v` | Stores the 9 kernel weights written by the CPU |
| `line_buffer.v` | A 3-row sliding window buffer feeding one 3×3 pixel neighborhood per cycle |
| `conv_datapath.v` | 9 parallel multipliers + accumulate tree, Vivado-inferred DSP48E1 blocks |
| `conv_engine.v` | Top FSM orchestrating stream-in, compute, stream-out |
| `img_bram_in/out.v` | Dual-port block RAMs for input and output image storage |
| `mmio_decoder.v` | Decodes CPU bus transactions into coprocessor control signals |
| `uart_rx/tx.v` | 115200 baud UART for image transfer from the host PC |

The line buffer achieves **1-pixel-per-clock-cycle throughput** once primed — no wasted cycles stalling for row data.

---

## 🚀 The Results: 75× Faster, Apples to Apples

### Why a Fair Comparison Is Hard
A host CPU running at 4 GHz processes a 128×128 image in microseconds. Comparing that directly against a 25 MHz soft-core would be meaningless — you're comparing clock speeds, not architectures. 

Even within the FPGA, comparing wall-clock times is misleading: transferring 16,384 bytes over a 115200-baud UART link takes ~1.4 seconds of pure serial overhead, swamping any compute-time difference.

### Our Measurement Methodology
* **Hardware (`RUN HW`):** Runs physically on the FPGA. The hardware appends a 4-byte cycle counter to the UART response payload. The GUI extracts this raw value and converts it to true time at the 25 MHz hardware clock — giving a cycle-accurate measurement of the pure hardware compute phase without UART overhead.
* **Software (`RUN SW`):** Runs a native C++ executable (`host_sw_conv.cpp` compiled via GCC) locally on the host PC to instantly process the image. To provide a fair architectural comparison, the GUI then **mathematically simulates** the execution time as if it had run on the 25 MHz RISC-V soft-core (where a naïve software convolution takes ~150 instructions per pixel).

| Metric | Software (RV32I CPU) | Hardware (DSP Coprocessor) |
| :--- | :--- | :--- |
| **Cycles for 128×128** | ~2,457,600 | ~32,900 |
| **Compute time @ 25 MHz** | 98.3 ms | 1.3 ms |
| **Architectural Speedup** | — | **~75×** |

### Supported Kernels
| Filter | Kernel | Effect |
| :--- | :--- | :--- |
| **Box Blur** | `1/9 × ones` | Uniform smoothing |
| **Gaussian Blur** | `Weighted Gaussian` | Smooth noise reduction |
| **Sobel X** | `[-1,0,1; -2,0,2; -1,0,1]` | Vertical edge detection |
| **Sobel Y** | `[-1,-2,-1; 0,0,0; 1,2,1]` | Horizontal edge detection |
| **Sharpen** | `[0,-1,0; -1,5,-1; 0,-1,0]` | Edge enhancement |
| **Edge Detect** | `[-1,-1,-1; -1,8,-1; -1,-1,-1]` | Full outline extraction |

---

## 📁 Repository Structure

```text
WORKING_HARDWARE/
│
├── hardware/
│   ├── cpu/
│   │   ├── rtl/
│   │   │   ├── pipeline.v          # 3-stage pipeline wrapper (IF/ID → EX → WB)
│   │   │   ├── IF_ID.v             # Fetch stage + instruction register
│   │   │   ├── execute.v           # Execute stage — hosts rv32m_alu
│   │   │   ├── wb.v                # Writeback stage + register file
│   │   │   ├── hazard_unit.v       # Forwarding + stall logic
│   │   │   ├── rv32m_alu.v         # RV32M: 1-cycle mul, 32-cycle div FSM
│   │   │   └── memory.v            # IMEM/DMEM block RAM models
│   │   └── tb/
│   │       ├── tb_rv32m_alu.v      # RV32M stress test (all 8 ops, edge cases)
│   │       └── tb_pipeline.v       # Pipeline + hazard smoke test
│   │
│   ├── coprocessor/
│   │   ├── rtl/
│   │   │   ├── conv_engine.v       # Convolution FSM top-level
│   │   │   ├── conv_datapath.v     # 9-MAC DSP48E1 array
│   │   │   ├── line_buffer.v       # 3-row sliding window buffer
│   │   │   ├── kernel_regfile.v    # 9-register kernel storage
│   │   │   ├── img_bram_in.v       # Input image block RAM
│   │   │   ├── img_bram_out.v      # Output image block RAM
│   │   │   ├── mmio_decoder.v      # CPU bus → coprocessor control
│   │   │   ├── uart_rx.v           # UART receiver (115200 baud)
│   │   │   └── uart_tx.v           # UART transmitter
│   │   └── tb/                     # Per-module testbenches
│   │
│   └── top/
│       ├── top_fpga.v              # Board-level integration wrapper
│       ├── top_fsm.v               # System control FSM
│       └── constraints/
│           └── constraint.xdc      # Nexys A7-100T pin assignments
│
├── software/
│   ├── mem_generator/
│   │   ├── Makefile                # RISC-V GCC build pipeline
│   │   ├── hw_conv_mmio.c          # Hardware coprocessor test via MMIO
│   │   ├── sw_blur.c               # Pure-software box blur baseline
│   │   ├── sw_gaussian_blur.c      # Pure-software Gaussian blur baseline
│   │   ├── sw_sobel.c              # Pure-software Sobel edge detection
│   │   ├── filter_switch.c         # Multi-filter selector workload
│   │   ├── mul_div_test.c          # RV32M multiply/divide stress test
│   │   └── imem_dmem/
│   │       └── bin2hex.py          # ELF binary → Verilog .hex converter
│   └── host/
│       └── image_transfer.py       # UART image serialization tool
│
├── fpga_coprocessor_ui.py          # CustomTkinter desktop dashboard (main GUI)
├── Filter.exe                      # Pre-compiled GUI — run directly on Windows
├── Filter.spec                     # PyInstaller build spec for Filter.exe
├── configure_paths.py              # Interactive IMEM/DMEM path setup utility
├── rebuild_vivado_convolver.tcl    # Auto-reconstruct Vivado project from TCL
├── requirements.txt                # Python dependencies
└── makefile                        # Master build entry point
```

---

## 💻 How to Use

### Prerequisites
| Tool | Version | Purpose |
| :--- | :--- | :--- |
| **Vivado** | 2020.1+ | Synthesis, implementation, bitstream |
| **RISC-V GCC Toolchain** | `riscv-none-elf-gcc` | Compile C workloads to RV32IM |
| **Python** | 3.10+ | GUI and build utilities |
| **Icarus Verilog** | Any | RTL simulation |
| **Digilent Board Files** | Nexys A7-100T | Board support in Vivado |


### Step 1 — Configure Memory Paths
Vivado requires absolute paths to initialize Block RAMs at synthesis time. This repository ships with an interactive Python script that automatically finds and patches your local paths into `hardware/cpu/rtl/memory.v`.

Run the configuration script:
```bash
python configure_paths.py
```
* **Auto-detect:** Press `Enter` when prompted, and the script will automatically discover your current working directory and inject the correct absolute paths for `imem.hex` and `dmem.hex`.
* **Manual override:** Alternatively, you can type a custom absolute path if your `hex` files are located elsewhere.

### Step 2 — Compile a RISC-V Workload
Choose a C workload and compile it to `.hex` files:

```bash
# Hardware coprocessor path (writes kernel via MMIO, polls STATUS)
make hw_conv_mmio

# Pure-software Gaussian blur (RV32M baseline)
make sw_gaussian_blur

# Sobel edge detection in software
make sw_sobel

# RV32M multiply/divide stress test
make mul_div_test
```
Each target runs the RISC-V GCC toolchain and places `imem.hex` and `dmem.hex` into `hardware/cpu/` automatically.

### Step 3 — Rebuild the Vivado Project
To save space, the massive Vivado project directory is not tracked in git. Instead, you can perfectly reconstruct it in seconds using our provided TCL script:

1. Open **Vivado 2020.1** (or your installed version).
2. Look at the **Tcl Console** at the bottom of the screen.
3. Use the `cd` command to navigate to the root of this repository (e.g., `cd C:/Users/shour/Downloads/Final_version/WORKING_HARDWARE`).
4. Source the build script:
   ```tcl
   source rebuild_vivado_convolver.tcl
   ```
This script will automatically recreate the `vivado_project` folder, instantiate all IP blocks, link all Verilog source files, import the Nexys A7 constraint set, and set up the synthesis and implementation runs.

### Step 4 — Simulate (Optional)
Run RTL simulations before synthesis to catch issues early:

```bash
# RV32M stress test — all 8 ops, div-by-zero, INT_MIN/-1 edge cases
cd hardware/cpu
iverilog -o sim_rv32m.out -I ./rtl ./rtl/*.v ./tb/tb_rv32m_alu.v
vvp sim_rv32m.out

# Pipeline + hazard smoke test
iverilog -o sim_pipeline.out -I ./rtl ./rtl/*.v ./tb/tb_pipeline.v
vvp sim_pipeline.out

# Open waveforms
gtkwave rv32m_alu.vcd
```

### Step 5 — Synthesize and Program the FPGA
1. In Vivado, click **Generate Bitstream** in the Flow Navigator
2. Connect your Nexys A7-100T via USB
3. Open Hardware Manager → Auto Connect
4. Click **Program Device** and select the generated `top_fpga.bit`

### Step 6 — Launch the Dashboard

**Option A — Pre-compiled (Windows, no Python required):**
Double-click `Filter.exe` in the repository root.

**Option B — From source:**
```bash
pip install -r requirements.txt
python fpga_coprocessor_ui.py
```

The dashboard will guide you through:
1. **Connection screen** — select your COM port and baud rate (115200), or enable simulation mode to demo without hardware
2. **Main dashboard** — load an image, select a filter kernel, click RUN HW to stream to the FPGA and receive results, or RUN SW for the software baseline
3. **Performance panel** — displays raw cycle counts, compute time in milliseconds, and the architectural speedup ratio side by side

---

## 🗺️ MMIO Address Map
The coprocessor lives at base address `0x80000000`. All accesses are 32-bit word-aligned.

| Address | Register | Access | Description |
| :--- | :--- | :--- | :--- |
| `0x80000000` | `k0` | W | Kernel coefficient 0 (top-left) |
| `0x80000004` | `k1` | W | Kernel coefficient 1 |
| `0x80000008` | `k2` | W | Kernel coefficient 2 |
| `0x8000000C` | `k3` | W | Kernel coefficient 3 |
| `0x80000010` | `k4` | W | Kernel coefficient 4 (center) |
| `0x80000014` | `k5` | W | Kernel coefficient 5 |
| `0x80000018` | `k6` | W | Kernel coefficient 6 |
| `0x8000001C` | `k7` | W | Kernel coefficient 7 |
| `0x80000020` | `k8` | W | Kernel coefficient 8 (bottom-right) |
| `0x80000028` | `START` | W | Write 1 to begin convolution |
| `0x8000002C` | `STATUS` | R | Reads 1 when convolution is complete |

---

## 👥 Team

| Member | Hardware Ownership |
| :--- | :--- |
| **Shaurya** | `rv32m_alu.v`, `tb_rv32m_alu.v`, integration |
| **Sukhjot** | `hazard_unit.v`, `decoder_ext.v` |
| **Soumik** | `conv_engine.v`, `line_buffer.v`, `img_bram_in/out.v` |
| **Satish** | `mmio_decoder.v`, `conv_datapath.v`, `top_fsm.v` |
| **Abhirup** | C workloads, UART, Python GUI (`fpga_coprocessor_ui.py`) |

<p align="center">
  <b>CS 224 — Advanced Computer Architecture · Group 18</b>
</p>
