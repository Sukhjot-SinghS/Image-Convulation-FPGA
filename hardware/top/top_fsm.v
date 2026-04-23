`timescale 1ns / 1ps
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
    input  wire [31:0] cpu_addr,    // CPU WRITE address bus (from WB)
    input  wire [31:0] cpu_raddr,   // <--- BUG 2 FIX: NEW READ address bus (from EX)
    input  wire [31:0] cpu_wdata,   // CPU write data
    output wire [31:0] cpu_rdata,   // CPU read data

    // ── Benchmark cycle counter (from top_fpga.v) ────────────
    input  wire [31:0] cycle_count  // frozen cycle count for UART TX
);

// ─────────────────────────────────────────────────────────────
//  Reset — UART needs active HIGH, rest of design active LOW
// ─────────────────────────────────────────────────────────────
//wire uart_rst = ~reset;   // invert for UART modules
wire uart_rst = reset;   // don't invert for UART modules

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
wire        sw_done;        // Need this wire to catch the doorbell!
wire [31:0] mmio_rdata;



// ─────────────────────────────────────────────────────────────
//  THE BRAM HIJACK LOGIC
// ─────────────────────────────────────────────────────────────
// BUG 2 FIX: Use cpu_raddr for reading, and cpu_addr for writing!
wire cpu_reads_bram_in   = (cpu_raddr[31:16] == 16'hC000) && mem_read; 
wire cpu_writes_bram_out = (cpu_addr[31:16] == 16'hC001) && mem_write;

// Mux the Read port of BRAM_IN (Hardware vs CPU)
wire [13:0] actual_bram_in_rd_addr = cpu_reads_bram_in ? cpu_raddr[13:0] : bram_in_rd_addr;

// Mux the Write port of BRAM_OUT (Hardware vs CPU)
wire [13:0] actual_bram_out_wr_addr = cpu_writes_bram_out ? cpu_addr[13:0] : pixel_idx_out;
wire [7:0]  actual_bram_out_wr_data = cpu_writes_bram_out ? cpu_wdata[7:0] : pixel_out;
wire        actual_bram_out_we      = cpu_writes_bram_out ? 1'b1           : ce_out_valid;

// Your excellent 1-cycle delay fix to match BRAM latency!
reg cpu_reads_bram_d1;
always @(posedge clk or negedge reset) begin
    if (!reset)
        cpu_reads_bram_d1 <= 1'b0;
    else
        cpu_reads_bram_d1 <= cpu_reads_bram_in;
end

// Multiplex BRAM read and MMIO read safely
assign cpu_rdata = cpu_reads_bram_d1 ? {24'd0, bram_in_rd_data} : mmio_rdata;

// // ─────────────────────────────────────────────────────────────
// //  Internal wires 
// // ─────────────────────────────────────────────────────────────
// wire        rx_dv;          
// wire [7:0]  rx_byte;        
// reg         bram_in_we;
// reg  [13:0] bram_in_wr_addr;
// wire [13:0] bram_in_rd_addr;   
// wire [7:0]  bram_in_rd_data;   
// wire        lb_start;           
// wire        lb_done;            
// wire [7:0]  p00, p01, p02;
// wire [7:0]  p10, p11, p12;
// wire [7:0]  p20, p21, p22;
// wire        window_valid;
// wire [13:0] out_pixel_idx;
// wire [7:0]  pixel_out;
// wire        ce_out_valid;
// wire [13:0] pixel_idx_out;
// wire signed [7:0] k0, k1, k2;
// wire signed [7:0] k3, k4, k5;
// wire signed [7:0] k6, k7, k8;
// wire        norm_en;
// wire        kernel_we;
// wire [3:0]  kernel_addr;
// wire [31:0] kernel_wdata;
// reg  [13:0] bram_out_rd_addr;
// wire [7:0]  bram_out_rd_data;
// reg         tx_start;
// reg  [7:0]  tx_byte;
// wire        tx_done;
// wire        sw_done;        // Need this wire to catch the doorbell!
// wire [31:0] mmio_rdata;     

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
//  Output transmit counter and robust FSM
// ─────────────────────────────────────────────────────────────
reg  [13:0] tx_byte_count;
reg  [2:0]  tx_fsm;

localparam TX_FETCH_ADDR = 3'd0;
localparam TX_FETCH_WAIT = 3'd1;
localparam TX_PULSE_START= 3'd2;
localparam TX_WAIT_DONE  = 3'd3;
localparam TX_SEND_CYCLES= 3'd4;  // NEW: transmit 4 cycle-count bytes

reg [1:0] cycle_byte_sel;  // selects which byte of cycle_count to send (0=MSB..3=LSB)

always @(posedge clk or negedge reset) begin
    if (!reset) begin
        tx_byte_count    <= 14'd0;
        bram_out_rd_addr <= 14'd0;
        tx_start         <= 1'b0;
        tx_byte          <= 8'd0;
        tx_fsm           <= TX_FETCH_ADDR;
    end
    else begin
        tx_start <= 1'b0;   

        if (fsm_state == TRANSMIT) begin
            case (tx_fsm)
                TX_FETCH_ADDR: begin
                    bram_out_rd_addr <= tx_byte_count;
                    tx_fsm           <= TX_FETCH_WAIT;
                end
                TX_FETCH_WAIT: begin
                    tx_fsm           <= TX_PULSE_START;
                end
                TX_PULSE_START: begin
                    tx_byte          <= bram_out_rd_data;
                    tx_start         <= 1'b1;
                    tx_fsm           <= TX_WAIT_DONE;
                end
                TX_WAIT_DONE: begin
                    if (tx_done) begin
                        if (tx_byte_count < 14'd15875) begin
                            // Still sending image bytes
                            tx_byte_count <= tx_byte_count + 14'd1;
                            tx_fsm        <= TX_FETCH_ADDR;
                        end
                        else if (tx_byte_count == 14'd15875) begin
                            // Last image byte done → start cycle-count phase
                            tx_byte_count  <= 14'd15876;
                            cycle_byte_sel <= 2'd0;
                            tx_fsm         <= TX_SEND_CYCLES;
                        end
                        else if (tx_byte_count < 14'd15879) begin
                            // Intermediate cycle-count byte done → next one
                            tx_byte_count <= tx_byte_count + 14'd1;
                            tx_fsm        <= TX_SEND_CYCLES;
                        end
                        // tx_byte_count == 15879: last cycle byte done
                        // Main FSM catches this and transitions to IDLE_DONE
                    end
                end
                TX_SEND_CYCLES: begin
                    // Send 4 bytes of cycle_count, MSB first
                    case (cycle_byte_sel)
                        2'd0: tx_byte <= cycle_count[31:24];
                        2'd1: tx_byte <= cycle_count[23:16];
                        2'd2: tx_byte <= cycle_count[15:8];
                        2'd3: tx_byte <= cycle_count[7:0];
                    endcase
                    tx_start       <= 1'b1;
                    tx_fsm         <= TX_WAIT_DONE;
                    cycle_byte_sel <= cycle_byte_sel + 2'd1;
                end
            endcase
        end
        else begin
            tx_byte_count    <= 14'd0;
            bram_out_rd_addr <= 14'd0;
            tx_fsm           <= TX_FETCH_ADDR;
            cycle_byte_sel   <= 2'd0;
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
                else if (sw_done)          // <--- ESCAPE HATCH ADDED HERE!
                    fsm_state <= TRANSMIT; 
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
                    fsm_state <= 3'd6; // WAIT_TX_DB
                else
                    drain_count <= drain_count + 3'd1;
            end
            3'd6: begin // WAIT_TX_DB
                if (sw_done)
                    fsm_state <= TRANSMIT;
            end
            TRANSMIT: begin
                if (tx_done && tx_byte_count == 14'd15879)
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
    .waddr        (cpu_addr),    // BUG 2 FIX: Write address
    .raddr        (cpu_raddr),   // BUG 2 FIX: Read address
    .wdata        (cpu_wdata),
    .mem_read     (mem_read),
    .rdata        (mmio_rdata), 
    .kernel_we    (kernel_we),
    .kernel_index (kernel_addr),   
    .kernel_wdata (kernel_wdata),
    .start        (lb_start),
    .sw_done      (sw_done),
    .done_in      (lb_done),
    .img_ready    ((fsm_state == WAIT_START) || (fsm_state == PROCESSING) || (fsm_state == DRAIN))
);
// comment diya h yha 
endmodule