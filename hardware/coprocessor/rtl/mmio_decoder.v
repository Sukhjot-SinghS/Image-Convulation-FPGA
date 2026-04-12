`timescale 1ns / 1ps

module mmio_decoder (
    input  wire        clk,
    input  wire        reset,        

    // CPU Interface (Fixed names to match top_fsm.v!)
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    input  wire        mem_write,
    input  wire        mem_read,
    output reg  [31:0] rdata,

    // Kernel Regfile Interface
    output reg         kernel_we,
    output reg  [3:0]  kernel_index,
    output reg  [31:0] kernel_wdata,

    // Control Signals
    output reg         start,
    output reg         sw_done,      // <--- ADDED SOFTWARE DOORBELL!
    input  wire        done_in       // <--- Fixed to done_in
);

localparam KERNEL_BASE  = 32'h80000000;
localparam START_ADDR   = 32'h80000024;
localparam STATUS_ADDR  = 32'h80000028;
localparam NORM_ADDR    = 32'h80000030;
localparam SW_DONE_ADDR = 32'h80000034; // New doorbell address!

reg done_reg;

always @(posedge clk) begin
    if (!reset) begin
        start       <= 0;
        sw_done     <= 0;
        kernel_we   <= 0;
        done_reg    <= 0;
        kernel_index<= 0;
        kernel_wdata<= 0;
    end 
    else begin
        kernel_we <= 0;
        start     <= 0;
        sw_done   <= 0; // Default to 0 so it pulses for exactly 1 cycle

        // 1. Hardware Coprocessor Start
        if (mem_write && addr == START_ADDR && wdata[0])
            start <= 1;
            
        // 2. Software Mode Done Doorbell
        if (mem_write && addr == SW_DONE_ADDR && wdata[0])
            sw_done <= 1;

        // 3. Kernel Coefficient Writes
        if (mem_write && addr >= KERNEL_BASE && addr < KERNEL_BASE + 36) begin
            kernel_we    <= 1;
            kernel_index <= (addr - KERNEL_BASE) >> 2;
            kernel_wdata <= wdata;
        end

        // 4. Normalization Toggle Write
        if (mem_write && addr == NORM_ADDR) begin
            kernel_we    <= 1;
            kernel_index <= 4'd10;
            kernel_wdata <= wdata;
        end

        // Hardware Done Latch
        if (start)
            done_reg <= 0;
        else if (done_in)
            done_reg <= 1;
    end
end

always @(*) begin
    if (mem_read && addr == STATUS_ADDR)
        rdata = {31'b0, done_reg};
    else
        rdata = 32'd0;
end

endmodule