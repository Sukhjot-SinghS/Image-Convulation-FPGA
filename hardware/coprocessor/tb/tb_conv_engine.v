`timescale 1ns / 1ps
// ============================================================
//  tb_conv_engine.v
//  Author : Soumik Roy (Noob_Duck) — Group 18
//
//  What this testbench checks:
//  TEST 1  — Reset behaviour
//  TEST 2  — Pipeline delay is exactly 3 cycles
//  TEST 3  — Identity kernel (output = centre pixel)
//  TEST 4  — All zeros kernel (output = 0)
//  TEST 5  — All pixels zero (output = 0)
//  TEST 6  — Normal Sobel-like result (positive, no clamp)
//  TEST 7  — Negative result clamps to 0
//  TEST 8  — Overflow result clamps to 255
//  TEST 9  — out_valid is 0 when window_valid is 0
//  TEST 10 — pixel_idx_out arrives exactly 3 cycles after idx_in
//  TEST 11 — Pipeline throughput: 1 pixel per cycle
//  TEST 12 — out_valid follows window_valid with 3 cycle delay
// ============================================================

module tb_conv_engine;

// ─────────────────────────────────────────────────────────────
//  DUT signals
// ─────────────────────────────────────────────────────────────
reg        clk;
reg        rst;

reg [7:0]  p00, p01, p02;
reg [7:0]  p10, p11, p12;
reg [7:0]  p20, p21, p22;

reg signed [7:0] k0, k1, k2;
reg signed [7:0] k3, k4, k5;
reg signed [7:0] k6, k7, k8;

reg        window_valid;
reg [13:0] pixel_idx_in;

wire [7:0]  pixel_out;
wire        out_valid;
wire [13:0] pixel_idx_out;

// ─────────────────────────────────────────────────────────────
//  DUT instantiation
// ─────────────────────────────────────────────────────────────
conv_engine dut (
    .clk          (clk),
    .rst          (rst),
    .p00(p00), .p01(p01), .p02(p02),
    .p10(p10), .p11(p11), .p12(p12),
    .p20(p20), .p21(p21), .p22(p22),
    .k0(k0), .k1(k1), .k2(k2),
    .k3(k3), .k4(k4), .k5(k5),
    .k6(k6), .k7(k7), .k8(k8),
    .norm_en      (1'b0),
    .window_valid (window_valid),
    .pixel_idx_in (pixel_idx_in),
    .pixel_out    (pixel_out),
    .out_valid    (out_valid),
    .pixel_idx_out(pixel_idx_out)
);

// ─────────────────────────────────────────────────────────────
//  Clock — 10ns period
// ─────────────────────────────────────────────────────────────
initial clk = 0;
always #5 clk = ~clk;

// ─────────────────────────────────────────────────────────────
//  Test tracking
// ─────────────────────────────────────────────────────────────
integer pass_count;
integer fail_count;

// ─────────────────────────────────────────────────────────────
//  Helper task — check and print
// ─────────────────────────────────────────────────────────────
task check;
    input condition;
    input [255:0] test_name;
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
//  Helper task — apply reset (active low)
// ─────────────────────────────────────────────────────────────
task apply_reset;
    begin
        rst = 0;          // assert reset (active low)
        window_valid = 0;
        pixel_idx_in = 0;
        set_pixels(0,0,0, 0,0,0, 0,0,0);
        set_kernel_identity;
        @(posedge clk);
        @(posedge clk);
        rst = 1;          // release reset
        @(posedge clk);
    end
endtask

// ─────────────────────────────────────────────────────────────
//  Helper task — set all 9 pixels at once
// ─────────────────────────────────────────────────────────────
task set_pixels;
    input [7:0] v00, v01, v02;
    input [7:0] v10, v11, v12;
    input [7:0] v20, v21, v22;
    begin
        p00=v00; p01=v01; p02=v02;
        p10=v10; p11=v11; p12=v12;
        p20=v20; p21=v21; p22=v22;
    end
endtask

// ─────────────────────────────────────────────────────────────
//  Helper task — set all 9 kernel values at once
// ─────────────────────────────────────────────────────────────
task set_kernel;
    input signed [7:0] v0, v1, v2;
    input signed [7:0] v3, v4, v5;
    input signed [7:0] v6, v7, v8;
    begin
        k0=v0; k1=v1; k2=v2;
        k3=v3; k4=v4; k5=v5;
        k6=v6; k7=v7; k8=v8;
    end
endtask

// ─────────────────────────────────────────────────────────────
//  Helper task — identity kernel
//  0 0 0
//  0 1 0   → output = centre pixel (p11)
//  0 0 0
// ─────────────────────────────────────────────────────────────
task set_kernel_identity;
    begin
        set_kernel(0,0,0, 0,1,0, 0,0,0);
    end
endtask

// ─────────────────────────────────────────────────────────────
//  Helper task — send one window and wait 3 cycles for result
// ─────────────────────────────────────────────────────────────
task send_window_and_wait;
    input [13:0] idx;
    begin
        pixel_idx_in = idx;
        window_valid = 1;
        @(posedge clk);
        window_valid = 0;
        pixel_idx_in = 0;
        // wait 3 cycles for pipeline
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
    end
endtask

// ─────────────────────────────────────────────────────────────
//  Helper function — compute expected result in software
//  returns clamped result 0..255
// ─────────────────────────────────────────────────────────────
function [7:0] expected_result;
    input [7:0] v00, v01, v02;
    input [7:0] v10, v11, v12;
    input [7:0] v20, v21, v22;
    input signed [7:0] c0, c1, c2;
    input signed [7:0] c3, c4, c5;
    input signed [7:0] c6, c7, c8;
    integer sum;
    begin
        sum = ($signed({1'b0,v00})*c0) + ($signed({1'b0,v01})*c1) + ($signed({1'b0,v02})*c2)
            + ($signed({1'b0,v10})*c3) + ($signed({1'b0,v11})*c4) + ($signed({1'b0,v12})*c5)
            + ($signed({1'b0,v20})*c6) + ($signed({1'b0,v21})*c7) + ($signed({1'b0,v22})*c8);
        if      (sum < 0)   expected_result = 8'd0;
        else if (sum > 255) expected_result = 8'd255;
        else                expected_result = sum[7:0];
    end
endfunction

// ─────────────────────────────────────────────────────────────
//  MAIN TEST SEQUENCE
// ─────────────────────────────────────────────────────────────
integer cycle_cnt;
integer mismatch;
integer v;

initial begin
    $display("============================================");
    $display("  tb_conv_engine — Group 18 — Noob_Duck");
    $display("============================================");

    pass_count   = 0;
    fail_count   = 0;
    window_valid = 0;
    pixel_idx_in = 0;
    rst          = 1;

    // ─────────────────────────────────────────────
    // TEST 1 — Reset behaviour
    // ─────────────────────────────────────────────
    $display("\n--- TEST 1: Reset behaviour ---");
    set_pixels(100,100,100, 100,100,100, 100,100,100);
    set_kernel_identity;

    rst = 0;   // assert reset
    @(posedge clk);
    @(posedge clk);
    check(out_valid    == 0,   "out_valid=0 during reset");
    check(pixel_out    == 0,   "pixel_out=0 during reset");
    check(pixel_idx_out== 0,   "pixel_idx_out=0 during reset");

    rst = 1;   // release reset
    @(posedge clk);
    check(out_valid    == 0,   "out_valid=0 after reset released");

    // ─────────────────────────────────────────────
    // TEST 2 — Pipeline delay is exactly 3 cycles
    //          Send window_valid=1 for 1 cycle
    //          Check out_valid appears exactly 3 cycles later
    // ─────────────────────────────────────────────
    $display("\n--- TEST 2: Pipeline delay = exactly 3 cycles ---");
    apply_reset;
    set_pixels(50,50,50, 50,50,50, 50,50,50);
    set_kernel_identity;

    // send one valid window
    window_valid = 1;
    @(posedge clk);
    window_valid = 0;

    // cycle 1 after input — should NOT be valid yet
    @(posedge clk);
    check(out_valid == 0, "out_valid=0 at cycle+1 (too early)");

    // cycle 2 after input
    @(posedge clk);
    check(out_valid == 0, "out_valid=0 at cycle+2 (too early)");

    // cycle 3 after input — NOW it should be valid
    @(posedge clk);
    check(out_valid == 1, "out_valid=1 at cycle+3 (exactly right)");

    // cycle 4 — should be gone (only 1 cycle pulse)
    @(posedge clk);
    check(out_valid == 0, "out_valid=0 at cycle+4 (pulse ended)");

    // ─────────────────────────────────────────────
    // TEST 3 — Identity kernel
    //          kernel = 0 0 0 / 0 1 0 / 0 0 0
    //          result must equal p11 exactly
    // ─────────────────────────────────────────────
    $display("\n--- TEST 3: Identity kernel (output = p11) ---");
    apply_reset;
    set_kernel_identity;

    // case A: p11 = 100
    set_pixels(10,20,30, 40,100,60, 70,80,90);
    send_window_and_wait(14'd0);
    check(out_valid  == 1,      "TEST3a: out_valid=1");
    check(pixel_out  == 8'd100, "TEST3a: pixel_out=100 (p11)");

    // case B: p11 = 0
    apply_reset;
    set_kernel_identity;
    set_pixels(50,60,70, 80,0,90, 100,110,120);
    send_window_and_wait(14'd0);
    check(pixel_out  == 8'd0,   "TEST3b: pixel_out=0 (p11=0)");

    // case C: p11 = 255
    apply_reset;
    set_kernel_identity;
    set_pixels(1,2,3, 4,255,6, 7,8,9);
    send_window_and_wait(14'd0);
    check(pixel_out  == 8'd255, "TEST3c: pixel_out=255 (p11=255)");

    // ─────────────────────────────────────────────
    // TEST 4 — All zeros kernel
    //          result must always be 0
    // ─────────────────────────────────────────────
    $display("\n--- TEST 4: All zeros kernel (output always 0) ---");
    apply_reset;
    set_kernel(0,0,0, 0,0,0, 0,0,0);
    set_pixels(200,200,200, 200,200,200, 200,200,200);
    send_window_and_wait(14'd0);
    check(out_valid == 1,    "TEST4: out_valid=1");
    check(pixel_out == 8'd0, "TEST4: pixel_out=0 (zero kernel)");

    // ─────────────────────────────────────────────
    // TEST 5 — All pixels zero
    //          result must always be 0
    // ─────────────────────────────────────────────
    $display("\n--- TEST 5: All pixels zero (output always 0) ---");
    apply_reset;
    set_kernel(1,2,3, 4,5,6, 7,8,9);
    set_pixels(0,0,0, 0,0,0, 0,0,0);
    send_window_and_wait(14'd0);
    check(out_valid == 1,    "TEST5: out_valid=1");
    check(pixel_out == 8'd0, "TEST5: pixel_out=0 (zero pixels)");

    // ─────────────────────────────────────────────
    // TEST 6 — Normal result (no clamping needed)
    //          Use simple known values
    //          pixels all = 10
    //          kernel all = 1
    //          result = 10*1 * 9 = 90 → no clamp needed
    // ─────────────────────────────────────────────
    $display("\n--- TEST 6: Normal result no clamping ---");
    apply_reset;
    set_kernel(1,1,1, 1,1,1, 1,1,1);
    set_pixels(10,10,10, 10,10,10, 10,10,10);
    send_window_and_wait(14'd5);
    check(out_valid  == 1,    "TEST6: out_valid=1");
    check(pixel_out  == 8'd90,"TEST6: pixel_out=90 (10x1x9=90)");

    // ─────────────────────────────────────────────
    // TEST 7 — Negative result clamps to 0
    //          Use Sobel-like kernel with negative values
    //          pixels = uniform 100
    //          kernel = -1 0 1 / -2 0 2 / -1 0 1  (Sobel X)
    //          result = 100*(-1+0+1-2+0+2-1+0+1) = 100*0 = 0
    //
    //          Better test: asymmetric pixels
    //          left col = 200, right col = 0, middle = 100
    //          Sobel X result will be very negative
    // ─────────────────────────────────────────────
    $display("\n--- TEST 7: Negative result clamps to 0 ---");
    apply_reset;
    // Sobel X kernel: -1 0 1 / -2 0 2 / -1 0 1
    set_kernel(-1, 0, 1,
               -2, 0, 2,
               -1, 0, 1);
    // left side bright, right side dark → negative Sobel X result
    set_pixels(200, 100, 0,
               200, 100, 0,
               200, 100, 0);
    // expected = (-1*200 + 0*100 + 1*0)
    //          + (-2*200 + 0*100 + 2*0)
    //          + (-1*200 + 0*100 + 1*0)
    //          = -200 + (-400) + (-200) = -800 → clamp to 0
    send_window_and_wait(14'd0);
    check(out_valid == 1,    "TEST7: out_valid=1");
    check(pixel_out == 8'd0, "TEST7: negative result clamped to 0");

    // ─────────────────────────────────────────────
    // TEST 8 — Overflow result clamps to 255
    //          pixels all = 255
    //          kernel all = 1
    //          result = 255 * 9 = 2295 → clamp to 255
    // ─────────────────────────────────────────────
    $display("\n--- TEST 8: Overflow result clamps to 255 ---");
    apply_reset;
    set_kernel(1,1,1, 1,1,1, 1,1,1);
    set_pixels(255,255,255, 255,255,255, 255,255,255);
    // 255 * 1 * 9 = 2295 > 255 → must clamp to 255
    send_window_and_wait(14'd0);
    check(out_valid == 1,      "TEST8: out_valid=1");
    check(pixel_out == 8'd255, "TEST8: overflow clamped to 255");

    // ─────────────────────────────────────────────
    // TEST 9 — out_valid=0 when window_valid=0
    //          Send window_valid=0 and check no output
    // ─────────────────────────────────────────────
    $display("\n--- TEST 9: out_valid=0 when window_valid=0 ---");
    apply_reset;
    set_kernel_identity;
    set_pixels(100,100,100, 100,100,100, 100,100,100);

    window_valid = 0;   // explicitly not valid
    pixel_idx_in = 14'd99;
    repeat(8) @(posedge clk);
    check(out_valid == 0, "TEST9: out_valid=0 when window_valid=0");

    // ─────────────────────────────────────────────
    // TEST 10 — pixel_idx_out arrives 4 cycles after pixel_idx_in
    // ─────────────────────────────────────────────
    $display("\n--- TEST 10: pixel_idx_out delayed by 3 cycles ---");
    apply_reset;
    set_kernel_identity;
    set_pixels(50,50,50, 50,50,50, 50,50,50);

    // send idx = 42
    pixel_idx_in = 14'd42;
    window_valid = 1;
    @(posedge clk);
    window_valid = 0;
    pixel_idx_in = 0;

    // wait 3 cycles
    @(posedge clk);
    @(posedge clk);
    @(posedge clk);
    check(pixel_idx_out == 14'd42, "TEST10: pixel_idx_out=42 after 3 cycles");

    // send idx = 1337
    apply_reset;
    set_kernel_identity;
    set_pixels(10,20,30, 40,50,60, 70,80,90);
    pixel_idx_in = 14'd1337;
    window_valid = 1;
    @(posedge clk);
    window_valid = 0;
    pixel_idx_in = 0;
    @(posedge clk);
    @(posedge clk);
    @(posedge clk);
    check(pixel_idx_out == 14'd1337, "TEST10: pixel_idx_out=1337 after 3 cycles");

    // ─────────────────────────────────────────────
    // TEST 11 — Pipeline throughput: 1 pixel per cycle
    //           Send 5 windows back to back
    //           Each with different p11 value
    //           Using identity kernel
    //           After 4 cycle delay, results come out 1 per cycle
    // ─────────────────────────────────────────────
    $display("\n--- TEST 11: Throughput 1 pixel per cycle ---");
    apply_reset;
    set_kernel_identity;

    // Send 5 windows in 5 consecutive cycles
    // window 0: p11=10, idx=0
    // window 1: p11=20, idx=1
    // window 2: p11=30, idx=2
    // window 3: p11=40, idx=3
    // window 4: p11=50, idx=4

    // window 0
    set_pixels(0,0,0, 0,10,0, 0,0,0);
    pixel_idx_in=14'd0; window_valid=1; @(posedge clk);

    // window 1
    set_pixels(0,0,0, 0,20,0, 0,0,0);
    pixel_idx_in=14'd1; @(posedge clk);

    // window 2
    set_pixels(0,0,0, 0,30,0, 0,0,0);
    pixel_idx_in=14'd2; @(posedge clk);

    // window 3
    set_pixels(0,0,0, 0,40,0, 0,0,0);
    pixel_idx_in=14'd3; @(posedge clk);

    // window 4
    set_pixels(0,0,0, 0,50,0, 0,0,0);
    pixel_idx_in=14'd4; @(posedge clk);

    window_valid=0;

    // wait for first result (3 cycles total from window 0)
    // already spent 5 cycles sending, so window 0 result
    // comes 3 cycles after its entry = cycle 3
    // we are currently at cycle 5, so results 0+1 already came.
    // Next result should be result 2.

    @(posedge clk);  // cycle 6 — result 2
    check(out_valid == 1,    "TEST11: result 2 valid");
    check(pixel_out == 8'd30,"TEST11: result 2 = 30");

    @(posedge clk);  // cycle 7 — result 3
    check(out_valid == 1,    "TEST11: result 3 valid");
    check(pixel_out == 8'd40,"TEST11: result 3 = 40");

    @(posedge clk);  // cycle 8 — result 4
    check(out_valid == 1,    "TEST11: result 4 valid");
    check(pixel_out == 8'd50,"TEST11: result 4 = 50");

    // ─────────────────────────────────────────────
    // TEST 12 — Gaussian blur kernel
    //           All same pixels = 128
    //           Gaussian kernel sums to 16
    //           result = 128 * 16 / 16 = 128
    //           (we use scaled version summing to 1 in integer)
    //           Flat image through any kernel = flat output
    //           Use kernel: 1 1 1 / 1 1 1 / 1 1 1 (box blur)
    //           pixels = 28 each
    //           result = 28*9 = 252 → no clamp
    // ─────────────────────────────────────────────
    $display("\n--- TEST 12: Box blur on flat image ---");
    apply_reset;
    set_kernel(1,1,1, 1,1,1, 1,1,1);
    set_pixels(28,28,28, 28,28,28, 28,28,28);
    send_window_and_wait(14'd0);
    check(out_valid == 1,      "TEST12: out_valid=1");
    check(pixel_out == 8'd252, "TEST12: 28*9=252 correct");

    // ─────────────────────────────────────────────
    //  FINAL RESULTS
    // ─────────────────────────────────────────────
    $display("\n============================================");
    $display("  RESULTS: %0d PASSED,  %0d FAILED", pass_count, fail_count);
    $display("============================================");

    if (fail_count == 0)
        $display("  ALL TESTS PASSED - conv_engine is correct");
    else
        $display("  SOME TESTS FAILED - check above");

    $display("============================================\n");
    $finish;
end

// ─────────────────────────────────────────────────────────────
//  Timeout watchdog
// ─────────────────────────────────────────────────────────────
initial begin
    #100_000;
    $display("TIMEOUT — simulation stuck");
    $finish;
end

// ─────────────────────────────────────────────────────────────
//  Waveform dump
// ─────────────────────────────────────────────────────────────
initial begin
    $dumpfile("tb_conv_engine.vcd");
    $dumpvars(0, tb_conv_engine);
end

endmodule
