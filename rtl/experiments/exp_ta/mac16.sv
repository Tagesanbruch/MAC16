`timescale 1ns/1ps
//============================================================================
// Experiment TA: DCS Booth Multiplier with CSA-only 6->2 Compression
//
// Variant based on exp_sd, replacing LLCBC (CSA+4:2) with CSA tree compression.
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

    logic [ACC_WIDTH-1:0] acc_sum;
    logic [ACC_WIDTH-1:0] acc_carry;

    logic [ACC_WIDTH-1:0] prev_sum;
    logic [ACC_WIDTH-1:0] prev_carry;

    logic [OUTPUT_BITS-1:0] out_shift_reg;
    logic carry_reg;
    logic first_op;
    logic mode_r;

    logic [INPUT_BITS-1:0] mult_in_a, mult_in_b;
    logic mult_input_valid;
    logic [ACC_WIDTH-1:0] mult_result_sum, mult_result_carry;
    logic mult_valid_out;

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

    wire [ACC_WIDTH-1:0] vma_result;
    wire vma_cout;
    spanning_tree_adder #(.WIDTH(ACC_WIDTH)) u_vma (
        .a(mult_result_sum),
        .b(mult_result_carry),
        .sum(vma_result),
        .cout(vma_cout)
    );
    wire [OUTPUT_BITS-1:0] mac_result = vma_result[OUTPUT_BITS-1:0];
    wire vma_overflow = vma_result[OUTPUT_BITS];

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
                        if (mode_r == 1'b0) begin
                            prev_sum   <= mult_result_sum;
                            prev_carry <= mult_result_carry;
                        end else begin
                            acc_sum   <= mult_result_sum;
                            acc_carry <= mult_result_carry;
                        end

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
