`timescale 1ns / 1ps
// ============================================================
//  tb_conv_datapath.v
//  Author : Soumik Roy (Noob_Duck) — Group 18
//
//  Purpose:
//    Tests the COMPLETE datapath:
//    img_bram_in → line_buffer → conv_engine → img_bram_out
//
//  Tests:
//  TEST 1 — Identity kernel: output pixel = centre pixel (p11)
//  TEST 2 — Total output pixel count = 15876 (126×126)
//  TEST 3 — done pulses exactly once at end
//  TEST 4 — out_valid arrives 4 cycles after window_valid
//  TEST 5 — Zero kernel: all outputs = 0
//  TEST 6 — pixel_idx_out stored correctly in img_bram_out
//  TEST 7 — Second run works correctly after done
// ============================================================

module tb_conv_datapath;

// ─────────────────────────────────────────────────────────────
//  Clock and reset
// ─────────────────────────────────────────────────────────────
reg clk;
reg reset;    // active low
reg start;

// ─────────────────────────────────────────────────────────────
//  img_bram_in signals
// ─────────────────────────────────────────────────────────────
reg         bram_in_we;
reg  [13:0] bram_in_wr_addr;
reg  [ 7:0] bram_in_wr_data;
wire [13:0] bram_in_rd_addr;   // driven by line_buffer
wire [ 7:0] bram_in_rd_data;   // goes to line_buffer

// ─────────────────────────────────────────────────────────────
//  line_buffer signals
// ─────────────────────────────────────────────────────────────
wire [ 7:0] p00, p01, p02;
wire [ 7:0] p10, p11, p12;
wire [ 7:0] p20, p21, p22;
wire        window_valid;
wire [13:0] out_pixel_idx;
wire        out_valid;
wire        lb_done;

// ─────────────────────────────────────────────────────────────
//  kernel — hardwired for each test
// ─────────────────────────────────────────────────────────────
reg signed [7:0] k0, k1, k2;
reg signed [7:0] k3, k4, k5;
reg signed [7:0] k6, k7, k8;

// ─────────────────────────────────────────────────────────────
//  conv_engine output signals
// ─────────────────────────────────────────────────────────────
wire [ 7:0] pixel_out;
wire        ce_out_valid;
wire [13:0] pixel_idx_out;

// ─────────────────────────────────────────────────────────────
//  img_bram_out signals
// ─────────────────────────────────────────────────────────────
reg  [13:0] bram_out_rd_addr;
wire [ 7:0] bram_out_rd_data;

// ─────────────────────────────────────────────────────────────
//  Module instantiations
// ─────────────────────────────────────────────────────────────

img_bram_in bram_in_inst (
    .clk     (clk),
    .we      (bram_in_we),
    .wr_addr (bram_in_wr_addr),
    .wr_data (bram_in_wr_data),
    .rd_addr (bram_in_rd_addr),
    .rd_data (bram_in_rd_data)
);

line_buffer #(
    .IMG_W(128),
    .IMG_H(128)
) lb_inst (
    .clk          (clk),
    .reset        (reset),
    .start        (start),
    .done         (lb_done),
    .bram_rd_addr (bram_in_rd_addr),
    .bram_rd_data (bram_in_rd_data),
    .p00(p00), .p01(p01), .p02(p02),
    .p10(p10), .p11(p11), .p12(p12),
    .p20(p20), .p21(p21), .p22(p22),
    .window_valid (window_valid),
    .out_pixel_idx(out_pixel_idx),
    .out_valid    (out_valid)
);

conv_engine ce_inst (
    .clk          (clk),
    .rst          (reset),
    .p00(p00), .p01(p01), .p02(p02),
    .p10(p10), .p11(p11), .p12(p12),
    .p20(p20), .p21(p21), .p22(p22),
    .k0(k0), .k1(k1), .k2(k2),
    .k3(k3), .k4(k4), .k5(k5),
    .k6(k6), .k7(k7), .k8(k8),
    .window_valid (window_valid),
    .pixel_idx_in (out_pixel_idx),
    .pixel_out    (pixel_out),
    .out_valid    (ce_out_valid),
    .pixel_idx_out(pixel_idx_out)
);

img_bram_out bram_out_inst (
    .clk     (clk),
    .we      (ce_out_valid),
    .wr_addr (pixel_idx_out),
    .wr_data (pixel_out),
    .rd_addr (bram_out_rd_addr),
    .rd_data (bram_out_rd_data)
);

// ─────────────────────────────────────────────────────────────
//  Clock
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

task check;
    input condition;
    input [255:0] name;
    begin
        if (condition) begin
            $display("  PASS : %s", name);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL : %s", name);
            fail_count = fail_count + 1;
        end
    end
endtask

// ─────────────────────────────────────────────────────────────
//  Count output pixels and done pulses
// ─────────────────────────────────────────────────────────────
always @(posedge clk) begin
    if (ce_out_valid) pixel_count = pixel_count + 1;
    if (lb_done)      done_count  = done_count  + 1;
end

// ─────────────────────────────────────────────────────────────
//  Helper — apply reset
// ─────────────────────────────────────────────────────────────
task apply_reset;
    begin
        reset = 0;
        start = 0;
        @(posedge clk);
        @(posedge clk);
        reset = 1;
        @(posedge clk);
    end
endtask

// ─────────────────────────────────────────────────────────────
//  Helper — set identity kernel
//  0 0 0 / 0 1 0 / 0 0 0
//  output = p11 = centre pixel
// ─────────────────────────────────────────────────────────────
task set_kernel_identity;
    begin
        k0=0; k1=0; k2=0;
        k3=0; k4=1; k5=0;
        k6=0; k7=0; k8=0;
    end
endtask

// ─────────────────────────────────────────────────────────────
//  Helper — set zero kernel
// ─────────────────────────────────────────────────────────────
task set_kernel_zero;
    begin
        k0=0; k1=0; k2=0;
        k3=0; k4=0; k5=0;
        k6=0; k7=0; k8=0;
    end
endtask

// ─────────────────────────────────────────────────────────────
//  Helper — fill img_bram_in with known pattern
//  pixel value = address & 0xFF
// ─────────────────────────────────────────────────────────────
task fill_bram_in;
    integer i;
    begin
        $display("  Filling img_bram_in with known pattern...");
        for (i = 0; i < 16384; i = i + 1) begin
            bram_in_we      <= 1;
            bram_in_wr_addr <= i[13:0];
            bram_in_wr_data <= i[7:0];
            @(posedge clk);
        end
        bram_in_we <= 0;
        @(posedge clk);
        $display("  img_bram_in filled.");
    end
endtask

// ─────────────────────────────────────────────────────────────
//  Helper — run full image and wait for done
// ─────────────────────────────────────────────────────────────
task run_full_image;
    integer cycle_cnt;
    begin
        start = 1;
        @(posedge clk);
        start = 0;

        cycle_cnt = 0;
        while (!lb_done && cycle_cnt < 50000) begin
            @(posedge clk);
            cycle_cnt = cycle_cnt + 1;
        end
    end
endtask

// ─────────────────────────────────────────────────────────────
//  Helper — read from img_bram_out (1-cycle latency)
// ─────────────────────────────────────────────────────────────
task read_bram_out;
    input  [13:0] addr;
    output [ 7:0] data;
    begin
        bram_out_rd_addr <= addr;
        @(posedge clk);
        @(posedge clk);
        data = bram_out_rd_data;
    end
endtask

integer cycle_cnt;
reg [7:0] read_val;
reg [7:0] expected;

initial begin
    $display("============================================");
    $display("  tb_conv_datapath — Group 18 — Noob_Duck");
    $display("============================================");

    pass_count      = 0;
    fail_count      = 0;
    pixel_count     = 0;
    done_count      = 0;
    bram_in_we      = 0;
    bram_in_wr_addr = 0;
    bram_in_wr_data = 0;
    bram_out_rd_addr= 0;
    start           = 0;
    reset           = 1;

    // ─────────────────────────────────────────────
    // SETUP — fill img_bram_in with known values
    //         pixel(row,col) = (row*128+col) & 0xFF
    // ─────────────────────────────────────────────
    apply_reset;
    fill_bram_in;

    // ─────────────────────────────────────────────
    // TEST 1 — Identity kernel
    //          output pixel = centre pixel p11
    //          p11 for first window = row1_reg[1]
    //          = bram[1*128+1] = bram[129] = 129
    // ─────────────────────────────────────────────
    $display("\n--- TEST 1: Identity kernel output=p11 ---");
    apply_reset;
    set_kernel_identity;
    pixel_count = 0;
    done_count  = 0;

    run_full_image;

    // read first output pixel from img_bram_out
    // first valid pixel = row1,col1 = bram[129] = 129 & 0xFF = 129
    read_bram_out(14'd0, read_val);
    check(read_val == 8'd129, "First output pixel = 129 (p11 of first window)");

    // second output pixel = row1,col2 = bram[130] = 130
    read_bram_out(14'd1, read_val);
    check(read_val == 8'd130, "Second output pixel = 130");

    // 126th output pixel = row1,col126 = bram[254] = 254
    read_bram_out(14'd125, read_val);
    check(read_val == 8'd254, "126th output pixel = 254");

    // ─────────────────────────────────────────────
    // TEST 2 — Total pixel count = 15876
    // ─────────────────────────────────────────────
    $display("\n--- TEST 2: Total output pixels = 15876 ---");
    check(pixel_count == 15876, "Total output pixels = 15876 (126x126)");

    // ─────────────────────────────────────────────
    // TEST 3 — done pulses exactly once
    // ─────────────────────────────────────────────
    $display("\n--- TEST 3: done pulses exactly once ---");
    repeat(5) @(posedge clk);
    check(done_count == 1,    "done pulsed exactly once");
    check(lb_done    == 1'b0, "done returns to 0 after pulse");

    // ─────────────────────────────────────────────
    // TEST 4 — Zero kernel: all outputs = 0
    // ─────────────────────────────────────────────
    $display("\n--- TEST 4: Zero kernel all outputs = 0 ---");
    apply_reset;
    set_kernel_zero;
    pixel_count = 0;
    done_count  = 0;

    run_full_image;

    // check several output pixels — all should be 0
    read_bram_out(14'd0,   read_val);
    check(read_val == 8'd0, "Zero kernel: pixel 0 = 0");
    read_bram_out(14'd100, read_val);
    check(read_val == 8'd0, "Zero kernel: pixel 100 = 0");
    read_bram_out(14'd15875, read_val);
    check(read_val == 8'd0, "Zero kernel: pixel 15875 = 0");

    // ─────────────────────────────────────────────
    // TEST 5 — pixel_idx_out stored at correct
    //          address in img_bram_out
    //          idx 0 → addr 0
    //          idx 1 → addr 1
    // ─────────────────────────────────────────────
    $display("\n--- TEST 5: pixel_idx_out maps to correct address ---");
    apply_reset;
    set_kernel_identity;
    pixel_count = 0;
    done_count  = 0;

    run_full_image;

    // pixel at output idx 0 = row1,col1 = bram[129] = 129
    read_bram_out(14'd0, read_val);
    check(read_val == 8'd129, "idx 0 stored at bram_out addr 0");

    // pixel at output idx 126 = row2,col1 = bram[257] = 1
    // bram[257] = 257 & 0xFF = 1
    read_bram_out(14'd126, read_val);
    check(read_val == 8'd1, "idx 126 stored at bram_out addr 126");

    // ─────────────────────────────────────────────
    // TEST 6 — Second run works correctly
    // ─────────────────────────────────────────────
    $display("\n--- TEST 6: Second run works correctly ---");
    apply_reset;
    set_kernel_identity;
    pixel_count = 0;
    done_count  = 0;

    run_full_image;

    check(pixel_count == 15876, "Second run: 15876 pixels");
    check(done_count  == 1,     "Second run: done pulses once");

    read_bram_out(14'd0, read_val);
    check(read_val == 8'd129,   "Second run: first pixel still correct");

    // ─────────────────────────────────────────────
    //  RESULTS
    // ─────────────────────────────────────────────
    $display("\n============================================");
    $display("  RESULTS: %0d PASSED,  %0d FAILED",
             pass_count, fail_count);
    $display("============================================");
    if (fail_count == 0)
        $display("  ALL TESTS PASSED - full datapath correct");
    else
        $display("  SOME TESTS FAILED - check above");
    $display("============================================\n");
    $finish;
end

// ─────────────────────────────────────────────────────────────
//  Timeout — full image takes ~35000 cycles × 3 runs
// ─────────────────────────────────────────────────────────────
initial begin
    #50_000_000;
    $display("TIMEOUT — something is stuck");
    $finish;
end

initial begin
    $dumpfile("tb_conv_datapath.vcd");
    $dumpvars(0, tb_conv_datapath);
end

endmodule
