`timescale 1ns / 1ps
// ============================================================
// kernel_regfile.v
// Author: Satish Kumar
// Purpose: Stores 3x3 convolution kernel values
// ============================================================

module kernel_regfile (
    input  wire        clk,
    input  wire        rst,       // active LOW
    
    // MMIO interface (write from CPU via mmio_decoder)
    input  wire        we,        // write enable pulse
    input  wire [3:0]  addr,      // kernel index 0–8
    input  wire [31:0] wdata,     // 32-bit CPU data
    
    // Output to conv engine
    output reg signed [7:0] k0,
    output reg signed [7:0] k1,
    output reg signed [7:0] k2,
    output reg signed [7:0] k3,
    output reg signed [7:0] k4,
    output reg signed [7:0] k5,
    output reg signed [7:0] k6,
    output reg signed [7:0] k7,
    output reg signed [7:0] k8
);

////////////////////////////////////////////////////////////
// INTERNAL WRITE LOGIC
////////////////////////////////////////////////////////////
always @(posedge clk or negedge rst) begin
    if (!rst) begin
        k0 <= 8'sd0;
        k1 <= 8'sd0;
        k2 <= 8'sd0;
        k3 <= 8'sd0;
        k4 <= 8'sd0;
        k5 <= 8'sd0;
        k6 <= 8'sd0;
        k7 <= 8'sd0;
        k8 <= 8'sd0;
    end
    else if (we) begin
        case(addr)
            4'd0: k0 <= wdata[7:0];
            4'd1: k1 <= wdata[7:0];
            4'd2: k2 <= wdata[7:0];
            4'd3: k3 <= wdata[7:0];
            4'd4: k4 <= wdata[7:0];
            4'd5: k5 <= wdata[7:0];
            4'd6: k6 <= wdata[7:0];
            4'd7: k7 <= wdata[7:0];
            4'd8: k8 <= wdata[7:0];
            default: ; // ignore out-of-range writes
        endcase
    end
end

endmodule
