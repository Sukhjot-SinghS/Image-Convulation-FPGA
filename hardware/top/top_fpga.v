`timescale 1ns / 1ps

// ============================================================
// top_fpga.v — DEMO 1
// Phase 1 milestone: RV32I + RV32M 3-stage pipeline on Nexys A7
// No UART, no MMIO coprocessor — just CPU + IMEM + DMEM.
// PC[15:0] is shown on the 16 board LEDs as visible proof of life.
// ============================================================

module top_fpga #(
    parameter IMEMSIZE = 4096,
    parameter DMEMSIZE = 4096
)(
    input  wire        clk,    // 100 MHz board clock
    input  wire        reset,  // active-low reset (CPU_RESETN)
    output wire [15:0] led     // PC visualizer
);

    // ========================================================
    // PIPELINE PC OUTPUT
    // ========================================================
    wire [31:0] pc_out;
    assign led = pc_out[15:0];

    // ========================================================
    // SLOW CLOCK GENERATOR (~1 Hz toggle from 100 MHz)
    // Lets you watch the PC advance on LEDs and visibly see
    // the pipeline stall during 32-cycle DIV/REM execution.
    // ========================================================
    reg [25:0] clk_cnt;
    reg        slow_clk;

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            clk_cnt  <= 26'd0;
            slow_clk <= 1'b0;
        end else begin
            if (clk_cnt == 26'd49_999_999) begin
                clk_cnt  <= 26'd0;
                slow_clk <= ~slow_clk;
            end else begin
                clk_cnt <= clk_cnt + 1'b1;
            end
        end
    end

    // ========================================================
    // PIPE <-> MEMORY WIRES
    // ========================================================
    wire [31:0] inst_mem_read_data;
    wire        inst_mem_is_valid = 1'b1;

    wire [31:0] dmem_read_data;
    wire        dmem_write_valid  = 1'b1;
    wire        dmem_read_valid   = 1'b1;
    wire        exception;

    wire        dmem_re, dmem_we;
    wire [31:0] dmem_raddr, dmem_waddr, dmem_wdata;
    wire [3:0]  dmem_wstrb;

    // ========================================================
    // MMIO PORTS — TIED OFF FOR DEMO 1
    // The pipe module still exposes MMIO ports (Phase 2 hooks).
    // Outputs from pipe are left floating; mmio_read_data is
    // driven to zero so loads from MMIO space return 0.
    // ========================================================
    wire        mmio_we_unused;
    wire        mmio_re_unused;
    wire [31:0] mmio_addr_unused;
    wire [31:0] mmio_wdata_unused;
    wire [31:0] mmio_rdata_tie = 32'h0000_0000;

    // ========================================================
    // 1. PIPELINE CPU (RV32I + RV32M)
    // ========================================================
    pipe DUT (
        .clk(slow_clk),
        .reset(reset),
        .stall(1'b0),
        .exception(exception),
        .pc_out(pc_out),

        // Instruction Memory
        .inst_mem_is_valid(inst_mem_is_valid),
        .inst_mem_read_data(inst_mem_read_data),

        // Data Memory
        .dmem_read_valid(dmem_read_valid),
        .dmem_write_valid(dmem_write_valid),
        .dmem_read_data_temp(dmem_read_data),
        .dmem_re_o    (dmem_re),
        .dmem_raddr_o (dmem_raddr),
        .dmem_we_o    (dmem_we),
        .dmem_waddr_o (dmem_waddr),
        .dmem_wdata_o (dmem_wdata),
        .dmem_wstrb_o (dmem_wstrb),

        // MMIO bridge — tied off for Demo 1
        .mmio_write_enable  (mmio_we_unused),
        .mmio_read_enable   (mmio_re_unused),
        .mmio_write_address (mmio_addr_unused),
        .mmio_write_data    (mmio_wdata_unused),
        .mmio_read_data     (mmio_rdata_tie)
    );

    // ========================================================
    // 2. INSTRUCTION MEMORY
    // ========================================================
    instr_mem IMEM (
        .clk(clk),
        .pc(pc_out),
        .instr(inst_mem_read_data)
    );

    // ========================================================
    // 3. DATA MEMORY
    // ========================================================
    data_mem DMEM (
        .clk   (slow_clk),
        .re    (dmem_re),
        .raddr (dmem_raddr),
        .rdata (dmem_read_data),
        .we    (dmem_we),
        .waddr (dmem_waddr),
        .wdata (dmem_wdata),
        .wstrb (dmem_wstrb)
    );

endmodule