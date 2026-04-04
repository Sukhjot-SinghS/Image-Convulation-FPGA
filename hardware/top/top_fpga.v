`timescale 1ns / 1ps

module top_fpga #(
    parameter IMEMSIZE = 4096,
    parameter DMEMSIZE = 4096
)(
    input  wire clk,        // fast board clock (e.g. 100 MHz)
    input  wire reset,      // active-low reset
    output [15:0] led       // PC visualizer
	input  wire uart_rx_pin, // UART RX from PC
    output wire uart_tx_pin
);

    wire [31:0] pc_out;

    // CLEAN LED ASSIGNMENT: Direct wire to the PC output so synthesis doesn't complain
    assign led = pc_out[15:0]; 

    // ========================================================
    // SLOW CLOCK GENERATOR (1 Hz)
    // ========================================================


    reg [25:0] clk_cnt;     // enough for 50 million
    reg        slow_clk;

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            clk_cnt  <= 26'd0;
            slow_clk <= 1'b0;
        end else begin
            if (clk_cnt == 26'd49_999_999) begin
                clk_cnt  <= 26'd0;
                slow_clk <= ~slow_clk;   // toggle every 0.5 sec
            end else begin
                clk_cnt <= clk_cnt + 1'b1;
            end
        end
    end

    // ========================================================
    // PIPE ↔ MEMORY WIRES
    // ========================================================
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
    // NEW: PIPE ↔ SATISH'S MMIO WIRES
    // ========================================================
    wire        mmio_we;
    wire        mmio_re;
    wire [31:0] mmio_addr;
    wire [31:0] mmio_wdata;
    wire [31:0] mmio_rdata;


    // ========================================================
    // 1. PIPELINE CPU
    // ========================================================
    pipe DUT (
        .clk(slow_clk),              // Running on slow clock
        .reset(reset),
        .stall(1'b0),
        .exception(exception),
        .pc_out(pc_out),

        // Instruction Memory
        .inst_mem_is_valid(inst_mem_is_valid),
        .inst_mem_read_data(inst_mem_read_data),

        // Data Memory (RAM)
        .dmem_read_valid(dmem_read_valid),
        .dmem_write_valid(dmem_write_valid),
        .dmem_read_data_temp(dmem_read_data),
        .dmem_re_o    (dmem_re),
        .dmem_raddr_o (dmem_raddr),
        .dmem_we_o    (dmem_we),
        .dmem_waddr_o (dmem_waddr),
        .dmem_wdata_o (dmem_wdata),
        .dmem_wstrb_o (dmem_wstrb),

        // MMIO Bridge (Satish)
        .mmio_write_enable  (mmio_we),
        .mmio_read_enable   (mmio_re),
        .mmio_write_address (mmio_addr),
        .mmio_write_data    (mmio_wdata),
        .mmio_read_data     (mmio_rdata)
    );

    // ========================================================
    // 2. INSTRUCTION MEMORY
    // ========================================================
    instr_mem IMEM (
        .clk(clk),                   // Your original used fast clk here
        .pc(pc_out),
        .instr(inst_mem_read_data)
    );

    // ========================================================
    // 3. DATA MEMORY 
    // ========================================================
    data_mem DMEM (
        .clk   (slow_clk),           // Running on slow clock
        .re    (dmem_re),
        .raddr (dmem_raddr),
        .rdata (dmem_read_data),
        .we    (dmem_we),
        .waddr (dmem_waddr),
        .wdata (dmem_wdata),
        .wstrb (dmem_wstrb)
    );

    

	top_fsm u_coprocessor_island (
        .clk        (slow_clk),
        .reset      (reset),
        
        // Physical UART Pins (Route these to the actual FPGA pins)
        .rx_pin     (uart_rx_pin), // You need to add this to top_fpga inputs
        .tx_pin     (uart_tx_pin), // You need to add this to top_fpga outputs

        // The 5 Wires from your CPU (Sukhjot -> Satish Mediator)
        .mem_write  (mmio_we),
        .mem_read   (mmio_re),
        .cpu_addr   (mmio_addr),
        .cpu_wdata  (mmio_wdata),
        .cpu_rdata  (mmio_rdata)
    );

endmodule