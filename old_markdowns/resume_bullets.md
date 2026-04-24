# SWE Intern Resume — FPGA Project Bullets

**Full-Stack RISC-V SoC & Image Processing Accelerator** | Jan 2026 – May 2026  
*CS 224 Course Project, IIT Guwahati* | [GitHub Link]

- Built a 3-stage RV32IM processor in Verilog on a Nexys A7 FPGA, implementing all 8 multiply/divide instructions with single-cycle DSP48E1 multiply and a 32-cycle iterative division FSM with pipeline stall control.
- Designed a memory-mapped (MMIO) hardware accelerator for 3×3 grayscale image convolution (Sobel/Blur) that offloads CPU compute to a DSP48E1 MAC array with line buffering, reducing convolution time by ~50× over software.
- Built a Python/CustomTkinter GUI with async UART serial communication to stream image data to the FPGA and toggle live between software and hardware execution modes.
