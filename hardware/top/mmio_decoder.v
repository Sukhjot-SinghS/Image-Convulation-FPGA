`timescale 1ns / 1ps

module mmio_decoder (
    input  wire        clk,
    input  wire        reset,        

    // CPU Interface
    input  wire [31:0] address,
    input  wire [31:0] write_data,
    input  wire        write_enable,
    input  wire        read_enable,
    output reg  [31:0] read_data,

    // Kernel Regfile Interface
    output reg         kernel_we,
    output reg  [3:0]  kernel_index,
    output reg  [31:0] kernel_wdata,

    // Control Signals
    output reg         start,
    input  wire        done
);

localparam KERNEL_BASE = 32'h80000000;
localparam START_ADDR  = 32'h80000024;
localparam STATUS_ADDR = 32'h80000028;
localparam NORM_ADDR   = 32'h80000030;

reg done_reg;

always @(posedge clk) begin
    if (!reset) begin
        start       <= 0;
        kernel_we   <= 0;
        done_reg    <= 0;
        kernel_index<= 0;
        kernel_wdata<= 0;
    end 
    else begin
        kernel_we <= 0;
        start     <= 0;

        if (write_enable && address == START_ADDR && write_data[0])
            start <= 1;

        if (write_enable && address >= KERNEL_BASE && address < KERNEL_BASE + 36) begin
            kernel_we    <= 1;
            kernel_index <= (address - KERNEL_BASE) >> 2;
            kernel_wdata <= write_data;
        end

        if (write_enable && address == NORM_ADDR) begin
            kernel_we    <= 1;
            kernel_index <= 4'd10;
            kernel_wdata <= write_data;
        end

        if (start)
            done_reg <= 0;
        else if (done)
            done_reg <= 1;
    end
end

always @(*) begin
    if (read_enable && address == STATUS_ADDR)
        read_data = {31'b0, done_reg};
    else
        read_data = 32'd0;
end

endmodule