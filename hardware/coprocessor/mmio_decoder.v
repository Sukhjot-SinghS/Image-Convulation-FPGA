`timescale 1ns / 1ps

module mmio_decoder (
    input  wire        clk,
    input  wire        rst,   // active LOW

    // CPU Interface
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    input  wire        we,
    output reg  [31:0] rdata,

    // Kernel Regfile Interface
    output reg         kernel_we,
    output reg  [3:0]  kernel_index,
    output reg  [31:0] kernel_wdata,

    // Control Signals
    output reg start,
    input  wire done
);

////////////////////////////////////////////////////////////
// ADDRESS MAP (MATCHES C CODE)
////////////////////////////////////////////////////////////
localparam KERNEL_BASE = 32'h80000000;   // kernel[0] → kernel[8]
localparam START_ADDR  = 32'h80000028;
localparam STATUS_ADDR = 32'h8000002C;

////////////////////////////////////////////////////////////
// INTERNAL DONE REGISTER
////////////////////////////////////////////////////////////
reg done_reg;

////////////////////////////////////////////////////////////
// WRITE + CONTROL LOGIC
////////////////////////////////////////////////////////////
always @(posedge clk) begin
    if (!rst) begin
        start       <= 0;
        kernel_we   <= 0;
        done_reg    <= 0;
    end 
    else begin
        // default
        kernel_we <= 0;
        start     <= 0;

        // START (1-cycle pulse)
        if (we && addr == START_ADDR && wdata[0])
            start <= 1;

        // KERNEL WRITE (9 registers)
        if (we && addr >= KERNEL_BASE && addr < KERNEL_BASE + 36) begin
            kernel_we    <= 1;
            kernel_index <= (addr - KERNEL_BASE) >> 2;
            kernel_wdata <= wdata;
        end

        // DONE handling
        if (start)
            done_reg <= 0;
        else if (done)
            done_reg <= 1;
    end
end

////////////////////////////////////////////////////////////
// READ LOGIC
////////////////////////////////////////////////////////////
always @(*) begin
    case (addr)
        STATUS_ADDR: rdata = {31'b0, done_reg};
        default:     rdata = 32'd0;
    endcase
end

endmodule
