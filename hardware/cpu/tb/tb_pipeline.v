`timescale 1ns / 1ps

module tb_pipeline;

////////////////////////////////////////////////////////////
// CLOCK & RESET
////////////////////////////////////////////////////////////
reg clk;
reg reset;

// 100 MHz clock
initial begin
    clk = 0; 
    $dumpfile("../../pipeline.vcd"); // fixed path for standard simulation
    $dumpvars(0, tb_pipeline);
    forever #5 clk = ~clk;
end

// reset (active low in our CPU)
initial begin
    reset = 0;
   #10;
    reset = 1;
end

////////////////////////////////////////////////////////////
// PIPE ↔ MEMORY SIGNALS
////////////////////////////////////////////////////////////
wire [31:0] inst_mem_read_data;
wire        inst_mem_is_valid;

wire [31:0] dmem_read_data;
wire        dmem_write_valid;
wire        dmem_read_valid;

assign inst_mem_is_valid = 1'b1;
assign dmem_write_valid  = 1'b1;
assign dmem_read_valid   = 1'b1;

wire exception;
wire [31:0] pc_out; // added

wire        dmem_re, dmem_we;
wire [31:0] dmem_raddr, dmem_waddr, dmem_wdata;
wire [3:0]  dmem_wstrb;

////////////////////////////////////////////////////////////
// DUMMY MMIO SIGNALS (CRITICAL TO PREVENT 'X')
////////////////////////////////////////////////////////////
wire        mmio_we;
wire        mmio_re;
wire [31:0] mmio_addr;
wire [31:0] mmio_wdata;
wire [31:0] mmio_raddr;
wire [31:0] mmio_rdata = 32'd0; // Ties floating wire to 0!

////////////////////////////////////////////////////////////
// DUT : PIPELINE CPU
////////////////////////////////////////////////////////////
pipe DUT (
    .clk(clk),
    .reset(reset),
    .stall(1'b0),
    .exception(exception),

    .inst_mem_is_valid(inst_mem_is_valid),
    .inst_mem_read_data(inst_mem_read_data),

    .dmem_read_data_temp(dmem_read_data),
    .dmem_write_valid(dmem_write_valid),
    .dmem_read_valid(dmem_read_valid),

    .pc_out(pc_out),
    .dmem_re_o    (dmem_re),
    .dmem_raddr_o (dmem_raddr),
    .dmem_we_o    (dmem_we),
    .dmem_waddr_o (dmem_waddr),
    .dmem_wdata_o (dmem_wdata),
    .dmem_wstrb_o (dmem_wstrb),
    
    // NEW MMIO PORTS PLUGGED IN
    .mmio_write_enable  (mmio_we),
    .mmio_read_enable   (mmio_re),
    .mmio_write_address (mmio_addr),
    .mmio_write_data    (mmio_wdata),
    .mmio_read_data     (mmio_rdata),
    .mmio_read_address  (mmio_raddr)
);

////////////////////////////////////////////////////////////
// INSTRUCTION MEMORY  
////////////////////////////////////////////////////////////
instr_mem IMEM (
    .clk(clk),
    .pc(pc_out),
    .instr(inst_mem_read_data)
);

////////////////////////////////////////////////////////////
// DATA MEMORY 
////////////////////////////////////////////////////////////
data_mem DMEM (
    .clk(clk),
    .rdata (dmem_read_data),
    .re    (dmem_re),
    .raddr (dmem_raddr),
    .we    (dmem_we),
    .waddr (dmem_waddr),
    .wdata (dmem_wdata),
    .wstrb (dmem_wstrb)
);

////////////////////////////////////////////////////////////
// RAM INITIALIZER (KILLS THE X VIRUS)
////////////////////////////////////////////////////////////


////////////////////////////////////////////////////////////
// SIMULATION TIME & LOGGING
////////////////////////////////////////////////////////////
always @(posedge clk ) begin 
    // Left your exact display statement intact
    $display("time: %0d, next_pc = %h,pc = %h result = %0d,busy  = %b", $time,DUT.next_pc ,DUT.pc ,$signed(DUT.execute.ex_result),DUT.execute.alu_busy_o);
end

initial begin
    #5000;   
    $finish;
end

endmodule