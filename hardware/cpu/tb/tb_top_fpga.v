`timescale 1ns / 1ps

module tb_top_fpga();

    // 1. Declare System Signals
    reg clk;
    reg reset;         // Active-low
    reg uart_rx_pin;
    wire uart_tx_pin;

    // 2. Instantiate your Top Level FPGA module
    top_fpga uut (
        .clk(clk),
        .reset(reset),
        // If your top_fpga has an LED output, uncomment the line below:
        // .led(), 
        .uart_rx_pin(uart_rx_pin),
        .uart_tx_pin(uart_tx_pin)
    );

    // 3. Generate 100 MHz Clock (10ns period)
    always #5 clk = ~clk;

    // 4. Main Simulation Sequence
    initial begin
        // Initialize Inputs
        clk = 0;
        uart_rx_pin = 1; // UART idles high
        
        // Apply Active-Low Reset
        reset = 0; 
        #100;
        reset = 1;       // Release reset to let CPU fetch PC 0
        
        // Let it run long enough for the C code to execute completely
        // (100us should be plenty for the mul_div_test)
        #100000; 
        
        $display("--- Simulation End ---");
        $finish;
    end

endmodule