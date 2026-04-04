`timescale 1ns / 1ps
// ============================================================
// top_fpga.v
// Fully integrated top-level module
// Combines CPU, MMIO, kernel regfile, FSM, memories
// ============================================================

module top_fpga #(
    parameter IMEMSIZE = 4096,
    parameter DMEMSIZE = 4096,
    parameter IMG_W = 128,
    parameter IMG_H = 128,
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
    // FSM + image processing integration
    // =========================================================

    wire        mem_write, mem_read;
    wire [31:0] cpu_addr, cpu_wdata, cpu_rdata;
    assign mem_write = dmem_we;  // map CPU DMEM write to MMIO
    assign mem_read  = dmem_re;  // map CPU DMEM read to MMIO
    assign cpu_addr  = dmem_waddr; // address to MMIO decoder
    assign cpu_wdata = dmem_wdata; // data to MMIO decoder

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

endmodule
