`timescale 1ns / 1ps
// ============================================================
// top_fpga.v (EXPLICIT 1 Hz TOGGLE CLOCK)
// ============================================================
 
module top_fpga #(
    parameter IMEMSIZE = 4096,
    parameter DMEMSIZE = 4096
)(
    input  wire clk,         // fast board clock (100 MHz)
    input  wire reset,       // N17 physical button
    output [15:0] led,       // PC visualizer
    input  wire uart_rx_pin, // UART RX from PC
    output wire uart_tx_pin  // UART TX to PC
);

    wire [31:0] pc_out;
    assign led = pc_out[15:0]; 

    // MASTER RESET INVERTER
    wire sys_resetn = ~reset; 
    
    // ========================================================
    // 25 MHz CLOCK DIVIDER 
    // 100 MHz input / 4 = 25 MHz. Toggle every 2 ticks.
    // ========================================================
    /* 
    // OLD 1 Hz DIVIDER (Commented out)
    reg [25:0] counter = 26'd0;
    reg clk_slow = 1'b0;

    always @(posedge clk) begin
        if (counter == 26'd49_999_999) begin
            counter  <= 26'd0;
            clk_slow <= ~clk_slow; // Toggle the clock
        end else begin
            counter  <= counter + 1;
        end
    end
    */

    reg [1:0] counter = 2'd0;
    reg clk_slow = 1'b0;

    always @(posedge clk) begin
        if (counter == 2'd1) begin
            counter  <= 2'd0;
            clk_slow <= ~clk_slow; // Toggle the clock
        end else begin
            counter  <= counter + 1;
        end
    end
    // ========================================================

    wire [31:0] mmio_raddr;
    // PIPE Γåö MEMORY WIRES
    wire [31:0] inst_mem_read_data;
    wire        inst_mem_is_valid = 1'b1;
    wire [31:0] dmem_read_data;
    wire        dmem_write_valid  = 1'b1;
    wire        dmem_read_valid   = 1'b1;
    wire        exception;

    wire        dmem_re, dmem_we;
    wire [31:0] dmem_raddr, dmem_waddr, dmem_wdata;
    wire [3:0]  dmem_wstrb;

    // ========================================================
    // BENCHMARK CYCLE COUNTER
    // Snoops DMEM write bus for the BENCHMARK_FLAG at 0x00000F00
    //   Write 0x11111111 ΓåÆ START counting
    //   Write 0x99999999 ΓåÆ STOP  counting (freeze value)
    // ========================================================
    reg         cycle_counting;
    reg  [31:0] cycle_counter;
    reg  [31:0] cycle_count_frozen;  // latched value sent via UART

    wire bench_hit = dmem_we && (dmem_waddr == 32'h00000F00);

    always @(posedge clk_slow or negedge sys_resetn) begin
        if (!sys_resetn) begin
            cycle_counting     <= 1'b0;
            cycle_counter      <= 32'd0;
            cycle_count_frozen <= 32'd0;
        end
        else begin
            // Detect start / stop markers
            if (bench_hit && dmem_wdata == 32'h11111111) begin
                cycle_counting <= 1'b1;
                cycle_counter  <= 32'd0;  // reset on start
            end
            else if (bench_hit && dmem_wdata == 32'h99999999) begin
                cycle_counting     <= 1'b0;
                cycle_count_frozen <= cycle_counter;  // freeze
            end

            // Free-running increment while active
            if (cycle_counting)
                cycle_counter <= cycle_counter + 32'd1;
        end
    end

    // PIPE Γåö MMIO WIRES
    wire        mmio_we;
    wire        mmio_re;
    wire [31:0] mmio_addr;
    wire [31:0] mmio_wdata;
    wire [31:0] mmio_rdata;

    // 1. PIPELINE CPU (Running on clk_slow)
    pipe DUT (
        .clk                (clk_slow),             
        .reset              (sys_resetn),
        .stall              (1'b0),
        .exception          (exception),
        .pc_out             (pc_out),
        .inst_mem_is_valid  (inst_mem_is_valid),
        .inst_mem_read_data (inst_mem_read_data),
        .dmem_read_valid    (dmem_read_valid),
        .dmem_write_valid   (dmem_write_valid),
        .dmem_read_data_temp(dmem_read_data),
        .dmem_re_o          (dmem_re),
        .dmem_raddr_o       (dmem_raddr),
        .dmem_we_o          (dmem_we),
        .dmem_waddr_o       (dmem_waddr),
        .dmem_wdata_o       (dmem_wdata),
        .dmem_wstrb_o       (dmem_wstrb),
        .mmio_write_enable  (mmio_we),
        .mmio_read_enable   (mmio_re),
        .mmio_write_address (mmio_addr),
        .mmio_write_data    (mmio_wdata),
        .mmio_read_data     (mmio_rdata),
        .mmio_read_address  (mmio_raddr)
    );
    
    // 2. INSTRUCTION MEMORY (Running on clk_slow)
    instr_mem IMEM (
        .clk    (clk),                    
        .pc     (pc_out),
        .instr  (inst_mem_read_data)
    );

    // 3. DATA MEMORY (Running on clk_slow)
    data_mem DMEM (
        .clk    (clk_slow),            
        .re     (dmem_re),
        .raddr  (dmem_raddr),
        .rdata  (dmem_read_data),
        .we     (dmem_we),
        .waddr  (dmem_waddr),
        .wdata  (dmem_wdata),
        .wstrb  (dmem_wstrb)
    );

    // 4. COPROCESSOR ISLAND & FSM (Running on clk_slow)
    top_fsm u_coprocessor_island (
        .clk        (clk_slow),
        .reset      (sys_resetn),
        .rx_pin     (uart_rx_pin), 
        .tx_pin     (uart_tx_pin), 
        .mem_write  (mmio_we),
        .mem_read   (mmio_re),
        .cpu_addr   (mmio_addr),
        .cpu_wdata  (mmio_wdata),
        .cpu_rdata  (mmio_rdata),
        .cpu_raddr  (mmio_raddr),
        .cycle_count(cycle_count_frozen)   // ΓåÉ benchmark cycle count
    );

endmodule
