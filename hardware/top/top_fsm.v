// ============================================================
//  top_fsm.v
//  Authors : Group 18 — Integration
//
//  Purpose:
//    Top level module that connects ALL submodules together.
//    Instantiates and wires:
//      1. img_bram_in      (Abhirup)
//      2. img_bram_out     (Soumik)
//      3. line_buffer      (Soumik)
//      4. conv_engine      (Soumik)
//      5. kernel_regfile   (Satish)
//      6. mmio_decoder     (Satish)
//      7. uart_rx          (Abhirup)
//      8. uart_tx          (Abhirup)
//
//  FSM States:
//    WAIT_IMAGE  → waiting for full image to arrive via UART
//    WAIT_START  → image loaded, waiting for CPU to write START
//    PROCESSING  → line_buffer + conv_engine running
//    TRANSMIT    → sending output image back via UART
//    DONE        → all done, wait for next command
//
//  Reset note:
//    Main design uses active-LOW  reset (reset)
//    UART modules use active-HIGH reset (uart_rst = ~reset)
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
    output wire [31:0] cpu_rdata    // CPU read data (done status)
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
//  Internal wires — UART RX side
// ─────────────────────────────────────────────────────────────
wire        rx_dv;          // uart_rx: byte valid pulse
wire [7:0]  rx_byte;        // uart_rx: received byte

// ─────────────────────────────────────────────────────────────
//  Internal wires — img_bram_in
// ─────────────────────────────────────────────────────────────
reg         bram_in_we;
reg  [13:0] bram_in_wr_addr;
wire [13:0] bram_in_rd_addr;   // driven by line_buffer
wire [7:0]  bram_in_rd_data;   // goes to line_buffer

// ─────────────────────────────────────────────────────────────
//  Internal wires — line_buffer
// ─────────────────────────────────────────────────────────────
wire        lb_start;           // from mmio_decoder
wire        lb_done;            // to mmio_decoder + FSM
wire [7:0]  p00, p01, p02;
wire [7:0]  p10, p11, p12;
wire [7:0]  p20, p21, p22;
wire        window_valid;
wire [13:0] out_pixel_idx;

// ─────────────────────────────────────────────────────────────
//  Internal wires — conv_engine
// ─────────────────────────────────────────────────────────────
wire [7:0]  pixel_out;
wire        ce_out_valid;
wire [13:0] pixel_idx_out;

// ─────────────────────────────────────────────────────────────
//  Internal wires — kernel_regfile
// ─────────────────────────────────────────────────────────────
wire signed [7:0] k0, k1, k2;
wire signed [7:0] k3, k4, k5;
wire signed [7:0] k6, k7, k8;
wire        norm_en;

// ─────────────────────────────────────────────────────────────
//  Internal wires — mmio_decoder
// ─────────────────────────────────────────────────────────────
wire        kernel_we;
wire [3:0]  kernel_addr;
wire [31:0] kernel_wdata;

// ─────────────────────────────────────────────────────────────
//  Internal wires — img_bram_out
// ─────────────────────────────────────────────────────────────
reg  [13:0] bram_out_rd_addr;
wire [7:0]  bram_out_rd_data;

// ─────────────────────────────────────────────────────────────
//  Internal wires — uart_tx
// ─────────────────────────────────────────────────────────────
reg         tx_start;
reg  [7:0]  tx_byte;
wire        tx_done;

// ─────────────────────────────────────────────────────────────
//  Image load counter
//  Counts bytes 0→16383 as uart_rx receives them
//  Signals img_load_done when full image received
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
            // write incoming byte into img_bram_in
            bram_in_we      <= 1'b1;
            bram_in_wr_addr <= rx_byte_count;

            if (rx_byte_count == 14'd16383) begin
                // full image received
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
//  After lb_done, reads img_bram_out and feeds uart_tx
//  byte by byte 0→15875
//  tx_fetch_state:
//    0 = IDLE    → give BRAM the address
//    1 = WAIT    → wait 1 cycle for BRAM to respond
//    2 = SEND    → data stable, fire uart_tx
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
        tx_start <= 1'b0;   // default clear

        if (fsm_state == TRANSMIT) begin

            // ── 3-state BRAM fetch machine ────────────────
            // State 0: give BRAM the address
            if (tx_fetch_state == 2'd0 && !tx_done) begin
                bram_out_rd_addr <= tx_byte_count;
                tx_fetch_state   <= 2'd1;
            end

            // State 1: wait exactly 1 cycle for BRAM output
            else if (tx_fetch_state == 2'd1) begin
                tx_fetch_state   <= 2'd2;
            end

            // State 2: data is stable, grab and send
            else if (tx_fetch_state == 2'd2) begin
                tx_byte        <= bram_out_rd_data;
                tx_start       <= 1'b1;
                tx_fetch_state <= 2'd0;
            end

            // ── increment counter when UART done ─────────
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

            // ──────────────────────────────────────────────────
            // WAIT_IMAGE — receive full 128×128 image via UART
            // ──────────────────────────────────────────────────
            WAIT_IMAGE: begin
                if (img_load_done)
                    fsm_state <= WAIT_START;
            end

            // ──────────────────────────────────────────────────
            // WAIT_START — image in BRAM, wait for CPU to write
            //              to START_ADDR via MMIO
            //              mmio_decoder will pulse lb_start
            // ──────────────────────────────────────────────────
            WAIT_START: begin
                if (lb_start)
                    fsm_state <= PROCESSING;
            end

            // ──────────────────────────────────────────────────
            // PROCESSING — line_buffer + conv_engine running
            //              wait for lb_done pulse
            // ──────────────────────────────────────────────────
            PROCESSING: begin
                if (lb_done) begin
                    fsm_state <= DRAIN;
                    drain_count <= 3'd0;
                end
            end

            // ──────────────────────────────────────────────────
            // DRAIN — wait 4 cycles for conv_engine pipeline
            // ──────────────────────────────────────────────────
            DRAIN: begin
                if (drain_count == 3'd4)
                    fsm_state <= TRANSMIT;
                else
                    drain_count <= drain_count + 3'd1;
            end

            // ──────────────────────────────────────────────────
            // TRANSMIT — send output image back via UART
            //            15876 bytes, one per uart_tx frame
            // ──────────────────────────────────────────────────
            TRANSMIT: begin
                if (tx_done && tx_byte_count == 14'd15875)
                    fsm_state <= IDLE_DONE;
            end

            // ──────────────────────────────────────────────────
            // IDLE_DONE — all done
            //             wait for next image (go back to start)
            // ──────────────────────────────────────────────────
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

// ── 1. uart_rx ───────────────────────────────────────────────
uart_rx #(
    .CLKS_PER_BIT(CLKS_PER_BIT)
) uart_rx_inst (
    .clk       (clk),
    .rst       (uart_rst),      // active HIGH
    .rx_serial (rx_pin),
    .rx_dv     (rx_dv),
    .rx_byte   (rx_byte)
);

// ── 2. uart_tx ───────────────────────────────────────────────
uart_tx #(
    .CLKS_PER_BIT(CLKS_PER_BIT)
) uart_tx_inst (
    .clk       (clk),
    .rst       (uart_rst),      // active HIGH
    .tx_start  (tx_start),
    .tx_byte   (tx_byte),
    .tx_serial (tx_pin),
    .tx_done   (tx_done)
);

// ── 3. img_bram_in ───────────────────────────────────────────
img_bram_in bram_in_inst (
    .clk     (clk),
    // write port — Abhirup (UART RX controller above)
    .we      (bram_in_we),
    .wr_addr (bram_in_wr_addr),
    .wr_data (rx_byte),
    // read port — Soumik (line_buffer)
    .rd_addr (bram_in_rd_addr),
    .rd_data (bram_in_rd_data)
);

// ── 4. line_buffer ───────────────────────────────────────────
line_buffer #(
    .IMG_W(IMG_W),
    .IMG_H(IMG_H)
) lb_inst (
    .clk          (clk),
    .reset        (reset),
    // handshake
    .start        (lb_start),
    .done         (lb_done),
    // BRAM read port
    .bram_rd_addr (bram_in_rd_addr),
    .bram_rd_data (bram_in_rd_data),
    // pixel window to conv_engine
    .p00(p00), .p01(p01), .p02(p02),
    .p10(p10), .p11(p11), .p12(p12),
    .p20(p20), .p21(p21), .p22(p22),
    .window_valid (window_valid),
    // output index to conv_engine
    .out_pixel_idx(out_pixel_idx)
);

// ── 5. conv_engine ───────────────────────────────────────────
conv_engine ce_inst (
    .clk          (clk),
    .rst          (reset),          // active LOW — matches fixed conv_engine
    // pixel window from line_buffer
    .p00(p00), .p01(p01), .p02(p02),
    .p10(p10), .p11(p11), .p12(p12),
    .p20(p20), .p21(p21), .p22(p22),
    // kernel from kernel_regfile
    .k0(k0), .k1(k1), .k2(k2),
    .k3(k3), .k4(k4), .k5(k5),
    .k6(k6), .k7(k7), .k8(k8),
    // control
    .norm_en      (norm_en),
    .window_valid (window_valid),
    .pixel_idx_in (out_pixel_idx),
    // outputs
    .pixel_out    (pixel_out),
    .out_valid    (ce_out_valid),
    .pixel_idx_out(pixel_idx_out)
);

// ── 6. img_bram_out ──────────────────────────────────────────
img_bram_out bram_out_inst (
    .clk     (clk),
    // write port — Soumik (conv_engine)
    .we      (ce_out_valid),
    .wr_addr (pixel_idx_out),
    .wr_data (pixel_out),
    // read port — Abhirup (UART TX controller above)
    .rd_addr (bram_out_rd_addr),
    .rd_data (bram_out_rd_data)
);

// ── 7. kernel_regfile ────────────────────────────────────────
kernel_regfile krf_inst (
    .clk   (clk),
    .rst   (reset),             // active LOW
    // from mmio_decoder
    .we    (kernel_we),
    .addr  (kernel_addr),
    .wdata (kernel_wdata),
    // to conv_engine
    .k0(k0), .k1(k1), .k2(k2),
    .k3(k3), .k4(k4), .k5(k5),
    .k6(k6), .k7(k7), .k8(k8),
    .norm_en(norm_en)
);

// ── 8. mmio_decoder ──────────────────────────────────────────
mmio_decoder mmio_inst (
    .clk          (clk),
    .reset        (reset),          // active LOW
    // CPU write interface
    .mem_write    (mem_write),
    .addr         (cpu_addr),
    .wdata        (cpu_wdata),
    // CPU read interface
    .mem_read     (mem_read),
    .rdata        (cpu_rdata),
    // to kernel_regfile
    .kernel_we    (kernel_we),
    .kernel_index (kernel_addr),    // <--- FIXED: mmio_decoder calls this kernel_index
    .kernel_wdata (kernel_wdata),
    // to line_buffer and FSM
    .start        (lb_start),
    .sw_done      (sw_done),        // <--- ADDED: Your software doorbell connection!
    // from line_buffer
    .done_in      (lb_done)
);

endmodule