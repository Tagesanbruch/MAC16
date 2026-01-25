`timescale 1ns/1ps
//============================================================================
// Experiment F: Ultra-High-Speed Fused MAC with DCS + Kogge-Stone
// Yosys-compatible Verilog 2005
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
    input  wire         clk,
    input  wire         rst_n,
    input  wire         mode,       // 0: multiply only, 1: accumulate
    input  wire         clear,      // Clear accumulator
    input  wire  [15:0] inA,
    input  wire  [15:0] inB,
    input  wire         valid_in,
    output wire  [39:0] result_sum,
    output wire  [39:0] result_carry,
    output wire  [39:0] result_binary,
    output wire         valid_out
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
    reg [7:0]  neg_s1, zero_s1, two_s1;
    reg [15:0] a_s1;
    reg        valid_s1, mode_s1, clear_s1;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            neg_s1   <= 8'b0;
            zero_s1  <= 8'b0;
            two_s1   <= 8'b0;
            a_s1     <= 16'b0;
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
    wire [32:0] pp_s1_0, pp_s1_1, pp_s1_2, pp_s1_3, pp_s1_4, pp_s1_5, pp_s1_6, pp_s1_7;
    partial_product_gen u_ppg (
        .a(a_s1),
        .neg(neg_s1),
        .zero(zero_s1),
        .two(two_s1),
        .pp0(pp_s1_0),
        .pp1(pp_s1_1),
        .pp2(pp_s1_2),
        .pp3(pp_s1_3),
        .pp4(pp_s1_4),
        .pp5(pp_s1_5),
        .pp6(pp_s1_6),
        .pp7(pp_s1_7)
    );

    // Align partial products
    wire [39:0] pp_aligned0 = {{7{pp_s1_0[32]}}, pp_s1_0};
    wire [39:0] pp_aligned1 = {{5{pp_s1_1[32]}}, pp_s1_1, 2'b0};
    wire [39:0] pp_aligned2 = {{3{pp_s1_2[32]}}, pp_s1_2, 4'b0};
    wire [39:0] pp_aligned3 = {{1{pp_s1_3[32]}}, pp_s1_3, 6'b0};
    wire [39:0] pp_aligned4 = {pp_s1_4[30:0], 8'b0};
    wire [39:0] pp_aligned5 = {pp_s1_5[28:0], 10'b0};
    wire [39:0] pp_aligned6 = {pp_s1_6[26:0], 12'b0};
    wire [39:0] pp_aligned7 = {pp_s1_7[24:0], 14'b0};

    //========================================================================
    // Double Carry-Save Accumulator
    //========================================================================
    reg [39:0] acc_sum, acc_carry;
    
    wire [39:0] feedback_sum   = (mode_s1 && !clear_s1) ? acc_sum   : 40'd0;
    wire [39:0] feedback_carry = (mode_s1 && !clear_s1) ? acc_carry : 40'd0;

    //========================================================================
    // Stage 2: First Half Compression (10 -> 4)
    //========================================================================
    wire [39:0] l1_s0, l1_c0, l1_s1, l1_c1, l1_s2, l1_c2;
    
    csa #(.WIDTH(40)) u_l1_csa0 (
        .a(pp_aligned0),
        .b(pp_aligned1),
        .c(pp_aligned2),
        .sum(l1_s0),
        .carry(l1_c0)
    );
    
    csa #(.WIDTH(40)) u_l1_csa1 (
        .a(pp_aligned3),
        .b(pp_aligned4),
        .c(pp_aligned5),
        .sum(l1_s1),
        .carry(l1_c1)
    );
    
    csa #(.WIDTH(40)) u_l1_csa2 (
        .a(pp_aligned6),
        .b(pp_aligned7),
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
    reg [39:0] l2_s0_r, l2_c0_r, l2_s1_r, l2_c1_r, fb_carry_r;
    reg        valid_s2, mode_s2, clear_s2;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            l2_s0_r   <= 40'b0;
            l2_c0_r   <= 40'b0;
            l2_s1_r   <= 40'b0;
            l2_c1_r   <= 40'b0;
            fb_carry_r <= 40'b0;
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
    reg valid_s3;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_sum   <= 40'b0;
            acc_carry <= 40'b0;
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
