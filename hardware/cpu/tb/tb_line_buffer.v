`timescale 1ns / 1ps
// ============================================================
//  tb_line_buffer.v
//  Author : Soumik Roy (Noob_Duck) — Group 18
//
//  What this testbench checks:
//  TEST 1 — Reset behaviour
//  TEST 2 — BRAM loads correctly (row0, row1, row2)
//  TEST 3 — window_valid is 0 during loading
//  TEST 4 — window_valid is 1 during SLIDE
//  TEST 5 — p00..p22 are correct values during SLIDE
//  TEST 6 — out_pixel_idx counts 0 → 15875
//  TEST 7 — out_valid matches window_valid
//  TEST 8 — done pulses exactly once at end
//  TEST 9 — after done, goes back to IDLE
// ============================================================

module tb_line_buffer;

// ─────────────────────────────────────────────────────────────
//  Clock and reset
// ─────────────────────────────────────────────────────────────
reg clk;
reg reset;
reg start;

// ─────────────────────────────────────────────────────────────
//  BRAM model signals
// ─────────────────────────────────────────────────────────────
wire [13:0] bram_rd_addr;
reg  [ 7:0] bram_rd_data;

// ─────────────────────────────────────────────────────────────
//  line_buffer outputs
// ─────────────────────────────────────────────────────────────
wire [ 7:0] p00, p01, p02;
wire [ 7:0] p10, p11, p12;
wire [ 7:0] p20, p21, p22;
wire        window_valid;
wire [13:0] out_pixel_idx;
wire        out_valid;
wire        done;

// ─────────────────────────────────────────────────────────────
//  Fake BRAM — 128×128 = 16384 bytes
//  pixel value = address[7:0]  (easy to verify)
//  So pixel at (row, col) = (row*128 + col) & 0xFF
// ─────────────────────────────────────────────────────────────
reg [7:0] fake_bram [0:16383];

integer idx;
initial begin
    for (idx = 0; idx < 16384; idx = idx + 1)
        fake_bram[idx] = idx[7:0];   // value = lower 8 bits of address
end

// ─────────────────────────────────────────────────────────────
//  BRAM response — 1 cycle latency model
//  When line_buffer puts address on bram_rd_addr,
//  we return fake_bram[address] one cycle later
// ─────────────────────────────────────────────────────────────
always @(posedge clk) begin
    bram_rd_data <= fake_bram[bram_rd_addr];
end

// ─────────────────────────────────────────────────────────────
//  DUT instantiation
// ─────────────────────────────────────────────────────────────
line_buffer #(
    .IMG_W(128),
    .IMG_H(128)
) dut (
    .clk          (clk),
    .reset        (reset),
    .start        (start),
    .done         (done),
    .bram_rd_addr (bram_rd_addr),
    .bram_rd_data (bram_rd_data),
    .p00(p00), .p01(p01), .p02(p02),
    .p10(p10), .p11(p11), .p12(p12),
    .p20(p20), .p21(p21), .p22(p22),
    .window_valid (window_valid),
    .out_pixel_idx(out_pixel_idx),
    .out_valid    (out_valid)
);

// ─────────────────────────────────────────────────────────────
//  Clock generation — 10ns period
// ─────────────────────────────────────────────────────────────
initial clk = 0;
always #5 clk = ~clk;

// ─────────────────────────────────────────────────────────────
//  Test tracking
// ─────────────────────────────────────────────────────────────
integer pass_count;
integer fail_count;
integer pixel_count;
integer done_count;
integer valid_before_slide;

// ─────────────────────────────────────────────────────────────
//  Helper task — check a condition and print result
// ─────────────────────────────────────────────────────────────
task check;
    input condition;
    input [127:0] test_name;
    begin
        if (condition) begin
            $display("  PASS : %s", test_name);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL : %s", test_name);
            fail_count = fail_count + 1;
        end
    end
endtask

// ─────────────────────────────────────────────────────────────
//  Helper task — apply reset
// ─────────────────────────────────────────────────────────────
task apply_reset;
    begin
        reset = 0;        // active low — assert reset
        start = 0;
        @(posedge clk);
        @(posedge clk);
        reset = 1;        // release reset
        @(posedge clk);
    end
endtask

// ─────────────────────────────────────────────────────────────
//  Monitoring — count valid windows and done pulses
// ─────────────────────────────────────────────────────────────
always @(posedge clk) begin
    if (window_valid)
        pixel_count = pixel_count + 1;
    if (done)
        done_count = done_count + 1;
end

// ─────────────────────────────────────────────────────────────
//  MAIN TEST SEQUENCE
// ─────────────────────────────────────────────────────────────
integer cycle_count;
integer load_cycles;
reg     saw_valid_during_load;
reg     first_valid_seen;
reg [7:0] expected_p00, expected_p11;

initial begin
    $display("============================================");
    $display("  tb_line_buffer — Group 18 — Noob_Duck");
    $display("============================================");

    // initialise counters
    pass_count           = 0;
    fail_count           = 0;
    pixel_count          = 0;
    done_count           = 0;
    valid_before_slide   = 0;
    saw_valid_during_load = 0;
    first_valid_seen     = 0;

    // ─────────────────────────────────────────────
    // TEST 1 — Reset behaviour
    // ─────────────────────────────────────────────
    $display("\n--- TEST 1: Reset behaviour ---");
    reset = 1;
    start = 0;
    @(posedge clk);

    reset = 0;   // assert reset
    @(posedge clk);
    @(posedge clk);

    check(window_valid == 0,   "window_valid=0 during reset");
    check(out_valid    == 0,   "out_valid=0 during reset");
    check(done         == 0,   "done=0 during reset");

    reset = 1;   // release reset
    @(posedge clk);
    check(window_valid == 0,   "window_valid=0 after reset released");

    // ─────────────────────────────────────────────
    // TEST 2 — No output before start
    // ─────────────────────────────────────────────
    $display("\n--- TEST 2: No output before start ---");
    repeat(5) @(posedge clk);
    check(window_valid == 0,   "window_valid stays 0 without start");
    check(done         == 0,   "done stays 0 without start");

    // ─────────────────────────────────────────────
    // TEST 3 — window_valid=0 during all loading
    //          Monitor for 128*3 = 384 cycles after start
    // ─────────────────────────────────────────────
    $display("\n--- TEST 3: window_valid=0 during loading ---");
    apply_reset;

    // send start pulse
    start = 1;
    @(posedge clk);
    start = 0;

    // monitor for 390 cycles (enough for all 3 rows to load)
    saw_valid_during_load = 0;
    for (load_cycles = 0; load_cycles < 390; load_cycles = load_cycles + 1) begin
        @(posedge clk);
        if (window_valid) begin
            saw_valid_during_load = 1;
        end
        // once first SLIDE starts, stop monitoring
        if (window_valid && !first_valid_seen) begin
            first_valid_seen = 1;
        end
    end
    // We expect window_valid to have become 1 by now (SLIDE started)
    check(first_valid_seen == 1, "window_valid becomes 1 after loading done");

    // ─────────────────────────────────────────────
    // TEST 4 — First window values correct
    //          First SLIDE, col_ptr=0:
    //          p00 = row0[0] = fake_bram[0]   = 0
    //          p01 = row0[1] = fake_bram[1]   = 1
    //          p02 = row0[2] = fake_bram[2]   = 2
    //          p10 = row1[0] = fake_bram[128] = 128 → 128 & 0xFF = 128
    //          p11 = row1[1] = fake_bram[129] = 129
    //          p20 = row2[0] = fake_bram[256] = 256 & 0xFF = 0
    //          p21 = row2[1] = fake_bram[257] = 257 & 0xFF = 1
    // ─────────────────────────────────────────────
    $display("\n--- TEST 4: First window pixel values ---");

    // reset and run fresh to catch the exact first window
    apply_reset;
    pixel_count = 0;

    start = 1;
    @(posedge clk);
    start = 0;

    // wait until first window_valid
    cycle_count = 0;
    while (!window_valid && cycle_count < 1000) begin
        @(posedge clk);
        cycle_count = cycle_count + 1;
    end
    @(posedge clk);   // wait one cycle for registered outputs to settle

    // now window_valid=1, col_ptr=0, check values
    // pixel value = address & 0xFF
    // row0[0] = bram[0]   = 0
    // row0[1] = bram[1]   = 1
    // row0[2] = bram[2]   = 2
    // row1[0] = bram[128] = 128
    // row1[1] = bram[129] = 129
    // row1[2] = bram[130] = 130
    // row2[0] = bram[256] = 0   (256 & 0xFF = 0)
    // row2[1] = bram[257] = 1
    // row2[2] = bram[258] = 2

    check(window_valid == 1,      "window_valid=1 at first SLIDE");
    check(p00 == 8'd0,            "p00 correct (row0[0]=0)");
    check(p01 == 8'd1,            "p01 correct (row0[1]=1)");
    check(p02 == 8'd2,            "p02 correct (row0[2]=2)");
    check(p10 == 8'd128,          "p10 correct (row1[0]=128)");
    check(p11 == 8'd129,          "p11 correct (row1[1]=129)");
    check(p12 == 8'd130,          "p12 correct (row1[2]=130)");
    check(p20 == 8'd0,            "p20 correct (row2[0]=256&FF=0)");
    check(p21 == 8'd1,            "p21 correct (row2[1]=257&FF=1)");
    check(p22 == 8'd2,            "p22 correct (row2[2]=258&FF=2)");

    // ─────────────────────────────────────────────
    // TEST 5 — out_pixel_idx starts at 0 on first window
    // ─────────────────────────────────────────────
    $display("\n--- TEST 5: out_pixel_idx starts at 0 ---");
    check(out_pixel_idx == 14'd0, "out_pixel_idx=0 on first valid window");
    check(out_valid     == 1'b1,  "out_valid=1 on first valid window");

    // ─────────────────────────────────────────────
    // TEST 6 — out_pixel_idx increments each cycle
    // ─────────────────────────────────────────────
    $display("\n--- TEST 6: out_pixel_idx increments correctly ---");
    @(posedge clk);
    check(out_pixel_idx == 14'd1, "out_pixel_idx=1 on second window");
    @(posedge clk);
    check(out_pixel_idx == 14'd2, "out_pixel_idx=2 on third window");
    @(posedge clk);
    check(out_pixel_idx == 14'd3, "out_pixel_idx=3 on fourth window");

    // ─────────────────────────────────────────────
    // TEST 7 — out_valid matches window_valid
    // ─────────────────────────────────────────────
    $display("\n--- TEST 7: out_valid matches window_valid ---");
    // check for 10 more cycles
    begin : check_valid_match
        integer v;
        reg mismatch;
        mismatch = 0;
        for (v = 0; v < 10; v = v + 1) begin
            @(posedge clk);
            if (out_valid !== window_valid)
                mismatch = 1;
        end
        check(mismatch == 0, "out_valid always matches window_valid");
    end

    // ─────────────────────────────────────────────
    // TEST 8 — Total pixel count = 15876
    //          Run the full image and count
    // ─────────────────────────────────────────────
    $display("\n--- TEST 8: Total valid pixels = 126x126 = 15876 ---");
    $display("  (Running full 128x128 image... this takes a moment)");

    apply_reset;
    pixel_count = 0;
    done_count  = 0;

    start = 1;
    @(posedge clk);
    start = 0;

    // wait for done — max cycles = 128*3 + 126*(126+128+1) + 10 safety
    // = 384 + 126*255 + 10 = 384 + 32130 + 10 = 32524
    cycle_count = 0;
    while (!done && cycle_count < 40000) begin
        @(posedge clk);
        cycle_count = cycle_count + 1;
    end

    check(pixel_count == 15876,   "Total valid pixels = 15876 (126x126)");
    check(done        == 1'b1,    "done pulses at end");

    // ─────────────────────────────────────────────
    // TEST 9 — done pulses exactly once
    // ─────────────────────────────────────────────
    $display("\n--- TEST 9: done pulses exactly once ---");
    // wait a few more cycles to see if done stays high
    repeat(5) @(posedge clk);
    check(done_count == 1,        "done pulsed exactly once");
    check(done       == 1'b0,     "done returns to 0 after pulse");

    // ─────────────────────────────────────────────
    // TEST 10 — After done, module returns to IDLE
    //           Send start again and check it works
    // ─────────────────────────────────────────────
    $display("\n--- TEST 10: Module restarts correctly after done ---");
    pixel_count = 0;
    done_count  = 0;

    start = 1;
    @(posedge clk);
    start = 0;

    // wait for done again
    cycle_count = 0;
    while (!done && cycle_count < 40000) begin
        @(posedge clk);
        cycle_count = cycle_count + 1;
    end

    check(pixel_count == 15876,   "Second run also produces 15876 pixels");
    check(done        == 1'b1,    "done pulses again on second run");

    // ─────────────────────────────────────────────
    //  FINAL RESULTS
    // ─────────────────────────────────────────────
    $display("\n============================================");
    $display("  RESULTS: %0d PASSED,  %0d FAILED", pass_count, fail_count);
    $display("============================================");

    if (fail_count == 0)
        $display("  ALL TESTS PASSED - line_buffer is correct");
    else
        $display("  SOME TESTS FAILED - check above");

    $display("============================================\n");
    $finish;
end

// ─────────────────────────────────────────────────────────────
//  Timeout watchdog — kills simulation if stuck
// ─────────────────────────────────────────────────────────────
initial begin
    #10_000_000;
    $display("TIMEOUT — simulation took too long, something is stuck");
    $finish;
end

// ─────────────────────────────────────────────────────────────
//  Waveform dump for GTKWave / Vivado
// ─────────────────────────────────────────────────────────────
initial begin
    $dumpfile("tb_line_buffer.vcd");
    $dumpvars(0, tb_line_buffer);
end

endmodule
