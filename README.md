# 🚀 Hardware-Accelerated Grayscale Image Convolution Coprocessor
**CS 224 — FPGA Project | Group 18**  
**Platform:** Nexys A7 (Artix-7 XC7A100T)

**Team:** Shaurya · Soumik · Satish · Abhirup · Sukhjot

---

## 📋 System Summary

A memory-mapped **3×3 grayscale image convolution coprocessor** integrated with a custom **3-stage pipelined RV32IM RISC-V CPU**. The system receives a 128×128 grayscale image over UART, applies a programmable convolution kernel (Sobel, Sharpen, Box Blur) using a dedicated DSP48E1-based MAC array, and transmits the 126×126 filtered result back. The CPU controls the coprocessor through MMIO registers at `0x80000000`.

### Architecture at a Glance

```
PC (Python) ──UART──► img_bram_in ──► line_buffer ──► conv_engine ──► img_bram_out
                          ▲                                                │
                          │            ┌──────────────┐                    │
                    uart_rx            │  RV32IM CPU  │              uart_tx ──► PC
                                       │  (3-stage)   │
                                       └──────┬───────┘
                                              │
                                        mmio_decoder
                                              │
                                       kernel_regfile
```

---

## 🛠️ Current Project Status

| Component | Description | Verification |
|-----------|-------------|:---:|
| **RV32I CPU** | 3-stage pipeline (IF/ID, EX, MEM/WB) with forwarding & hazard detection | ✅ |
| **RV32M ALU** | All 8 MUL/DIV instructions · Single-cycle multiply · 32-cycle restoring division | ✅ 29/29 |
| **Conv Engine** | 3-cycle pipelined 3×3 MAC array with saturation clamping (0–255) | ✅ 33/33 |
| **Line Buffer** | 3-row sliding window with 1-cycle BRAM latency compensation | ✅ 29/29 |
| **Full Datapath** | img_bram_in → line_buffer → conv_engine → img_bram_out | ✅ 14/14 |
| **BRAM In/Out** | Dual-port 16KB block RAM for input and output images | ✅ 26/26 |
| **UART TX/RX** | 115200 baud, 8N1 | ✅ Module-level |
| **Top FSM** | 6-state controller with pipeline drain stage | RTL complete |
| **FPGA Synthesis** | Targeting Nexys A7 XC7A100T | ⬜ Pending |

**Total: 131/131 tests passing across 6 testbenches**

---

## 🏗️ Design Highlights

### Phase 1 — RV32M Extension
- All 8 multiply/divide instructions (`MUL`, `MULH`, `MULHSU`, `MULHU`, `DIV`, `DIVU`, `REM`, `REMU`)
- Multiplications are **single-cycle** (Vivado infers DSP48E1 blocks)
- Division uses a **32-cycle iterative restoring-division FSM** and stalls the pipeline via `alu_busy_o`
- Edge cases handled: division by zero, signed overflow, `MIN_INT / -1`

### Phase 2 — Convolution Coprocessor
- **9 parallel DSP48E1 multipliers** for the 3×3 kernel
- **3-cycle registered pipeline**: Multiply → Row Sums → Accumulate+Clamp
- **Line buffer** streams 128-pixel rows through a 3-row sliding window
- **BRAM latency compensation** — pipelined pending signals ensure correct data sampling
- **Pipeline drain state** in top FSM — 4 extra cycles after `lb_done` to flush final pixels

### MMIO Memory Map

| Address | Register | Access |
|---------|----------|--------|
| `0x80000000`–`0x80000020` | Kernel coefficients k0–k8 | Write |
| `0x80000040` | START (pulse) | Write |
| `0x80000044` | DONE status | Read |

---

## 📁 Repository Structure

```
📦 Image-Convolution-FPGA
 ┣ 📂 hardware/
 ┃ ┣ 📂 cpu/
 ┃ ┃ ┣ 📂 rtl/           # IF_ID.v, execute.v, memory.v, wb.v, pipeline.v
 ┃ ┃ ┃                    # rv32m_alu.v, hazard_unit.v, opcode.vh
 ┃ ┃ ┗ 📂 tb/            # tb_rv32m_alu.v, tb_pipeline.v, tb_hazard_unit.v
 ┃ ┣ 📂 coprocessor/
 ┃ ┃ ┣ 📂 rtl/           # conv_engine.v, conv_datapath.v, line_buffer.v
 ┃ ┃ ┃                    # img_bram_in.v, img_bram_out.v
 ┃ ┃ ┃                    # kernel_regfile.v, mmio_decoder.v
 ┃ ┃ ┃                    # uart_rx.v, uart_tx.v
 ┃ ┃ ┗ 📂 tb/            # tb_conv_engine.v, tb_conv_datapath.v
 ┃ ┃                      # tb_line_buffer.v, tb_img_bram_in.v, tb_img_bram_out.v
 ┃ ┗ 📂 top/
 ┃   ┣ top_fsm.v          # Top-level integration FSM (6 states)
 ┃   ┗ top_fpga.v         # FPGA wrapper with pin constraints
 ┣ 📂 software/
 ┃ ┗ 📂 mem_generator/    # C test programs, linker scripts, hex generators
 ┃   ┣ hw_conv_mmio.c     # MMIO convolution driver
 ┃   ┣ sw_sobel.c         # Software Sobel edge detection
 ┃   ┣ sw_blur.c          # Software box blur
 ┃   ┣ mul_div_test.c     # RV32M stress test
 ┃   ┗ start.s            # Bootloader (SP init → main)
 ┣ 📂 uart/               # Standalone UART testbench and simulation
 ┗ 📜 Makefile             # Master build controller
```

---

## 🏃 Quickstart

### Run Simulation (Icarus Verilog)

```bash
# Clone
git clone https://github.com/Sukhjot-SinghS/Image-Convulation-FPGA.git
cd Image-Convulation-FPGA

# Run conv_engine testbench (33 tests)
cd hardware/coprocessor
iverilog -o sim.vvp rtl/conv_engine.v rtl/conv_datapath.v rtl/line_buffer.v tb/tb_conv_engine.v
vvp sim.vvp

# Run full datapath testbench (14 tests)
iverilog -o sim_dp.vvp rtl/conv_datapath.v rtl/conv_engine.v rtl/line_buffer.v \
    rtl/img_bram_in.v rtl/img_bram_out.v tb/tb_conv_datapath.v
vvp sim_dp.vvp

# Run RV32M ALU testbench (29 tests)
cd ../cpu
iverilog -o sim_alu.vvp rtl/rv32m_alu.v tb/tb_rv32m_alu.v
vvp sim_alu.vvp
```

### Build C Programs (requires `riscv-none-elf-gcc`)

```bash
make sw_sobel        # Compile and generate hex for Sobel filter
make mul_div_test    # Compile and generate hex for MUL/DIV test
make clean           # Clean build artifacts
```

---

## 📊 Verification Results

```
tb_rv32m_alu ........... 29/29 PASSED  ✅  (MUL/DIV/REM + edge cases)
tb_conv_engine ......... 33/33 PASSED  ✅  (pipeline timing + saturation)
tb_line_buffer ......... 29/29 PASSED  ✅  (BRAM streaming + window alignment)
tb_conv_datapath ....... 14/14 PASSED  ✅  (end-to-end pixel correctness)
tb_img_bram_in ......... 12/12 PASSED  ✅  (read/write/latency)
tb_img_bram_out ........ 14/14 PASSED  ✅  (read/write/burst)
─────────────────────────────────────────
TOTAL                  131/131 PASSED
```

---

## 👥 Team Contributions

| Member | Responsibility |
|--------|---------------|
| **Shaurya** | RV32M ALU, 3-stage CPU pipeline, hazard unit, line buffer fix |
| **Soumik** | Conv engine, line buffer, BRAMs, all coprocessor testbenches |
| **Satish** | Kernel register file, MMIO decoder, top FSM integration |
| **Abhirup** | UART TX/RX, top_fpga wrapper, build system, C test programs |
| **Sukhjot** | Repository management, documentation, demo coordination |

---

## 📜 License

Academic project for CS 224 — Digital Design Laboratory, Spring 2026.
