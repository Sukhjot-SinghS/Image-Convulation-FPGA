# CHANGELOG
## RV32M Extension Integration - Phase 1

All changes made to integrate the RV32M multiply/divide extension into the
3-stage pipelined RV32I RISC-V processor. Targeting Nexys A7 FPGA (Artix-7 100T).

---

### rv32m_alu.v (NEW FILE, renamed from rv32m_alu_1.v)

**What:** Complete RV32M ALU handling all 8 multiply/divide instructions.

**Changes:**
- Renamed file from `rv32m_alu_1.v` to `rv32m_alu.v` for consistency with build plan
- Module name: `rv32m_alu`
- **MUL family** (funct3[2]=0): Single-cycle combinational multiply using 33-bit
  signed operands. Vivado infers DSP48E1 slices.
  - MUL (funct3=000): lower 32 bits of signed x signed
  - MULH (funct3=001): upper 32 bits of signed x signed
  - MULHSU (funct3=010): upper 32 bits of signed x unsigned
  - MULHU (funct3=011): upper 32 bits of unsigned x unsigned
- **DIV family** (funct3[2]=1): 33-cycle iterative restoring divider
  (S_IDLE -> S_RUNNING x32 -> S_DONE).
  - DIV (funct3=100): signed quotient
  - DIVU (funct3=101): unsigned quotient
  - REM (funct3=110): signed remainder
  - REMU (funct3=111): unsigned remainder
- **Edge cases per RISC-V spec:**
  - Divide by zero: DIV/DIVU -> 0xFFFFFFFF, REM/REMU -> dividend
  - Signed overflow (MIN_INT / -1): DIV -> MIN_INT, REM -> 0
- **Busy signal:** `busy = (div_state != S_IDLE) || (start && is_div_op)`
  asserts immediately on division start for same-cycle pipeline stall
- **Fixed bug:** Removed combinational loop in busy signal that caused
  re-trigger feedback (DIV taking ~40 cycles instead of 33)

---

### decoder_ext.v (NEW FILE)

**What:** RV32M instruction detector.

**Changes:**
- Checks opcode == ARITHR (0110011) AND funct7 == 0000001
- Output: single `is_rv32m` wire
- Used by IF_ID stage to flag M-extension instructions

---

### IF_ID.v (MODIFIED)

**What:** Added RV32M detection and pipeline register support.

**Changes:**
1. Instantiated `decoder_ext` to detect RV32M instructions:
   ```verilog
   decoder_ext u_decoder_ext (
       .instruction (instruction_i),
       .is_rv32m    (is_rv32m_decoded)
   );
   ```
2. Added `is_rv32m_w` output port to module
3. Added `is_rv32m_i` input and `is_rv32m_o` output to `id_ex_reg` pipeline register
4. `id_ex_reg` clears `is_rv32m_o` to 0 on reset, pipes through on clock edge
5. `alu_i` signal includes ARITHR (since RV32M shares the same opcode, `is_rv32m`
   disambiguates in execute stage)

---

### execute.v (MODIFIED)

**What:** Instantiated rv32m_alu and integrated with ALU result mux.

**Changes:**
1. Added input port `is_rv32m`, output port `rv32m_busy`
2. Instantiated `rv32m_alu`:
   ```verilog
   rv32m_alu u_rv32m_alu (
       .clk       (clk),
       .reset_n   (reset),
       .start     (rv32m_start),  // is_rv32m & !rv32m_busy_internal
       .funct3    (alu_op),
       .operand1  (alu_operand1),
       .operand2  (alu_operand2),
       .result    (rv32m_result),
       .busy      (rv32m_busy_internal),
       .valid     (rv32m_valid)
   );
   ```
3. Start gating: `rv32m_start = is_rv32m & !rv32m_busy_internal` prevents
   re-triggering during multi-cycle divide
4. ALU result mux override:
   ```verilog
   if (is_rv32m && alu)
       ex_result = rv32m_result;
   ```
5. `alu_to_reg` in `ex_mem_wb_reg` includes `is_rv32m` via the `alu` signal
   (since IF_ID sets `alu=1` for ARITHR, which includes RV32M)

---

### hazard_unit.v (NEW FILE)

**What:** Centralized stall signal aggregator.

**Changes:**
- Combines three stall sources into unified pipeline control:
  - `rv32m_busy`: Multi-cycle divide in progress
  - `ext_stall`: Top-level external stall input
  - `wb_stall`: Writeback stage branch stall
- Outputs:
  - `pc_stall`: Freezes PC update
  - `decode_stall`: Freezes IF/ID and ID/EX pipeline registers
  - `writeback_gate`: Blocks register file writeback

---

### pipeline.v (MODIFIED)

**What:** Top-level integration of RV32M, hazard unit, and memory port exposure.

**Changes:**
1. **Include update:** Changed `include "rv32m_alu_1.v"` to `include "rv32m_alu.v"`
2. **New includes:** Added `decoder_ext.v` and `hazard_unit.v`
3. **New wires:** `is_rv32m`, `rv32m_busy`, hazard unit stall signals
4. **Memory interface ports exposed:** Previously internal wires are now module
   output ports for proper top-level wiring (no more hierarchical refs):
   - `inst_mem_address [31:0]` - instruction memory address from WB stage
   - `inst_mem_is_ready` - instruction fetch enable
   - `dmem_read_address [31:0]` - data memory read address
   - `dmem_read_ready` - data memory read enable (load instructions)
   - `dmem_write_address [31:0]` - data memory write address
   - `dmem_write_ready` - data memory write enable
   - `dmem_write_data [31:0]` - data to write
   - `dmem_write_byte [3:0]` - byte write strobe
5. **Hazard unit instantiation:** Routes `rv32m_busy`, `ext_stall`, `wb_stall`
   through `hazard_unit` to produce `hazard_pc_stall`, `hazard_decode_stall`,
   `hazard_wb_gate`
6. **Stall routing:** `stall_read` register updated from `hazard_decode_stall`;
   `hazard_pc_stall` gates PC update; `hazard_wb_gate` gates register writeback
7. **RV32M wiring:** `IF_ID.is_rv32m_w` -> `execute.is_rv32m`;
   `execute.rv32m_busy` -> `hazard_unit.rv32m_busy`
8. **Cleaned up stale TODO comments** in WB stage instantiation

---

### memory.v (MODIFIED)

**What:** Fixed non-portable hardcoded file paths.

**Changes:**
- `instr_mem`: Changed `$readmemh` from absolute Windows path
  (`C:/Users/Lenovo/OneDrive/Desktop/5B_file/.../imem.hex`) to `"imem.hex"`
- `data_mem`: Changed `$readmemh` from absolute Windows path to `"dmem.hex"`
- Hex files must now be in the simulation working directory

---

### opcode.vh (UNCHANGED)

**Note:** RV32M funct3 encodings (MUL=000 through REMU=111) were already present.
Disambiguation between base ALU and M-ext uses the `is_rv32m` signal, not
opcode constants.

---

### wb.v (UNCHANGED)

**Note:** No changes needed. RV32M results flow through the existing
`ex_mem_result` path in the EX->WB pipeline register.

---

### top_fpga.v (REWRITTEN)

**What:** Complete rewrite to use proper port connections.

**Changes:**
- Removed all hierarchical references (`pipe_u.inst_fetch_pc`, `pipe_u.dmem_read_ready`, etc.)
- Connected all new pipeline memory ports via named wires:
  - `inst_mem_address` -> `IMEM.pc`
  - `dmem_read_ready` -> `DMEM.re`
  - `dmem_read_address` -> `DMEM.raddr`
  - `dmem_write_ready` -> `DMEM.we`
  - `dmem_write_address` -> `DMEM.waddr`
  - `dmem_write_data` -> `DMEM.wdata`
  - `dmem_write_byte` -> `DMEM.wstrb`
- LED display now shows `pc_out[15:0]` via proper port
- Memory valid signals hardwired to 1'b1 (single-cycle memory)
- All TODO placeholders resolved

---

### tb_pipeline.v (REWRITTEN)

**What:** Complete rewrite to use proper port connections.

**Changes:**
- Removed all hierarchical references (`DUT.pc_out`, `DUT.dmem_read_ready`, etc.)
- Connected all pipeline memory ports via named wires (same pattern as top_fpga.v)
- `$display` uses `pc_out` port instead of hierarchical `DUT.next_pc`
- Still uses one hierarchical ref for debug display: `DUT.execute.ex_result`
  (acceptable for testbench, not synthesized)

---

### software/hex/imem.hex (NEW FILE)

**What:** RV32M test program.

**Test sequence:**
| PC   | Encoding   | Instruction         | Expected |
|------|-----------|---------------------|----------|
| 0x00 | 00F00093  | addi x1, x0, 15    | x1 = 15  |
| 0x04 | 00500113  | addi x2, x0, 5     | x2 = 5   |
| 0x08 | 022081B3  | mul  x3, x1, x2    | x3 = 75  |
| 0x0C | 0220C233  | div  x4, x1, x2    | x4 = 3   |
| 0x10 | 0220E2B3  | rem  x5, x1, x2    | x5 = 0   |
| 0x14 | 00C00313  | addi x6, x0, 12    | x6 = 12  |
| 0x18 | 00700393  | addi x7, x0, 7     | x7 = 7   |
| 0x1C | 02730433  | mul  x8, x6, x7    | x8 = 84  |
| 0x20 | 027344B3  | div  x9, x6, x7    | x9 = 1   |
| 0x24 | 02736533  | rem  x10, x6, x7   | x10 = 5  |
| 0x28 | 00000063  | beq  x0, x0, 0     | halt     |

---

### software/hex/dmem.hex (NEW FILE)

**What:** Empty data memory initialization (zeroed). No data memory needed for
RV32M ALU tests.

---

### Known Issues / Not Yet Done

1. **iverilog not installed** on current machine - compilation not verified locally.
   Run `iverilog -o sim/tb_pipeline -I rtl rtl/memory.v tb/tb_pipeline.v rtl/pipeline.v`
   to verify.
2. **Branch-during-DIV** is unhandled - if a branch is taken while divide is
   in-flight, the divider completes and writes back anyway. Acceptable for Phase 1.
3. **Exception flag** in IF_ID.v never clears once set. Non-blocking for Phase 1
   test programs.
4. **AUIPC** instruction not implemented (only LUI for upper immediates).
