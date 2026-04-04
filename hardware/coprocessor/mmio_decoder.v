`timescale 1ns / 1ps
// ============================================================
// mmio_decoder.v
// Author: Satish Kumar
// Purpose: Memory-mapped IO decoder for kernel and START control
//          Receives CPU read/write, outputs kernel registers
// ============================================================

module mmio_decoder (
    input  wire        clk,
    input  wire        reset,        // Active-low reset
    
    // CPU Interface
    input  wire [31:0] address,      // CPU memory address
    input  wire [31:0] write_data,   // CPU write data
    input  wire        write_enable, // CPU write enable
    input  wire        read_enable,  // CPU read enable
    output reg  [31:0] read_data,    // CPU read data
    
    // Kernel Regfile Interface
    output reg         kernel_we,    // Pulse to write kernel register
    output reg  [3:0]  kernel_index, // Which kernel register to write (0–8)
    output reg  [31:0] kernel_wdata, // Data to kernel register
    
    // Control Signals
    output reg         start,        // Pulse to start line buffer/FSM
    input  wire        done          // Done signal from FSM/line_buffer
);

////////////////////////////////////////////////////////////
// ADDRESS MAP
////////////////////////////////////////////////////////////
localparam KERNEL_BASE = 32'h80000000; // k0–k8 registers
localparam START_ADDR  = 32'h80000028; // start pulse
localparam STATUS_ADDR = 32'h8000002C; // CPU polls done status

// Internal done register for CPU polling
reg done_reg;

////////////////////////////////////////////////////////////
// WRITE + CONTROL LOGIC
////////////////////////////////////////////////////////////
always @(posedge clk) begin
    if (!reset) begin
        start        <= 1'b0;
        kernel_we    <= 1'b0;
        kernel_index <= 4'd0;
        kernel_wdata <= 32'd0;
        done_reg     <= 1'b0;
    end
    else begin
        // Default values
        kernel_we <= 1'b0;
        start     <= 1'b0;

        // START pulse: CPU writes 1 to START_ADDR
        if (write_enable && address == START_ADDR && write_data[0])
            start <= 1'b1;

        // KERNEL write: CPU writes to KERNEL_BASE + offset
        if (write_enable && address >= KERNEL_BASE && address < KERNEL_BASE + 36) begin
            kernel_we    <= 1'b1;
            kernel_index <= (address - KERNEL_BASE) >> 2; // 0–8
            kernel_wdata <= write_data;
        end

        // DONE handling for polling
        if (start)
            done_reg <= 1'b0;     // Reset done when new start issued
        else if (done)
            done_reg <= 1'b1;     // Set done when FSM signals completion
    end
end

////////////////////////////////////////////////////////////
// READ LOGIC
////////////////////////////////////////////////////////////
always @(*) begin
    if (read_enable && address == STATUS_ADDR)
        read_data = {31'b0, done_reg}; // LSB is done
    else
        read_data = 32'd0;
end

endmodule
