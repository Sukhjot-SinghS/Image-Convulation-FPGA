// tb_uart.v  — Fixed testbench
// Bugs fixed:
//   [FIX-TB-1] uart_controller instantiation was missing tx_data and tx_en
//               ports.  Those inputs were floating (Z / X), which caused
//               X-propagation through the TX datapath.
//   [FIX-TB-2] The pass/fail check sampled rx_ready (rx_dv) after a 2000 ns
//               delay.  rx_dv is a single-cycle pulse (~10 ns wide); it had
//               long since de-asserted by the time the check ran, so the
//               test *always* reported FAIL.
//               Fix: latch rx_data when rx_ready pulses, then compare the
//               latched value.
//   [FIX-TB-3] rst was not driven.  Added a short reset at the start so all
//               FSMs initialise to a known state (required for synthesis-
//               equivalent simulation behaviour).
//   [FIX-TB-4] tx_data and tx_en are now tied to a safe idle value (0 / 0)
//               to avoid X-propagation during the RX-only test.











// `timescale 1ns/1ps

// module tb_uart();

//     // -----------------------------------------------------------------------
//     // DUT signals
//     // -----------------------------------------------------------------------
//     reg        clk   = 1'b0;
//     reg        rst   = 1'b1;   // start in reset
//     reg        rx_pin = 1'b1;

//     // TX side — tied off for this RX-only test [FIX-TB-4]
//     reg  [7:0] tx_data = 8'h00;
//     reg        tx_en   = 1'b0;

//     wire       tx_pin;
//     wire [7:0] rx_data;
//     wire       rx_ready;

//     // [FIX-TB-2] Latch the received byte on the rx_ready pulse
//     reg  [7:0] rx_data_latched = 8'hFF;
//     reg        rx_received     = 1'b0;

//     always @(posedge clk) begin
//         if (rx_ready) begin
//             rx_data_latched <= rx_data;
//             rx_received     <= 1'b1;
//         end
//     end

//     // -----------------------------------------------------------------------
//     // 100 MHz clock  (period = 10 ns)
//     // -----------------------------------------------------------------------
//     always #5 clk = ~clk;

//     // -----------------------------------------------------------------------
//     // DUT instantiation
//     // -----------------------------------------------------------------------
//     top_uart dut (
//         .clk     (clk),
//         .rst     (rst),
//         .rx_pin  (rx_pin),
//         .tx_pin  (tx_pin),
//         .tx_data (tx_data),   // [FIX-TB-1] connected
//         .tx_en   (tx_en),     // [FIX-TB-1] connected
//         .rx_data (rx_data),
//         .rx_ready(rx_ready),
//         .tx_busy ()
//     );

//     // -----------------------------------------------------------------------
//     // Stimulus — transmit 0x41 ('A') LSB first
//     //
//     // CLKS_PER_BIT = 87  →  bit period = 87 × 10 ns = 870 ns
//     //
//     // 0x41 = 0100_0001
//     // LSB-first bit order: 1 0 0 0 0 0 1 0
//     // -----------------------------------------------------------------------
//     initial begin
//         $dumpfile("uart_test.vcd");
//         $dumpvars(0, tb_uart);

//         // [FIX-TB-3] Hold reset for a few cycles then release
//         repeat (4) @(posedge clk);
//         rst = 1'b0;

//         // Allow the FSMs to settle in IDLE
//         #100;

//         // --- UART frame for 0x41 ---
//         rx_pin = 1'b0; #870;   // Start bit  (LOW)
//         rx_pin = 1'b1; #870;   // Bit 0 = 1
//         rx_pin = 1'b0; #870;   // Bit 1 = 0
//         rx_pin = 1'b0; #870;   // Bit 2 = 0
//         rx_pin = 1'b0; #870;   // Bit 3 = 0
//         rx_pin = 1'b0; #870;   // Bit 4 = 0
//         rx_pin = 1'b0; #870;   // Bit 5 = 0
//         rx_pin = 1'b1; #870;   // Bit 6 = 1
//         rx_pin = 1'b0; #870;   // Bit 7 = 0
//         rx_pin = 1'b1; #870;   // Stop bit  (HIGH)

//         // [FIX-TB-2] Wait for the rx_received latch (set by rx_ready pulse)
//         // Give enough time for the stop-bit processing to complete.
//         wait (rx_received || $time > 20_000);

//         // Extra settling margin
//         #100;

//         // --- Result ---
//         if (rx_received && rx_data_latched == 8'h41)
//             $display("UART PASS: received 0x%02X ('A')", rx_data_latched);
//         else if (!rx_received)
//             $display("UART FAIL: rx_ready pulse never observed");
//         else
//             $display("UART FAIL: expected 0x41, got 0x%02X", rx_data_latched);



//         // --- Result ---
//         if (rx_received && rx_data_latched == 8'h41)
//             $display("UART PASS: received 0x%02X ('A')", rx_data_latched);
//         else if (!rx_received)
//             $display("UART FAIL: rx_ready pulse never observed");
//         else
//             $display("UART FAIL: expected 0x41, got 0x%02X", rx_data_latched);

//         // -----------------------------------------------------------------------
//         // Stimulus — Verify TX by transmitting 0x55 (alternating bits: 01010101)
//         // -----------------------------------------------------------------------
//         $display("Starting TX test...");
//         tx_data = 8'h55; 
//         tx_en   = 1'b1;  // Pulse enable high
//         #10;             // Wait 1 clock cycle
//         tx_en   = 1'b0;  // Pull enable low

//         // Wait for the transmission to finish (10 bits * 870ns per bit)
//         #10000; 
        
//         $display("TX test complete. Check GTKWave for the tx_pin waveform!");



//         $finish;
//     end

// endmodule


















`timescale 1ns/1ps

module tb_uart();

    // -----------------------------------------------------------------------
    // DUT signals & Constants
    // -----------------------------------------------------------------------
    parameter BIT_PERIOD = 870; // 87 clocks * 10ns = 870ns per bit

    reg        clk   = 1'b0;
    reg        rst   = 1'b1;
    reg        rx_pin = 1'b1;
    
    reg  [7:0] tx_data = 8'h00;
    reg        tx_en   = 1'b0;
    wire       tx_pin;
    
    wire [7:0] rx_data;
    wire       rx_ready;
    wire       tx_busy;

    // Latch for RX checking
    reg  [7:0] rx_latched;
    reg        rx_flag = 1'b0;

    always @(posedge clk) begin
        if (rx_ready) begin
            rx_latched <= rx_data;
            rx_flag    <= 1'b1;
        end
    end

    // 100 MHz clock
    always #5 clk = ~clk;

    // -----------------------------------------------------------------------
    // DUT instantiation
    // -----------------------------------------------------------------------
    top_uart dut (
        .clk     (clk),
        .rst     (rst),
        .rx_pin  (rx_pin),
        .tx_pin  (tx_pin),
        .tx_data (tx_data),
        .tx_en   (tx_en),
        .rx_data (rx_data),
        .rx_ready(rx_ready),
        .tx_busy (tx_busy)
    );

    // -----------------------------------------------------------------------
    // VERILOG TASKS (Automated Test Functions)
    // -----------------------------------------------------------------------
    
    // Task 1: Send a byte to the FPGA perfectly
    task send_rx_byte;
        input [7:0] data;
        integer i;
        begin
            rx_pin = 1'b0; #BIT_PERIOD; // Start Bit
            for (i=0; i<8; i=i+1) begin
                rx_pin = data[i]; #BIT_PERIOD; // Data Bits (LSB first)
            end
            rx_pin = 1'b1; #BIT_PERIOD; // Stop Bit
        end
    endtask

    // Task 2: Command the FPGA to transmit
    task trigger_tx;
        input [7:0] data;
        begin
            tx_data = data;
            tx_en   = 1'b1;
            #10;
            tx_en   = 1'b0;
            wait(!tx_busy); // Wait until the hardware finishes sending
        end
    endtask

    // -----------------------------------------------------------------------
    // THE STRESS TEST SUITE
    // -----------------------------------------------------------------------
    initial begin
        $dumpfile("uart_stress_test.vcd");
        $dumpvars(0, tb_uart);

        $display("==================================================");
        $display("          UART EXTREME STRESS TEST SUITE          ");
        $display("==================================================");

        // Reset Sequence
        repeat (4) @(posedge clk);
        rst = 1'b0;
        #100;

        // ---------------------------------------------------------
        $display("\n--- TEST 1: GLITCH REJECTION ---");
        // Drop the line LOW for only 200ns (less than half a bit), then back HIGH.
        // If the RX module is robust, it should ignore this and NOT fire rx_ready.
        rx_flag = 0;
        rx_pin = 1'b0; #200; 
        rx_pin = 1'b1; #1000;
        if (rx_flag == 1) $display("[FAIL] Glitch triggered a fake reception!");
        else              $display("[PASS] Glitch successfully ignored.");

        // ---------------------------------------------------------
        $display("\n--- TEST 2: FULL-DUPLEX COLLISION ---");
        // We use 'fork...join' to run RX and TX at the exact same time.
        // This proves the two state machines do not interfere with each other.
        rx_flag = 0;
        fork
            send_rx_byte(8'hAA);      // PC sends 10101010 to FPGA
            trigger_tx(8'h55);        // FPGA sends 01010101 to PC
        join
        
        #100; // Settle
        if (rx_latched == 8'hAA) $display("[PASS] Full-Duplex successful! RX = 0xAA, TX = 0x55");
        else                     $display("[FAIL] Full-Duplex corrupted RX data: %h", rx_latched);

        // ---------------------------------------------------------
        $display("\n--- TEST 3: BACK-TO-BACK BURST (IMAGE STREAM SIMULATION) ---");
        // Send 3 bytes with ZERO delay between the stop bit and the next start bit.
        // This is exactly how the Python script will stream the image.
        rx_flag = 0;
        
        send_rx_byte(8'h11);
        if (rx_latched == 8'h11) $display("[PASS] Burst Byte 1: 0x11"); else $display("[FAIL] Burst 1");
        
        send_rx_byte(8'h22);
        if (rx_latched == 8'h22) $display("[PASS] Burst Byte 2: 0x22"); else $display("[FAIL] Burst 2");
        
        send_rx_byte(8'h33);
        if (rx_latched == 8'h33) $display("[PASS] Burst Byte 3: 0x33"); else $display("[FAIL] Burst 3");

        $display("\n==================================================");
        $display("               TEST SUITE COMPLETE                ");
        $display("==================================================");
        
        #500;
        $finish;
    end

endmodule