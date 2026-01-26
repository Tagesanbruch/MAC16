`timescale 1ns/1ps
//============================================================================
// Experiment H: Aggressive Operand Isolation + Clock Gating
// 
// Key Optimizations:
//   1. Operand isolation: Multiplier inputs only update once per 16 cycles
//   2. Fine-grained clock gating via explicit enable signals
//   3. Valid chain for all pipeline stages
//
// Expected Benefits:
//   - 80-90% dynamic power reduction (multiplier toggles 1/16 vs every cycle)
//   - Significant reduction in glitch power
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
    localparam S_MULT_STAGE1 = 3'd1;
    localparam S_MULT_STAGE2 = 3'd2;
    localparam S_MULT_STAGE3 = 3'd3;
    localparam S_ADD         = 3'd4;
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

    //=========================================================================
    // KEY OPTIMIZATION 1: Isolated Multiplier Inputs
    // These registers ONLY update when all 16 bits are received
    //=========================================================================
    logic [INPUT_BITS-1:0] mult_in_a, mult_in_b;
    logic mult_input_valid;  // Only high for ONE cycle when inputs are ready

    //=========================================================================
    // KEY OPTIMIZATION 2: Explicit Enable Signals for Clock Gating
    //=========================================================================
    logic shift_reg_en;      // Enable for shift registers
    logic mult_reg_en;       // Enable for multiplier result register
    logic accum_reg_en;      // Enable for accumulator
    logic output_reg_en;     // Enable for output shift register

    assign shift_reg_en = (state == S_INPUT);
    assign mult_reg_en = (state >= S_MULT_STAGE1 && state <= S_MULT_STAGE3);
    assign accum_reg_en = (state == S_ADD);
    assign output_reg_en = (state == S_ADD || state == S_OUTPUT);

    logic [31:0] mult_result;
    logic [31:0] mult_reg;
    logic [24:0] add_result;
    logic [23:0] mac_result;
    logic mult_valid_out;

    // Structural Booth multiplier with isolated inputs
    mult16_booth u_mult (
        .clk(clk),
        .rst_n(rst_n),
        .a(mult_in_a),       // ISOLATED: only changes once per operation
        .b(mult_in_b),       // ISOLATED: only changes once per operation
        .valid_in(mult_input_valid),
        .product(mult_result),
        .valid_out(mult_valid_out)
    );

    // Accumulation logic (combinational)
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

    //=========================================================================
    // Main State Machine with Explicit Enable Gating
    //=========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_INPUT;
            cnt <= '0;
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
            // Default: deassert one-shot signals
            mult_input_valid <= 1'b0;
            
            case (state)
                S_INPUT: begin
                    out_ready <= 1'b0;
                    sum_out <= 1'b0;
                    mode_r <= mode;

                    // Shift registers - enabled during INPUT state
                    if (shift_reg_en) begin
                        shift_a <= {shift_a[INPUT_BITS-2:0], inA};
                        shift_b <= {shift_b[INPUT_BITS-2:0], inB};
                    end

                    if (cnt == INPUT_BITS - 1) begin
                        cnt <= '0;
                        state <= S_MULT_STAGE1;
                        
                        // KEY: Latch inputs to isolated registers ONCE
                        mult_in_a <= {shift_a[INPUT_BITS-2:0], inA};
                        mult_in_b <= {shift_b[INPUT_BITS-2:0], inB};
                        mult_input_valid <= 1'b1;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                S_MULT_STAGE1: begin
                    state <= S_MULT_STAGE2;
                end

                S_MULT_STAGE2: begin
                    state <= S_MULT_STAGE3;
                end

                S_MULT_STAGE3: begin
                    if (mult_valid_out) begin
                        // Only update mult_reg when valid
                        if (mult_reg_en) begin
                            mult_reg <= mult_result;
                        end
                        state <= S_ADD;
                    end
                end

                S_ADD: begin
                    // Update accumulator/prev_product with enable gating
                    if (accum_reg_en) begin
                        out_shift_reg <= mac_result;

                        if (mode_r == 1'b0) begin
                            prev_product <= mac_result;
                        end else begin
                            accum <= mac_result;
                        end

                        if ((!first_op || mode_r == 1'b1) && add_result[OUTPUT_BITS]) begin
                            carry_reg <= 1'b1;
                        end
                    end

                    first_op <= 1'b0;
                    out_ready <= 1'b1;
                    sum_out <= mac_result[OUTPUT_BITS-1];
                    state <= S_OUTPUT;
                end

                S_OUTPUT: begin
                    // Output shift with enable
                    if (output_reg_en) begin
                        out_shift_reg <= {out_shift_reg[OUTPUT_BITS-2:0], 1'b0};
                    end
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
