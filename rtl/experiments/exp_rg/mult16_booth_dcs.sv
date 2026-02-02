`timescale 1ns/1ps
//============================================================================
// Experiment RG: Strict Balanced 5-Stage Split-Booth Architecture
// 
// IMPORTANT: This module implements 4 INTERNAL cycles.
// The 5th cycle (VMA) is in mac16.sv
//
// Architecture Requirements:
// - S1: Booth Encoding → Register Booth signals + A/2A
// - S2: PPG MUX + CSA L1 (8→4) → Register 4 vectors (NOT 6! NOT 8!)
// - S3: CSA L2 (4→2) + Feedback (4+2=6→2) → Register Sum/Carry
// - S4: Buffer / VMA prep → Register (pass through for timing isolation)
// - S5: VMA (in mac16.sv, NOT in this module)
//
// mult16 internal latency: 4 cycles (S1→S2→S3→S4)
// Total MAC latency: 5 cycles (with mac16's VMA)
//============================================================================
module mult16_booth_dcs (
    input  wire         clk,
    input  wire         rst_n,
    input  wire  [15:0] a,
    input  wire  [15:0] b,
    input  wire         valid_in,
    input  wire  [39:0] acc_sum_in,
    input  wire  [39:0] acc_carry_in,
    output reg   [39:0] result_sum,
    output reg   [39:0] result_carry,
    output reg          valid_out
);

    //=========================================================================
    // STAGE 1: Booth Encoding ONLY
    // Logic depth: ~4 gates (XOR, AND, OR for Booth decode)
    // Register: neg[7:0], zero[7:0], two[7:0], a_ext, a_2x, acc_sum, acc_carry
    //=========================================================================
    
    wire [16:0] b_ext = {b, 1'b0};
    
    wire [7:0] neg_comb, zero_comb, two_comb;
    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : booth_gen
            wire [2:0] group = b_ext[2*i+2 : 2*i];
            assign neg_comb[i]  = group[2];
            assign zero_comb[i] = (group == 3'b000) || (group == 3'b111);
            assign two_comb[i]  = (group == 3'b011) || (group == 3'b100);
        end
    endgenerate
    
    reg [7:0]  neg_s1, zero_s1, two_s1;
    reg [16:0] a_ext_s1;
    reg [17:0] a_2x_s1;
    reg [39:0] acc_sum_s1, acc_carry_s1;
    reg        valid_s1;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            neg_s1 <= 8'b0; zero_s1 <= 8'b0; two_s1 <= 8'b0;
            a_ext_s1 <= 17'b0; a_2x_s1 <= 18'b0;
            acc_sum_s1 <= 40'b0; acc_carry_s1 <= 40'b0;
            valid_s1 <= 1'b0;
        end else if (valid_in) begin
            neg_s1  <= neg_comb;
            zero_s1 <= zero_comb;
            two_s1  <= two_comb;
            a_ext_s1 <= {a[15], a};
            a_2x_s1  <= {a[15], a, 1'b0};
            acc_sum_s1 <= acc_sum_in;
            acc_carry_s1 <= acc_carry_in;
            valid_s1 <= 1'b1;
        end else begin
            valid_s1 <= 1'b0;
        end
    end
    
    //=========================================================================
    // STAGE 2: PPG MUX + CSA L1 (8→4)
    // Logic depth: ~6 gates (MUX ~3 + CSA ~2-3)
    // CRITICAL: Register ONLY 4 vectors, NOT 6 or 8!
    // Compression: (pp0,pp1,pp2) → (s1,c1), (pp3,pp4,pp5) → (s2,c2)
    //              (pp6,pp7,s1) → (s3,c3), (c1,s2,c2) → (s4,c4)
    // Final: 4 vectors = s3, c3, s4, c4
    //=========================================================================
    
    function [32:0] gen_pp;
        input [17:0] a_2x_in;
        input [16:0] a_ext_in;
        input neg_in, zero_in, two_in;
        reg [17:0] a_sel, a_neg, a_final;
        begin
            a_sel = two_in ? a_2x_in : {a_ext_in[16], a_ext_in};
            a_neg = neg_in ? (~a_sel + 1'b1) : a_sel;
            a_final = zero_in ? 18'd0 : a_neg;
            gen_pp = {{15{a_final[17]}}, a_final};
        end
    endfunction
    
    wire [32:0] pp_w0 = gen_pp(a_2x_s1, a_ext_s1, neg_s1[0], zero_s1[0], two_s1[0]);
    wire [32:0] pp_w1 = gen_pp(a_2x_s1, a_ext_s1, neg_s1[1], zero_s1[1], two_s1[1]);
    wire [32:0] pp_w2 = gen_pp(a_2x_s1, a_ext_s1, neg_s1[2], zero_s1[2], two_s1[2]);
    wire [32:0] pp_w3 = gen_pp(a_2x_s1, a_ext_s1, neg_s1[3], zero_s1[3], two_s1[3]);
    wire [32:0] pp_w4 = gen_pp(a_2x_s1, a_ext_s1, neg_s1[4], zero_s1[4], two_s1[4]);
    wire [32:0] pp_w5 = gen_pp(a_2x_s1, a_ext_s1, neg_s1[5], zero_s1[5], two_s1[5]);
    wire [32:0] pp_w6 = gen_pp(a_2x_s1, a_ext_s1, neg_s1[6], zero_s1[6], two_s1[6]);
    wire [32:0] pp_w7 = gen_pp(a_2x_s1, a_ext_s1, neg_s1[7], zero_s1[7], two_s1[7]);
    
    wire [39:0] pp0 = {{7{pp_w0[32]}}, pp_w0};
    wire [39:0] pp1 = {{5{pp_w1[32]}}, pp_w1, 2'b0};
    wire [39:0] pp2 = {{3{pp_w2[32]}}, pp_w2, 4'b0};
    wire [39:0] pp3 = {{1{pp_w3[32]}}, pp_w3, 6'b0};
    wire [39:0] pp4 = {pp_w4[30:0], 8'b0};
    wire [39:0] pp5 = {pp_w5[28:0], 10'b0};
    wire [39:0] pp6 = {pp_w6[26:0], 12'b0};
    wire [39:0] pp7 = {pp_w7[24:0], 14'b0};
    
    // CSA Layer 1a: (pp0, pp1, pp2) → (s1, c1)
    wire [39:0] s1, c1;
    csa #(.WIDTH(40)) u_csa1 (.a(pp0), .b(pp1), .c(pp2), .sum(s1), .carry(c1));
    
    // CSA Layer 1b: (pp3, pp4, pp5) → (s2, c2)
    wire [39:0] s2, c2;
    csa #(.WIDTH(40)) u_csa2 (.a(pp3), .b(pp4), .c(pp5), .sum(s2), .carry(c2));
    
    // CSA Layer 2a: (pp6, pp7, s1) → (s3, c3)
    wire [39:0] s3, c3;
    csa #(.WIDTH(40)) u_csa3 (.a(pp6), .b(pp7), .c(s1), .sum(s3), .carry(c3));
    
    // CSA Layer 2b: (c1<<1, s2, c2<<1) → (s4, c4)
    wire [39:0] s4, c4;
    csa #(.WIDTH(40)) u_csa4 (.a({c1[38:0], 1'b0}), .b(s2), .c({c2[38:0], 1'b0}), .sum(s4), .carry(c4));
    
    // S2 Registers: ONLY 4 vectors (160 bits) + acc (80 bits) = 240 bits
    reg [39:0] vec0_s2, vec1_s2, vec2_s2, vec3_s2;
    reg [39:0] acc_sum_s2, acc_carry_s2;
    reg        valid_s2;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vec0_s2 <= 40'b0; vec1_s2 <= 40'b0; vec2_s2 <= 40'b0; vec3_s2 <= 40'b0;
            acc_sum_s2 <= 40'b0; acc_carry_s2 <= 40'b0;
            valid_s2 <= 1'b0;
        end else if (valid_s1) begin
            vec0_s2 <= s3;
            vec1_s2 <= {c3[38:0], 1'b0};
            vec2_s2 <= s4;
            vec3_s2 <= {c4[38:0], 1'b0};
            acc_sum_s2 <= acc_sum_s1;
            acc_carry_s2 <= acc_carry_s1;
            valid_s2 <= 1'b1;
        end else begin
            valid_s2 <= 1'b0;
        end
    end
    
    //=========================================================================
    // STAGE 3: CSA (4→2) + Feedback Injection (6 inputs → 2 outputs)
    // Input: 4 vectors from S2 + 2 feedback = 6 total
    // Logic depth: ~6 gates (3 CSA layers)
    // Register: Sum_S3, Carry_S3
    //=========================================================================
    
    // CSA 3a: (vec0, vec1, vec2) → (s5, c5)
    wire [39:0] s5, c5;
    csa #(.WIDTH(40)) u_csa5 (.a(vec0_s2), .b(vec1_s2), .c(vec2_s2), .sum(s5), .carry(c5));
    
    // CSA 3b: (vec3, acc_sum, acc_carry) → (s6, c6)
    wire [39:0] s6, c6;
    csa #(.WIDTH(40)) u_csa6 (.a(vec3_s2), .b(acc_sum_s2), .c(acc_carry_s2), .sum(s6), .carry(c6));
    
    // CSA 3c: (s5, c5<<1, s6) → (s7, c7)
    wire [39:0] s7, c7;
    csa #(.WIDTH(40)) u_csa7 (.a(s5), .b({c5[38:0], 1'b0}), .c(s6), .sum(s7), .carry(c7));
    
    // CSA 3d: (c6<<1, s7, c7<<1) → Final (sum_s3, carry_s3)
    wire [39:0] sum_s3_comb, carry_s3_comb;
    csa #(.WIDTH(40)) u_csa8 (.a({c6[38:0], 1'b0}), .b(s7), .c({c7[38:0], 1'b0}), .sum(sum_s3_comb), .carry(carry_s3_comb));
    
    // S3 Registers
    reg [39:0] sum_s3, carry_s3;
    reg        valid_s3;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sum_s3 <= 40'b0; carry_s3 <= 40'b0;
            valid_s3 <= 1'b0;
        end else if (valid_s2) begin
            sum_s3 <= sum_s3_comb;
            carry_s3 <= {carry_s3_comb[38:0], 1'b0};
            valid_s3 <= 1'b1;
        end else begin
            valid_s3 <= 1'b0;
        end
    end
    
    //=========================================================================
    // STAGE 4: Buffer / VMA Prep (Timing Isolation Stage)
    // Logic: Direct pass-through (provides setup margin for VMA in mac16)
    // This stage exists purely for timing isolation between compression and VMA
    //=========================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result_sum <= 40'b0; result_carry <= 40'b0;
            valid_out <= 1'b0;
        end else if (valid_s3) begin
            result_sum <= sum_s3;
            result_carry <= carry_s3;
            valid_out <= 1'b1;
        end else begin
            valid_out <= 1'b0;
        end
    end

endmodule
