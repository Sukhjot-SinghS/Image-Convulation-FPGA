// ============================================================
//  line_buffer.v  —  "same" / zero-padding convolution
//  Author : Soumik Roy (Noob_Duck)  —  Group 18
//
//  Produces 128×128 = 16,384 output pixels (full input size).
//  Border pixels use implicit zero-padding: any 3×3 neighbor
//  that falls outside [0,127] × [0,127] is presented as 0x00.
//
//  Interface to surrounding modules:
//    ← img_bram_in   : single-byte pixel read port
//    → conv_engine   : 9 × 8-bit pixel window + window_valid
//    → img_bram_out  : output write address + write enable
//    ← top_fsm       : start / done handshake
// ============================================================
`timescale 1ns / 1ps

module line_buffer #(
    parameter IMG_W = 128,
    parameter IMG_H = 128
)(
    input  wire        clk,
    input  wire        reset,        // active-low

    // ── Handshake with top_fsm ───────────────────────────────
    input  wire        start,
    output reg         done,

    // ── img_bram_in read port ────────────────────────────────
    output reg  [13:0] bram_rd_addr,
    input  wire [ 7:0] bram_rd_data,

    // ── conv_engine pixel window ─────────────────────────────
    output reg  [ 7:0] p00, p01, p02,
    output reg  [ 7:0] p10, p11, p12,
    output reg  [ 7:0] p20, p21, p22,
    output reg         window_valid,

    // ── img_bram_out write port ──────────────────────────────
    output reg  [13:0] out_pixel_idx,
    output reg         out_valid
);

// ─────────────────────────────────────────────────────────────
//  Row register files  (prev / curr / next)
//  row0 = top  (slide_row-1), row1 = middle (slide_row),
//  row2 = bottom (slide_row+1)
// ─────────────────────────────────────────────────────────────
reg [7:0] row0_reg [0:127];
reg [7:0] row1_reg [0:127];
reg [7:0] row2_reg [0:127];

// ─────────────────────────────────────────────────────────────
//  FSM states
// ─────────────────────────────────────────────────────────────
localparam IDLE       = 3'd0;
localparam LOAD_ROW0  = 3'd1;   // img row 0 → row1_reg  (middle for slide_row=0)
localparam LOAD_ROW1  = 3'd2;   // img row 1 → row2_reg  (bottom for slide_row=0)
localparam SLIDE      = 3'd4;   // expose boundary-aware 3×3 window
localparam SHIFT_ROWS = 3'd5;   // row0←row1←row2, advance slide_row
localparam LOAD_NEXT  = 3'd6;   // stream next image row into row2_reg
localparam DONE_ST    = 3'd7;

reg [2:0] state;

// ─────────────────────────────────────────────────────────────
//  Counters
// ─────────────────────────────────────────────────────────────
reg [6:0] load_col;    // 0..127 — column index while loading a row
reg [6:0] col_ptr;     // 0..127 — output column (window centre)
reg [6:0] slide_row;   // 0..127 — output row    (window centre)
reg [7:0] next_row;    // 0..128 — next image row index to load into row2_reg
                       //          needs 8 bits to represent the sentinel value 128

// ─────────────────────────────────────────────────────────────
//  Output pixel index counter
// ─────────────────────────────────────────────────────────────
reg [13:0] out_idx_counter;   // 0..16383  (128×128)

// ─────────────────────────────────────────────────────────────
//  BRAM 1-cycle read latency bookkeeping
// ─────────────────────────────────────────────────────────────
reg        bram_rd_pending;
reg [6:0]  pending_col;
reg [1:0]  pending_row_sel;   // 1 → row1_reg, 2 → row2_reg

// ─────────────────────────────────────────────────────────────
//  Helper: build 14-bit BRAM byte address from (row, col)
//  row*128 + col = {row[6:0], col[6:0]}
// ─────────────────────────────────────────────────────────────
function [13:0] bram_addr;
    input [6:0] row;
    input [6:0] col;
    begin
        bram_addr = {row, col};
    end
endfunction

integer i;

// ─────────────────────────────────────────────────────────────
//  Main FSM
// ─────────────────────────────────────────────────────────────
always @(posedge clk or negedge reset) begin
    if (!reset) begin
        state           <= IDLE;
        done            <= 1'b0;
        window_valid    <= 1'b0;
        out_valid       <= 1'b0;
        bram_rd_addr    <= 14'd0;
        bram_rd_pending <= 1'b0;
        load_col        <= 7'd0;
        col_ptr         <= 7'd0;
        slide_row       <= 7'd0;
        next_row        <= 8'd0;
        out_idx_counter <= 14'd0;
        out_pixel_idx   <= 14'd0;
    end
    else begin

        // ── defaults ──────────────────────────────────────────
        done         <= 1'b0;
        window_valid <= 1'b0;
        out_valid    <= 1'b0;

        // ── absorb pending BRAM byte (1-cycle latency) ────────
        if (bram_rd_pending) begin
            bram_rd_pending <= 1'b0;
            case (pending_row_sel)
                2'd1: row1_reg[pending_col] <= bram_rd_data;
                2'd2: row2_reg[pending_col] <= bram_rd_data;
                default: ;
            endcase
        end

        // ── FSM ───────────────────────────────────────────────
        case (state)

            // ──────────────────────────────────────────────────
            IDLE: begin
                if (start) begin
                    load_col        <= 7'd0;
                    slide_row       <= 7'd0;
                    next_row        <= 8'd2;   // first row to load after preloading rows 0 & 1
                    out_idx_counter <= 14'd0;
                    // Issue first read address: img row 0, col 0 → will land in row1_reg
                    bram_rd_addr    <= bram_addr(7'd0, 7'd0);
                    bram_rd_pending <= 1'b1;
                    pending_col     <= 7'd0;
                    pending_row_sel <= 2'd1;
                    state           <= LOAD_ROW0;
                end
            end

            // ──────────────────────────────────────────────────
            //  Load img row 0 into row1_reg (middle row for slide_row=0)
            // ──────────────────────────────────────────────────
            LOAD_ROW0: begin
                if (load_col == 7'd127) begin
                    // All 128 bytes of img row 0 absorbed.
                    // Issue first address of img row 1 → row2_reg.
                    load_col        <= 7'd0;
                    bram_rd_addr    <= bram_addr(7'd1, 7'd0);
                    bram_rd_pending <= 1'b1;
                    pending_col     <= 7'd0;
                    pending_row_sel <= 2'd2;
                    state           <= LOAD_ROW1;
                end
                else begin
                    load_col        <= load_col + 7'd1;
                    bram_rd_addr    <= bram_addr(7'd0, load_col + 7'd1);
                    bram_rd_pending <= 1'b1;
                    pending_col     <= load_col + 7'd1;
                    pending_row_sel <= 2'd1;
                end
            end

            // ──────────────────────────────────────────────────
            //  Load img row 1 into row2_reg (bottom row for slide_row=0)
            // ──────────────────────────────────────────────────
            LOAD_ROW1: begin
                if (load_col == 7'd127) begin
                    // All 128 bytes of img row 1 absorbed.
                    // Ready to slide starting at output row 0.
                    load_col <= 7'd0;
                    col_ptr  <= 7'd0;
                    state    <= SLIDE;
                end
                else begin
                    load_col        <= load_col + 7'd1;
                    bram_rd_addr    <= bram_addr(7'd1, load_col + 7'd1);
                    bram_rd_pending <= 1'b1;
                    pending_col     <= load_col + 7'd1;
                    pending_row_sel <= 2'd2;
                end
            end

            // ──────────────────────────────────────────────────
            //  SLIDE — boundary-aware 3×3 window for output
            //          pixel at (slide_row, col_ptr).
            //
            //  Zero-padding rules:
            //    top    row  → row0_reg if slide_row > 0, else 0x00
            //    bottom row  → row2_reg if slide_row < 127, else 0x00
            //    left   col  → reg[col_ptr-1] if col_ptr > 0, else 0x00
            //    right  col  → reg[col_ptr+1] if col_ptr < 127, else 0x00
            // ──────────────────────────────────────────────────
            SLIDE: begin
                // Top row (slide_row - 1)
                p00 <= (slide_row == 7'd0 || col_ptr == 7'd0)   ? 8'h00 : row0_reg[col_ptr - 7'd1];
                p01 <= (slide_row == 7'd0)                       ? 8'h00 : row0_reg[col_ptr];
                p02 <= (slide_row == 7'd0 || col_ptr == 7'd127) ? 8'h00 : row0_reg[col_ptr + 7'd1];
                // Middle row (slide_row)
                p10 <= (col_ptr == 7'd0)                         ? 8'h00 : row1_reg[col_ptr - 7'd1];
                p11 <=                                                      row1_reg[col_ptr];
                p12 <= (col_ptr == 7'd127)                       ? 8'h00 : row1_reg[col_ptr + 7'd1];
                // Bottom row (slide_row + 1)
                p20 <= (slide_row == 7'd127 || col_ptr == 7'd0)   ? 8'h00 : row2_reg[col_ptr - 7'd1];
                p21 <= (slide_row == 7'd127)                       ? 8'h00 : row2_reg[col_ptr];
                p22 <= (slide_row == 7'd127 || col_ptr == 7'd127) ? 8'h00 : row2_reg[col_ptr + 7'd1];

                window_valid    <= 1'b1;
                out_valid       <= 1'b1;
                out_pixel_idx   <= out_idx_counter;
                out_idx_counter <= out_idx_counter + 14'd1;

                if (col_ptr == 7'd127) begin
                    col_ptr <= 7'd0;
                    if (slide_row == 7'd127)
                        state <= DONE_ST;
                    else
                        state <= SHIFT_ROWS;
                end
                else begin
                    col_ptr <= col_ptr + 7'd1;
                end
            end

            // ──────────────────────────────────────────────────
            //  SHIFT_ROWS — row0←row1, row1←row2, then
            //               load the next image row into row2
            //               (or go straight to SLIDE if no more
            //                image rows exist — slide_row==127
            //                uses zero-padding for the bottom).
            // ──────────────────────────────────────────────────
            SHIFT_ROWS: begin
                for (i = 0; i < 128; i = i + 1) begin
                    row0_reg[i] <= row1_reg[i];
                    row1_reg[i] <= row2_reg[i];
                end
                slide_row <= slide_row + 7'd1;
                if (next_row < 8'd128) begin
                    load_col        <= 7'd0;
                    bram_rd_addr    <= bram_addr(next_row[6:0], 7'd0);
                    bram_rd_pending <= 1'b1;
                    pending_col     <= 7'd0;
                    pending_row_sel <= 2'd2;
                    state           <= LOAD_NEXT;
                end
                else begin
                    // next_row == 128: no image row below slide_row=126.
                    // slide_row will become 127; SLIDE handles the bottom
                    // border with zero-padding (slide_row==127 guard).
                    col_ptr <= 7'd0;
                    state   <= SLIDE;
                end
            end

            // ──────────────────────────────────────────────────
            //  LOAD_NEXT — stream image row next_row into row2_reg
            // ──────────────────────────────────────────────────
            LOAD_NEXT: begin
                if (load_col == 7'd127) begin
                    next_row <= next_row + 8'd1;
                    col_ptr  <= 7'd0;
                    state    <= SLIDE;
                end
                else begin
                    load_col        <= load_col + 7'd1;
                    bram_rd_addr    <= bram_addr(next_row[6:0], load_col + 7'd1);
                    bram_rd_pending <= 1'b1;
                    pending_col     <= load_col + 7'd1;
                    pending_row_sel <= 2'd2;
                end
            end

            // ──────────────────────────────────────────────────
            DONE_ST: begin
                done  <= 1'b1;
                state <= IDLE;
            end

            default: state <= IDLE;

        endcase
    end
end

endmodule
