// uart_tx.v  — Fixed version
// Bugs fixed:
//   [FIX-TX-1] CRITICAL: count and index were never reset inside the IDLE
//               state.  After the first transmission both registers held their
//               end-of-frame values (count = CLKS_PER_BIT-1, index = 7).
//               On the very next START state the "count < CLKS_PER_BIT-1"
//               guard was already false, so the start bit was skipped in 0
//               clock cycles and DATA began immediately — producing a
//               malformed frame from the second byte onward.
//               Fix: reset count and index in the IDLE state.
//   [FIX-TX-2] Added synchronous reset (rst) for synthesis safety.

module uart_tx #(parameter CLKS_PER_BIT = 87) (
    input            clk,
    input            rst,       // synchronous active-high reset
    input            tx_start,  // assert for one cycle to begin transmission
    input      [7:0] tx_byte,   // byte to transmit (must be stable while busy)
    output reg       tx_serial, // UART TX line
    output reg       tx_done    // 1-cycle pulse when frame is complete
);
    localparam IDLE  = 3'b000,
               START = 3'b001,
               DATA  = 3'b010,
               STOP  = 3'b011;

    reg [2:0] state = IDLE;
    reg [7:0] count = 0;
    reg [2:0] index = 0;

    always @(posedge clk) begin
        if (rst) begin
            state     <= IDLE;
            tx_serial <= 1'b1;
            tx_done   <= 1'b0;
            count     <= 0;
            index     <= 0;
        end else begin
            case (state)
                // --------------------------------------------------------
                IDLE: begin
                    tx_serial <= 1'b1;   // line idles high
                    tx_done   <= 1'b0;
                    // [FIX-TX-1] Always reset count and index in IDLE so
                    // subsequent transmissions begin cleanly.
                    count     <= 0;
                    index     <= 0;
                    if (tx_start)
                        state <= START;
                end

                // --------------------------------------------------------
                START: begin
                    tx_serial <= 1'b0;   // pull line low for start bit
                    if (count < CLKS_PER_BIT - 1)
                        count <= count + 1;
                    else begin
                        count <= 0;
                        state <= DATA;
                    end
                end

                // --------------------------------------------------------
                DATA: begin
                    tx_serial <= tx_byte[index];
                    if (count < CLKS_PER_BIT - 1) begin
                        count <= count + 1;
                    end else begin
                        count <= 0;
                        if (index < 7)
                            index <= index + 1;
                        else
                            state <= STOP;
                    end
                end

                // --------------------------------------------------------
                STOP: begin
                    tx_serial <= 1'b1;   // stop bit — line high
                    if (count < CLKS_PER_BIT - 1) begin
                        count <= count + 1;
                    end else begin
                        tx_done <= 1'b1;
                        state   <= IDLE;
                    end
                end

                default: begin
                    tx_serial <= 1'b1;
                    state     <= IDLE;
                end
            endcase
        end
    end
endmodule
