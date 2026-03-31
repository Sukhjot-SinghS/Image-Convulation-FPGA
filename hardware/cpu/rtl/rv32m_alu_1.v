`timescale 1ns/1ps

//============================================================================
// RV32M ALU Extension
//============================================================================
// Handles all 8 RV32M instructions:
//   MUL, MULH, MULHSU, MULHU  (single-cycle, DSP-inferred)
//   DIV, DIVU, REM, REMU      (33-cycle iterative restoring divider)
//
// Interface:
//   - Assert `start` for 1 cycle to begin an operation
//   - MUL results appear combinationally on `result` (busy stays low)
//   - DIV results take 33 cycles; `busy` is high until `valid` pulses
//   - When `busy`, the hazard unit must stall the pipeline
//
// RISC-V spec edge cases handled:
//   Division by zero:  DIV  → 0xFFFF_FFFF   DIVU → 0xFFFF_FFFF
//                      REM  → dividend       REMU → dividend
//   Signed overflow:   MIN_INT / -1 → MIN_INT (DIV), 0 (REM)
//============================================================================

module rv32m_alu (
    input  wire        clk,
    input  wire        reset_n,      // active-low (matches pipeline convention)

    // Control
    input  wire        start,        // pulse high 1 cycle to begin
    input  wire [2:0]  funct3,       // selects M operation

    // Operands (directly from alu_operand1/2 in execute.v)
    input  wire [31:0] operand1,     // rs1
    input  wire [31:0] operand2,     // rs2

    // Outputs
    output wire [31:0] result,       // operation result
    output wire        busy,         // high during multi-cycle DIV
    output wire        valid         // high for 1 cycle when result ready
);

    // -----------------------------------------------------------------------
    // funct3 encoding for RV32M (all use opcode=0110011, funct7=0000001)
    // -----------------------------------------------------------------------
    localparam [2:0] F3_MUL    = 3'b000,
                     F3_MULH   = 3'b001,
                     F3_MULHSU = 3'b010,
                     F3_MULHU  = 3'b011,
                     F3_DIV    = 3'b100,
                     F3_DIVU   = 3'b101,
                     F3_REM    = 3'b110,
                     F3_REMU   = 3'b111;

    wire is_mul_op = ~funct3[2];     // funct3[2]==0 -> MUL family
    wire is_div_op =  funct3[2];     // funct3[2]==1 -> DIV family


    // =======================================================================
    //  MULTIPLY — single cycle
    // =======================================================================
    // Vivado will infer DSP48E1 slices for the 33x33 multiply.
    // We extend to 33 bits to handle signed/unsigned combinations,
    // then take the lower 64 bits of the 66-bit product.
    // -----------------------------------------------------------------------

    wire signed [32:0] mul_a;
    wire signed [32:0] mul_b;
    wire signed [65:0] mul_wide;
    wire        [63:0] mul_product;

    // operand1 sign extension:
    //   MULHU -> zero-extend (unsigned x unsigned)
    //   MUL, MULH, MULHSU -> sign-extend
    assign mul_a = (funct3 == F3_MULHU)
                   ? {1'b0, operand1}
                   : {operand1[31], operand1};

    // operand2 sign extension:
    //   MULHU, MULHSU -> zero-extend
    //   MUL, MULH -> sign-extend
    assign mul_b = (funct3 == F3_MULHU || funct3 == F3_MULHSU)
                   ? {1'b0, operand2}
                   : {operand2[31], operand2};

    assign mul_wide    = mul_a * mul_b;
    assign mul_product = mul_wide[63:0];

    wire [31:0] mul_result = (funct3 == F3_MUL)
                             ? mul_product[31:0]     // MUL  -> lower 32
                             : mul_product[63:32];   // MULH variants -> upper 32


    // =======================================================================
    //  DIVIDE — iterative restoring divider (33 cycles: 1 latch + 32 iter)
    // =======================================================================
    //
    // Algorithm (restoring division, unsigned, MSB-first):
    //   remainder = 0
    //   for i = 31 downto 0:
    //       shifted = {remainder[31:0], dividend[i]}     // shift left, bring bit in
    //       trial   = shifted - divisor
    //       if trial >= 0:
    //           remainder = trial       // accept
    //           quotient[i] = 1
    //       else:
    //           remainder = shifted     // restore
    //           quotient[i] = 0
    //
    // Signed division: take abs of both operands, divide unsigned,
    //                  negate result if signs differ.
    // -----------------------------------------------------------------------

    // --- FSM states ---
    localparam S_IDLE    = 2'd0,
               S_RUNNING = 2'd1,     // 32 cycles
               S_DONE    = 2'd2;     // 1 cycle: apply sign + output

    reg [1:0]  div_state;
    reg [4:0]  bit_idx;              // 31 down to 0

    // --- latched control ---
    reg [31:0] dividend;             // |rs1| or rs1
    reg [31:0] divisor;              // |rs2| or rs2
    reg        negate_quot;
    reg        negate_rem;
    reg        is_rem_op;            // 1 = REM/REMU, 0 = DIV/DIVU
    reg        div_by_zero;
    reg        signed_ovf;
    reg [31:0] dividend_orig;        // raw rs1, for div-by-zero REM

    // --- datapath ---
    reg [31:0] quotient;
    reg [32:0] remainder;            // 33 bits for sign detection

    // Combinational: shift-and-subtract for current bit_idx
    wire [32:0] shifted_rem = {remainder[31:0], dividend[bit_idx]};
    wire [32:0] trial_sub   = shifted_rem - {1'b0, divisor};
    wire        trial_fits  = ~trial_sub[32];  // 1 if divisor fits (trial >= 0)

    // --- output ---
    reg [31:0] div_result_r;
    reg        div_valid_r;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            div_state     <= S_IDLE;
            bit_idx       <= 5'd0;
            div_valid_r   <= 1'b0;
            div_result_r  <= 32'd0;
            quotient      <= 32'd0;
            remainder     <= 33'd0;
            dividend      <= 32'd0;
            divisor       <= 32'd0;
            negate_quot   <= 1'b0;
            negate_rem    <= 1'b0;
            is_rem_op     <= 1'b0;
            div_by_zero   <= 1'b0;
            signed_ovf    <= 1'b0;
            dividend_orig <= 32'd0;
        end
        else begin
            div_valid_r <= 1'b0;   // default: single-cycle pulse

            case (div_state)

            // =============================================================
            // IDLE: latch operands and flags on start
            // =============================================================
            S_IDLE: begin
                if (start && is_div_op) begin
                    // Operation type
                    is_rem_op     <= funct3[1];   // REM=110, REMU=111
                    div_by_zero   <= (operand2 == 32'd0);
                    dividend_orig <= operand1;

                    if (funct3 == F3_DIV || funct3 == F3_REM) begin
                        // Signed division
                        signed_ovf  <= (operand1 == 32'h8000_0000) &&
                                       (operand2 == 32'hFFFF_FFFF);
                        dividend    <= operand1[31] ? (~operand1 + 1) : operand1;
                        divisor     <= operand2[31] ? (~operand2 + 1) : operand2;
                        negate_quot <= operand1[31] ^ operand2[31];
                        negate_rem  <= operand1[31];
                    end
                    else begin
                        // Unsigned division
                        signed_ovf  <= 1'b0;
                        dividend    <= operand1;
                        divisor     <= operand2;
                        negate_quot <= 1'b0;
                        negate_rem  <= 1'b0;
                    end

                    // Init datapath for 32 iterations
                    quotient  <= 32'd0;
                    remainder <= 33'd0;
                    bit_idx   <= 5'd31;
                    div_state <= S_RUNNING;
                end
            end

            // =============================================================
            // RUNNING: process one bit per cycle (31 downto 0)
            // =============================================================
            S_RUNNING: begin
                // Step 1: shift remainder left, bring in dividend[bit_idx]
                // Step 2: subtract divisor from shifted value
                // Step 3: keep or restore based on sign of subtraction
                if (trial_fits) begin
                    remainder         <= trial_sub;     // accept
                    quotient[bit_idx] <= 1'b1;
                end
                else begin
                    remainder         <= shifted_rem;   // restore
                    // quotient[bit_idx] stays 0 from initialization
                end

                if (bit_idx == 5'd0)
                    div_state <= S_DONE;
                else
                    bit_idx <= bit_idx - 1;
            end

            // =============================================================
            // DONE: apply edge cases and sign correction, output result
            // =============================================================
            S_DONE: begin
                if (div_by_zero) begin
                    // RISC-V spec: div by zero does NOT trap
                    div_result_r <= is_rem_op ? dividend_orig    // REM  -> rs1
                                             : 32'hFFFF_FFFF;  // DIV  -> -1
                end
                else if (signed_ovf) begin
                    // RISC-V spec: -2^31 / -1 overflow
                    div_result_r <= is_rem_op ? 32'd0            // REM  -> 0
                                             : 32'h8000_0000;  // DIV  -> -2^31
                end
                else if (is_rem_op) begin
                    // Remainder sign matches dividend
                    div_result_r <= negate_rem ? (~remainder[31:0] + 1)
                                              :  remainder[31:0];
                end
                else begin
                    // Quotient sign = xor of operand signs
                    div_result_r <= negate_quot ? (~quotient + 1)
                                               :  quotient;
                end

                div_valid_r <= 1'b1;
                div_state   <= S_IDLE;
            end

            default: div_state <= S_IDLE;

            endcase
        end
    end

    // --- divider busy flag ---
    // Assert immediately when division starts (combinational OR),
    // so hazard unit stalls the pipeline on the same cycle as start.
    assign busy = (div_state != S_IDLE) || (start && is_div_op);


    // =======================================================================
    //  OUTPUT MUX
    // =======================================================================
    // MUL: combinational result, valid same cycle as start
    // DIV: registered result, valid on S_DONE pulse

    assign result = is_mul_op ? mul_result : div_result_r;
    assign valid  = is_mul_op ? start      : div_valid_r;

endmodule
