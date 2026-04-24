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

    input  wire        norm_en,
    input  wire        window_valid,
    input  wire [13:0] pixel_idx_in,

    output reg  [7:0]  pixel_out,
    output reg         out_valid,
    output reg  [13:0] pixel_idx_out
);

// ============================================================
// HARDCODED GAUSSIAN BLUR ΓÇö purely unsigned arithmetic
// Kernel: [1 2 1; 2 4 2; 1 2 1]  sum=16  divide by 16 (>>4)
//
// This bypasses the kernel_regfile entirely to eliminate
// any signed arithmetic or MMIO loading issues.
// Once this is confirmed working, the generic kernel path
// can be debugged separately.
// ============================================================

// STAGE 1 ΓÇö Hardcoded weighted pixel values (all unsigned)
// *1 = itself, *2 = left-shift 1, *4 = left-shift 2
reg [9:0] w00, w01, w02;   // max: 255*4 = 1020 ΓåÆ 10 bits
reg [9:0] w10, w11, w12;
reg [9:0] w20, w21, w22;
reg       valid_s1;
reg [13:0] idx_s1;

always @(posedge clk or negedge rst) begin
    if (!rst) begin
        valid_s1 <= 0; idx_s1 <= 0;
        w00<=0; w01<=0; w02<=0;
        w10<=0; w11<=0; w12<=0;
        w20<=0; w21<=0; w22<=0;
    end else begin
        valid_s1 <= window_valid;
        idx_s1   <= pixel_idx_in;
        // Gaussian kernel [1,2,1; 2,4,2; 1,2,1]
        w00 <= {2'b0, p00};            // *1
        w01 <= {1'b0, p01, 1'b0};      // *2 (shift left 1)
        w02 <= {2'b0, p02};            // *1
        w10 <= {1'b0, p10, 1'b0};      // *2
        w11 <= {p11, 2'b0};            // *4 (shift left 2)
        w12 <= {1'b0, p12, 1'b0};      // *2
        w20 <= {2'b0, p20};            // *1
        w21 <= {1'b0, p21, 1'b0};      // *2
        w22 <= {2'b0, p22};            // *1
    end
end

// STAGE 2 ΓÇö Row-wise addition (unsigned)
reg [11:0] sum_row0, sum_row1, sum_row2;  // max per row: 1020+1020+1020 = 3060 ΓåÆ 12 bits
reg        valid_s2;
reg [13:0] idx_s2;

always @(posedge clk or negedge rst) begin
    if (!rst) begin
        valid_s2 <= 0; idx_s2 <= 0;
        sum_row0 <= 0; sum_row1 <= 0; sum_row2 <= 0;
    end else begin
        valid_s2 <= valid_s1;
        idx_s2   <= idx_s1;
        sum_row0 <= w00 + w01 + w02;
        sum_row1 <= w10 + w11 + w12;
        sum_row2 <= w20 + w21 + w22;
    end
end

// STAGE 3 ΓÇö Final accumulation (unsigned)
reg [13:0] raw_sum;   // max: 3060*3 = 9180 ΓåÆ 14 bits (but actual max = 255*16=4080 ΓåÆ 12 bits)
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

// OUTPUT STAGE ΓÇö divide by 16 (>>4) and clamp to 0-255
// Since raw_sum max = 4080, raw_sum>>4 max = 255. No clamping needed!
always @(posedge clk or negedge rst) begin
    if (!rst) begin
        pixel_out     <= 8'd0;
        out_valid     <= 1'b0;
        pixel_idx_out <= 14'd0;
    end else begin
        out_valid     <= valid_s3;
        pixel_idx_out <= idx_s3;
        pixel_out     <= raw_sum[11:4];  // unsigned >>4 = divide by 16
    end
end

endmodule
