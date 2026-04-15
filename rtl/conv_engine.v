`timescale 1ns / 1ps

module conv_engine (
    input  wire        clk,
    input  wire        rst,

    input  wire [7:0]  p00, p01, p02,
    input  wire [7:0]  p10, p11, p12,
    input  wire [7:0]  p20, p21, p22,

    input  wire signed [7:0] k0, k1, k2,
    input  wire signed [7:0] k3, k4, k5,
    input  wire signed [7:0] k6, k7, k8,

    input  wire        norm_en,        // CHANGE 1: new port added
    input  wire        window_valid,
    input  wire [13:0] pixel_idx_in,

    output reg  [7:0]  pixel_out,
    output reg         out_valid,
    output reg  [13:0] pixel_idx_out
);

// STAGE 1 — 9 parallel multiplications
reg signed [16:0] prod0, prod1, prod2;
reg signed [16:0] prod3, prod4, prod5;
reg signed [16:0] prod6, prod7, prod8;
reg        valid_s1;
reg [13:0] idx_s1;

always @(posedge clk or negedge rst) begin
    if (!rst) begin
        valid_s1 <= 0; idx_s1 <= 0;
        prod0<=0; prod1<=0; prod2<=0;
        prod3<=0; prod4<=0; prod5<=0;
        prod6<=0; prod7<=0; prod8<=0;
    end else begin
        valid_s1 <= window_valid;
        idx_s1   <= pixel_idx_in;
        prod0 <= $signed({1'b0, p00}) * k0;
        prod1 <= $signed({1'b0, p01}) * k1;
        prod2 <= $signed({1'b0, p02}) * k2;
        prod3 <= $signed({1'b0, p10}) * k3;
        prod4 <= $signed({1'b0, p11}) * k4;
        prod5 <= $signed({1'b0, p12}) * k5;
        prod6 <= $signed({1'b0, p20}) * k6;
        prod7 <= $signed({1'b0, p21}) * k7;
        prod8 <= $signed({1'b0, p22}) * k8;
    end
end

// STAGE 2 — row-wise addition
reg signed [18:0] sum_row0, sum_row1, sum_row2;
reg        valid_s2;
reg [13:0] idx_s2;

always @(posedge clk or negedge rst) begin
    if (!rst) begin
        valid_s2 <= 0; idx_s2 <= 0;
        sum_row0 <= 0; sum_row1 <= 0; sum_row2 <= 0;
    end else begin
        valid_s2 <= valid_s1;
        idx_s2   <= idx_s1;
        sum_row0 <= prod0 + prod1 + prod2;
        sum_row1 <= prod3 + prod4 + prod5;
        sum_row2 <= prod6 + prod7 + prod8;
    end
end

// STAGE 3 — final accumulation
reg signed [20:0] raw_sum;
reg        valid_s3;
reg [13:0] idx_s3;

always @(posedge clk or negedge rst) begin
    if (!rst) begin
        valid_s3 <= 0; idx_s3 <= 0;
        raw_sum  <= 0;
    end else begin
        valid_s3 <= valid_s2;
        idx_s3   <= idx_s2;
        raw_sum  <= sum_row0 + sum_row1 + sum_row2;
    end
end

// processed_sum — blur uses shift right 3 (divide by 8)
// norm_en = 0 → Sobel/Sharpen
// norm_en = 1 → Blur
wire signed [20:0] processed_sum;
assign processed_sum = norm_en ? (raw_sum >>> 4) : raw_sum;

// abs_sum — take absolute value for Sobel edge detection
// This ensures BOTH edges are visible:
//   Dark→Light = positive → shows edge
//   Light→Dark = negative → abs makes positive → also shows edge
wire signed [20:0] abs_sum;
assign abs_sum = (processed_sum < $signed(21'd0))
                 ? -processed_sum
                 :  processed_sum;

// OUTPUT STAGE — clamp abs_sum to 0-255
always @(posedge clk or negedge rst) begin
    if (!rst) begin
        pixel_out     <= 8'd0;
        out_valid     <= 1'b0;
        pixel_idx_out <= 14'd0;
    end else begin
        out_valid     <= valid_s3;
        pixel_idx_out <= idx_s3;
        // abs_sum is always positive so only check > 255
        if (abs_sum > $signed(21'd255))
            pixel_out <= 8'd255;
        else
            pixel_out <= abs_sum[7:0];
    end
end

endmodule