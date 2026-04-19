// uart_rx.v  — Fixed version
// Bugs fixed:
//   [FIX-RX-1] START state now validates the start bit is still LOW at the
//               mid-point sample.  A glitch shorter than half a bit period no
//               longer causes a false reception.
//   [FIX-RX-2] STOP state now validates the stop bit is HIGH before asserting
//               rx_dv.  A framing error (missing stop bit) is silently
//               discarded and the FSM returns to IDLE to re-sync.
//   [FIX-RX-3] count is explicitly reset in STOP→IDLE transition so there is
//               no stale counter value on the next reception.
//   [FIX-RX-4] Added synchronous reset input (rst) so the module is safely
//               usable in synthesis (inline initialisation only works in sim).

module uart_rx #(parameter CLKS_PER_BIT = 87) (
    input            clk,
    input            rst,        // synchronous active-high reset
    input            rx_serial,  // physical RX pin
    output reg       rx_dv,      // 1-cycle data-valid pulse
    output reg [7:0] rx_byte     // received byte (stable when rx_dv is high)
);
    localparam IDLE  = 3'b000,
               START = 3'b001,
               DATA  = 3'b010,
               STOP  = 3'b011;

    reg [2:0] state = IDLE;
    reg [7:0] count = 0;   // 8 bits is enough for CLKS_PER_BIT up to 255
    reg [2:0] index = 0;

    always @(posedge clk) begin
        if (rst) begin
            state   <= IDLE;
            count   <= 0;
            index   <= 0;
            rx_dv   <= 0;
            rx_byte <= 0;
        end else begin
            case (state)
                // --------------------------------------------------------
                IDLE: begin
                    rx_dv <= 0;
                    count <= 0;
                    index <= 0;
                    // Falling edge on rx_serial → possible start bit
                    if (rx_serial == 1'b0)
                        state <= START;
                end

                // --------------------------------------------------------
                // Wait until the middle of the start bit, then verify it
                // is still LOW.  If it has gone high it was just a glitch.
                START: begin
                    if (count < (CLKS_PER_BIT - 1) / 2) begin
                        count <= count + 1;
                    end else begin
                        count <= 0;
                        // [FIX-RX-1] Validate start bit at mid-point
                        if (rx_serial == 1'b0)
                            state <= DATA;
                        else
                            state <= IDLE;   // glitch – abort
                    end
                end

                // --------------------------------------------------------
                DATA: begin
                    if (count < CLKS_PER_BIT - 1) begin
                        count <= count + 1;
                    end else begin
                        count           <= 0;
                        rx_byte[index]  <= rx_serial;
                        if (index < 7)
                            index <= index + 1;
                        else
                            state <= STOP;
                    end
                end

                // --------------------------------------------------------
                // Wait a full bit period, then sample the stop bit.
                STOP: begin
                    if (count < CLKS_PER_BIT - 1) begin
                        count <= count + 1;
                    end else begin
                        count <= 0;           // [FIX-RX-3] reset count
                        // [FIX-RX-2] Validate stop bit is HIGH
                        if (rx_serial == 1'b1)
                            rx_dv <= 1;       // valid frame
                        // framing error: rx_dv stays 0, byte discarded
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
