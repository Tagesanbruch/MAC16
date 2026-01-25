`timescale 1ns/1ps
//============================================================================
// Experiment C: 4-Stage Deep Pipeline Multiplier
// 
// Architecture:
//   Stage 1: Register inputs + split operands
//   Stage 2: Compute 4 partial products (8x8 multiplications)
//   Stage 3: Combine partial products (carry-save)
//   Stage 4: Final addition
//
// Key optimization: Move the 8x8 multiplications to a separate pipeline stage
// to reduce combinational delay
//============================================================================
module mult16_4stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [15:0] a,
    input  logic [15:0] b,
    input  logic        valid_in,
    output logic [31:0] product,
    output logic        valid_out
);

    //=========================================================================
    // Stage 1: Register inputs and split operands
    //=========================================================================
    logic [7:0] a_lo_s1, a_hi_s1, b_lo_s1, b_hi_s1;
    logic valid_s1;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_lo_s1 <= '0;
            a_hi_s1 <= '0;
            b_lo_s1 <= '0;
            b_hi_s1 <= '0;
            valid_s1 <= 1'b0;
        end else begin
            a_lo_s1 <= a[7:0];
            a_hi_s1 <= a[15:8];
            b_lo_s1 <= b[7:0];
            b_hi_s1 <= b[15:8];
            valid_s1 <= valid_in;
        end
    end

    //=========================================================================
    // Stage 2: Compute 4 partial products (8x8 multiplications)
    // This is the critical stage - 8x8 multipliers
    //=========================================================================
    logic [15:0] pp_ll_s2, pp_lh_s2, pp_hl_s2, pp_hh_s2;
    logic valid_s2;
    
    // Compute partial products combinationally
    wire [15:0] pp_ll = a_lo_s1 * b_lo_s1;
    wire [15:0] pp_lh = a_lo_s1 * b_hi_s1;
    wire [15:0] pp_hl = a_hi_s1 * b_lo_s1;
    wire [15:0] pp_hh = a_hi_s1 * b_hi_s1;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pp_ll_s2 <= '0;
            pp_lh_s2 <= '0;
            pp_hl_s2 <= '0;
            pp_hh_s2 <= '0;
            valid_s2 <= 1'b0;
        end else begin
            pp_ll_s2 <= pp_ll;
            pp_lh_s2 <= pp_lh;
            pp_hl_s2 <= pp_hl;
            pp_hh_s2 <= pp_hh;
            valid_s2 <= valid_s1;
        end
    end

    //=========================================================================
    // Stage 3: Combine partial products (carry-save addition)
    //=========================================================================
    
    // Middle terms sum
    wire [16:0] mid_sum = {1'b0, pp_lh_s2} + {1'b0, pp_hl_s2};
    
    // Aligned partial products
    wire [31:0] aligned_hh = {pp_hh_s2, 16'b0};
    wire [31:0] aligned_mid = {7'b0, mid_sum, 8'b0};
    wire [31:0] aligned_ll = {16'b0, pp_ll_s2};
    
    logic [31:0] partial_sum_s3;
    logic [31:0] remaining_s3;
    logic valid_s3;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            partial_sum_s3 <= '0;
            remaining_s3 <= '0;
            valid_s3 <= 1'b0;
        end else begin
            partial_sum_s3 <= aligned_ll + aligned_mid;
            remaining_s3 <= aligned_hh;
            valid_s3 <= valid_s2;
        end
    end

    //=========================================================================
    // Stage 4: Final Addition
    //=========================================================================
    logic [31:0] product_s4;
    logic valid_s4;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            product_s4 <= '0;
            valid_s4 <= 1'b0;
        end else begin
            product_s4 <= partial_sum_s3 + remaining_s3;
            valid_s4 <= valid_s3;
        end
    end
    
    assign product = product_s4;
    assign valid_out = valid_s4;

endmodule
