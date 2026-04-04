`timescale 1ns / 1ps

// ============================================================
//  kernel_regfile.v
//  Stores 3×3 convolution kernel (9 values)
//  Written by CPU via MMIO → Used by conv_engine
// ============================================================

module kernel_regfile (
    input  wire clk,
    input  wire rst,   // active LOW

    input  wire        kernel_we,
    input  wire [3:0]  kernel_index,
    input  wire [31:0] kernel_wdata,

    output wire [31:0] k0, k1, k2,
    output wire [31:0] k3, k4, k5,
    output wire [31:0] k6, k7, k8
);

reg [31:0] kernel [0:8];
integer i;

always @(posedge clk) begin
    if (!rst) begin
        for (i = 0; i < 9; i = i + 1)
            kernel[i] <= 32'd0;
    end 
    else if (kernel_we) begin
        if (kernel_index < 9)
            kernel[kernel_index] <= kernel_wdata;
    end
end

assign k0 = kernel[0];
assign k1 = kernel[1];
assign k2 = kernel[2];
assign k3 = kernel[3];
assign k4 = kernel[4];
assign k5 = kernel[5];
assign k6 = kernel[6];
assign k7 = kernel[7];
assign k8 = kernel[8];

endmodule
