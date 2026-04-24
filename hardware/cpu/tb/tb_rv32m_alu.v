`timescale 1ns / 1ps

// ============================================================================
// RV32M Stress Test — Full Pipeline Testbench
// ============================================================================
// Loads imem_stress.hex with 52 instructions testing all 8 RV32M operations:
//   - Basic MUL/DIV/REM
//   - All signed combinations (-/+, +/-, -/-)
//   - Division by zero (DIV, DIVU, REM, REMU)
//   - Signed overflow (MIN_INT / -1)
//   - Upper multiply (MULH, MULHSU, MULHU) with tricky sign combos
//   - Unsigned division (DIVU, REMU) with large values
//   - Back-to-back MUL→DIV→REM→MUL
//   - Data dependency (forwarding: DIV result → MUL operand)
//
// Self-checking: dumps all registers and reports PASS/FAIL per register.
// ============================================================================

module tb_rv32m_alu;

    // -----------------------------------------------------------------------
    // Clock and Reset
    // -----------------------------------------------------------------------
    reg clk;
    reg reset;

    initial clk = 0;
    always #5 clk = ~clk;  // 100 MHz

    initial begin
        reset = 0;
        #15;
        reset = 1;
    end

    // -----------------------------------------------------------------------
    // Waveform dump
    // -----------------------------------------------------------------------
    initial begin
        $dumpfile("rv32m_alu.vcd");
        $dumpvars(0, tb_rv32m_alu);
    end

    // -----------------------------------------------------------------------
    // Pipe <-> Memory wires
    // -----------------------------------------------------------------------
    wire [31:0] inst_mem_read_data;

    wire [31:0] dmem_read_address;
    wire        dmem_read_ready;
    wire [31:0] dmem_read_data;

    wire [31:0] dmem_write_address;
    wire        dmem_write_ready;
    wire [31:0] dmem_write_data;
    wire [3:0]  dmem_write_byte;

    wire [31:0] pc_out;
    wire        exception;

    // -----------------------------------------------------------------------
    // DUT: Pipeline CPU
    // -----------------------------------------------------------------------
    pipe DUT (
        .clk                (clk),
        .reset              (reset),
        .stall              (1'b0),
        .exception          (exception),
        .pc_out             (pc_out),

        .inst_mem_is_valid  (1'b1),
        .inst_mem_read_data (inst_mem_read_data),

        .dmem_read_data_temp(dmem_read_data),
        .dmem_read_valid    (1'b1),
        .dmem_write_valid   (1'b1),

        .dmem_re_o          (dmem_read_ready),
        .dmem_raddr_o       (dmem_read_address),
        .dmem_we_o          (dmem_write_ready),
        .dmem_waddr_o       (dmem_write_address),
        .dmem_wdata_o       (dmem_write_data),
        .dmem_wstrb_o       (dmem_write_byte),

        .mmio_read_data     (32'b0)
    );

    // -----------------------------------------------------------------------
    // Instruction Memory
    // -----------------------------------------------------------------------
    instr_mem IMEM (
        .clk  (clk),
        .pc   (pc_out),
        .instr(inst_mem_read_data)
    );

    // -----------------------------------------------------------------------
    // Data Memory
    // -----------------------------------------------------------------------
    data_mem DMEM (
        .clk  (clk),
        .re   (dmem_read_ready),
        .raddr(dmem_read_address),
        .rdata(dmem_read_data),
        .we   (dmem_write_ready),
        .waddr(dmem_write_address),
        .wdata(dmem_write_data),
        .wstrb(dmem_write_byte)
    );

    // -----------------------------------------------------------------------
    // Halt detection: PC has reached the final self-loop instruction
    // (BEQ at 0xCC).  Because the 2-cycle branch stall makes PC oscillate
    // between 0xCC / 0xD0 / 0xD4, we count *any* cycle where PC >= 0xCC
    // and the pipeline is not busy.  10 such cycles = program done.
    // -----------------------------------------------------------------------
    reg [31:0] stuck_count;

    localparam HALT_PC = 32'h000000CC;

    always @(posedge clk) begin
        if (!reset) begin
            stuck_count <= 0;
        end
        else begin
            if (pc_out >= HALT_PC && !DUT.alu_busy)
                stuck_count <= stuck_count + 1;
            else if (pc_out < HALT_PC)
                stuck_count <= 0;
            // pc_out >= HALT_PC but alu_busy: hold count
        end
    end

    // -----------------------------------------------------------------------
    // Register checker task
    // -----------------------------------------------------------------------
    integer pass_count;
    integer fail_count;

    task check_reg;
        input integer regnum;
        input [31:0]  expected;
        reg [31:0] actual;
        begin
            actual = DUT.regs[regnum];
            if (actual === expected) begin
                $display("[PASS]  x%-2d = 0x%08H  (%0d)", regnum, actual, $signed(actual));
                pass_count = pass_count + 1;
            end
            else begin
                $display("[FAIL]  x%-2d = 0x%08H  expected 0x%08H  (%0d != %0d)",
                         regnum, actual, expected, $signed(actual), $signed(expected));
                fail_count = fail_count + 1;
            end
        end
    endtask

    // -----------------------------------------------------------------------
    // PC trace — shows pipeline progress and stalls in real time
    // -----------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset && stuck_count < 5) begin
            $display("t=%0t  PC=0x%04H  busy=%b  stall=%b",
                     $time, pc_out,
                     DUT.alu_busy, DUT.stall_read);
        end
    end

    // -----------------------------------------------------------------------
    // Main test: wait for halt, then check all registers
    // -----------------------------------------------------------------------
    initial begin
        pass_count = 0;
        fail_count = 0;

        // Wait for reset
        @(posedge reset);
        #10;

        // Wait for program to halt (PC reached halt region) or timeout.
        // Poll one clock at a time so the loop reliably re-checks each cycle.
        // 50000 cycles @ 100 MHz = 500 µs — well above the ~3000-cycle budget.
        begin : halt_wait
            integer wait_cyc;
            wait_cyc = 0;
            while (stuck_count < 10 && wait_cyc < 50000) begin
                @(posedge clk);
                wait_cyc = wait_cyc + 1;
            end
        end

        if (stuck_count < 10) begin
            $display("\n*** TIMEOUT: Program did not halt within 500us ***");
            $display("    Last PC = 0x%08H", pc_out);
            $display("    This likely means the pipeline is stuck in a stall loop.");
            $finish;
        end

        $display("");
        $display("================================================================");
        $display("  Program halted at PC = 0x%04H after %0t ns", pc_out, $time);
        $display("  Checking all register values...");
        $display("================================================================");

        // ---- GROUP A: Basic MUL/DIV/REM ----
        $display("\n--- Group A: Basic MUL/DIV/REM ---");
        check_reg( 3, 32'h0000004B); //  75 = 15*5
        check_reg( 4, 32'h00000003); //   3 = 15/5
        check_reg( 5, 32'h00000000); //   0 = 15%5

        // ---- GROUP B: Signed combinations ----
        $display("\n--- Group B: Signed combinations ---");
        check_reg( 6, 32'hFFFFFFEB); // -21 = (-7)*3
        check_reg( 7, 32'hFFFFFFFE); //  -2 = (-7)/3
        check_reg( 8, 32'hFFFFFFFF); //  -1 = (-7)%3
        check_reg( 9, 32'hFFFFFFFE); //  -2 = 7/(-3)
        check_reg(10, 32'h00000001); //   1 = 7%(-3)
        check_reg(11, 32'h00000002); //   2 = (-7)/(-3)
        check_reg(12, 32'hFFFFFFFF); //  -1 = (-7)%(-3)

        // ---- GROUP C: Spec edge cases ----
        $display("\n--- Group C: Division by zero + signed overflow ---");
        check_reg(13, 32'hFFFFFFFF); // DIV by zero -> -1
        check_reg(14, 32'h0000002A); // REM by zero -> dividend (42)
        check_reg(15, 32'hFFFFFFFF); // DIVU by zero -> 0xFFFFFFFF
        check_reg(16, 32'h0000002A); // REMU by zero -> dividend (42)
        check_reg(17, 32'h80000000); // MIN_INT / -1 -> MIN_INT
        check_reg(18, 32'h00000000); // MIN_INT % -1 -> 0

        // ---- GROUP D: Upper multiply ----
        $display("\n--- Group D: MULH / MULHU / MULHSU ---");
        check_reg(19, 32'h00000001); // MULH(0x40000000, 4) = 1
        check_reg(20, 32'h00000001); // MULHU(0x40000000, 4) = 1
        check_reg(21, 32'h00000001); // MULHSU(0x40000000, 4) = 1
        check_reg(22, 32'h00000000); // MULH(-1, -1) = 0
        check_reg(23, 32'hFFFFFFFE); // MULHU(0xFFFFFFFF, 0xFFFFFFFF) = 0xFFFFFFFE
        check_reg(24, 32'hFFFFFFFF); // MULHSU(-1, 0xFFFFFFFF) = 0xFFFFFFFF

        // ---- GROUP E: Unsigned division ----
        $display("\n--- Group E: Unsigned division ---");
        check_reg(25, 32'h7FFFFFFF); // DIVU(0xFFFFFFFF, 2) = 0x7FFFFFFF
        check_reg(26, 32'h00000001); // REMU(0xFFFFFFFF, 2) = 1

        // ---- GROUP F: Back-to-back ----
        $display("\n--- Group F: Back-to-back MUL/DIV/REM ---");
        check_reg(27, 32'h00000054); // 84 = 12*7
        check_reg(28, 32'h00000001); //  1 = 12/7
        check_reg(29, 32'h00000005); //  5 = 12%7
        check_reg(30, 32'h00000054); // 84 = 12*7 (MUL after REM)

        // ---- GROUP G: Forwarding ----
        $display("\n--- Group G: Data dependency / forwarding ---");
        check_reg(31, 32'h00000054); // 84 = 1*84 (x28*x27)

        // ---- Summary ----
        $display("");
        $display("================================================================");
        $display("  RESULTS: %0d passed, %0d failed out of %0d tests",
                 pass_count, fail_count, pass_count + fail_count);
        if (fail_count == 0)
            $display("  >>> ALL TESTS PASSED <<<");
        else
            $display("  >>> %0d TESTS FAILED <<<", fail_count);
        $display("================================================================");

        #50;
        $finish;
    end

    // -----------------------------------------------------------------------
    // Safety timeout
    // -----------------------------------------------------------------------
    initial begin
        #1000000;
        $display("\n*** HARD TIMEOUT at 1ms — something is very wrong ***");
        $display("    PC = 0x%08H, busy=%b, stall=%b",
                 pc_out, DUT.alu_busy, DUT.stall_read);
        $finish;
    end

endmodule
