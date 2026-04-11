`timescale 1ns/1ps

module rv32m_alu (
    input  wire        clk,
    input  wire        reset_n,

    input  wire        start,        
    input  wire [2:0]  funct3,       

    input  wire [31:0] operand1,     
    input  wire [31:0] operand2,     

    output wire [31:0] result,
    output wire        busy,         
    output reg         valid         
);

    // =======================================================================
    // 1. MULTIPLIER (Single Cycle, DSP-Inferred)
    // =======================================================================
    wire is_mul = ~funct3[2]; // 0xx is MUL family

    wire signed [32:0] mul_a = (funct3 == 3'b011) ? {1'b0, operand1} : {operand1[31], operand1};
    wire signed [32:0] mul_b = (funct3 == 3'b011 || funct3 == 3'b010) ? {1'b0, operand2} : {operand2[31], operand2};
    
    wire signed [65:0] full_product = mul_a * mul_b;
    wire [31:0] mul_result = (funct3 == 3'b000) ? full_product[31:0] : full_product[63:32];


    // =======================================================================
    // 2. ITERATIVE DIVIDER FSM (32 Cycles)
    // =======================================================================
    wire is_div = funct3[2]; // 1xx is DIV/REM family
    
    localparam S_IDLE = 2'b00, S_CALC = 2'b01, S_DONE = 2'b10;
    reg [1:0]  state = S_IDLE;
    reg [4:0]  counter = 5'd0;
    
    reg [31:0] quotient = 32'd0;
    reg [31:0] divisor = 32'd0;
    reg [32:0] remainder = 33'd0;
    reg invert_quotient = 1'b0;
    reg invert_remainder = 1'b0;
    reg is_rem = 1'b0;
    reg div_by_zero = 1'b0;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= S_IDLE;
            valid <= 1'b0;
            counter <= 5'd0;
            quotient <= 32'd0;
            divisor <= 32'd0;
            remainder <= 33'd0;
            invert_quotient <= 1'b0;
            invert_remainder <= 1'b0;
            is_rem <= 1'b0;
            div_by_zero <= 1'b0;
        end else begin
            valid <= 1'b0; // Default to 0, pulses in S_DONE

            case (state)
                S_IDLE: begin
                    // FIX: We use '!valid' instead of an edge detector.
                    // This prevents infinite loops but catches back-to-back instructions perfectly.
                    if (start && is_div && !valid) begin
                        is_rem      <= funct3[1];
                        div_by_zero <= (operand2 == 32'd0);
                        
                        if (funct3 == 3'b100 || funct3 == 3'b110) begin 
                            quotient         <= operand1[31] ? (~operand1 + 1) : operand1;
                            divisor          <= operand2[31] ? (~operand2 + 1) : operand2;
                            invert_quotient  <= operand1[31] ^ operand2[31];
                            invert_remainder <= operand1[31];
                        end else begin 
                            quotient         <= operand1;
                            divisor          <= operand2;
                            invert_quotient  <= 1'b0;
                            invert_remainder <= 1'b0;
                        end
                        
                        remainder <= 33'd0;
                        counter   <= 5'd31;
                        state     <= S_CALC;
                    end
                end

                S_CALC: begin
                    if ( {remainder[31:0], quotient[counter]} >= {1'b0, divisor} ) begin
                        remainder <= {remainder[31:0], quotient[counter]} - {1'b0, divisor};
                        quotient[counter] <= 1'b1;
                    end else begin
                        remainder <= {remainder[31:0], quotient[counter]};
                        quotient[counter] <= 1'b0;
                    end

                    if (counter == 5'd0) state <= S_DONE;
                    else                 counter <= counter - 1;
                end

                S_DONE: begin
                    if (div_by_zero) begin
                        quotient  <= 32'hFFFF_FFFF;
                        remainder <= {1'b0, operand1};
                    end else begin
                        if (invert_quotient)  quotient  <= ~quotient + 1;
                        if (invert_remainder) remainder <= ~(remainder) + 1;
                    end
                    
                    valid <= 1'b1;
                    state <= S_IDLE;
                end
            endcase
        end
    end

    // =======================================================================
    // 3. OUTPUT ROUTING (Combinational Stall Lock)
    // =======================================================================
    wire combinational_busy = (state == S_IDLE) && start && is_div && !valid;
    assign busy   = (state != S_IDLE) || combinational_busy;
    assign result = is_mul ? mul_result : (is_rem ? remainder[31:0] : quotient);

endmodule