`timescale 1ns/1ps

module top_uart #(parameter CLKS_PER_BIT = 87) (
    input  wire        clk,
    input  wire        rst,       // Active-high reset from testbench/system
    input  wire        rx_pin,    // Serial RX input from PC
    output wire        tx_pin,    // Serial TX output to PC
    
    // TX Control (for CPU interaction or loopback testing)
    input  wire [7:0]  tx_data,
    input  wire        tx_en,
    output wire        tx_busy,   
    
    // RX Data Output
    output wire [7:0]  rx_data,
    output wire        rx_ready,
    
    // BRAM Controller Interface (Image Loader)
    output wire [13:0] bram_write_addr,
    output wire [7:0]  bram_write_data,
    output wire        bram_we,
    output wire        image_loaded
);

    // Internal wires
    wire tx_done_w;

    // ---------------------------------------------------------------------
    // 1. UART Receiver
    // ---------------------------------------------------------------------
    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk       (clk),
        .rst       (rst),         // Active-high
        .rx_serial (rx_pin),
        .rx_dv     (rx_ready),
        .rx_byte   (rx_data)
    );

    // ---------------------------------------------------------------------
    // 2. UART Transmitter
    // ---------------------------------------------------------------------
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk       (clk),
        .rst       (rst),         // Active-high
        .tx_start  (tx_en),
        .tx_byte   (tx_data),
        .tx_serial (tx_pin),
        .tx_done   (tx_done_w)
    );

    // ---------------------------------------------------------------------
    // 3. TX Busy Status Latch
    // ---------------------------------------------------------------------
    // Set 'busy' high when tx_en is triggered, clear it when tx_done pulses.
    reg busy_reg;
    always @(posedge clk) begin
        if (rst) begin
            busy_reg <= 1'b0;
        end else if (tx_en) begin
            busy_reg <= 1'b1;
        end else if (tx_done_w) begin
            busy_reg <= 1'b0;
        end
    end
    assign tx_busy = busy_reg;

    // ---------------------------------------------------------------------
    // 4. UART to BRAM Controller (Image Loader)
    // ---------------------------------------------------------------------
    // Notice the ~rst: We invert the active-high rst to drive the active-low reset_n
    uart_to_bram_ctrl u_bram_ctrl (
        .clk          (clk),
        .reset_n      (~rst),     
        .rx_done      (rx_ready),
        .rx_data      (rx_data),
        .write_addr   (bram_write_addr),
        .write_data   (bram_write_data),
        .we           (bram_we),
        .image_loaded (image_loaded)
    );

endmodule