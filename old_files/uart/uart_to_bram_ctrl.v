`timescale 1ns / 1ps
// uart_to_bram_ctrl.v - Sequential Loader for Image Data
// Author: Abhirup Paul

module uart_to_bram_ctrl (
    input  wire        clk,          // 100 MHz System Clock
    input  wire        reset_n,      // Active-low reset

    // Interface from your uart_rx.v
    input  wire        rx_done,      // Pulse when 8-bit data is ready
    input  wire [7:0]  rx_data,      // The received pixel byte

    // Interface to Soumik's img_bram_in
    output reg [13:0]  write_addr,   // 14-bit addr for 128x128 image
    output reg [7:0]   write_data,   // Data to BRAM
    output reg         we,           // Write Enable pulse

    // Status to Top Level
    output reg         image_loaded  // High when 16,384 bytes are stored
);

    // Constant for 128x128 image size [cite: 229]
    localparam MAX_PIXELS = 16384;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            write_addr   <= 14'd0;
            write_data   <= 8'd0;
            we           <= 1'b0;
            image_loaded <= 1'b0;
        end else begin
            // Default: Pull Write Enable low after 1 cycle
            we <= 1'b0;

            if (rx_done && !image_loaded) begin
                // 1. Prepare data and address
                write_data <= rx_data;
                we         <= 1'b1; // Trigger BRAM write

                // 2. Increment address or finish loading
                if (write_addr < MAX_PIXELS - 1) begin
                    write_addr <= write_addr + 14'd1;
                end else begin
                    image_loaded <= 1'b1; // All 16,384 pixels received
                end
            end
        end
    end

endmodule