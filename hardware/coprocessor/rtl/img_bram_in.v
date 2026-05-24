// ============================================================
//  img_bram_in.v
//  Author : Soumik Roy (Noob_Duck) — Group 18
//
//  Purpose:
//    Stores the full 128×128 = 16,384 byte input image.
//    Abhirup's uart_rx fills it one byte at a time.
//    line_buffer reads from it one byte at a time.
//
//  Two ports:
//    WRITE port → Abhirup drives this (uart_rx side)
//    READ  port → Soumik drives this (line_buffer side)
//                 1-cycle read latency (real BRAM behaviour)
//
//  Memory map:
//    pixel(row, col) lives at address = row*128 + col
//    address range 0 → 16383
// ============================================================

module img_bram_in (
    input  wire        clk,

    // ── WRITE port (Abhirup — uart_rx controller) ────────────
    input  wire        we,           // write enable — 1 when uart_rx has a byte
    input  wire [13:0] wr_addr,      // byte address to write (0 → 16383)
    input  wire [ 7:0] wr_data,      // pixel byte from uart_rx

    // ── READ port (Soumik — line_buffer) ─────────────────────
    input  wire [13:0] rd_addr,      // byte address line_buffer wants
    output reg  [ 7:0] rd_data       // pixel byte — arrives ONE cycle later
);

// ─────────────────────────────────────────────────────────────
//  BRAM array — 16384 bytes
//  (* ram_style = "block" *) tells Vivado to use BRAM not LUTs
// ─────────────────────────────────────────────────────────────
(* ram_style = "block" *)
reg [7:0] mem [0:16383];

// ─────────────────────────────────────────────────────────────
//  WRITE — synchronous
//  Abhirup writes one byte per uart_rx byte received
// ─────────────────────────────────────────────────────────────
always @(posedge clk) begin
    if (we)
        mem[wr_addr] <= wr_data;
end

// ─────────────────────────────────────────────────────────────
//  READ — synchronous (1-cycle latency)
//  line_buffer puts address on rd_addr this cycle
//  rd_data arrives NEXT cycle
//  This matches the bram_rd_pending system in line_buffer
// ─────────────────────────────────────────────────────────────
always @(posedge clk) begin
    if (we && wr_addr == rd_addr)
      rd_data <= wr_data;    // forward new value
    else
      rd_data <= mem[rd_addr];
  end

endmodule