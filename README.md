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
* `/demo` - Python GUI scripts and UART communication drivers for the final live demonstration.

## Team Setup & Branching
This project is actively developed by a 5-member team. 
* **Main Branch:** Reserved strictly for Verilog modules that have passed isolated testbench verification.
* **Vivado Users:** Please ensure your local environment respects the root `.gitignore` to prevent pushing `.log`, `.jou`, and massive `.cache/` build directories.

---
*Developed for CS 224: Computer Architecture.*
