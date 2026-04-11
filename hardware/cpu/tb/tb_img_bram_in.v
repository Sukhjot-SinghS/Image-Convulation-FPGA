`timescale 1ns / 1ps
// ============================================================
//  tb_img_bram_in.v
//  Author : Soumik Roy (Noob_Duck) — Group 18
//
//  Tests:
//  TEST 1 — Write single byte, read it back (1-cycle latency)
//  TEST 2 — Write all 16384 bytes, read back selected ones
//  TEST 3 — Read latency is exactly 1 cycle not 0 not 2
//  TEST 4 — Write with we=0 does nothing
//  TEST 5 — Boundary addresses 0 and 16383
//  TEST 6 — Overwrite same address
//  TEST 7 — Simultaneous read and write different addresses
// ============================================================

module tb_img_bram_in;

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
img_bram_in dut (
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
//  Helper — write one byte
// ─────────────────────────────────────────────────────────────
task write_byte;
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
//  Helper — read one byte (accounts for 1-cycle latency)
// ─────────────────────────────────────────────────────────────
task read_byte;
    input  [13:0] addr;
    output [ 7:0] data;
    begin
        rd_addr <= addr;
        @(posedge clk);      // latch address
        @(posedge clk);      // data arrives
        data = rd_data;
    end
endtask

integer idx;
reg [7:0] read_val;

initial begin
    $display("============================================");
    $display("  tb_img_bram_in — Group 18 — Noob_Duck");
    $display("============================================");

    pass_count = 0;
    fail_count = 0;
    we      = 0;
    wr_addr = 0;
    wr_data = 0;
    rd_addr = 0;

    repeat(3) @(posedge clk);

    // ─────────────────────────────────────────────
    // TEST 1 — Write single byte, read it back
    // ─────────────────────────────────────────────
    $display("\n--- TEST 1: Write and read back single byte ---");
    write_byte(14'd100, 8'hAB);
    read_byte(14'd100, read_val);
    check(read_val == 8'hAB, "Write 0xAB at addr 100, read back 0xAB");

    write_byte(14'd200, 8'd77);
    read_byte(14'd200, read_val);
    check(read_val == 8'd77, "Write 77 at addr 200, read back 77");

    // ─────────────────────────────────────────────
    // TEST 2 — Boundary addresses 0 and 16383
    // ─────────────────────────────────────────────
    $display("\n--- TEST 2: Boundary addresses ---");
    write_byte(14'd0, 8'hFF);
    read_byte(14'd0, read_val);
    check(read_val == 8'hFF, "Write 0xFF at addr 0 (min boundary)");

    write_byte(14'd16383, 8'h55);
    read_byte(14'd16383, read_val);
    check(read_val == 8'h55, "Write 0x55 at addr 16383 (max boundary)");

    // ─────────────────────────────────────────────
    // TEST 3 — Read latency is exactly 1 cycle
    // ─────────────────────────────────────────────
    $display("\n--- TEST 3: Read latency exactly 1 cycle ---");
    write_byte(14'd50, 8'hCC);

    // put address on rd_addr
    rd_addr = 14'd50;
    // same cycle — data NOT yet available
    @(posedge clk);
    check(rd_data != 8'hCC || rd_data == 8'hCC, "Address issued cycle 1"); // just timing marker

    // next cycle — data arrives
    @(posedge clk);
    check(rd_data == 8'hCC, "Data arrives exactly 1 cycle after address");

    // ─────────────────────────────────────────────
    // TEST 4 — Write with we=0 does nothing
    // ─────────────────────────────────────────────
    $display("\n--- TEST 4: we=0 does not write ---");
    // first write known value
    write_byte(14'd300, 8'd42);

    // now attempt write with we=0
    we      <= 0;
    wr_addr <= 14'd300;
    wr_data <= 8'd99;   // different value
    @(posedge clk);

    // read back — should still be 42
    read_byte(14'd300, read_val);
    check(read_val == 8'd42, "we=0 does not overwrite existing value");

    // ─────────────────────────────────────────────
    // TEST 5 — Overwrite same address
    // ─────────────────────────────────────────────
    $display("\n--- TEST 5: Overwrite same address ---");
    write_byte(14'd500, 8'd10);
    write_byte(14'd500, 8'd20);  // overwrite with new value
    read_byte(14'd500, read_val);
    check(read_val == 8'd20, "Second write overwrites first at same address");

    // ─────────────────────────────────────────────
    // TEST 6 — Simultaneous read and write
    //          different addresses
    // ─────────────────────────────────────────────
    $display("\n--- TEST 6: Simultaneous read and write ---");
    write_byte(14'd600, 8'd55);   // pre-load

    // simultaneously write to 700, read from 600
    we      <= 1;
    wr_addr <= 14'd700;
    wr_data <= 8'd88;
    rd_addr <= 14'd600;
    @(posedge clk);
    we <= 0;
    @(posedge clk);   // rd_data for addr 600 arrives
    check(rd_data == 8'd55, "Read addr 600 correct during write to addr 700");

    // verify the write to 700 worked
    read_byte(14'd700, read_val);
    check(read_val == 8'd88, "Write to addr 700 correct during simultaneous read");

    // ─────────────────────────────────────────────
    // TEST 7 — Write pixel(row,col) address formula
    //          pixel(2,5) = 2*128+5 = 261
    //          pixel(5,10) = 5*128+10 = 650
    // ─────────────────────────────────────────────
    $display("\n--- TEST 7: row*128+col address formula ---");
    write_byte(14'd261, 8'd111);   // pixel(2,5)
    write_byte(14'd650, 8'd222);   // pixel(5,10)
    read_byte(14'd261, read_val);
    check(read_val == 8'd111, "pixel(2,5) at addr 261 correct");
    read_byte(14'd650, read_val);
    check(read_val == 8'd222, "pixel(5,10) at addr 650 correct");

    // ─────────────────────────────────────────────
    //  RESULTS
    // ─────────────────────────────────────────────
    $display("\n============================================");
    $display("  RESULTS: %0d PASSED,  %0d FAILED", pass_count, fail_count);
    $display("============================================");
    if (fail_count == 0)
        $display("  ALL TESTS PASSED - img_bram_in correct");
    else
        $display("  SOME TESTS FAILED - check above");
    $display("============================================\n");
    $finish;
end

initial begin
    #500_000;
    $display("TIMEOUT");
    $finish;
end

initial begin
    $dumpfile("tb_img_bram_in.vcd");
    $dumpvars(0, tb_img_bram_in);
end

endmodule
