`timescale 1ns / 1ps

module mmio_decoder (
    input  wire        clk,
    input  wire        reset,        

    // CPU Interface (Split read/write addresses!)
    input  wire [31:0] waddr,
    input  wire [31:0] raddr,

    input  wire [31:0] wdata,
    input  wire        mem_write,
    input  wire        mem_read,
    
    output reg  [31:0] rdata,

    // Kernel Regfile Interface
    output reg         kernel_we,
    output reg  [3:0]  kernel_index,
    output reg  [31:0] kernel_wdata,

    // Control Signals
    output reg         start,
    output reg         sw_done,      // Software Doorbell!
    input  wire        done_in,
    input  wire        img_ready     // Tells CPU image is fully loaded via UART
);

localparam KERNEL_BASE  = 32'h80000000;
localparam START_ADDR   = 32'h80000024;
localparam STATUS_ADDR  = 32'h80000028;
localparam NORM_ADDR    = 32'h80000030;
localparam SW_DONE_ADDR = 32'h80000034; 
localparam IMG_READY_ADDR = 32'h80000038;

reg done_reg;

// Combinatorial detection of CPU writing HW_CMD_START=1
// Used to clear done_reg in the SAME cycle as the write, not 1 cycle later.
// This eliminates the race window where a stale done=1 could be read.
wire cpu_start_detected = mem_write && waddr == START_ADDR && wdata[0];

always @(posedge clk) begin
    if (!reset) begin
        start        <= 0;
        sw_done      <= 0;
        kernel_we    <= 0;
        done_reg     <= 0;
        kernel_index <= 0;
        kernel_wdata <= 0;
        rdata        <= 32'd0; // Initialize read data
    end 
    else begin
        // Default to 0 so they pulse for exactly 1 cycle
        kernel_we <= 0;
        start     <= 0;
        sw_done   <= 0; 

        // ==========================================
        // 1. WRITE LOGIC (Uses 'waddr')
        // ==========================================
        
        // Hardware Coprocessor Start
        if (cpu_start_detected)
            start <= 1;
            
        // Software Mode Done Doorbell
        if (mem_write && waddr == SW_DONE_ADDR && wdata[0])
            sw_done <= 1;

        // Kernel Coefficient Writes
        if (mem_write && waddr >= KERNEL_BASE && waddr < KERNEL_BASE + 36) begin
            kernel_we    <= 1;
            kernel_index <= (waddr - KERNEL_BASE) >> 2;
            kernel_wdata <= wdata;
        end

        // Normalization Toggle Write
        if (mem_write && waddr == NORM_ADDR) begin
            kernel_we    <= 1;
            kernel_index <= 4'd10;
            kernel_wdata <= wdata;
        end

        // Hardware Done Latch
        // FIX: Clear done_reg on EITHER the combinatorial write detection (same cycle)
        // OR on the registered start (next cycle). The double guard ensures done_reg
        // is 0 before the CPU's first poll, which arrives ~4+ cycles after the write.
        if (cpu_start_detected || start)
            done_reg <=0;
        else if (done_in)
            done_reg <= 1;

        // ==========================================
        // 2. READ LOGIC (Uses 'raddr')
        // ==========================================
        if (mem_read) begin
            if (raddr == STATUS_ADDR)
                rdata <= {31'b0, done_reg};
            else if (raddr == IMG_READY_ADDR)
                rdata <= {31'b0, img_ready};
            else
                rdata <= 32'd0;
        end else begin
            rdata <= 32'd0;
        end
        
    end
end

endmodule