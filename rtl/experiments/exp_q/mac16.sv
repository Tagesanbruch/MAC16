`timescale 1ns/1ps
//============================================================================
// Experiment Q: MAC16 with 8-Stage Hyper-Pipeline
// 
// Key Innovation: VMA isolation inside 8-stage multiplier
// - Multiplier outputs BINARY result (not carry-save)
// - VMA computation is pipelined inside multiplier (Stage 7)
// - mac16 FSM simplified - no need for S_VMA state
//
// Pipeline latency: 8 cycles (multiplier)
// Total latency: 16 (input) + 8 (mult) + 24 (output) = 48 cycles
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

    // State machine (no S_VMA needed - VMA is inside multiplier)
    localparam S_INPUT     = 2'd0;
    localparam S_MULT_WAIT = 2'd1;
    localparam S_OUTPUT    = 2'd2;

    logic [1:0] state;
    
    logic [4:0] cnt;
    logic [INPUT_BITS-1:0] shift_a, shift_b;
    
    // Accumulator (kept in binary - VMA done inside mult)
    logic [ACC_WIDTH-1:0] acc;
    // Previous product for mode=0 
    logic [ACC_WIDTH-1:0] prev_product;
    
    logic [OUTPUT_BITS-1:0] out_shift_reg;
    logic carry_reg;
    logic first_op;
    logic mode_r;

    // Multiplier interface
    logic [INPUT_BITS-1:0] mult_in_a, mult_in_b;
    logic mult_input_valid;
    logic [ACC_WIDTH-1:0] mult_result;
    logic mult_valid_out;
    
    // Feedback to multiplier - need to convert binary back to CS for feedback
    // For simplicity, acc_sum = acc, acc_carry = 0
    wire [ACC_WIDTH-1:0] feedback_sum, feedback_carry;
    
    assign feedback_sum = first_op ? '0 : (mode_r ? acc : prev_product);
    assign feedback_carry = '0;

    // 8-Stage Hyper-Pipeline Multiplier with VMA inside
    mult16_booth_8stage u_mult (
        .clk(clk),
        .rst_n(rst_n),
        .a(mult_in_a),
        .b(mult_in_b),
        .valid_in(mult_input_valid),
        .acc_sum_in(feedback_sum),
        .acc_carry_in(feedback_carry),
        .result(mult_result),
        .valid_out(mult_valid_out)
    );
    
    // MAC result directly from multiplier (already in binary)
    wire [OUTPUT_BITS-1:0] mac_result = mult_result[OUTPUT_BITS-1:0];
    wire mac_overflow = mult_result[OUTPUT_BITS];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_INPUT;
            cnt <= '0;
            shift_a <= '0;
            shift_b <= '0;
            mult_in_a <= '0;
            mult_in_b <= '0;
            mult_input_valid <= 1'b0;
            acc <= '0;
            prev_product <= '0;
            out_shift_reg <= '0;
            carry_reg <= 1'b0;
            first_op <= 1'b1;
            mode_r <= 1'b0;
            sum_out <= 1'b0;
            out_ready <= 1'b0;
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
                        state <= S_MULT_WAIT;
                        
                        mult_in_a <= {shift_a[INPUT_BITS-2:0], inA};
                        mult_in_b <= {shift_b[INPUT_BITS-2:0], inB};
                        mult_input_valid <= 1'b1;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                S_MULT_WAIT: begin
                    if (mult_valid_out) begin
                        // Store results (binary form)
                        if (mode_r == 1'b0) begin
                            prev_product <= mult_result;
                        end else begin
                            acc <= mult_result;
                        end
                        
                        // Load output shift register directly
                        out_shift_reg <= mac_result;
                        
                        if (!first_op && mac_overflow) begin
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
