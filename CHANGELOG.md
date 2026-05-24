# CHANGELOG

## Convolution Coprocessor Integration - Phase 2 (CURRENT)
Full integration of the memory-mapped image processing engine with the RV32IM CPU. Targeting Nexys A7 FPGA (Artix-7 100T).

---

### line_buffer.v (MODIFIED)
**What:** 3-row sliding window for pixel streaming.
**Changes:**
- **Latency Fix:** Added 1-cycle pipeline for BRAM pending signals (`bram_rd_valid`). This compensates for synchronous BRAM read latency, ensuring pixel indices (`p11`, etc.) align perfectly with the BRAM data arrival.
- **Handshake:** Implemented `start`/`done` signals for top-level FSM coordination.
- **Verification:** 29/29 tests PASSED in `tb_line_buffer.v`.

### conv_engine.v (MODIFIED)
**What:** 3×3 MAC array with 9 DSP48E1 multipliers.
**Changes:**
- **Pipeline:** 3-cycle registered pipeline (Multiply → Row Sums → Accumulate/Clamp).
- **Saturation:** Added hard clamping to ensure output pixels stay within 0-255 range.
- **Verification:** 33/33 tests PASSED in `tb_conv_engine.v`.

### top_fsm.v (REWRITTEN)
**What:** Master system controller (6-state machine).
**Changes:**
- **DRAIN State:** Added 4-cycle pipeline flush counter to extract the final pixels from the conv_engine after processing finishes.
- **UART Integration:** Automated sequence: `WAIT_IMAGE` → `WAIT_START` → `PROCESSING` → `DRAIN` → `TRANSMIT`.
- **UART TX Sync:** Implemented 3-state BRAM fetch machine (`IDLE` → `WAIT` → `SEND`) for stable UART data extraction.

### mmio_decoder.v & kernel_regfile.v (INTEGRATED)
**What:** CPU-to-Coprocessor bridge.
**Changes:**
- **Memory Map:** Kernel weights at `0x80000000`, Start at `0x80000040`, Done status at `0x80000044`.
- **Race Guard:** Latch-based MMIO write gating to prevent kernel updates during active processing.

---

## RV32M Extension Integration - Phase 1
All changes made to integrate the RV32M multiply/divide extension into the 3-stage pipelined RV32I RISC-V processor.

---

### rv32m_alu.v
**What:** Complete RV32M ALU handling all 8 multiply/divide instructions.
**Features:**
- MUL family: Single-cycle multiply using DSP48E1 slices.
- DIV family: 33-cycle iterative restoring divider.
- Edge cases: Division by zero and signed overflow (MIN_INT / -1) handled per RISC-V spec.

### hazard_unit.v
**What:** Centralized stall signal aggregator.
**Features:**
- Combines `rv32m_busy`, `ext_stall`, and `wb_stall` to freeze pipeline registers and gate writeback.

---

## Final Verification Summary
| Test Group | Component | Passing | Result |
|:---|:---|:---:|:---|
| **Pipeline** | `tb_rv32m_alu` | 29/29 | ✅ **CLEAN** |
| **Logic** | `tb_conv_engine` | 33/33 | ✅ **CLEAN** |
| **Streaming**| `tb_line_buffer` | 29/29 | ✅ **CLEAN** |
| **System** | `tb_conv_datapath` | 14/14 | ✅ **CLEAN** |
| **Memory** | `tb_img_bram_in` | 12/12 | ✅ **CLEAN** |
| **Memory** | `tb_img_bram_out`| 14/14 | ✅ **CLEAN** |
| **TOTAL** | | **131/131** | ✅ **100% PASS** |

---

## Known Issues (Resolved)
- ✅ **BRAM Latency:** Fixed via pending signal pipelining in line_buffer.
- ✅ **Pipeline Drainage:** Fixed via DRAIN state in top_fsm.
- ✅ **UART Send Mismatch:** Fixed via 3-state BRAM fetch machine.
