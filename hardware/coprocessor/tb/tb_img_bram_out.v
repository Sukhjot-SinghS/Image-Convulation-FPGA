`timescale 1ns / 1ps
// ============================================================
//  tb_img_bram_out.v
//  Author : Soumik Roy (Noob_Duck) — Group 18
//
//  Tests:
//  TEST 1 — Write single pixel, read it back
//  TEST 2 — Boundary addresses 0 and 15875
//  TEST 3 — Read latency exactly 1 cycle
//  TEST 4 — we=0 does not write
//  TEST 5 — Overwrite same address
//  TEST 6 — Write all 15876 pixels, spot check several
//  TEST 7 — Simultaneous read and write
// ============================================================

module tb_img_bram_out;

// ─────────────────────────────────────────────────────────────
//  DUT signals
// ─────────────────────────────────────────────────────────────
reg         clk;
reg         we;
reg  [13:0] wr_addr;
reg  [ 7:0] wr_data;
reg  [13:0] rd_addr;
wire [ 7:0] rd_data;

// ─────────────────────────────────────────────────────────────
//  DUT instantiation
// ─────────────────────────────────────────────────────────────
img_bram_out dut (
    .clk     (clk),
    .we      (we),
    .wr_addr (wr_addr),
    .wr_data (wr_data),
    .rd_addr (rd_addr),
    .rd_data (rd_data)
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
//  Helper — write one pixel
// ─────────────────────────────────────────────────────────────
task write_pixel;
    input [13:0] addr;
    input [ 7:0] data;
    begin
        we      <= 1;
        wr_addr <= addr;
        wr_data <= data;
        @(posedge clk);
        we <= 0;
    end
endtask

// ─────────────────────────────────────────────────────────────
//  Helper — read one pixel (1-cycle latency)
// ─────────────────────────────────────────────────────────────
task read_pixel;
    input  [13:0] addr;
    output [ 7:0] data;
    begin
        rd_addr <= addr;
        @(posedge clk);
        @(posedge clk);
        data = rd_data;
    end
endtask

integer idx;
integer mismatch;
reg [7:0] read_val;

initial begin
    $display("============================================");
    $display("  tb_img_bram_out — Group 18 — Noob_Duck");
    $display("============================================");

    pass_count = 0;
    fail_count = 0;
    we      = 0;
    wr_addr = 0;
    wr_data = 0;
    rd_addr = 0;

    repeat(3) @(posedge clk);

    // ─────────────────────────────────────────────
    // TEST 1 — Write single pixel, read back
    // ─────────────────────────────────────────────
    $display("\n--- TEST 1: Write and read back single pixel ---");
    write_pixel(14'd0, 8'd128);
    read_pixel(14'd0, read_val);
    check(read_val == 8'd128, "Write 128 at addr 0, read back 128");

    write_pixel(14'd100, 8'd255);
    read_pixel(14'd100, read_val);
    check(read_val == 8'd255, "Write 255 at addr 100, read back 255");

    // ─────────────────────────────────────────────
    // TEST 2 — Boundary addresses
    //          addr 0 = first output pixel
    //          addr 15875 = last output pixel
    // ─────────────────────────────────────────────
    $display("\n--- TEST 2: Boundary addresses ---");
    write_pixel(14'd0, 8'hAA);
    read_pixel(14'd0, read_val);
    check(read_val == 8'hAA, "First output pixel addr 0 correct");

    write_pixel(14'd15875, 8'hBB);
    read_pixel(14'd15875, read_val);
    check(read_val == 8'hBB, "Last output pixel addr 15875 correct");

    // ─────────────────────────────────────────────
    // TEST 3 — Read latency exactly 1 cycle
    // ─────────────────────────────────────────────
    $display("\n--- TEST 3: Read latency exactly 1 cycle ---");
    write_pixel(14'd200, 8'hCC);
    rd_addr = 14'd200;
    @(posedge clk);          // address issued
    @(posedge clk);          // data arrives
    check(rd_data == 8'hCC,  "Data arrives exactly 1 cycle after address");

    // ─────────────────────────────────────────────
    // TEST 4 — we=0 does not write
    // ─────────────────────────────────────────────
    $display("\n--- TEST 4: we=0 does not write ---");
    write_pixel(14'd300, 8'd50);

    we      <= 0;
    wr_addr <= 14'd300;
    wr_data <= 8'd99;
    @(posedge clk);

    read_pixel(14'd300, read_val);
    check(read_val == 8'd50, "we=0 does not overwrite existing value");

    // ─────────────────────────────────────────────
    // TEST 5 — Overwrite same address
    // ─────────────────────────────────────────────
    $display("\n--- TEST 5: Overwrite same address ---");
    write_pixel(14'd400, 8'd10);
    write_pixel(14'd400, 8'd20);
    read_pixel(14'd400, read_val);
    check(read_val == 8'd20, "Second write overwrites first correctly");

    // ─────────────────────────────────────────────
    // TEST 6 — Write all 15876 output pixels
    //          value = idx & 0xFF
    //          spot check 5 addresses
    // ─────────────────────────────────────────────
    $display("\n--- TEST 6: Write all 15876 pixels, spot check ---");
    $display("  (Writing all pixels... moment)");

    for (idx = 0; idx < 15876; idx = idx + 1) begin
        we      <= 1;
        wr_addr <= idx[13:0];
        wr_data <= idx[7:0];
        @(posedge clk);
    end
    we <= 0;
    @(posedge clk);

    // spot check 5 addresses
    read_pixel(14'd0, read_val);
    check(read_val == 8'd0,   "Spot check addr 0 = 0");

    read_pixel(14'd255, read_val);
    check(read_val == 8'd255, "Spot check addr 255 = 255");

    read_pixel(14'd256, read_val);
    check(read_val == 8'd0,   "Spot check addr 256 = 0 (256 & 0xFF)");

    read_pixel(14'd1000, read_val);
    check(read_val == 8'd232, "Spot check addr 1000 = 232 (1000 & 0xFF)");

    read_pixel(14'd15875, read_val);
    check(read_val == 8'd3,   "Spot check addr 15875 = 3 (15875 & 0xFF)");

    // ─────────────────────────────────────────────
    // TEST 7 — Simultaneous read and write
    //          different addresses
    // ─────────────────────────────────────────────
    $display("\n--- TEST 7: Simultaneous read and write ---");
    write_pixel(14'd500, 8'd77);

    we      <= 1;
    wr_addr <= 14'd600;
    wr_data <= 8'd88;
    rd_addr <= 14'd500;
    @(posedge clk);
    we <= 0;
    @(posedge clk);
    check(rd_data == 8'd77, "Read addr 500 correct during write to 600");

    read_pixel(14'd600, read_val);
    check(read_val == 8'd88, "Write to 600 correct during simultaneous read");

    // ─────────────────────────────────────────────
    //  RESULTS
    // ─────────────────────────────────────────────
    $display("\n============================================");
    $display("  RESULTS: %0d PASSED,  %0d FAILED", pass_count, fail_count);
    $display("============================================");
    if (fail_count == 0)
        $display("  ALL TESTS PASSED - img_bram_out correct");
    else
        $display("  SOME TESTS FAILED - check above");
    $display("============================================\n");
    $finish;
end

initial begin
    #5_000_000;
    $display("TIMEOUT");
    $finish;
end

initial begin
    $dumpfile("tb_img_bram_out.vcd");
    $dumpvars(0, tb_img_bram_out);
end

endmodule
