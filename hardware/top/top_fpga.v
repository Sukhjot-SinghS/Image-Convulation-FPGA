`timescale 1ns / 1ps

// ============================================================
// top_fpga.v
// Author: Group 18 (Integration)
// Purpose: Top-level FPGA module integrating CPU pipeline
//          and convolution accelerator system (FSM, BRAM, MMIO, kernel)
// ============================================================

module top_fpga #(
    parameter IMEMSIZE = 4096,
    parameter DMEMSIZE = 4096,
    parameter CLKS_PER_BIT = 87,    // UART baud divider
    parameter IMG_W = 128,
    parameter IMG_H = 128,
    parameter IMG_SIZE = 16384,     // 128*128
    parameter OUT_SIZE = 15876      // 126*126
)(
    input  wire        clk,       // board clock e.g. 100 MHz
    input  wire        reset,     // active-low reset
    input  wire        rx_pin,    // UART RX from PC
    output wire        tx_pin,    // UART TX to PC
    output wire [15:0] led        // optional debug LEDs
);

////////////////////////////////////////////////////////////
// Slow clock generation (for CPU simulation / LEDs)
// Toggle every 0.5 sec
////////////////////////////////////////////////////////////
reg [25:0] clk_cnt;
reg slow_clk;

always @(posedge clk or negedge reset) begin
    if (!reset) begin
        clk_cnt  <= 26'd0;
        slow_clk <= 1'b0;
    end else begin
        if (clk_cnt == 26'd49_999_999) begin
            clk_cnt  <= 26'd0;
            slow_clk <= ~slow_clk;
        end else begin
            clk_cnt <= clk_cnt + 1'b1;
        end
    end
end

////////////////////////////////////////////////////////////
// LED debug output (show lower 16 bits of PC)
////////////////////////////////////////////////////////////
wire [31:0] pc_out;
assign led = pc_out[15:0];

////////////////////////////////////////////////////////////
// CPU ↔ MEMORY INTERFACES
////////////////////////////////////////////////////////////
wire [31:0] inst_mem_read_data;
wire        inst_mem_is_valid = 1'b1;

wire [31:0] dmem_read_data;
wire        dmem_write_valid  = 1'b1;
wire        dmem_read_valid   = 1'b1;

wire        dmem_re, dmem_we;
wire [31:0] dmem_raddr, dmem_waddr, dmem_wdata, dmem_rdata;
wire [3:0]  dmem_wstrb;
wire        exception;

////////////////////////////////////////////////////////////
// ==================== CPU PIPELINE =======================
////////////////////////////////////////////////////////////
pipe DUT (
    .clk(slow_clk),
    .reset(reset),
    .stall(1'b0),
    .exception(exception),

    .inst_mem_is_valid(inst_mem_is_valid),
    .inst_mem_read_data(inst_mem_read_data),
    .pc_out(pc_out),

    .dmem_read_data_temp(dmem_read_data),
    .dmem_write_valid(dmem_write_valid),
    .dmem_read_valid(dmem_read_valid),

    .dmem_re_o    (dmem_re),
    .dmem_raddr_o (dmem_raddr),
    .dmem_we_o    (dmem_we),
    .dmem_waddr_o (dmem_waddr),
    .dmem_wdata_o (dmem_wdata),
    .dmem_wstrb_o (dmem_wstrb),
    .dmem_rdata_i (dmem_rdata)
);

////////////////////////////////////////////////////////////
// ==================== INSTRUCTION MEMORY =================
////////////////////////////////////////////////////////////
instr_mem #(
    .IMEMSIZE(IMEMSIZE)
) IMEM (
    .clk(clk),
    .pc(pc_out),
    .instr(inst_mem_read_data)
);

////////////////////////////////////////////////////////////
// ==================== DATA MEMORY ========================
////////////////////////////////////////////////////////////
data_mem #(
    .DMEMSIZE(DMEMSIZE)
) DMEM (
    .clk(clk),
    .re(dmem_re),
    .raddr(dmem_raddr),
    .rdata(dmem_read_data),
    .we(dmem_we),
    .waddr(dmem_waddr),
    .wdata(dmem_wdata),
    .wstrb(dmem_wstrb)
);

////////////////////////////////////////////////////////////
// ==================== CONVOLUTION ACCELERATOR =============
////////////////////////////////////////////////////////////
// FSM + BRAM + line buffer + conv_engine + kernel + MMIO
////////////////////////////////////////////////////////////

// MMIO decoder wires
wire        mem_write  = dmem_we;      // CPU write
wire        mem_read   = dmem_re;      // CPU read
wire [31:0] cpu_addr   = dmem_waddr;   // CPU address
wire [31:0] cpu_wdata  = dmem_wdata;
wire [31:0] cpu_rdata;                 // read result from MMIO

// Kernel regfile wires
wire        kernel_we;
wire [3:0]  kernel_addr;
wire [31:0] kernel_wdata;
wire signed [7:0] k0,k1,k2,k3,k4,k5,k6,k7,k8;

// FSM wires
wire        lb_start;
wire        lb_done;

// BRAM in/out wires
wire [13:0] bram_in_rd_addr;
wire [7:0]  bram_in_rd_data;
reg  [13:0] bram_out_rd_addr;
wire [7:0]  bram_out_rd_data;

////////////////////////////////////////////////////////////
// Top FSM instance
////////////////////////////////////////////////////////////
top_fsm #(
    .CLKS_PER_BIT(CLKS_PER_BIT),
    .IMG_W(IMG_W),
    .IMG_H(IMG_H),
    .IMG_SIZE(IMG_SIZE),
    .OUT_SIZE(OUT_SIZE)
) fsm_inst (
    .clk(clk),
    .reset(reset),
    .rx_pin(rx_pin),
    .tx_pin(tx_pin),

    // CPU interface
    .mem_write(mem_write),
    .mem_read(mem_read),
    .cpu_addr(cpu_addr),
    .cpu_wdata(cpu_wdata),
    .cpu_rdata(cpu_rdata)
);

////////////////////////////////////////////////////////////
// Kernel register file
////////////////////////////////////////////////////////////
kernel_regfile krf_inst (
    .clk(clk),
    .rst(reset),
    .we(kernel_we),
    .addr(kernel_addr),
    .wdata(kernel_wdata),
    .k0(k0), .k1(k1), .k2(k2),
    .k3(k3), .k4(k4), .k5(k5),
    .k6(k6), .k7(k7), .k8(k8)
);

////////////////////////////////////////////////////////////
// MMIO Decoder
////////////////////////////////////////////////////////////
mmio_decoder mmio_inst (
    .clk(clk),
    .rst(reset),
    .mem_write(mem_write),
    .mem_read(mem_read),
    .addr(cpu_addr),
    .wdata(cpu_wdata),
    .rdata(cpu_rdata),
    .kernel_we(kernel_we),
    .kernel_addr(kernel_addr),
    .kernel_wdata(kernel_wdata),
    .start(lb_start),
    .done(lb_done)
);

endmodule
