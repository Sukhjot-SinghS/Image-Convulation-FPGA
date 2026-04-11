# CLAUDE.md

This file gives Claude Code the context it needs to work on this repository productively. Read it before doing anything else in a new session.

---

## Project Overview

**Group 18 — Hardware-Accelerated Grayscale Image Convolution Coprocessor**
CS 224 FPGA project, built on a **Nexys A7 (Artix-7 XC7A100T)**.

The design extends a 3-stage RV32I RISC-V pipeline in two phases:

- **Phase 1 — RV32M extension**: All 8 multiply/divide instructions (`MUL`, `MULH`, `MULHSU`, `MULHU`, `DIV`, `DIVU`, `REM`, `REMU`) added to the Execute stage via a dedicated `rv32m_alu` module. Multiplications are single-cycle (Vivado infers DSP48E1 blocks). Division uses a 32-cycle iterative restoring-division FSM and stalls the pipeline via `alu_busy_o`.
- **Phase 2 — Convolution coprocessor**: A memory-mapped 3×3 grayscale convolution engine attached to the CPU through an MMIO decoder. The CPU writes the kernel and a START flag, the engine streams pixels through a line buffer + DSP48E1 MAC array, and writes results back to BRAM. The CPU polls a STATUS register for completion.

**Roles:**
- **Shaurya** — integration lead, owner of `rv32m_alu.v` and `tb_rv32m_alu.v` in `hardware/cpu/`
- **Sukhjot** — `hazard_unit.v`, `decoder_ext.v`
- **Soumik** — `conv_engine.v`, `line_buffer.v`, `img_bram_in.v`, `img_bram_out.v`
- **Satish** — MMIO decoder, `conv_datapath.v`, `top_fsm.v`
- **Abhirup** — C workloads, UART, Python GUI (`demo.py`)

---

## Repository Layout

```
.
├── CLAUDE.md                # AI agent context file
├── CHANGELOG.md             # Project changelog
├── demo/                    # Python GUI / scripts
├── docs/                    # Project documentation (PDFs, diagrams)
├── hardware/                # Core hardware Verilog files
│   ├── coprocessor/         # Phase 2: Convolution Coprocessor
│   │   ├── rtl/             # Coprocessor source code
│   │   └── tb/              # Coprocessor testbenches
│   ├── cpu/                 # Phase 1: RV32I + RV32M 3-stage pipeline
│   │   ├── dmem.hex         # Data Memory initialization
│   │   ├── imem.hex         # Instruction Memory initialization
│   │   ├── rtl/             # CPU source code
│   │   │   ├── pipeline.v   # Top-level pipeline wrapper 
│   │   │   ├── IF_ID.v      # Fetch + IF/ID pipeline register
│   │   │   ├── execute.v    # Execute stage; instantiates rv32m_alu
│   │   │   ├── wb.v         # Writeback stage + register file
│   │   │   ├── hazard_unit.v# Forwarding / stall logic
│   │   │   ├── decoder_ext.v# RV32M decode extension
│   │   │   ├── rv32m_alu.v  # 8 RV32M ops
│   │   │   └── memory.v     # IMEM/DMEM models
│   │   └── tb/              # CPU testbenches
│   │       ├── tb_pipeline.v
│   │       └── tb_rv32m_alu.v # Stress test for RV32M ops
│   └── top/
│       └── top_fpga.v       # Board-level top
└── software/                # C code and tools
    └── hex/                 # Compiled hex binaries
```

`pipeline.v` and `top_fpga.v` are wrappers — they should not appear as functional blocks in the architecture diagram, only their contents should.

---

## MMIO Address Map

Base: `0x8000_0000`

| Address       | Register     | Access | Notes                                 |
|---------------|--------------|--------|---------------------------------------|
| `0x8000_0000` | `k0`         | W      | Kernel coefficient 0                  |
| `0x8000_0004` | `k1`         | W      |                                       |
| ...           | ...          | W      |                                       |
| `0x8000_0020` | `k8`         | W      | Kernel coefficient 8                  |
| `0x8000_0028` | `START`      | W      | Write 1 to start convolution          |
| `0x8000_002C` | `STATUS`     | R      | Reads 1 when convolution is done      |

Kernel writes are gated to `(addr - KERNEL_BASE) < 36` and 4-byte aligned. Image data lives in `img_bram` and is accessed by the conv engine directly, not through the CPU bus.

---

## Build & Simulation

**Simulator:** Icarus Verilog + GTKWave
**Synthesis:** Vivado (Nexys A7, Artix-7 XC7A100T)

Typical sim flow from the repo root in powershell/bash:

```bash
# RV32M stress (all 8 ops, edge cases incl. div-by-zero, INT_MIN/-1)
cd hardware/cpu
iverilog -o sim_rv32m.out -I ./rtl ./rtl/*.v ./tb/tb_rv32m_alu.v
vvp sim_rv32m.out
gtkwave rv32m_alu.vcd &

# Pipeline / Hazard smoke test
iverilog -o sim_pipeline.out -I ./rtl ./rtl/*.v ./tb/tb_pipeline.v
vvp sim_pipeline.out
```
*(Use similar commands for coprocessor components using files from `hardware/coprocessor/rtl/*.v`)*

---

## Architectural Invariants (don't break these)

1. **Pipeline stall composition:** `pipe_stall = stall_read || div_busy`. Both must remain in the OR. `div_busy` comes from `rv32m_alu.alu_busy_o`.
2. **Division start gating:** In `execute.v`, the `start` signal into `rv32m_alu` must be `is_rv32m & ~div_busy`. Without the `~div_busy` mask, the FSM re-triggers combinationally and never finishes — this bug already bit us once.
3. **Busy signal definition:** Inside `rv32m_alu.v`, `assign busy = (div_state != S_IDLE);` — do **not** OR in `start` or any combinational expression of it. That re-creates the re-trigger loop.
4. **DSP48E1 inference:** Multiplies in `rv32m_alu.v` and `conv_datapath.v` use plain `*` operators on unsigned/signed wires so Vivado infers DSP48E1 hard blocks. Do not replace with shift-and-add unless asked.
5. **Three-stage pipeline:** IF/ID → EX → WB. There is no separate MEM stage; memory access happens inside EX. Keep new logic consistent with this.
6. **Wrappers are invisible:** `pipeline.v` and `top_fpga.v` exist only for hookup. Functional logic belongs in stage modules (`IF_ID.v`, `execute.v`, `wb.v`) or coprocessor modules.

---

## Known Issues / Open Work

These are real, code-verified issues — not speculation. Fix only when asked, but be aware of them:

- **Kernel write lockout missing** in `mmio_decoder.v` / `kernel_regfile.v`: kernel coefficients can be overwritten while `conv_engine` is mid-run. Should be gated on `~conv_busy`.
- **DMEM passthrough missing** in `mmio_decoder.v`: non-MMIO addresses aren't currently routed back to main DMEM cleanly in all paths.
- **`is_rv32m` signal path** from `decoder_ext` → `execute` → `rv32m_alu` should be re-traced end-to-end before final synthesis.
- **Conv engine bugs flagged in review:** missing normalization shift on the MAC output, output width mismatch between `conv_datapath` and the BRAM write port, and a potential MMIO race where START can be asserted before all 9 kernel words have committed.
- **`top_fpga.v` integration:** the MMIO decoder and hazard unit are not yet fully wired in the top wrapper as of last check. (Demo 1 uses a simplified subset of the CPU without the coprocessor).

---

## Working Style & Conventions

- **Verilog-2001/2012**, lowercase_snake signal names, `_o`/`_i` suffixes for module ports where the existing files use them (keep the local convention of each file).
- Prefer **synchronous resets** unless the surrounding module is async — match the file you're editing.
- New FSMs use the `S_IDLE / S_CALC / S_DONE` naming pattern from `rv32m_alu.v`.
- When adding signals across module boundaries, update **all** of: the producing module's port list, the wrapper's wire declaration, the wrapper's instantiation, and the consumer's port list. Missed wires in `pipeline.v` are the #1 source of "it simulates but synthesizes wrong" bugs here.
- Don't generate scaffolding files, READMEs, or extra docs unless explicitly asked.
- When asked to fix a bug, **trace it in the actual RTL first** and quote the exact signal names — don't speculate from intent.
- Block-diagram or documentation tasks: verify against the real signal names in the `.v` files, not against the abstract design.

---

## Quick Sanity Checklist Before Committing

- [ ] `iverilog -o sim ... -I hardware/cpu/rtl hardware/cpu/rtl/*.v ...` builds clean (no redefinition warnings)
- [ ] `tb_rv32m_alu` passes — all 8 ops, div-by-zero returns `-1`/dividend, `INT_MIN / -1` returns `INT_MIN` for `DIV` and `0` for `REM`
- [ ] `tb_pipeline` passes — no infinite stalls, `div_busy` deasserts within 32 cycles of a divide
- [ ] No new hardcoded absolute paths
- [ ] Any new cross-module signal is wired in `pipeline.v` AND declared in both endpoints
- [ ] DSP48E1 / BRAM inference still happens after synthesis (check Vivado utilization report)
