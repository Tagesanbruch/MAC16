`timescale 1ns/1ps
//============================================================================
// Experiment B: Radix-4 Booth Encoded Multiplier with Compression Tree
// Description:
//   - Radix-4 Modified Booth encoding (reduces partial products from 16 to 8)
//   - 4:2 Compressor based Wallace tree
//   - 3-stage pipeline for 1GHz timing
//   - Operand isolation for low power
// Target: 1GHz+ timing closure with power optimization
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

    // State machine
    localparam S_INPUT       = 3'd0;
    localparam S_MULT_STAGE1 = 3'd1;  // Booth encoding + partial product gen
    localparam S_MULT_STAGE2 = 3'd2;  // Compression tree
    localparam S_MULT_STAGE3 = 3'd3;  // Final addition
    localparam S_ADD         = 3'd4;  // Accumulation
    localparam S_OUTPUT      = 3'd5;

    logic [2:0] state;
    
    logic [4:0] cnt;
    logic [INPUT_BITS-1:0] shift_a, shift_b;
    logic [OUTPUT_BITS-1:0] accum;
    logic [OUTPUT_BITS-1:0] prev_product;
    logic [OUTPUT_BITS-1:0] out_shift_reg;
    logic carry_reg;
    logic first_op;
    logic mode_r;

    logic [31:0] mult_result;
    logic [31:0] mult_reg;
    logic [24:0] add_result;
    logic [23:0] mac_result;
    logic mult_valid_in, mult_valid_out;
    logic mult_enable;

    // Operand isolation control
    assign mult_enable = (state == S_INPUT && cnt == INPUT_BITS - 1) ||
                         (state == S_MULT_STAGE1) ||
                         (state == S_MULT_STAGE2) ||
                         (state == S_MULT_STAGE3);

    // Booth-encoded 3-stage pipeline multiplier
    mult16_booth u_mult (
        .clk(clk),
        .rst_n(rst_n),
        .a(mult_enable ? shift_a : 16'd0),
        .b(mult_enable ? shift_b : 16'd0),
        .valid_in(mult_valid_in),
        .product(mult_result),
        .valid_out(mult_valid_out)
    );

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
            shift_a <= '0;
            shift_b <= '0;
            accum <= '0;
            prev_product <= '0;
            out_shift_reg <= '0;
            carry_reg <= 1'b0;
            first_op <= 1'b1;
            mode_r <= 1'b0;
            sum_out <= 1'b0;
            out_ready <= 1'b0;
            mult_valid_in <= 1'b0;
            mult_reg <= '0;
        end else begin
            case (state)
                S_INPUT: begin
                    out_ready <= 1'b0;
                    sum_out <= 1'b0;
                    mode_r <= mode;
                    mult_valid_in <= 1'b0;

                    shift_a <= {shift_a[INPUT_BITS-2:0], inA};
                    shift_b <= {shift_b[INPUT_BITS-2:0], inB};

                    if (cnt == INPUT_BITS - 1) begin
                        cnt <= '0;
                        state <= S_MULT_STAGE1;
                        mult_valid_in <= 1'b1;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                S_MULT_STAGE1: begin
                    mult_valid_in <= 1'b0;
                    state <= S_MULT_STAGE2;
                end

                S_MULT_STAGE2: begin
                    state <= S_MULT_STAGE3;
                end

                S_MULT_STAGE3: begin
                    if (mult_valid_out) begin
                        mult_reg <= mult_result;
                        state <= S_ADD;
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
                    cnt <= '0;
                    state <= S_OUTPUT;
                end

                S_OUTPUT: begin
                    out_ready <= 1'b1;
                    sum_out <= out_shift_reg[OUTPUT_BITS-2];
                    out_shift_reg <= {out_shift_reg[OUTPUT_BITS-2:0], 1'b0};

                    if (cnt == OUTPUT_BITS - 2) begin
                        cnt <= '0;
                        out_ready <= 1'b0;
                        state <= S_INPUT;

                        if (mode != mode_r) begin
                            accum <= '0;
                            prev_product <= '0;
                            carry_reg <= 1'b0;
                            first_op <= 1'b1;
                        end
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
