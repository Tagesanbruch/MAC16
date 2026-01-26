`timescale 1ns/1ps
//============================================================================
// Experiment K: MAC16 with 5-Stage Deep Pipeline Multiplier
// 
// Key Changes from Exp I:
//   1. Multiplier latency: 3 stages → 5 stages
//   2. Added S_MULT_STAGE4 and S_MULT_STAGE5 states
//   3. Target: SS Corner @ 1GHz (TT @ ~1.5GHz)
//
// Pipeline latency: 5 cycles for multiplication
// Total latency: 16 (input) + 5 (mult) + 1 (add) = 22 cycles < 24 cycles limit
//============================================================================
module mac16 (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        mode,
    input  logic        inA,
    input  logic        inB,
    output logic        sum_out,
    output logic        carry,
    output logic        out_ready
);

    localparam INPUT_BITS  = 16;
    localparam OUTPUT_BITS = 24;

    // State machine - now with 5 multiply stages
    localparam S_INPUT       = 3'd0;
    localparam S_MULT_WAIT   = 3'd1;  // Wait for 5-stage pipeline
    localparam S_ADD         = 3'd2;
    localparam S_OUTPUT      = 3'd3;

    logic [2:0] state;
    
    logic [4:0] cnt;
    logic [2:0] mult_wait_cnt;  // Counter for 5 pipeline stages
    logic [INPUT_BITS-1:0] shift_a, shift_b;
    logic [OUTPUT_BITS-1:0] accum;
    logic [OUTPUT_BITS-1:0] prev_product;
    logic [OUTPUT_BITS-1:0] out_shift_reg;
    logic carry_reg;
    logic first_op;
    logic mode_r;

    // Isolated multiplier inputs
    logic [INPUT_BITS-1:0] mult_in_a, mult_in_b;
    logic mult_input_valid;

    logic [31:0] mult_result;
    logic [31:0] mult_reg;
    logic [24:0] add_result;
    logic [23:0] mac_result;
    logic mult_valid_out;

    // 5-Stage Deep Pipeline Booth multiplier
    mult16_booth_5stage u_mult (
        .clk(clk),
        .rst_n(rst_n),
        .a(mult_in_a),
        .b(mult_in_b),
        .valid_in(mult_input_valid),
        .product(mult_result),
        .valid_out(mult_valid_out)
    );

    // Accumulation logic
    always_comb begin
        if (mode_r == 1'b0) begin
            add_result = {1'b0, mult_reg[23:0]} + {1'b0, prev_product};
        end else begin
            add_result = {1'b0, mult_reg[23:0]} + {1'b0, accum};
        end
        
        if (first_op && mode_r == 1'b0) begin
            mac_result = mult_reg[23:0];
        end else begin
            mac_result = add_result[23:0];
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_INPUT;
            cnt <= '0;
            mult_wait_cnt <= '0;
            shift_a <= '0;
            shift_b <= '0;
            mult_in_a <= '0;
            mult_in_b <= '0;
            mult_input_valid <= 1'b0;
            accum <= '0;
            prev_product <= '0;
            out_shift_reg <= '0;
            carry_reg <= 1'b0;
            first_op <= 1'b1;
            mode_r <= 1'b0;
            sum_out <= 1'b0;
            out_ready <= 1'b0;
            mult_reg <= '0;
        end else begin
            mult_input_valid <= 1'b0;
            
            case (state)
                S_INPUT: begin
                    out_ready <= 1'b0;
                    sum_out <= 1'b0;
                    mode_r <= mode;

                    shift_a <= {shift_a[INPUT_BITS-2:0], inA};
                    shift_b <= {shift_b[INPUT_BITS-2:0], inB};

                    if (cnt == INPUT_BITS - 1) begin
                        cnt <= '0;
                        mult_wait_cnt <= '0;
                        state <= S_MULT_WAIT;
                        
                        // Latch isolated inputs ONCE
                        mult_in_a <= {shift_a[INPUT_BITS-2:0], inA};
                        mult_in_b <= {shift_b[INPUT_BITS-2:0], inB};
                        mult_input_valid <= 1'b1;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                S_MULT_WAIT: begin
                    // Wait for 5-stage pipeline to complete
                    // Or use valid_out signal
                    if (mult_valid_out) begin
                        mult_reg <= mult_result;
                        state <= S_ADD;
                    end else begin
                        mult_wait_cnt <= mult_wait_cnt + 1'b1;
                    end
                end

                S_ADD: begin
                    out_shift_reg <= mac_result;

                    if (mode_r == 1'b0) begin
                        prev_product <= mac_result;
                    end else begin
                        accum <= mac_result;
                    end

                    if ((!first_op || mode_r == 1'b1) && add_result[OUTPUT_BITS]) begin
                        carry_reg <= 1'b1;
                    end

                    first_op <= 1'b0;
                    out_ready <= 1'b1;
                    sum_out <= mac_result[OUTPUT_BITS-1];
                    state <= S_OUTPUT;
                end

                S_OUTPUT: begin
                    out_shift_reg <= {out_shift_reg[OUTPUT_BITS-2:0], 1'b0};
                    sum_out <= out_shift_reg[OUTPUT_BITS-2];

                    if (cnt == OUTPUT_BITS - 2) begin
                        cnt <= '0;
                        state <= S_INPUT;
                        shift_a <= '0;
                        shift_b <= '0;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                default: state <= S_INPUT;
            endcase
        end
    end

    assign carry = carry_reg;

endmodule
