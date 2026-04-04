`timescale 1ns / 1ps
// ============================================================
// mmio_decoder.v
// Author : Satish Kumar (Group 18)
// Purpose: Decode CPU memory accesses to kernel registers & control
//          Generates START pulse and returns DONE status
// ============================================================

module mmio_decoder (
    input  wire        clk,
    input  wire        rst,          // active-low reset

    // ── CPU interface
    input  wire        mem_write,    // CPU write enable
    input  wire        mem_read,     // CPU read enable
    input  wire [31:0] addr,         // CPU address
    input  wire [31:0] wdata,        // CPU write data
    output reg  [31:0] rdata,        // CPU read data

    // ── Kernel register interface
    output reg         kernel_we,    // kernel write enable
    output reg  [3:0]  kernel_addr,  // kernel register index (0-8)
    output reg  [31:0] kernel_wdata, // kernel write data

    // ── Control signals
    output reg         start,        // START pulse to FSM / line_buffer
    input  wire        done_in       // DONE from line_buffer / conv engine
);

////////////////////////////////////////////////////////////
// Address Map
////////////////////////////////////////////////////////////
localparam KERNEL_BASE = 32'h8000_0000; // k0
localparam KERNEL_END  = 32'h8000_0020; // k8
localparam START_ADDR  = 32'h8000_0028; // START
localparam STATUS_ADDR = 32'h8000_002C; // DONE status

// Latch for DONE signal
reg done_reg;

////////////////////////////////////////////////////////////
// WRITE LOGIC (from CPU)
////////////////////////////////////////////////////////////
always @(posedge clk or negedge rst) begin
    if (!rst) begin
        // reset all outputs
        start        <= 1'b0;
        kernel_we    <= 1'b0;
        kernel_addr  <= 4'd0;
        kernel_wdata <= 32'd0;
        done_reg     <= 1'b0;
    end else begin
        // default: no write or start pulse
        kernel_we <= 1'b0;
        start     <= 1'b0;

        // CPU writes START
        if (mem_write && addr == START_ADDR && wdata[0]) begin
            start    <= 1'b1;  // 1-cycle START pulse
            done_reg <= 1'b0;  // clear done
        end

        // CPU writes kernel registers (k0–k8)
        if (mem_write &&
            (addr >= KERNEL_BASE) &&
            (addr <= KERNEL_END) &&
            addr[1:0] == 2'b00) begin
            kernel_we    <= 1'b1;                    // enable write to kernel
            kernel_addr  <= (addr - KERNEL_BASE) >> 2; // index 0-8
            kernel_wdata <= wdata;
        end

        // Latch DONE from conv_engine / line_buffer
        if (done_in)
            done_reg <= 1'b1;
    end
end

////////////////////////////////////////////////////////////
// READ LOGIC (from CPU)
////////////////////////////////////////////////////////////
always @(posedge clk or negedge rst) begin
    if (!rst) begin
        rdata <= 32'd0;
    end else begin
        rdata <= 32'd0; // default read = 0

        if (mem_read && addr == STATUS_ADDR)
            rdata <= {31'd0, done_reg}; // DONE status in LSB
    end
end

endmodule
