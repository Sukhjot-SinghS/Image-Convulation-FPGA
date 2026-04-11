`timescale 1ns / 1ps

// ============================================================
//  mmio_decoder.v
//  Authors: Group 18
//
//  Purpose:
//    Decodes CPU memory accesses to the 0x8000_xxxx memory map.
//    - 0x8000_0000 to 0x8000_0020 : Kernel coefficients (W)
//    - 0x8000_0040 : Coprocessor Start trigger (W)
//    - 0x8000_0044 : Coprocessor Done status (R)
// ============================================================

module mmio_decoder(
    input  wire        clk,
    input  wire        rst,          // active-low
    // CPU Interface
    input  wire        mem_write,
    input  wire        mem_read,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,
    
    // Kernel Regfile Interface
    output reg         kernel_we,
    output reg  [3:0]  kernel_addr,
    output reg  [31:0] kernel_wdata,
    
    // Top FSM Interface
    output reg         start,
    input  wire        done_in
);

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            start        <= 1'b0;
            kernel_we    <= 1'b0;
            kernel_addr  <= 4'd0;
            kernel_wdata <= 32'd0;
            rdata        <= 32'd0;
        end else begin
            // Default signals to prevent latching
            start     <= 1'b0;
            kernel_we <= 1'b0;
            
            // ── WRITE DECODE ────────────────────────────
            if (mem_write) begin
                // START Command (0x8000_0040)
                if (addr == 32'h8000_0040) begin
                    start <= wdata[0];
                end
                // KERNEL Coefficients (0x8000_0000 -> 0x8000_0020)
                else if (addr >= 32'h8000_0000 && addr <= 32'h8000_0020) begin
                    kernel_we    <= 1'b1;
                    kernel_addr  <= addr[5:2];  // divide offset by 4 bytes
                    kernel_wdata <= wdata;
                end
            end
            
            // ── READ DECODE ─────────────────────────────
            if (mem_read) begin
                // DONE Status (0x8000_0044)
                if (addr == 32'h8000_0044) begin
                    rdata <= {31'd0, done_in};
                end else begin
                    rdata <= 32'd0;
                end
            end
        end
    end

endmodule