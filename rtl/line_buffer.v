// ============================================================
//  line_buffer.v
//  Author : Soumik Roy  (Noob_Duck)  — Group 18
//
//  Purpose:
//    Holds 3 rows of a 128×128 grayscale image at a time.
//    Slides a 3×3 window across columns and exposes the 9
//    pixel values to conv_engine each clock cycle.
//    When all 126 valid column positions are done, drops the
//    oldest row, shifts down, and loads the next image row.
//    Repeats for rows 1→126  →  126 × 126 = 15,876 output pixels.
//
//  Interface to surrounding modules:
//    ← img_bram_in   : single-byte pixel read port
//    → conv_engine   : 9 × 8-bit pixel window + window_valid
//    → img_bram_out  : output write address + write enable
//    ← top_fsm       : start / done handshake
// ============================================================

module line_buffer #(
    parameter IMG_W  = 128,   // image width  in pixels
    parameter IMG_H  = 128    // image height in pixels
)(
    input  wire        clk,
    input  wire        reset,       // active-low, matches rest of project

    // ── Handshake with top_fsm ───────────────────────────────
    input  wire        start,       // pulse: begin processing
    output reg         done,        // pulse: all valid pixels sent

    // ── img_bram_in read port ────────────────────────────────
    output reg  [13:0] bram_rd_addr,  // byte address  (128×128 = 16384 → 14 bits)
    input  wire [ 7:0] bram_rd_data,  // pixel byte returned next cycle

    // ── conv_engine pixel window ─────────────────────────────
    output reg  [ 7:0] p00, p01, p02,
    output reg  [ 7:0] p10, p11, p12,
    output reg  [ 7:0] p20, p21, p22,
    output reg         window_valid,  // 1 → conv_engine may latch this window

    // ── img_bram_out write port (we pass through pixel coords) ──
    output reg  [13:0] out_pixel_idx, // which output pixel this result maps to
    output reg         out_valid       // 1 → conv_engine result should be stored
);

// ─────────────────────────────────────────────────────────────
//  Parameters derived from IMG_W / IMG_H
// ─────────────────────────────────────────────────────────────
localparam COL_MAX   = IMG_W - 1;        // 127
localparam ROW_MAX   = IMG_H - 1;        // 127
localparam VALID_COLS = IMG_W - 2;       // 126  (cols 1..126)
localparam VALID_ROWS = IMG_H - 2;       // 126  (rows 1..126)

// ─────────────────────────────────────────────────────────────
//  3 × 128 row registers   (prev / curr / next)
// ─────────────────────────────────────────────────────────────
reg [7:0] row0_reg [0:IMG_W-1];   // prev  (oldest)
reg [7:0] row1_reg [0:IMG_W-1];   // curr  (middle)
reg [7:0] row2_reg [0:IMG_W-1];   // next  (newest)

// ─────────────────────────────────────────────────────────────
//  FSM states
// ─────────────────────────────────────────────────────────────
localparam IDLE        = 3'd0;
localparam LOAD_ROW0   = 3'd1;   // fill row0_reg  (image row 0)
localparam LOAD_ROW1   = 3'd2;   // fill row1_reg  (image row 1)
localparam LOAD_ROW2   = 3'd3;   // fill row2_reg  (image row 2) — first next row
localparam SLIDE       = 3'd4;   // slide col_ptr across 126 valid columns
localparam SHIFT_ROWS  = 3'd5;   // drop prev, shift curr→prev, next→curr
localparam LOAD_NEXT   = 3'd6;   // load brand-new row into row2_reg
localparam DONE        = 3'd7;

reg [2:0] state;

// ─────────────────────────────────────────────────────────────
//  Counters
// ─────────────────────────────────────────────────────────────
reg  [6:0] load_col;   // 0..127  — column index while loading a row
reg  [6:0] col_ptr;    // 0..125  — leading-left column of the 3×3 window
                       //           window uses col_ptr, col_ptr+1, col_ptr+2
reg  [6:0] slide_row;  // 1..126  — which image row is currently "curr" (row1)
reg  [6:0] next_row;   // image row index being loaded into row2_reg

// ─────────────────────────────────────────────────────────────
//  BRAM read has 1-cycle latency — we issue address one cycle
//  early and store the arriving byte the next cycle.
// ─────────────────────────────────────────────────────────────
reg        bram_rd_pending;   // waiting for bram data
reg  [6:0] pending_col;       // which column the pending byte belongs to
reg  [1:0] pending_row_sel;   // which row register (0/1/2) to write into

// ─────────────────────────────────────────────────────────────
//  Output pixel index counter
// ─────────────────────────────────────────────────────────────
// Output pixel (r, c) where r = slide_row (1..126), c = col_ptr+1 (1..126)
// Stored linearly: idx = r * IMG_W + c
// But we keep a running counter for simplicity.
reg [13:0] out_idx_counter;

// ─────────────────────────────────────────────────────────────
//  Helper: build BRAM byte address from (row, col)
// ─────────────────────────────────────────────────────────────
function [13:0] bram_addr;
    input [6:0] row;
    input [6:0] col;
    begin
        bram_addr = {row, col};   // row*128 + col  (128 = 2^7)
    end
endfunction

// ─────────────────────────────────────────────────────────────
//  Integer for row-shift copy loop
// ─────────────────────────────────────────────────────────────
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
        slide_row       <= 7'd1;
        next_row        <= 7'd3;
        out_idx_counter <= 14'd0;
        out_pixel_idx   <= 14'd0;
    end
    else begin

        // ── defaults (cleared every cycle unless re-asserted) ──
        done         <= 1'b0;
        window_valid <= 1'b0;
        out_valid    <= 1'b0;

        // ── absorb pending BRAM byte ──────────────────────────
        if (bram_rd_pending) begin
            bram_rd_pending <= 1'b0;
            case (pending_row_sel)
                2'd0: row0_reg[pending_col] <= bram_rd_data;
                2'd1: row1_reg[pending_col] <= bram_rd_data;
                2'd2: row2_reg[pending_col] <= bram_rd_data;
                default: ;
            endcase
        end

        // ── FSM ──────────────────────────────────────────────
        case (state)

            // ------------------------------------------------
            IDLE: begin
                if (start) begin
                    load_col        <= 7'd0;
                    slide_row       <= 7'd1;   // first valid "curr" row
                    next_row        <= 7'd3;   // first row to load after initial 3
                    out_idx_counter <= 14'd0;
                    // Issue first read address for row 0 col 0
                    bram_rd_addr    <= bram_addr(7'd0, 7'd0);
                    bram_rd_pending <= 1'b1;
                    pending_col     <= 7'd0;
                    pending_row_sel <= 2'd0;
                    state           <= LOAD_ROW0;
                end
            end

            // ------------------------------------------------
            // LOAD_ROW0 : fill row0_reg from img_bram_in
            //   We issued address for col N-1 in previous cycle,
            //   the byte arrives this cycle (absorbed above).
            //   Now issue address for col N.
            // ------------------------------------------------
            LOAD_ROW0: begin
                if (load_col == 7'd126) begin
                    // Last byte of row 0 is being absorbed above.
                    // Start loading row 1 col 0 next cycle.
                    load_col        <= 7'd0;
                    bram_rd_addr    <= bram_addr(7'd1, 7'd0);
                    bram_rd_pending <= 1'b1;
                    pending_col     <= 7'd0;
                    pending_row_sel <= 2'd1;
                    state           <= LOAD_ROW1;
                end
                else begin
                    // Issue next column address
                    load_col        <= load_col + 7'd1;
                    bram_rd_addr    <= bram_addr(7'd0, load_col + 7'd1);
                    bram_rd_pending <= 1'b1;
                    pending_col     <= load_col + 7'd1;
                    pending_row_sel <= 2'd0;
                end
            end

            // ------------------------------------------------
            LOAD_ROW1: begin
                if (load_col == 7'd126) begin
                    load_col        <= 7'd0;
                    bram_rd_addr    <= bram_addr(7'd2, 7'd0);
                    bram_rd_pending <= 1'b1;
                    pending_col     <= 7'd0;
                    pending_row_sel <= 2'd2;
                    state           <= LOAD_ROW2;
                end
                else begin
                    load_col        <= load_col + 7'd1;
                    bram_rd_addr    <= bram_addr(7'd1, load_col + 7'd1);
                    bram_rd_pending <= 1'b1;
                    pending_col     <= load_col + 7'd1;
                    pending_row_sel <= 2'd1;
                end
            end

            // ------------------------------------------------
            LOAD_ROW2: begin
                if (load_col == 7'd126) begin
                    // All 3 rows loaded — begin sliding
                    load_col <= 7'd0;
                    col_ptr  <= 7'd0;   // window left edge starts at col 0
                    state    <= SLIDE;
                end
                else begin
                    load_col        <= load_col + 7'd1;
                    bram_rd_addr    <= bram_addr(7'd2, load_col + 7'd1);
                    bram_rd_pending <= 1'b1;
                    pending_col     <= load_col + 7'd1;
                    pending_row_sel <= 2'd2;
                end
            end

            // ------------------------------------------------
            //  SLIDE : expose 3×3 window for each valid column
            //
            //  col_ptr  = 0..125  → window cols  col_ptr .. col_ptr+2
            //  Valid output pixel is the centre: row1_reg[col_ptr+1]
            //
            //  We output the window combinatorially (see below),
            //  and register window_valid + out_valid here.
            // ------------------------------------------------
            SLIDE: begin
                // Drive the 3×3 pixel outputs (registered)
                p00 <= row0_reg[col_ptr];
                p01 <= row0_reg[col_ptr + 7'd1];
                p02 <= row0_reg[col_ptr + 7'd2];
                p10 <= row1_reg[col_ptr];
                p11 <= row1_reg[col_ptr + 7'd1];
                p12 <= row1_reg[col_ptr + 7'd2];
                p20 <= row2_reg[col_ptr];
                p21 <= row2_reg[col_ptr + 7'd1];
                p22 <= row2_reg[col_ptr + 7'd2];

                window_valid  <= 1'b1;
                out_valid     <= 1'b1;
                out_pixel_idx <= out_idx_counter;
                out_idx_counter <= out_idx_counter + 14'd1;

                if (col_ptr == 7'd125) begin
                    // Done with this row-triplet
                    col_ptr <= 7'd0;

                    if (slide_row == 7'd126) begin
                        // All 126 valid rows processed — finished!
                        state <= DONE;
                    end
                    else begin
                        state <= SHIFT_ROWS;
                    end
                end
                else begin
                    col_ptr <= col_ptr + 7'd1;
                end
            end

            // ------------------------------------------------
            //  SHIFT_ROWS : row0 ← row1 ← row2
            //  (copy in a single cycle — Verilog arrays allow
            //   loop in always block; synthesises to mux/regs)
            // ------------------------------------------------
            SHIFT_ROWS: begin
                for (i = 0; i < IMG_W; i = i + 1) begin
                    row0_reg[i] <= row1_reg[i];
                    row1_reg[i] <= row2_reg[i];
                end
                // row2_reg will be overwritten in LOAD_NEXT
                load_col        <= 7'd0;
                bram_rd_addr    <= bram_addr(next_row, 7'd0);
                bram_rd_pending <= 1'b1;
                pending_col     <= 7'd0;
                pending_row_sel <= 2'd2;
                state           <= LOAD_NEXT;
            end

            // ------------------------------------------------
            //  LOAD_NEXT : stream next image row into row2_reg
            // ------------------------------------------------
            LOAD_NEXT: begin
                if (load_col == 7'd127) begin
                    // New row fully loaded
                    slide_row <= slide_row + 7'd1;
                    next_row  <= next_row  + 7'd1;
                    col_ptr   <= 7'd0;
                    state     <= SLIDE;
                end
                else begin
                    load_col        <= load_col + 7'd1;
                    bram_rd_addr    <= bram_addr(next_row, load_col + 7'd1);
                    bram_rd_pending <= 1'b1;
                    pending_col     <= load_col + 7'd1;
                    pending_row_sel <= 2'd2;
                end
            end

            // ------------------------------------------------
            DONE: begin
                done  <= 1'b1;
                state <= IDLE;
            end

            default: state <= IDLE;

        endcase
    end
end

endmodule
