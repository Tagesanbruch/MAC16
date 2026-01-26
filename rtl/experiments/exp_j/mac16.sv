`timescale 1ns/1ps
//============================================================================
// Experiment J: Serial-Parallel Multiplier (Bit-Serial Architecture)
// 
// Key Innovation:
//   - No Booth encoder, no Wallace tree, no complex compression
//   - Collect all 16 bits first, then do bit-serial multiplication
//   - Uses carry-save accumulator to avoid long carry chains
//   - Extremely small area, very low power
//
// Architecture:
//   - Phase 1 (16 cycles): Collect A and B serially
//   - Phase 2 (16 cycles): Bit-serial multiply with CSA accumulator
//   - Phase 3 (1 cycle): Finalize + MAC accumulation  
//   - Phase 4 (24 cycles): Serial output
//
// Expected Benefits:
//   - Area: ~1/5 of parallel Booth multiplier
//   - Power: Potential to hit <100uW
//   - Timing: Simple paths, easy SS corner convergence
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
    localparam S_INPUT     = 3'd0;  // Receive serial input
    localparam S_MULTIPLY  = 3'd1;  // Bit-serial multiplication
    localparam S_FINALIZE  = 3'd2;  // Convert CS to binary, add accumulator
    localparam S_OUTPUT    = 3'd3;  // Serial output

    logic [2:0] state;
    logic [4:0] cnt;
    
    // Input registers
    logic [INPUT_BITS-1:0] reg_a, reg_b;
    logic [INPUT_BITS-1:0] shift_a, shift_b;
    
    // Serial-parallel multiplication accumulator (carry-save form)
    logic [31:0] mult_sum;
    logic [31:0] mult_carry;
    
    // Current bit position being processed
    logic [3:0] bit_pos;
    
    // Accumulator for MAC
    logic [23:0] accum;
    logic [23:0] prev_product;
    
    // Output
    logic [OUTPUT_BITS-1:0] out_shift_reg;
    logic carry_reg;
    logic first_op;
    logic mode_r;
    
    // Partial product for current bit (signed extension)
    logic [31:0] partial_product;
    logic [31:0] a_extended;
    
    // CSA signals
    logic [31:0] csa_in;
    logic [31:0] csa_sum_out, csa_carry_out;
    
    always_comb begin
        // Sign-extend A for signed multiplication
        a_extended = {{16{reg_a[15]}}, reg_a};
        
        // Generate partial product for current bit position
        // If B[bit_pos] is 1, PP = A << bit_pos, else PP = 0
        if (reg_b[bit_pos]) begin
            partial_product = a_extended << bit_pos;
        end else begin
            partial_product = 32'd0;
        end
        
        // Special handling for MSB of B (sign bit) in 2's complement
        // For signed multiplication: if B is negative, we need to subtract A << 15
        // This is handled by treating B[15] specially
        if (bit_pos == 4'd15 && reg_b[15]) begin
            // For the sign bit, we subtract instead of add
            // Subtract = add 2's complement = add (~A + 1)
            csa_in = ~(a_extended << 15) + 1;
        end else begin
            csa_in = partial_product;
        end
        
        // CSA: 3-input adder producing sum and carry
        csa_sum_out = mult_sum ^ mult_carry ^ csa_in;
        csa_carry_out = ((mult_sum & mult_carry) | 
                        (mult_carry & csa_in) | 
                        (mult_sum & csa_in)) << 1;
    end
    
    // Final result computation
    logic [31:0] mult_result;
    logic [23:0] mac_result;
    logic [24:0] add_result;
    
    always_comb begin
        // Convert carry-save to binary
        mult_result = mult_sum + mult_carry;
        
        // MAC result depends on mode
        if (mode_r == 1'b0) begin
            if (first_op) begin
                mac_result = mult_result[23:0];
                add_result = {1'b0, mult_result[23:0]};
            end else begin
                add_result = {1'b0, mult_result[23:0]} + {1'b0, prev_product};
                mac_result = add_result[23:0];
            end
        end else begin
            add_result = {1'b0, mult_result[23:0]} + {1'b0, accum};
            mac_result = add_result[23:0];
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_INPUT;
            cnt <= '0;
            shift_a <= '0;
            shift_b <= '0;
            reg_a <= '0;
            reg_b <= '0;
            bit_pos <= '0;
            mult_sum <= '0;
            mult_carry <= '0;
            accum <= '0;
            prev_product <= '0;
            out_shift_reg <= '0;
            carry_reg <= 1'b0;
            first_op <= 1'b1;
            mode_r <= 1'b0;
            sum_out <= 1'b0;
            out_ready <= 1'b0;
        end else begin
            case (state)
                S_INPUT: begin
                    out_ready <= 1'b0;
                    sum_out <= 1'b0;
                    mode_r <= mode;

                    // Shift in A and B (MSB first)
                    shift_a <= {shift_a[INPUT_BITS-2:0], inA};
                    shift_b <= {shift_b[INPUT_BITS-2:0], inB};

                    if (cnt == INPUT_BITS - 1) begin
                        cnt <= '0;
                        bit_pos <= '0;
                        // Latch complete inputs
                        reg_a <= {shift_a[INPUT_BITS-2:0], inA};
                        reg_b <= {shift_b[INPUT_BITS-2:0], inB};
                        // Reset multiply accumulator
                        mult_sum <= '0;
                        mult_carry <= '0;
                        state <= S_MULTIPLY;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                S_MULTIPLY: begin
                    // Bit-serial multiplication: process one bit per cycle
                    mult_sum <= csa_sum_out;
                    mult_carry <= csa_carry_out;
                    
                    if (bit_pos == INPUT_BITS - 1) begin
                        state <= S_FINALIZE;
                    end else begin
                        bit_pos <= bit_pos + 1;
                    end
                end

                S_FINALIZE: begin
                    // Compute final MAC result
                    out_shift_reg <= mac_result;
                    
                    if (mode_r == 1'b0) begin
                        prev_product <= mac_result;
                    end else begin
                        accum <= mac_result;
                    end
                    
                    // Check carry
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
