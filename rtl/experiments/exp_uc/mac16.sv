`timescale 1ns/1ps
//============================================================================
// Experiment UC: MAC16 with Optimized VMA (PG Pre-computed)
// 
// Optimization: Move VMA's Generate/Propagate computation into MAC output stage.
// This reduces VMA combinational depth from 7 levels to 6 levels.
// 
// Architecture:
// - MAC Internal: 4 Stages (same as Exp_SD)
// - MAC Output: Compute G/P (1 level), register them
// - VMA: Only Prefix Tree + Sum (6 levels instead of 7)
// 
// Latency: 5 cycles (compatible with constraint ≤5)
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
    localparam ACC_WIDTH   = 40;

    localparam S_INPUT     = 2'd0;
    localparam S_MULT_WAIT = 2'd1;
    localparam S_OUTPUT    = 2'd2;

    logic [1:0] state;
    logic [4:0] cnt;
    logic [INPUT_BITS-1:0] shift_a, shift_b;
    
    // DCS Accumulator
    logic [ACC_WIDTH-1:0] acc_sum, acc_carry;
    logic [ACC_WIDTH-1:0] prev_sum, prev_carry;
    
    logic [OUTPUT_BITS-1:0] out_shift_reg;
    logic carry_reg;
    logic first_op;
    logic mode_r;

    // Multiplier interface
    logic [INPUT_BITS-1:0] mult_in_a, mult_in_b;
    logic mult_input_valid;
    logic [ACC_WIDTH-1:0] mult_result_sum, mult_result_carry;
    logic mult_valid_out;
    
    // Feedback logic
    logic [ACC_WIDTH-1:0] feedback_sum, feedback_carry;
    
    always_comb begin
        if (first_op) begin
            feedback_sum   = '0;
            feedback_carry = '0;
        end else if (mode_r == 1'b0) begin
            feedback_sum   = prev_sum;
            feedback_carry = prev_carry;
        end else begin
            feedback_sum   = acc_sum;
            feedback_carry = acc_carry;
        end
    end

    // DCS Multiplier (4 Stages, same as Exp_SD)
    mult16_booth_dcs u_mult (
        .clk(clk),
        .rst_n(rst_n),
        .a(mult_in_a),
        .b(mult_in_b),
        .valid_in(mult_input_valid),
        .acc_sum_in(feedback_sum),
        .acc_carry_in(feedback_carry),
        .result_sum(mult_result_sum),
        .result_carry(mult_result_carry),
        .valid_out(mult_valid_out)
    );
    
    // =========================================================================
    // VMA Optimization: Pre-compute G/P, register them
    // This reduces VMA critical path by 1 gate level
    // =========================================================================
    
    // Combinational: Compute G and P from mult result
    wire [ACC_WIDTH-1:0] vma_g_comb = mult_result_sum & mult_result_carry;
    wire [ACC_WIDTH-1:0] vma_p_comb = mult_result_sum ^ mult_result_carry;
    
    // Registered G and P (Pipeline Stage 5)
    logic [ACC_WIDTH-1:0] vma_g_reg, vma_p_reg;
    logic vma_valid;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vma_g_reg <= '0;
            vma_p_reg <= '0;
            vma_valid <= 1'b0;
        end else begin
            vma_valid <= mult_valid_out;
            if (mult_valid_out) begin
                vma_g_reg <= vma_g_comb;
                vma_p_reg <= vma_p_comb;
            end
        end
    end
    
    // Optimized VMA: Takes pre-computed G/P, only does prefix tree + sum
    wire [ACC_WIDTH-1:0] vma_result;
    wire vma_cout;
    vma_prefix_only #(.WIDTH(ACC_WIDTH)) u_vma (
        .g_in(vma_g_reg),
        .p_in(vma_p_reg),
        .sum(vma_result),
        .cout(vma_cout)
    );
    
    wire [OUTPUT_BITS-1:0] mac_result = vma_result[OUTPUT_BITS-1:0];
    wire vma_overflow = vma_result[OUTPUT_BITS];

    // Main Control Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_INPUT;
            cnt <= '0;
            shift_a <= '0;
            shift_b <= '0;
            mult_in_a <= '0;
            mult_in_b <= '0;
            mult_input_valid <= 1'b0;
            acc_sum <= '0;
            acc_carry <= '0;
            prev_sum <= '0;
            prev_carry <= '0;
            out_shift_reg <= '0;
            carry_reg <= 1'b0;
            first_op <= 1'b1;
            mode_r <= 1'b0;
            sum_out <= 1'b0;
            out_ready <= 1'b0;
        end else begin
            mult_input_valid <= 1'b0;
            
            // Feedback path driven by mult_valid_out (Latency 4)
            if (mult_valid_out) begin
                if (mode_r == 1'b0) begin
                    prev_sum   <= mult_result_sum;
                    prev_carry <= mult_result_carry;
                end else begin
                    acc_sum   <= mult_result_sum;
                    acc_carry <= mult_result_carry;
                end
            end
            
            case (state)
                S_INPUT: begin
                    out_ready <= 1'b0;
                    sum_out <= 1'b0;
                    mode_r <= mode;
                    shift_a <= {shift_a[INPUT_BITS-2:0], inA};
                    shift_b <= {shift_b[INPUT_BITS-2:0], inB};

                    if (cnt == INPUT_BITS - 1) begin
                        cnt <= '0;
                        state <= S_MULT_WAIT;
                        mult_in_a <= {shift_a[INPUT_BITS-2:0], inA};
                        mult_in_b <= {shift_b[INPUT_BITS-2:0], inB};
                        mult_input_valid <= 1'b1;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                S_MULT_WAIT: begin
                    // Output driven by vma_valid (Latency 5)
                    if (vma_valid) begin
                        out_shift_reg <= mac_result;
                        
                        if (!first_op && vma_overflow) begin
                            carry_reg <= 1'b1;
                        end
                        
                        first_op <= 1'b0;
                        out_ready <= 1'b1;
                        sum_out <= mac_result[OUTPUT_BITS-1];
                        state <= S_OUTPUT;
                    end
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
