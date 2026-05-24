`timescale 1ns / 1ps

module tb_top_fsm();

    // System Signals
    reg clk;
    reg reset; // Active-low

    // UART Pins
    reg  rx_pin;
    wire tx_pin;

    // CPU MMIO Signals (Mocking Sukhjot's CPU)
    reg         mem_write;
    reg         mem_read;
    reg  [31:0] cpu_addr;
    reg  [31:0] cpu_wdata;
    wire [31:0] cpu_rdata;

    // Instantiate the Top Level Coprocessor
    top_fsm uut (
        .clk(clk),
        .reset(reset),
        .rx_pin(rx_pin),
        .tx_pin(tx_pin),
        .mem_write(mem_write),
        .mem_read(mem_read),
        .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata),
        .cpu_rdata(cpu_rdata)
    );

    // 100 MHz Clock Generation (10ns period)
    always #5 clk = ~clk;

    // =========================================================
    // UART Bit-Banging Task (Mimics a PC sending data)
    // CLKS_PER_BIT = 87 -> 87 * 10ns = 870ns per bit
    // =========================================================
    task send_uart_byte(input [7:0] data);
        integer i;
        begin
            // Start bit (pull low)
            rx_pin = 1'b0;
            #870; 

            // 8 Data bits (LSB first)
            for (i = 0; i < 8; i = i + 1) begin
                rx_pin = data[i];
                #870;
            end

            // Stop bit (pull high)
            rx_pin = 1'b1;
            #870;
        end
    endtask

    // =========================================================
    // MAIN SIMULATION SEQUENCE
    // =========================================================
    integer pixel_count;

    initial begin
        // 1. Initialize Inputs
        clk       = 0;
        rx_pin    = 1; // UART idles high
        mem_write = 0;
        mem_read  = 0;
        cpu_addr  = 0;
        cpu_wdata = 0;

        // 2. Apply Active-Low Reset
        reset = 0; 
        #100;
        reset = 1; // Release reset (System runs!)
        #100;

        $display("--- Starting Image Transmission via UART ---");

        // 3. Send 16,384 "fake" pixels via UART to fill BRAM
        for (pixel_count = 0; pixel_count < 16384; pixel_count = pixel_count + 1) begin
            send_uart_byte(8'hAA); // Send dummy pixel 0xAA
        end

        $display("--- Image Transmission Complete. FSM should be in WAIT_START ---");
        #2000;

        // 4. Mimic CPU triggering the MMIO 'start' register
        $display("--- CPU sending Start Command via MMIO ---");
        mem_write = 1;
        cpu_addr  = 32'h8000_0040; // Our dummy start address
        cpu_wdata = 32'h0000_0001;
        #10;
        mem_write = 0;

        // 5. Let the hardware run!
        // The Convolution Engine will process the image, and then
        // the FSM will automatically start driving the tx_pin.
        $display("--- Waiting for Coprocessor to finish and Transmit ---");
        
        // Wait an arbitrary long time to let processing happen
        #500000; 

        $display("--- Simulation End ---");
        $finish;
    end

endmodule