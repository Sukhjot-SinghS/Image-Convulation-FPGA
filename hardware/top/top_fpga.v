`timescale 1ns / 1ps
// ============================================================
// top_fpga.v
// Fully integrated top-level module
// Combines CPU, MMIO, kernel regfile, FSM, memories
// ============================================================

module top_fpga #(
    parameter IMEMSIZE   = 4096,
    parameter DMEMSIZE   = 4096,
    parameter IMG_W      = 128,
    parameter IMG_H      = 128,
    parameter CLKS_PER_BIT = 87
)(
    input  wire clk,      // board clock, e.g. 100 MHz
    input  wire reset,    // active LOW reset

    // UART physical pins
    input  wire rx_pin,
    output wire tx_pin,

    // LEDs to display PC or status
    output wire [15:0] led
);

    // =========================================================
    // Clock divider for CPU slow clock (optional)
    // =========================================================
    reg [25:0] clk_cnt;
    reg slow_clk;

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            clk_cnt  <= 26'd0;
            slow_clk <= 1'b0;
        end else begin
            if (clk_cnt == 26'd49_999_999) begin
                clk_cnt  <= 26'd0;
                slow_clk <= ~slow_clk;  // toggle every 0.5 sec
            end else begin
                clk_cnt <= clk_cnt + 1'b1;
            end
        end
    end

    // =========================================================
    // CPU ↔ MEMORY wires
    // =========================================================
    wire [31:0] inst_mem_read_data;
    wire inst_mem_is_valid = 1'b1;

    wire [31:0] dmem_read_data;
    wire dmem_write_valid = 1'b1;
    wire dmem_read_valid  = 1'b1;

    wire        dmem_re, dmem_we;
    wire [31:0] dmem_raddr, dmem_waddr, dmem_wdata, dmem_rdata;
    wire [3:0]  dmem_wstrb;
    wire [31:0] pc_out;
    wire exception;

    // =========================================================
    // CPU pipeline instantiation
    // =========================================================
    pipe cpu_inst (
        .clk(slow_clk),
        .reset(reset),
        .stall(1'b0),
        .exception(exception),

        .inst_mem_is_valid(inst_mem_is_valid),
        .inst_mem_read_data(inst_mem_read_data),
        .pc_out(pc_out),

        .dmem_read_data_temp(dmem_read_data),
        .dmem_write_valid(dmem_write_valid),
        .dmem_read_valid(dmem_read_valid),

        .dmem_re_o    (dmem_re),
        .dmem_raddr_o (dmem_raddr),
        .dmem_we_o    (dmem_we),
        .dmem_waddr_o (dmem_waddr),
        .dmem_wdata_o (dmem_wdata),
        .dmem_wstrb_o (dmem_wstrb),
        .dmem_rdata_i (dmem_rdata)
    );

    assign led = pc_out[15:0];  // display lower PC bits

    // =========================================================
    // Instruction Memory
    // =========================================================
    instr_mem IMEM (
        .clk(clk),
        .pc(pc_out),
        .instr(inst_mem_read_data)
    );

    // =========================================================
    // Data Memory
    // =========================================================
    data_mem DMEM (
        .clk(slow_clk),
        .re(dmem_re),
        .raddr(dmem_raddr),
        .rdata(dmem_read_data),
        .we(dmem_we),
        .waddr(dmem_waddr),
        .wdata(dmem_wdata),
        .wstrb(dmem_wstrb)
    );

    // =========================================================
    // MMIO + Kernel + FSM wires
    // =========================================================
    wire        k_we;
    wire [3:0]  k_idx;
    wire [31:0] k_wdata;
    wire        start_sig;
    wire        done_sig;
    wire signed [7:0] k0, k1, k2, k3, k4, k5, k6, k7, k8;
    wire        norm_en;

    // Map CPU DMEM interface to MMIO decoder
    wire [31:0] cpu_addr = dmem_waddr;
    wire [31:0] cpu_wdata = dmem_wdata;
    wire        mem_write = dmem_we;
    wire        mem_read  = dmem_re;

    wire [31:0] cpu_rdata;

    // =========================================================
    // Top FSM instantiation (handles RX/TX + start/done)
    // =========================================================
    top_fsm #(
        .IMG_W(IMG_W),
        .IMG_H(IMG_H),
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) fsm_inst (
        .clk(clk),
        .reset(reset),
        .rx_pin(rx_pin),
        .tx_pin(tx_pin),
        .mem_write(mem_write),
        .mem_read(mem_read),
        .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata),
        .cpu_rdata(cpu_rdata)
    );

    // =========================================================
    // MMIO decoder instantiation
    // =========================================================
    mmio_decoder mmio_inst (
        .clk(clk),
        .reset(reset),
        .address(cpu_addr),
        .write_data(cpu_wdata),
        .write_enable(mem_write),
        .read_enable(mem_read),
        .read_data(cpu_rdata),
        .kernel_we(k_we),
        .kernel_index(k_idx),
        .kernel_wdata(k_wdata),
        .start(start_sig),
        .done(done_sig)
    );

    // =========================================================
    // Kernel register file instantiation
    // =========================================================
    kernel_regfile kernel_inst (
        .clk(clk),
        .rst(reset),
        .we(k_we),
        .sel(k_idx),
        .wdata(k_wdata[7:0]),
        .done_in(done_sig),
        .k0(k0), .k1(k1), .k2(k2),
        .k3(k3), .k4(k4), .k5(k5),
        .k6(k6), .k7(k7), .k8(k8),
        .start_out(),   // connect to conv_datapath FSM if needed
        .done_out(done_sig),
        .norm_en(norm_en)
    );

endmodule
