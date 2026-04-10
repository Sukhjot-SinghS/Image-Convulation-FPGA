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

`timescale 1ns/1ps

module tb_uart();

    // -----------------------------------------------------------------------
    // DUT signals
    // -----------------------------------------------------------------------
    reg        clk   = 1'b0;
    reg        rst   = 1'b1;   // start in reset
    reg        rx_pin = 1'b1;

    // TX side — tied off for this RX-only test [FIX-TB-4]
    reg  [7:0] tx_data = 8'h00;
    reg        tx_en   = 1'b0;

    wire       tx_pin;
    wire [7:0] rx_data;
    wire       rx_ready;

    // [FIX-TB-2] Latch the received byte on the rx_ready pulse
    reg  [7:0] rx_data_latched = 8'hFF;
    reg        rx_received     = 1'b0;

    always @(posedge clk) begin
        if (rx_ready) begin
            rx_data_latched <= rx_data;
            rx_received     <= 1'b1;
        end
    end

    // -----------------------------------------------------------------------
    // 100 MHz clock  (period = 10 ns)
    // -----------------------------------------------------------------------
    always #5 clk = ~clk;

    // -----------------------------------------------------------------------
    // DUT instantiation
    // -----------------------------------------------------------------------
    uart_controller dut (
        .clk     (clk),
        .rst     (rst),
        .rx_pin  (rx_pin),
        .tx_pin  (tx_pin),
        .tx_data (tx_data),   // [FIX-TB-1] connected
        .tx_en   (tx_en),     // [FIX-TB-1] connected
        .rx_data (rx_data),
        .rx_ready(rx_ready),
        .tx_busy ()
    );

    // -----------------------------------------------------------------------
    // Stimulus — transmit 0x41 ('A') LSB first
    //
    // CLKS_PER_BIT = 87  →  bit period = 87 × 10 ns = 870 ns
    //
    // 0x41 = 0100_0001
    // LSB-first bit order: 1 0 0 0 0 0 1 0
    // -----------------------------------------------------------------------
    initial begin
        $dumpfile("uart_test.vcd");
        $dumpvars(0, tb_uart);

        // [FIX-TB-3] Hold reset for a few cycles then release
        repeat (4) @(posedge clk);
        rst = 1'b0;

        // Allow the FSMs to settle in IDLE
        #100;

        // --- UART frame for 0x41 ---
        rx_pin = 1'b0; #870;   // Start bit  (LOW)
        rx_pin = 1'b1; #870;   // Bit 0 = 1
        rx_pin = 1'b0; #870;   // Bit 1 = 0
        rx_pin = 1'b0; #870;   // Bit 2 = 0
        rx_pin = 1'b0; #870;   // Bit 3 = 0
        rx_pin = 1'b0; #870;   // Bit 4 = 0
        rx_pin = 1'b0; #870;   // Bit 5 = 0
        rx_pin = 1'b1; #870;   // Bit 6 = 1
        rx_pin = 1'b0; #870;   // Bit 7 = 0
        rx_pin = 1'b1; #870;   // Stop bit  (HIGH)

        // [FIX-TB-2] Wait for the rx_received latch (set by rx_ready pulse)
        // Give enough time for the stop-bit processing to complete.
        wait (rx_received || $time > 20_000);

        // Extra settling margin
        #100;

        // --- Result ---
        if (rx_received && rx_data_latched == 8'h41)
            $display("UART PASS: received 0x%02X ('A')", rx_data_latched);
        else if (!rx_received)
            $display("UART FAIL: rx_ready pulse never observed");
        else
            $display("UART FAIL: expected 0x41, got 0x%02X", rx_data_latched);

        $finish;
    end

endmodule
