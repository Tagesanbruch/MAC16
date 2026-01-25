`timescale 1ns/1ps
//============================================================================
// Experiment F: Ultra-High-Speed Fused MAC with DCS + Kogge-Stone
// 
// Improvements over Exp E:
//   1. Kogge-Stone parallel prefix adder for final output
//   2. Additional pipeline register in compression tree
//   3. Optimized critical path balancing
//
// Pipeline Structure:
//   Stage 1: Booth encode + PP generation
//   Stage 2: First half compression (10->4)
//   Stage 3: Second half compression (4->2) + DCS update
//   Output:  Kogge-Stone adder (not in loop)
//
// Target: 1.5 GHz
//============================================================================
module mac16_fused_ks (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        mode,       // 0: multiply only, 1: accumulate
    input  logic        clear,      // Clear accumulator
    input  logic [15:0] inA,
    input  logic [15:0] inB,
    input  logic        valid_in,
    output logic [39:0] result_sum,
    output logic [39:0] result_carry,
    output logic [39:0] result_binary,
    output logic        valid_out
);

    //========================================================================
    // Stage 1: Booth Encoding + Partial Product Generation
    //========================================================================
    wire [7:0] neg, zero, two;
    booth_encoder u_booth (
        .b(inB),
        .neg(neg),
        .zero(zero),
        .two(two)
    );

    // Pipeline register S1
    logic [7:0]  neg_s1, zero_s1, two_s1;
    logic [15:0] a_s1;
    logic        valid_s1, mode_s1, clear_s1;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            neg_s1   <= '0;
            zero_s1  <= '0;
            two_s1   <= '0;
            a_s1     <= '0;
            valid_s1 <= 1'b0;
            mode_s1  <= 1'b0;
            clear_s1 <= 1'b0;
        end else begin
            neg_s1   <= neg;
            zero_s1  <= zero;
            two_s1   <= two;
            a_s1     <= inA;
            valid_s1 <= valid_in;
            mode_s1  <= mode;
            clear_s1 <= clear;
        end
    end

    // Partial product generation
    wire [32:0] pp_s1 [0:7];
    partial_product_gen u_ppg (
        .a(a_s1),
        .neg(neg_s1),
        .zero(zero_s1),
        .two(two_s1),
        .pp(pp_s1)
    );

    // Align partial products
    wire [39:0] pp_aligned [0:7];
    assign pp_aligned[0] = {{7{pp_s1[0][32]}}, pp_s1[0]};
    assign pp_aligned[1] = {{5{pp_s1[1][32]}}, pp_s1[1], 2'b0};
    assign pp_aligned[2] = {{3{pp_s1[2][32]}}, pp_s1[2], 4'b0};
    assign pp_aligned[3] = {{1{pp_s1[3][32]}}, pp_s1[3], 6'b0};
    assign pp_aligned[4] = {pp_s1[4][30:0], 8'b0};
    assign pp_aligned[5] = {pp_s1[5][28:0], 10'b0};
    assign pp_aligned[6] = {pp_s1[6][26:0], 12'b0};
    assign pp_aligned[7] = {pp_s1[7][24:0], 14'b0};

    //========================================================================
    // Double Carry-Save Accumulator
    //========================================================================
    logic [39:0] acc_sum, acc_carry;
    
    wire [39:0] feedback_sum   = (mode_s1 && !clear_s1) ? acc_sum   : 40'd0;
    wire [39:0] feedback_carry = (mode_s1 && !clear_s1) ? acc_carry : 40'd0;

    //========================================================================
    // Stage 2: First Half Compression (10 -> 4)
    //========================================================================
    wire [39:0] l1_s0, l1_c0, l1_s1, l1_c1, l1_s2, l1_c2;
    
    csa #(.WIDTH(40)) u_l1_csa0 (
        .a(pp_aligned[0]),
        .b(pp_aligned[1]),
        .c(pp_aligned[2]),
        .sum(l1_s0),
        .carry(l1_c0)
    );
    
    csa #(.WIDTH(40)) u_l1_csa1 (
        .a(pp_aligned[3]),
        .b(pp_aligned[4]),
        .c(pp_aligned[5]),
        .sum(l1_s1),
        .carry(l1_c1)
    );
    
    csa #(.WIDTH(40)) u_l1_csa2 (
        .a(pp_aligned[6]),
        .b(pp_aligned[7]),
        .c(feedback_sum),
        .sum(l1_s2),
        .carry(l1_c2)
    );

    // Level 2: 7 -> 5
    wire [39:0] l2_s0, l2_c0, l2_s1, l2_c1;
    
    csa #(.WIDTH(40)) u_l2_csa0 (
        .a(l1_s0),
        .b({l1_c0[38:0], 1'b0}),
        .c(l1_s1),
        .sum(l2_s0),
        .carry(l2_c0)
    );
    
    csa #(.WIDTH(40)) u_l2_csa1 (
        .a({l1_c1[38:0], 1'b0}),
        .b(l1_s2),
        .c({l1_c2[38:0], 1'b0}),
        .sum(l2_s1),
        .carry(l2_c1)
    );

    // Pipeline register S2 (mid-compression)
    logic [39:0] l2_s0_r, l2_c0_r, l2_s1_r, l2_c1_r, fb_carry_r;
    logic        valid_s2, mode_s2, clear_s2;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            l2_s0_r   <= '0;
            l2_c0_r   <= '0;
            l2_s1_r   <= '0;
            l2_c1_r   <= '0;
            fb_carry_r <= '0;
            valid_s2  <= 1'b0;
            mode_s2   <= 1'b0;
            clear_s2  <= 1'b0;
        end else begin
            l2_s0_r   <= l2_s0;
            l2_c0_r   <= {l2_c0[38:0], 1'b0};
            l2_s1_r   <= l2_s1;
            l2_c1_r   <= {l2_c1[38:0], 1'b0};
            fb_carry_r <= feedback_carry;
            valid_s2  <= valid_s1;
            mode_s2   <= mode_s1;
            clear_s2  <= clear_s1;
        end
    end

    //========================================================================
    // Stage 3: Second Half Compression (5 -> 2)
    //========================================================================
    wire [39:0] l3_s0, l3_c0;
    
    csa #(.WIDTH(40)) u_l3_csa0 (
        .a(l2_s0_r),
        .b(l2_c0_r),
        .c(l2_s1_r),
        .sum(l3_s0),
        .carry(l3_c0)
    );

    // 4:2 compressor for final compression
    wire [39:0] final_sum_w, final_carry_w;
    
    compressor_4to2_array #(.WIDTH(40)) u_final_comp (
        .a(l3_s0),
        .b({l3_c0[38:0], 1'b0}),
        .c(l2_c1_r),
        .d(fb_carry_r),
        .sum(final_sum_w),
        .carry(final_carry_w)
    );

    // Pipeline register S3 / Accumulator update
    logic valid_s3;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_sum   <= '0;
            acc_carry <= '0;
            valid_s3  <= 1'b0;
        end else if (valid_s2) begin
            // When clear_s2=1, feedback was already zeroed, so this stores
            // just the multiplication result (not accumulated)
            acc_sum   <= final_sum_w;
            acc_carry <= {final_carry_w[38:0], 1'b0};
            valid_s3  <= 1'b1;
        end else begin
            valid_s3  <= 1'b0;
        end
    end

    //========================================================================
    // Output: Kogge-Stone Adder (NOT in critical loop!)
    //========================================================================
    wire [39:0] ks_sum;
    wire        ks_cout;
    
    kogge_stone_40bit u_ks_adder (
        .a(acc_sum),
        .b(acc_carry),
        .sum(ks_sum),
        .cout(ks_cout)
    );

    assign result_sum    = acc_sum;
    assign result_carry  = acc_carry;
    assign result_binary = ks_sum;
    assign valid_out     = valid_s3;

endmodule
