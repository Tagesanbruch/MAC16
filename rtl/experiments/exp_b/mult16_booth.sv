`timescale 1ns/1ps
//============================================================================
// High-Performance 3-Stage Pipeline Multiplier
// 
// Architecture:
//   Stage 1: Split operands + compute 4 partial products (8x8)
//   Stage 2: Combine partial products using carry-save
//   Stage 3: Final addition
//
// This uses 4-way decomposition which is simpler than Booth but equally
// efficient for synthesis tools to optimize.
//
// a * b = (a_hi * 2^8 + a_lo) * (b_hi * 2^8 + b_lo)
//       = a_hi*b_hi*2^16 + (a_hi*b_lo + a_lo*b_hi)*2^8 + a_lo*b_lo
//============================================================================
module mult16_booth (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [15:0] a,      // Multiplicand (unsigned)
    input  logic [15:0] b,      // Multiplier (unsigned)
    input  logic        valid_in,
    output logic [31:0] product,
    output logic        valid_out
);

    //=========================================================================
    // Stage 1: Compute 4 partial products (8x8 multiplications)
    //=========================================================================
    
    // Split operands into 8-bit parts
    wire [7:0] a_lo = a[7:0];
    wire [7:0] a_hi = a[15:8];
    wire [7:0] b_lo = b[7:0];
    wire [7:0] b_hi = b[15:8];
    
    // Compute 4 partial products
    wire [15:0] pp_ll = a_lo * b_lo;  // a[7:0] * b[7:0]     -> bits [15:0]
    wire [15:0] pp_lh = a_lo * b_hi;  // a[7:0] * b[15:8]    -> bits [23:8]
    wire [15:0] pp_hl = a_hi * b_lo;  // a[15:8] * b[7:0]    -> bits [23:8]
    wire [15:0] pp_hh = a_hi * b_hi;  // a[15:8] * b[15:8]   -> bits [31:16]
    
    // Pipeline register for stage 1
    logic [15:0] pp_ll_s1, pp_lh_s1, pp_hl_s1, pp_hh_s1;
    logic valid_s1;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pp_ll_s1 <= '0;
            pp_lh_s1 <= '0;
            pp_hl_s1 <= '0;
            pp_hh_s1 <= '0;
            valid_s1 <= 1'b0;
        end else begin
            pp_ll_s1 <= pp_ll;
            pp_lh_s1 <= pp_lh;
            pp_hl_s1 <= pp_hl;
            pp_hh_s1 <= pp_hh;
            valid_s1 <= valid_in;
        end
    end

    //=========================================================================
    // Stage 2: Combine partial products
    // 
    // Alignment:
    //   pp_hh:  [31:16]  -> {pp_hh, 16'b0}
    //   pp_lh:  [23:8]   -> {8'b0, pp_lh, 8'b0}
    //   pp_hl:  [23:8]   -> {8'b0, pp_hl, 8'b0}
    //   pp_ll:  [15:0]   -> {16'b0, pp_ll}
    //
    // Use carry-save addition for middle terms
    //=========================================================================
    
    // Middle terms sum (with overflow handling)
    wire [16:0] mid_sum = {1'b0, pp_lh_s1} + {1'b0, pp_hl_s1};
    
    // Aligned partial products
    wire [31:0] aligned_hh = {pp_hh_s1, 16'b0};
    wire [31:0] aligned_mid = {7'b0, mid_sum, 8'b0};  // mid_sum is 17 bits, shifted by 8
    wire [31:0] aligned_ll = {16'b0, pp_ll_s1};
    
    // Stage 2: Sum two of them, leave one for stage 3
    logic [31:0] partial_sum_s2;
    logic [31:0] remaining_s2;
    logic valid_s2;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            partial_sum_s2 <= '0;
            remaining_s2 <= '0;
            valid_s2 <= 1'b0;
        end else begin
            // Add ll and mid first (they overlap more)
            partial_sum_s2 <= aligned_ll + aligned_mid;
            remaining_s2 <= aligned_hh;
            valid_s2 <= valid_s1;
        end
    end

    //=========================================================================
    // Stage 3: Final Addition
    //=========================================================================
    logic [31:0] product_s3;
    logic valid_s3;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            product_s3 <= '0;
            valid_s3 <= 1'b0;
        end else begin
            product_s3 <= partial_sum_s2 + remaining_s2;
            valid_s3 <= valid_s2;
        end
    end
    
    assign product = product_s3;
    assign valid_out = valid_s3;

endmodule
