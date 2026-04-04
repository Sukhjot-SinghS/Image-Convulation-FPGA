`timescale 1ns / 1ps
// ============================================================
// kernel_regfile.v
// Author : Satish Kumar (Group 18)
// Purpose: 3x3 kernel storage for convolution engine
//          9 registers (k0–k8) with write enable from MMIO
// ============================================================

module kernel_regfile (
    input  wire        clk,
    input  wire        rst,       // active-low reset

    // Write interface from MMIO
    input  wire        we,        // write enable
    input  wire [3:0]  addr,      // kernel index 0–8
    input  wire [31:0] wdata,     // CPU data (only lower 8 bits used)

    // Outputs to conv_engine
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

always @(posedge clk or negedge rst) begin
    if (!rst) begin
        k0 <= 8'd0; k1 <= 8'd0; k2 <= 8'd0;
        k3 <= 8'd0; k4 <= 8'd0; k5 <= 8'd0;
        k6 <= 8'd0; k7 <= 8'd0; k8 <= 8'd0;
    end else if (we) begin
        case (addr)
            4'd0: k0 <= wdata[7:0];
            4'd1: k1 <= wdata[7:0];
            4'd2: k2 <= wdata[7:0];
            4'd3: k3 <= wdata[7:0];
            4'd4: k4 <= wdata[7:0];
            4'd5: k5 <= wdata[7:0];
            4'd6: k6 <= wdata[7:0];
            4'd7: k7 <= wdata[7:0];
            4'd8: k8 <= wdata[7:0];
            default: ; // do nothing for invalid addr
        endcase
    end
end

endmodule
