`timescale 1ns / 1ps
// ============================================================
// top_fpga.v
// ============================================================

module top_fpga #(
    parameter IMEMSIZE = 4096,
    parameter DMEMSIZE = 4096
)(
    input  wire clk,         // fast board clock (100 MHz)
    input  wire reset,       // N17 physical button (Active-High)
    output [15:0] led,       // PC visualizer
    input  wire uart_rx_pin, // UART RX from PC
    output wire uart_tx_pin  // UART TX to PC
);

    wire [31:0] pc_out;
    assign led = pc_out[15:0]; 

    // MASTER RESET INVERTER
    wire sys_resetn = ~reset; 
    
    reg [1:0] clk_div = 2'b00;
    always @(posedge clk) begin
        clk_div <= clk_div + 1;
    end
    wire clk_25mhz = clk_div[1];

    // PIPE ↔ MEMORY WIRES
    wire [31:0] inst_mem_read_data;
    wire        inst_mem_is_valid = 1'b1;
    wire [31:0] dmem_read_data;
    wire        dmem_write_valid  = 1'b1;
    wire        dmem_read_valid   = 1'b1;
    wire        exception;

    wire        dmem_re, dmem_we;
    wire [31:0] dmem_raddr, dmem_waddr, dmem_wdata;
    wire [3:0]  dmem_wstrb;

    // PIPE ↔ MMIO WIRES
    wire        mmio_we;
    wire        mmio_re;
    wire [31:0] mmio_addr;
    wire [31:0] mmio_wdata;
    wire [31:0] mmio_rdata;

    // 1. PIPELINE CPU
    pipe DUT (
        .clk                (clk_25mhz),             
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
        .mmio_read_data     (mmio_rdata)
    );
    
    // 2. INSTRUCTION MEMORY
    instr_mem IMEM (
        .clk    (clk_25mhz),                    
        .pc     (pc_out),
        .instr  (inst_mem_read_data)
    );

    // 3. DATA MEMORY 
    data_mem DMEM (
        .clk    (clk_25mhz),            
        .re     (dmem_re),
        .raddr  (dmem_raddr),
        .rdata  (dmem_read_data),
        .we     (dmem_we),
        .waddr  (dmem_waddr),
        .wdata  (dmem_wdata),
        .wstrb  (dmem_wstrb)
    );

    // 4. COPROCESSOR ISLAND & FSM
    top_fsm u_coprocessor_island (
        .clk        (clk_25mhz),
        .reset      (sys_resetn),
        .rx_pin     (uart_rx_pin), 
        .tx_pin     (uart_tx_pin), 
        .mem_write  (mmio_we),
        .mem_read   (mmio_re),
        .cpu_addr   (mmio_addr),
        .cpu_wdata  (mmio_wdata),
        .cpu_rdata  (mmio_rdata)
    );

endmodule