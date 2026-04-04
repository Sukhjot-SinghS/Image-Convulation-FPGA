`timescale 1ns / 1ps
// ============================================================
// top_fsm.v
// Top-level FSM connecting all submodules
// ============================================================

module top_fsm #(
    parameter CLKS_PER_BIT = 87,    // UART baud rate divider
    parameter IMG_W        = 128,   
    parameter IMG_H        = 128,
    parameter IMG_SIZE     = 16384, // 128*128
    parameter OUT_SIZE     = 15876  // 126*126 (after convolution)
)(
    input  wire        clk,          
    input  wire        reset,        

    // UART
    input  wire        rx_pin,       
    output wire        tx_pin,       

    // CPU/MMIO interface
    input  wire        mem_write,    
    input  wire        mem_read,     
    input  wire [31:0] cpu_addr,     
    input  wire [31:0] cpu_wdata,    
    output wire [31:0] cpu_rdata     
);

    // UART reset (active-high)
    wire uart_rst = ~reset;

    // FSM states
    localparam WAIT_IMAGE  = 3'd0;
    localparam WAIT_START  = 3'd1;
    localparam PROCESSING  = 3'd2;
    localparam TRANSMIT    = 3'd3;
    localparam IDLE_DONE   = 3'd4;

    reg [2:0] fsm_state;

    // UART RX
    wire        rx_dv;      
    wire [7:0]  rx_byte;    

    // BRAM input
    reg         bram_in_we;
    reg  [13:0] bram_in_wr_addr;
    wire [13:0] bram_in_rd_addr;  
    wire [7:0]  bram_in_rd_data;  

    // Line buffer
    wire        lb_start;      
    wire        lb_done;       
    wire [7:0]  p00,p01,p02,p10,p11,p12,p20,p21,p22;
    wire        window_valid;
    wire [13:0] out_pixel_idx;
    wire        out_valid;

    // Convolution engine
    wire [7:0]  pixel_out;
    wire        ce_out_valid;
    wire [13:0] pixel_idx_out;

    // Kernel regfile
    wire signed [7:0] k0,k1,k2,k3,k4,k5,k6,k7,k8;

    // MMIO decoder
    wire        kernel_we;
    wire [3:0]  kernel_addr;
    wire [31:0] kernel_wdata;

    // BRAM output
    reg  [13:0] bram_out_rd_addr;
    wire [7:0]  bram_out_rd_data;

    // UART TX
    reg         tx_start;
    reg  [7:0]  tx_byte;
    wire        tx_done;

    // Image receive
    reg  [13:0] rx_byte_count;
    reg         img_load_done;

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            rx_byte_count   <= 14'd0;
            bram_in_we      <= 1'b0;
            bram_in_wr_addr <= 14'd0;
            img_load_done   <= 1'b0;
        end else begin
            bram_in_we    <= 1'b0;
            img_load_done <= 1'b0;
            if (rx_dv && fsm_state == WAIT_IMAGE) begin
                bram_in_we      <= 1'b1;
                bram_in_wr_addr <= rx_byte_count;
                if (rx_byte_count == IMG_SIZE - 1) begin
                    rx_byte_count <= 14'd0;
                    img_load_done <= 1'b1;
                end else begin
                    rx_byte_count <= rx_byte_count + 14'd1;
                end
            end
        end
    end

    // Output transmit logic
    reg  [13:0] tx_byte_count;
    reg         tx_pending;

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            tx_byte_count    <= 14'd0;
            bram_out_rd_addr <= 14'd0;
            tx_start         <= 1'b0;
            tx_byte          <= 8'd0;
            tx_pending       <= 1'b0;
        end else begin
            tx_start <= 1'b0;
            if (fsm_state == TRANSMIT) begin
                if (!tx_pending && !tx_done) begin
                    bram_out_rd_addr <= tx_byte_count;
                    tx_pending       <= 1'b1;
                end
                if (tx_pending) begin
                    tx_byte    <= bram_out_rd_data;
                    tx_start   <= 1'b1;
                    tx_pending <= 1'b0;
                end
                if (tx_done) begin
                    if (tx_byte_count == OUT_SIZE - 1)
                        tx_byte_count <= 14'd0;
                    else
                        tx_byte_count <= tx_byte_count + 14'd1;
                end
            end else begin
                tx_byte_count    <= 14'd0;
                bram_out_rd_addr <= 14'd0;
                tx_pending       <= 1'b0;
            end
        end
    end

    // FSM transitions
    always @(posedge clk or negedge reset) begin
        if (!reset)
            fsm_state <= WAIT_IMAGE;
        else begin
            case (fsm_state)
                WAIT_IMAGE: if (img_load_done) fsm_state <= WAIT_START;
                WAIT_START: if (lb_start)      fsm_state <= PROCESSING;
                PROCESSING: if (lb_done)       fsm_state <= TRANSMIT;
                TRANSMIT:   if (tx_done && tx_byte_count == OUT_SIZE-1) fsm_state <= IDLE_DONE;
                IDLE_DONE:  fsm_state <= WAIT_IMAGE;
                default:    fsm_state <= WAIT_IMAGE;
            endcase
        end
    end

    // ────────────────────────────────
    // Module instantiations
    // ────────────────────────────────

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) uart_rx_inst (
        .clk       (clk),
        .rst       (uart_rst),
        .rx_serial (rx_pin),
        .rx_dv     (rx_dv),
        .rx_byte   (rx_byte)
    );

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) uart_tx_inst (
        .clk       (clk),
        .rst       (uart_rst),
        .tx_start  (tx_start),
        .tx_byte   (tx_byte),
        .tx_serial (tx_pin),
        .tx_done   (tx_done)
    );

    img_bram_in bram_in_inst (
        .clk     (clk),
        .we      (bram_in_we),
        .wr_addr (bram_in_wr_addr),
        .wr_data (rx_byte),
        .rd_addr (bram_in_rd_addr),
        .rd_data (bram_in_rd_data)
    );

    line_buffer #(.IMG_W(IMG_W), .IMG_H(IMG_H)) lb_inst (
        .clk          (clk),
        .reset        (reset),
        .start        (lb_start),
        .done         (lb_done),
        .bram_rd_addr (bram_in_rd_addr),
        .bram_rd_data (bram_in_rd_data),
        .p00(p00), .p01(p01), .p02(p02),
        .p10(p10), .p11(p11), .p12(p12),
        .p20(p20), .p21(p21), .p22(p22),
        .window_valid (window_valid),
        .out_pixel_idx(out_pixel_idx),
        .out_valid    (out_valid)
    );

    conv_engine ce_inst (
        .clk          (clk),
        .rst          (reset),
        .p00(p00), .p01(p01), .p02(p02),
        .p10(p10), .p11(p11), .p12(p12),
        .p20(p20), .p21(p21), .p22(p22),
        .k0(k0), .k1(k1), .k2(k2),
        .k3(k3), .k4(k4), .k5(k5),
        .k6(k6), .k7(k7), .k8(k8),
        .window_valid (window_valid),
        .pixel_idx_in (out_pixel_idx),
        .pixel_out    (pixel_out),
        .out_valid    (ce_out_valid),
        .pixel_idx_out(pixel_idx_out)
    );

    img_bram_out bram_out_inst (
        .clk     (clk),
        .we      (ce_out_valid),
        .wr_addr (pixel_idx_out),
        .wr_data (pixel_out),
        .rd_addr (bram_out_rd_addr),
        .rd_data (bram_out_rd_data)
    );

    kernel_regfile krf_inst (
        .clk   (clk),
        .rst   (reset),
        .we    (kernel_we),
        .sel   (kernel_addr),
        .wdata (kernel_wdata),
        .k0(k0), .k1(k1), .k2(k2),
        .k3(k3), .k4(k4), .k5(k5),
        .k6(k6), .k7(k7), .k8(k8)
    );

    mmio_decoder mmio_inst (
        .clk          (clk),
        .rst          (reset),
        .mem_write    (mem_write),
        .addr         (cpu_addr),
        .wdata        (cpu_wdata),
        .mem_read     (mem_read),
        .rdata        (cpu_rdata),
        .kernel_we    (kernel_we),
        .kernel_index (kernel_addr),
        .kernel_wdata (kernel_wdata),
        .start        (lb_start),
        .done_in      (lb_done)
    );

endmodule
