`timescale 1ns / 1ps

module kernel_regfile (
    input  wire        clk,
    input  wire        rst,        // active-low

    // Write interface from mmio_decoder
    input  wire        we,
    input  wire [3:0]  sel,
    input  wire [7:0]  wdata,

    // done from conv_engine
    input  wire        done_in,

    // Kernel coefficients → conv_datapath
    output reg signed [7:0] k0, k1, k2,
    output reg signed [7:0] k3, k4, k5,
    output reg signed [7:0] k6, k7, k8,

    // Control signals
    output reg         start_out,
    output reg         done_out,

    // Norm enable → conv_datapath
    output reg         norm_en
);

always @(posedge clk or negedge rst) begin
    if (!rst) begin
        k0        <= 8'sd0; k1 <= 8'sd0; k2 <= 8'sd0;
        k3        <= 8'sd0; k4 <= 8'sd0; k5 <= 8'sd0;
        k6        <= 8'sd0; k7 <= 8'sd0; k8 <= 8'sd0;
        start_out <= 1'b0;
        done_out  <= 1'b0;
        norm_en   <= 1'b0;   // default Sobel/Sharpen
    end
    else begin
        start_out <= 1'b0;  // 1-cycle pulse

        if (done_in)
            done_out <= 1'b1;

        if (we) begin
            case (sel)
                4'd0: k0 <= $signed(wdata);
                4'd1: k1 <= $signed(wdata);
                4'd2: k2 <= $signed(wdata);
                4'd3: k3 <= $signed(wdata);
                4'd4: k4 <= $signed(wdata);
                4'd5: k5 <= $signed(wdata);
                4'd6: k6 <= $signed(wdata);
                4'd7: k7 <= $signed(wdata);
                4'd8: k8 <= $signed(wdata);
                4'd9: begin
                    if (wdata[0]) begin
                        start_out <= 1'b1;
                        done_out  <= 1'b0; // clear done on new start
                    end
                end
                4'd10: norm_en <= wdata[0];  // new norm_en register
                default: ;
            endcase
        end
    end
end

endmodule
