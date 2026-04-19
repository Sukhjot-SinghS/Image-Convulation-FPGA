// ============================================================
//  img_bram_out.v
//  Author : Soumik Roy (Noob_Duck) — Group 18
//
//  Purpose:
//    Stores the 126×126 = 15,876 byte output image.
//    conv_engine writes one filtered pixel at a time.
//    Abhirup's uart_tx reads it one byte at a time to send
//    back to the Python GUI.
//
//  Two ports:
//    WRITE port → Soumik drives this (conv_engine side)
//    READ  port → Abhirup drives this (uart_tx side)
//                 1-cycle read latency
//
//  Memory map:
//    output pixel index 0 → 15875
//    stored linearly, same order conv_engine produces them
// ============================================================

module img_bram_out (
    input  wire        clk,

    // ── WRITE port (Soumik — conv_engine) ────────────────────
    input  wire        we,           // = out_valid from conv_engine
    input  wire [13:0] wr_addr,      // = pixel_idx_out from conv_engine
    input  wire [ 7:0] wr_data,      // = pixel_out from conv_engine

    // ── READ port (Abhirup — uart_tx controller) ──────────────
    input  wire [13:0] rd_addr,      // byte address uart_tx wants
    output reg  [ 7:0] rd_data       // filtered pixel — arrives ONE cycle later
);

// ─────────────────────────────────────────────────────────────
//  BRAM array — 16384 bytes
//  (slightly larger than 15876 for alignment, unused slots
//   at end are never read)
//  (* ram_style = "block" *) forces Vivado to use BRAM
// ─────────────────────────────────────────────────────────────
(* ram_style = "block" *)
reg [7:0] mem [0:16383];

// ─────────────────────────────────────────────────────────────
//  WRITE — synchronous
//  conv_engine writes one filtered pixel per cycle
//  when out_valid=1
// ─────────────────────────────────────────────────────────────
always @(posedge clk) begin
    if (we)
        mem[wr_addr] <= wr_data;
end

// ─────────────────────────────────────────────────────────────
//  READ — synchronous (1-cycle latency)
//  Abhirup's uart_tx controller drives rd_addr
//  rd_data arrives next cycle for uart_tx to send
// ─────────────────────────────────────────────────────────────
always @(posedge clk) begin
    rd_data <= mem[rd_addr];
end

endmodule