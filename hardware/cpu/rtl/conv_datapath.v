`timescale 1ns/1ps

module conv_datapath #(
    parameter IMG_W = 128,
    parameter IMG_H = 128
)(
    // Clock and Reset
    input  wire        clk,
    input  wire        reset,

    // Handshake with top_fsm
    input  wire        start,
    output wire        done,

    // img_bram_in read port
    output wire [13:0] bram_in_rd_addr,
    input  wire [ 7:0] bram_in_rd_data,

    // img_bram_out write port
    output wire [13:0] bram_out_wr_addr,
    output wire [ 7:0] bram_out_wr_data,
    output wire        bram_out_wr_en,

    // Kernel coefficients from kernel_regfile (Satish)
    input  wire signed [7:0] k0, k1, k2,
    input  wire signed [7:0] k3, k4, k5,
    input  wire signed [7:0] k6, k7, k8,

    // CHANGE 1: norm_en input port added
    // comes from kernel_regfile (Satish)
    // 0 = Sobel/Sharpen, 1 = Blur
    input  wire        norm_en
);

// Internal wires — line_buffer → conv_engine
wire [7:0] w_p00, w_p01, w_p02;
wire [7:0] w_p10, w_p11, w_p12;
wire [7:0] w_p20, w_p21, w_p22;
wire        w_window_valid;
wire [13:0] w_pixel_idx;

// line_buffer instantiation
line_buffer #(
    .IMG_W (IMG_W),
    .IMG_H (IMG_H)
) u_line_buffer (
    .clk            (clk),
    .reset          (reset),
    .start          (start),
    .done           (done),
    .bram_rd_addr   (bram_in_rd_addr),
    .bram_rd_data   (bram_in_rd_data),
    .p00            (w_p00),  .p01 (w_p01),  .p02 (w_p02),
    .p10            (w_p10),  .p11 (w_p11),  .p12 (w_p12),
    .p20            (w_p20),  .p21 (w_p21),  .p22 (w_p22),
    .window_valid   (w_window_valid),
    .out_pixel_idx  (w_pixel_idx),
    .out_valid      ()
);

// conv_engine instantiation
conv_engine u_conv_engine (
    .clk            (clk),
    .rst            (reset),
    .p00            (w_p00),  .p01 (w_p01),  .p02 (w_p02),
    .p10            (w_p10),  .p11 (w_p11),  .p12 (w_p12),
    .p20            (w_p20),  .p21 (w_p21),  .p22 (w_p22),
    .k0             (k0),  .k1 (k1),  .k2 (k2),
    .k3             (k3),  .k4 (k4),  .k5 (k5),
    .k6             (k6),  .k7 (k7),  .k8 (k8),
    // CHANGE 2: norm_en wired through to conv_engine
    .norm_en        (norm_en),
    .window_valid   (w_window_valid),
    .pixel_idx_in   (w_pixel_idx),
    .pixel_out      (bram_out_wr_data),
    .out_valid      (bram_out_wr_en),
    .pixel_idx_out  (bram_out_wr_addr)
);

endmodule
