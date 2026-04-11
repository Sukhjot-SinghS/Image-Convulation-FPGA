`timescale 1ns / 1ps

// DUMMY MODULE: Temporary placeholder until Satish provides the real one.
module mmio_decoder(
    input  wire        clk,
    input  wire        rst,          // active-low
    input  wire        mem_write,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    input  wire        mem_read,
    output reg  [31:0] rdata,
    output reg         kernel_we,
    output reg  [3:0]  kernel_addr,
    output reg  [31:0] kernel_wdata,
    output reg         start,
    input  wire        done_in
);

    // If the CPU writes a '1' to address 0x8000_0040, pulse the 'start' wire
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            start <= 1'b0;
        end else begin
            if (mem_write && addr == 32'h8000_0040)
                start <= wdata[0];
            else
                start <= 1'b0;
        end
    end

endmodule