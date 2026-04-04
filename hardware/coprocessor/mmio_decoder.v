`timescale 1ns / 1ps

// ============================================================
//  mmio_decoder.v
//  Author : Satish Kumar (Group 18)
//
//  Purpose:
//    Decodes CPU memory accesses into:
//      - Kernel writes
//      - Start signal
//      - Done status read
//
//  Address Map:
//    0x80000000 → k0
//    ...
//    0x80000020 → k8
//    0x80000028 → START
//    0x8000002C → STATUS (done)
// ============================================================

module mmio_decoder (
    input  wire        clk,
    input  wire        rst,          // active-low

    // CPU Interface
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    input  wire        mem_write,
    input  wire        mem_read,
    output reg  [31:0] rdata,

    // To kernel_regfile
    output reg         kernel_we,
    output reg  [3:0]  kernel_index,
    output reg  [31:0] kernel_wdata,

    // Control
    output reg         start,
    input  wire        done
);

////////////////////////////////////////////////////////////
// ADDRESS MAP
////////////////////////////////////////////////////////////
localparam KERNEL_BASE = 32'h8000_0000;
localparam START_ADDR  = 32'h8000_0028;
localparam STATUS_ADDR = 32'h8000_002C;

reg done_reg;

////////////////////////////////////////////////////////////
// WRITE LOGIC
////////////////////////////////////////////////////////////
always @(posedge clk or negedge rst) begin
    if (!rst) begin
        start        <= 1'b0;
        kernel_we    <= 1'b0;
        kernel_index <= 4'd0;
        kernel_wdata <= 32'd0;
        done_reg     <= 1'b0;
    end
    else begin
        // default
        kernel_we <= 1'b0;
        start     <= 1'b0;

        // START pulse (1 cycle)
        if (mem_write && addr == START_ADDR && wdata[0]) begin
            start    <= 1'b1;
            done_reg <= 1'b0;
        end

        // KERNEL WRITE (safe + aligned)
        if (mem_write &&
            (addr - KERNEL_BASE) < 32'd36 &&
            addr[1:0] == 2'b00) begin

            kernel_we    <= 1'b1;
            kernel_index <= (addr - KERNEL_BASE) >> 2;
            kernel_wdata <= wdata;
        end

        // DONE latch
        if (done)
            done_reg <= 1'b1;
    end
end

////////////////////////////////////////////////////////////
// READ LOGIC (REGISTERED)
////////////////////////////////////////////////////////////
always @(posedge clk or negedge rst) begin
    if (!rst)
        rdata <= 32'd0;
    else begin
        rdata <= 32'd0;

        if (mem_read && addr == STATUS_ADDR)
            rdata <= {31'd0, done_reg};
    end
end

endmodule
