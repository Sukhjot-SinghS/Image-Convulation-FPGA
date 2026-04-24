`timescale 1ns / 1ps

module kernel_regfile (
    input  wire        clk,
    input  wire        rst,        // active-low

    // Write interface from mmio_decoder (FIXED NAMES & WIDTHS)
    input  wire        we,
    input  wire [3:0]  addr,       // Fixed from 'sel' to 'addr'
    input  wire [31:0] wdata,      // Fixed to 32-bit to match CPU bus

    // Kernel coefficients ΓåÆ conv_datapath
    output reg signed [7:0] k0, k1, k2,
    output reg signed [7:0] k3, k4, k5,
    output reg signed [7:0] k6, k7, k8,

    // Norm enable ΓåÆ conv_datapath
    output reg         norm_en
);

always @(posedge clk or negedge rst) begin
    if (!rst) begin
        // Default to Gaussian blur kernel so HW conv works even without CPU init
        k0 <= 8'sd1; k1 <= 8'sd2; k2 <= 8'sd1;
        k3 <= 8'sd2; k4 <= 8'sd4; k5 <= 8'sd2;
        k6 <= 8'sd1; k7 <= 8'sd2; k8 <= 8'sd1;
        norm_en <= 1'b1;   // default blur normalization ON
    end
    else begin
        if (we) begin
            // We only take the bottom 8 bits of the 32-bit CPU bus word
            case (addr)
                4'd0: k0 <= $signed(wdata[7:0]);
                4'd1: k1 <= $signed(wdata[7:0]);
                4'd2: k2 <= $signed(wdata[7:0]);
                4'd3: k3 <= $signed(wdata[7:0]);
                4'd4: k4 <= $signed(wdata[7:0]);
                4'd5: k5 <= $signed(wdata[7:0]);
                4'd6: k6 <= $signed(wdata[7:0]);
                4'd7: k7 <= $signed(wdata[7:0]);
                4'd8: k8 <= $signed(wdata[7:0]);
                4'd10: norm_en <= wdata[0];  // Toggle bit for normalization
                default: ;
            endcase
        end
    end
end

endmodule
