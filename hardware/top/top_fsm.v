// ============================================================
//  top_fsm.v
// ============================================================

module top_fsm #(
    parameter CLKS_PER_BIT = 217,    // UART baud rate divider
    parameter IMG_W        = 128,
    parameter IMG_H        = 128,
    parameter IMG_SIZE     = 16384, // 128*128
    parameter OUT_SIZE     = 15876  // 126*126
)(
    input  wire        clk,
    input  wire        reset,       // active-low reset

    // ── Physical UART pins ───────────────────────────────────
    input  wire        rx_pin,      // UART RX from PC
    output wire        tx_pin,      // UART TX to PC

    // ── CPU pipeline interface (from pipeline.v) ─────────────
    input  wire        mem_write,   // CPU write enable
    input  wire        mem_read,    // CPU read enable
    input  wire [31:0] cpu_addr,    // CPU address bus
    input  wire [31:0] cpu_wdata,   // CPU write data
    output wire [31:0] cpu_rdata    // CPU read data
);

// ─────────────────────────────────────────────────────────────
//  Reset — UART needs active HIGH, rest of design active LOW
// ─────────────────────────────────────────────────────────────
wire uart_rst = ~reset;   // invert for UART modules

// ─────────────────────────────────────────────────────────────
//  FSM States
// ─────────────────────────────────────────────────────────────
localparam WAIT_IMAGE  = 3'd0;  // waiting for full image via UART
localparam WAIT_START  = 3'd1;  // image ready, waiting for CPU start
localparam PROCESSING  = 3'd2;  // conv running
localparam TRANSMIT    = 3'd3;  // sending output image back
localparam IDLE_DONE   = 3'd4;  // finished, back to wait
localparam DRAIN       = 3'd5;  // 4-cycle pipeline drain

reg [2:0] fsm_state;
reg [2:0] drain_count;

// ─────────────────────────────────────────────────────────────
//  THE BRAM HIJACK LOGIC (Fixed for Multi-Driver & Timing Loops)
// ─────────────────────────────────────────────────────────────
wire cpu_reads_bram_in   = (cpu_addr[31:16] == 16'hC000) && mem_read;
wire cpu_writes_bram_out = (cpu_addr[31:16] == 16'hC001) && mem_write;

// Mux the Read port of BRAM_IN (Hardware vs CPU)
wire [13:0] actual_bram_in_rd_addr = cpu_reads_bram_in ? cpu_addr[13:0] : bram_in_rd_addr;

// Mux the Write port of BRAM_OUT (Hardware vs CPU)
wire [13:0] actual_bram_out_wr_addr = cpu_writes_bram_out ? cpu_addr[13:0] : pixel_idx_out;
wire [7:0]  actual_bram_out_wr_data = cpu_writes_bram_out ? cpu_wdata[7:0] : pixel_out;
wire        actual_bram_out_we      = cpu_writes_bram_out ? 1'b1           : ce_out_valid;

// ONLY the BRAM drives cpu_rdata now. This kills the short circuit!
assign cpu_rdata = cpu_reads_bram_in ? {24'd0, bram_in_rd_data} : 32'd0;

// ─────────────────────────────────────────────────────────────
//  Internal wires 
// ─────────────────────────────────────────────────────────────
wire        rx_dv;          
wire [7:0]  rx_byte;        
reg         bram_in_we;
reg  [13:0] bram_in_wr_addr;
wire [13:0] bram_in_rd_addr;   
wire [7:0]  bram_in_rd_data;   
wire        lb_start;           
wire        lb_done;            
wire [7:0]  p00, p01, p02;
wire [7:0]  p10, p11, p12;
wire [7:0]  p20, p21, p22;
wire        window_valid;
wire [13:0] out_pixel_idx;
wire [7:0]  pixel_out;
wire        ce_out_valid;
wire [13:0] pixel_idx_out;
wire signed [7:0] k0, k1, k2;
wire signed [7:0] k3, k4, k5;
wire signed [7:0] k6, k7, k8;
wire        norm_en;
wire        kernel_we;
wire [3:0]  kernel_addr;
wire [31:0] kernel_wdata;
reg  [13:0] bram_out_rd_addr;
wire [7:0]  bram_out_rd_data;
reg         tx_start;
reg  [7:0]  tx_byte;
wire        tx_done;

// ─────────────────────────────────────────────────────────────
//  Image load counter
// ─────────────────────────────────────────────────────────────
reg  [13:0] rx_byte_count;
reg         img_load_done;

always @(posedge clk or negedge reset) begin
    if (!reset) begin
        rx_byte_count  <= 14'd0;
        bram_in_we     <= 1'b0;
        bram_in_wr_addr<= 14'd0;
        img_load_done  <= 1'b0;
    end
    else begin
        bram_in_we    <= 1'b0;
        img_load_done <= 1'b0;

        if (rx_dv && fsm_state == WAIT_IMAGE) begin
            bram_in_we      <= 1'b1;
            bram_in_wr_addr <= rx_byte_count;

            if (rx_byte_count == 14'd16383) begin
                rx_byte_count <= 14'd0;
                img_load_done <= 1'b1;
            end
            else begin
                rx_byte_count <= rx_byte_count + 14'd1;
            end
        end
    end
end

// ─────────────────────────────────────────────────────────────
//  Output transmit counter
// ─────────────────────────────────────────────────────────────
reg  [13:0] tx_byte_count;
reg  [1:0]  tx_fetch_state;

always @(posedge clk or negedge reset) begin
    if (!reset) begin
        tx_byte_count    <= 14'd0;
        bram_out_rd_addr <= 14'd0;
        tx_start         <= 1'b0;
        tx_byte          <= 8'd0;
        tx_fetch_state   <= 2'd0;
    end
    else begin
        tx_start <= 1'b0;   

        if (fsm_state == TRANSMIT) begin
            if (tx_fetch_state == 2'd0 && !tx_done) begin
                bram_out_rd_addr <= tx_byte_count;
                tx_fetch_state   <= 2'd1;
            end
            else if (tx_fetch_state == 2'd1) begin
                tx_fetch_state   <= 2'd2;
            end
            else if (tx_fetch_state == 2'd2) begin
                tx_byte        <= bram_out_rd_data;
                tx_start       <= 1'b1;
                tx_fetch_state <= 2'd0;
            end

            if (tx_done) begin
                if (tx_byte_count == 14'd15875)
                    tx_byte_count <= 14'd0;
                else
                    tx_byte_count <= tx_byte_count + 14'd1;
            end
        end
        else begin
            tx_byte_count    <= 14'd0;
            bram_out_rd_addr <= 14'd0;
            tx_fetch_state   <= 2'd0;
        end
    end
end

// ─────────────────────────────────────────────────────────────
//  Main FSM
// ─────────────────────────────────────────────────────────────
always @(posedge clk or negedge reset) begin
    if (!reset) begin
        fsm_state <= WAIT_IMAGE;
    end
    else begin
        case (fsm_state)
            WAIT_IMAGE: begin
                if (img_load_done)
                    fsm_state <= WAIT_START;
            end
            WAIT_START: begin
                if (lb_start)
                    fsm_state <= PROCESSING;
                else if (sw_done)           
                    fsm_state <= TRANSMIT;
            end
            PROCESSING: begin
                if (lb_done) begin
                    fsm_state <= DRAIN;
                    drain_count <= 3'd0;
                end
            end
            DRAIN: begin
                if (drain_count == 3'd4)
                    fsm_state <= TRANSMIT;
                else
                    drain_count <= drain_count + 3'd1;
            end
            TRANSMIT: begin
                if (tx_done && tx_byte_count == 14'd15875)
                    fsm_state <= IDLE_DONE;
            end
            IDLE_DONE: begin
                fsm_state <= WAIT_IMAGE;
            end
            default: fsm_state <= WAIT_IMAGE;
        endcase
    end
end

// ─────────────────────────────────────────────────────────────
//  Module instantiations
// ─────────────────────────────────────────────────────────────

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
    .rd_addr (actual_bram_in_rd_addr), 
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
    .out_pixel_idx(out_pixel_idx)
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
    .norm_en      (norm_en),
    .window_valid (window_valid),
    .pixel_idx_in (out_pixel_idx),
    .pixel_out    (pixel_out),
    .out_valid    (ce_out_valid),
    .pixel_idx_out(pixel_idx_out)
);

img_bram_out bram_out_inst (
    .clk     (clk),
    .we      (actual_bram_out_we),      
    .wr_addr (actual_bram_out_wr_addr), 
    .wr_data (actual_bram_out_wr_data), 
    .rd_addr (bram_out_rd_addr),
    .rd_data (bram_out_rd_data)
);

kernel_regfile krf_inst (
    .clk   (clk),
    .rst   (reset),
    .we    (kernel_we),
    .addr  (kernel_addr),
    .wdata (kernel_wdata),
    .k0(k0), .k1(k1), .k2(k2),
    .k3(k3), .k4(k4), .k5(k5),
    .k6(k6), .k7(k7), .k8(k8),
    .norm_en(norm_en)
);

mmio_decoder mmio_inst (
    .clk          (clk),
    .reset        (reset),
    .mem_write    (mem_write),
    .addr         (cpu_addr),
    .wdata        (cpu_wdata),
    .mem_read     (mem_read),
    
    // THIS IS THE FIX. We leave .rdata empty. It kills the timing loop and multi-driver error.
    .rdata        (), 

    .kernel_we    (kernel_we),
    .kernel_index (kernel_addr),   
    .kernel_wdata (kernel_wdata),
    .start        (lb_start),
    .sw_done      (sw_done),
    .done_in      (lb_done)
);

endmodule