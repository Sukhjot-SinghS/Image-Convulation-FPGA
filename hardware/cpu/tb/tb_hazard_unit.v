`timescale 1ns / 1ps

module tb_hazard_unit;

    // -----------------------------------------------------------------------
    // Testbench Signals
    // -----------------------------------------------------------------------
    reg  external_stall;
    reg  alu_busy;
    wire combined_stall;

    // -----------------------------------------------------------------------
    // Instantiate the Unit Under Test (UUT)
    // -----------------------------------------------------------------------
    hazard_unit DUT (
        .external_stall(external_stall),
        .alu_busy(alu_busy),
        .combined_stall(combined_stall)
    );

    // -----------------------------------------------------------------------
    // Main Test Sequence
    // -----------------------------------------------------------------------
    initial begin
        // Setup Waveform Dumping
        $dumpfile("tb_hazard_unit.vcd");
        $dumpvars(0, tb_hazard_unit);

        $display("=================================================");
        $display("          Hazard Unit Unit Test");
        $display("=================================================");
        $display(" Ext_Stall | ALU_Busy || Combined_Stall | Status");
        $display("-------------------------------------------------");

        // Test 1: Normal Operation (No stalls)
        external_stall = 0; alu_busy = 0; 
        #10; // Wait for logic to settle
        $display("     %b     |    %b     ||       %b        | %s", 
                 external_stall, alu_busy, combined_stall, 
                 (combined_stall === 1'b0) ? "PASS" : "FAIL");

        // Test 2: Hardware Math Running (ALU busy, e.g., DIV instruction)
        external_stall = 0; alu_busy = 1; 
        #10;
        $display("     %b     |    %b     ||       %b        | %s", 
                 external_stall, alu_busy, combined_stall, 
                 (combined_stall === 1'b1) ? "PASS" : "FAIL");

        // Test 3: External System Stall (e.g., Memory is slow)
        external_stall = 1; alu_busy = 0; 
        #10;
        $display("     %b     |    %b     ||       %b        | %s", 
                 external_stall, alu_busy, combined_stall, 
                 (combined_stall === 1'b1) ? "PASS" : "FAIL");

        // Test 4: Maximum Chaos (Both stalls triggered simultaneously)
        external_stall = 1; alu_busy = 1; 
        #10;
        $display("     %b     |    %b     ||       %b        | %s", 
                 external_stall, alu_busy, combined_stall, 
                 (combined_stall === 1'b1) ? "PASS" : "FAIL");

        $display("=================================================");
        $display("Simulation Complete.");
        $finish;
    end

endmodule