# Claude Code Technical Context — Image Convolution SoC

This document provides a summary of the current codebase state, architecture, and recent fixes to save time during planning and exploration.

## 🏗️ System Architecture
- **CPU**: 3-stage RISC-V Pipeline (RV32I + RV32M). No separate MEM stage; memory access happens in EX.
- **Interconnect**: MMIO decoder (Base `0x8000_0000`) manages control registers and kernel coefficients.
- **Coprocessor**: Convolution engine using a 3x128 byte line buffer and a 4-stage pipeline (Mul → RowAdd → Accum → Clamp).
- **Peripherals**: UART controller (serial bridge to PC) and board-level BRAM (16KB IMEM, 16KB DMEM).
- **Software**: PC-side Python GUI (`fpga_coprocessor_ui.py`) handles image preprocessing, real-time visualization, and UART orchestration.

## 🖥️ Host-Side Software (Python GUI)
- **Framework**: `customtkinter` with `Pillow` for image scaling/grayscale conversion.
- **Protocol**: 
  - **TX**: Streams 16,384 raw bytes (128x128 image) via UART.
  - **RX**: Awaits 15,876 raw bytes (126x126 convolved output).
  - **Baud Rate**: Configurable in UI (Default: 115,200).
- **Interactions**: Polling the STATUS MMIO register to trigger result download.

## 📊 MMIO Memory Map (Base: `0x8000_0000`)
| Address        | Description               | Access  | Notes |
|----------------|---------------------------|---------|-------|
| `0x8000_0000-20`| Kernel Coefficients (k0-k8)| Write   | Signed 8-bit |
| `0x8000_0024`  | START Signal              | Write   | Bit[0] = 1 triggers FSM |
| `0x8000_0028`  | STATUS Register           | Read    | Bit[0] = 1 when DONE |
| `0x8000_0030`  | NORM_EN Toggle            | Write   | Bit[0]: 1=Blur, 0=Sobel |
| `0x8000_0034`  | SW_DONE Doorbell          | Write   | Triggers UART transmission |

## 🛠️ Recent Critical Fixes (April 2026)
- **XDC Alignment**: `NexysA7.xdc` pins updated to match `top_fpga.v` ports (`uart_rx_pin`, `uart_tx_pin`).
- **Memory Initialization**: `memory.v` refactored with `INIT_FILE` parameters to resolve missing `.hex` file errors in Vivado synthesis.
- **Module Integration**:
  - `top_fsm.v`: Resolved "identifier used before declaration" for `bram_in_rd_addr`.
  - `top_fsm.v`: Fixed port count mismatch in `line_buffer` instantiation.
  - `pipeline.v`: Successfully routed internal `dmem_*` signals to top-level `dmem_*_o` ports.
- **Synthesis Optimization**: 
  - `line_buffer.v`: Changed `ram_style` from `block` to `distributed`. The row-shifting logic copies 128 registers in one cycle, which is physically impossible for BRAM but fits LUTRAM perfectly.

## ⚠️ Known Invariants & Gotchas
- **BRAM Latency**: IMEM and DMEM reads have a 1-cycle latency. In `pipeline.v`, the MMIO read select signal (`is_mmio_read_wb`) is registered to align the data return from the coprocessor with the CPU WB stage.
- **Division Loop**: Do not modify the division FSM start/busy gating logic. It is sensitive to combinational feedback loops.
- **Register File**: `x0` is hardwired to zero in `pipeline.v`.

## ⏭️ Pending Tasks/Investigations
- **Kernel Write Lockout**: Kernel coefficients can currently be overwritten while the engine is running.
- **DMEM Passthrough**: Ensure non-MMIO addresses in the MMIO decoder range are handled or gracefully ignored.
- **Normalization**: Double-check the bit-width of the clamp logic in `conv_engine.v` (Stage 4).

## 📁 Key File Map
- `hardware/top/top_fpga.v`: Physical board-level top.
- `hardware/cpu/rtl/pipeline.v`: Core CPU integration.
- `hardware/top/top_fsm.v`: Master integration of coprocessor + UART + BRAM.
- `hardware/coprocessor/rtl/line_buffer.v`: Pixel sliding window logic.
- `hardware/cpu/rtl/memory.v`: BRAM models for IMEM/DMEM.
