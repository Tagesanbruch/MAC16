`timescale 1ns/1ps
//============================================================================
// Experiment A: 3-Stage Pipeline Multiplier
// Description: Split multiplication into 3 stages for better timing
//   Stage 1: Register inputs
//   Stage 2: Partial product generation (lower half computation)
//   Stage 3: Upper half computation + final combination
//============================================================================
module mult16_pipeline_3stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [15:0] a,
    input  logic [15:0] b,
    input  logic        valid_in,
    output logic [31:0] product,
    output logic        valid_out
);

    //=========================================================================
    // Stage 1: Register inputs
    //=========================================================================
    logic [15:0] a_s1, b_s1;
    logic valid_s1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_s1 <= '0;
            b_s1 <= '0;
            valid_s1 <= 1'b0;
        end else begin
            a_s1 <= a;
            b_s1 <= b;
            valid_s1 <= valid_in;
        end
    end

    //=========================================================================
    // Stage 2: Split multiplication - compute partial products
    // Split each 16-bit operand into 8-bit high and low parts
    // a = aH * 2^8 + aL, b = bH * 2^8 + bL
    // a*b = aH*bH*2^16 + (aH*bL + aL*bH)*2^8 + aL*bL
    //=========================================================================
    logic [7:0] aH_s1, aL_s1, bH_s1, bL_s1;
    assign aH_s1 = a_s1[15:8];
    assign aL_s1 = a_s1[7:0];
    assign bH_s1 = b_s1[15:8];
    assign bL_s1 = b_s1[7:0];

    // Partial products (8x8 = 16 bits each)
    logic [15:0] pp_HH, pp_HL, pp_LH, pp_LL;
    
    // Stage 2 registers
    logic [15:0] pp_HH_s2, pp_HL_s2, pp_LH_s2, pp_LL_s2;
    logic valid_s2;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pp_HH_s2 <= '0;
            pp_HL_s2 <= '0;
            pp_LH_s2 <= '0;
            pp_LL_s2 <= '0;
            valid_s2 <= 1'b0;
        end else begin
            // Compute 4 partial products (8x8 multiplications)
            pp_HH_s2 <= aH_s1 * bH_s1;
            pp_HL_s2 <= aH_s1 * bL_s1;
            pp_LH_s2 <= aL_s1 * bH_s1;
            pp_LL_s2 <= aL_s1 * bL_s1;
            valid_s2 <= valid_s1;
        end
    end

    //=========================================================================
    // Stage 3: Combine partial products
    // result = pp_HH << 16 + (pp_HL + pp_LH) << 8 + pp_LL
    //=========================================================================
    logic [31:0] product_s3;
    logic valid_s3;

    // Intermediate sum for middle terms
    logic [16:0] mid_sum;  // 17 bits to handle overflow
    assign mid_sum = {1'b0, pp_HL_s2} + {1'b0, pp_LH_s2};

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            product_s3 <= '0;
            valid_s3 <= 1'b0;
        end else begin
            // Combine: HH<<16 + mid<<8 + LL
            product_s3 <= ({pp_HH_s2, 16'd0}) + 
                          ({7'd0, mid_sum, 8'd0}) + 
                          ({16'd0, pp_LL_s2});
            valid_s3 <= valid_s2;
        end
    end

    assign product = product_s3;
    assign valid_out = valid_s3;

endmodule
