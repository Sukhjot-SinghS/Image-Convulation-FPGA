# Image-Convulation-FPGA
A custom hardware-software co-processing architecture extending a RISC-V (RV32I) core with RV32M instructions and a memory-mapped 9-MAC DSP convolution engine on an FPGA.
# RISC-V Hardware Image Convolution Engine

## Overview
This repository contains the RTL, software workloads, and demonstration scripts for a custom processor-accelerator system. We extend a standard 3-stage RV32I RISC-V soft-core with two major architectural enhancements:
1. **Phase 1 (ISA Extension):** Full RV32M support (Hardware Multiply and Divide) integrated directly into the processor's Execute stage pipeline with multi-cycle hazard stall logic.
2. **Phase 2 (Hardware Acceleration):** A custom 3x3 convolution coprocessor attached to the CPU's memory bus via Memory-Mapped I/O (MMIO). 

The system is designed for the Xilinx Artix-7 FPGA architecture, utilizing dedicated DSP48E1 slices to achieve a massive >50x throughput speedup over standard sequential CPU execution for real-time edge detection and image filtering.

## System Architecture Highlights
* **CPU Core:** 3-stage pipelined RV32I + RV32M (implemented in Verilog).
* **Coprocessor Datapath:** 3-row sliding line buffer feeding a fully parallel 9-MAC DSP engine. 
* **Control Bridge:** Custom MMIO address decoder routing `0x80000000` memory ranges to hardware control registers.
* **Benchmarking:** Cycle-accurate CSR reads comparing C-compiled software execution (`MUL` instructions) against hardware-accelerated throughput (1 pixel/clock cycle).

## Repository Structure
To maintain a clean working environment and avoid Vivado merge conflicts, the repository is structured as follows:

* `/docs` - Project abstract, datapath block diagrams, and final reports.
* `/hardware`
  * `/cpu` - RV32M ALU, hazard detection unit, and decoder extensions.
  * `/coprocessor` - MMIO decoder, state machine, line buffer, and DSP MAC datapath.
  * `/constraints` - Physical `.xdc` pin mappings for the FPGA board.
* `/software` - The 5 C-workloads compiled via the RISC-V toolchain used for system validation (`sw_sobel.c`, `hw_conv_mmio.c`, etc.).
* `fpga_coprocessor_ui.py` (Root) - Python GUI script and UART communication driver for the live demonstration.

## Team Setup & Branching
This project is actively developed by a 5-member team. 
* **Main Branch:** Reserved strictly for Verilog modules that have passed isolated testbench verification.
* **Vivado Users:** Please ensure your local environment respects the root `.gitignore` to prevent pushing `.log`, `.jou`, and massive `.cache/` build directories.

## Quick Start / Running the Project

To evaluate and run this project on your local machine, please follow these exact steps:

### 1. Update Hardcoded Memory Paths
The FPGA block RAM initialization requires absolute paths for synthesis. Open `hardware/cpu/rtl/memory.v` and update the `$readmemh` paths on **line 17** and **line 58** by replacing `<INSERT_YOUR_PATH_HERE>` with the absolute path of this repository's root directory on your system.
*   **Example:** Change `"<INSERT_YOUR_PATH_HERE>/hardware/cpu/imem.hex"` to `"D:/Your/Path/hardware/cpu/imem.hex"`

### 2. Compile the Software (Make)
Open a terminal in the root directory of this repository and run `make` along with the program you want to load onto the CPU (e.g., the hardware convolution demonstration).
```bash
make hw_conv_mmio
```
*(This will invoke the RISC-V GCC toolchain to compile the C-code and generate the `imem.hex` and `dmem.hex` files needed by the FPGA).*

### 3. Rebuild the Vivado Project
We have provided a Tcl script to automatically reconstruct the Vivado project with all RTL files and constraints.
1. Open **Vivado**.
2. At the bottom of the screen, open the **Tcl Console**.
3. Use the `cd` command to navigate to the root of this project folder.
4. Run the rebuild script:
   ```tcl
   source rebuild_vivado_convolver.tcl
   ```

### 4. Program the FPGA
1. In Vivado, click **Generate Bitstream** in the Flow Navigator.
2. Once the bitstream is generated, open the **Hardware Manager**.
3. Connect your Nexys A7-100T board via USB and select **Auto Connect**.
4. Click **Program Device** to flash the bitstream onto the FPGA.

### 5. Launch the UI
With the FPGA programmed and running, you can now launch the Python GUI to send an image and see the convolution output.
*   **Easy Mode:** Simply double-click `Filter.exe` located in the root directory.
*   **From Source:** Install the dependencies (`pip install -r requirements.txt`) and run `python fpga_coprocessor_ui.py`.

---
*Developed for CS 224: Computer Architecture.*
