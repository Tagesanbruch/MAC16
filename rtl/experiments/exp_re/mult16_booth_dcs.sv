`timescale 1ns/1ps
//============================================================================
// Experiment RE: True 5-Stage Split-Booth Architecture
// 
// Key Optimization: Register Booth signals in S1, PPG in S2
// This properly splits the 11-gate-level PPG critical path into:
//   - Stage 1: Booth Encoding (~4 levels) → Register Booth signals
//   - Stage 2: MUX-based PPG only (~4 levels) → Register 8 PPs
//   - Stage 3: CSA Layer 1+2 + Feedback → Register
//   - Stage 4: 4:2 Compressor + Final CSA → Output
//
// Total Latency: 5 cycles (mult: 4 + VMA: 1 in mac16)
// But internal mult16 is 4 cycles from valid_in to valid_out
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
    // Stage 1: Booth Encoding ONLY → Register Control Signals + A/2A
    // This stage is very light: just Booth decode (~4 gate levels)
    //=========================================================================
    
    wire [16:0] b_ext = {b, 1'b0};
    
    // Combinational Booth encoding (very simple logic)
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
    
    // S1 Registers: Booth control signals + A/2A
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
    // Stage 2: PPG MUX ONLY → Register 8 Aligned Partial Products
    // This stage: MUX select + sign extend (~4 gate levels)
    // NO CSA in this stage!
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
    
    wire [39:0] pp_aligned0 = {{7{pp_w0[32]}}, pp_w0};
    wire [39:0] pp_aligned1 = {{5{pp_w1[32]}}, pp_w1, 2'b0};
    wire [39:0] pp_aligned2 = {{3{pp_w2[32]}}, pp_w2, 4'b0};
    wire [39:0] pp_aligned3 = {{1{pp_w3[32]}}, pp_w3, 6'b0};
    wire [39:0] pp_aligned4 = {pp_w4[30:0], 8'b0};
    wire [39:0] pp_aligned5 = {pp_w5[28:0], 10'b0};
    wire [39:0] pp_aligned6 = {pp_w6[26:0], 12'b0};
    wire [39:0] pp_aligned7 = {pp_w7[24:0], 14'b0};
    
    // S2 Registers: 8 aligned Partial Products + Accumulator
    reg [39:0] pp0_s2, pp1_s2, pp2_s2, pp3_s2, pp4_s2, pp5_s2, pp6_s2, pp7_s2;
    reg [39:0] acc_sum_s2, acc_carry_s2;
    reg        valid_s2;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pp0_s2 <= 40'b0; pp1_s2 <= 40'b0; pp2_s2 <= 40'b0; pp3_s2 <= 40'b0;
            pp4_s2 <= 40'b0; pp5_s2 <= 40'b0; pp6_s2 <= 40'b0; pp7_s2 <= 40'b0;
            acc_sum_s2 <= 40'b0; acc_carry_s2 <= 40'b0;
            valid_s2 <= 1'b0;
        end else if (valid_s1) begin
            pp0_s2 <= pp_aligned0; pp1_s2 <= pp_aligned1;
            pp2_s2 <= pp_aligned2; pp3_s2 <= pp_aligned3;
            pp4_s2 <= pp_aligned4; pp5_s2 <= pp_aligned5;
            pp6_s2 <= pp_aligned6; pp7_s2 <= pp_aligned7;
            acc_sum_s2 <= acc_sum_s1;
            acc_carry_s2 <= acc_carry_s1;
            valid_s2 <= 1'b1;
        end else begin
            valid_s2 <= 1'b0;
        end
    end
    
    //=========================================================================
    // Stage 3: CSA Layer 1 (8→6) + CSA Layer 2 (6→4) + Feedback
    // This is the heavy compression stage
    //=========================================================================
    
    // CSA Layer 1: 8 → 6
    wire [39:0] csa1_sum, csa1_carry;
    csa #(.WIDTH(40)) u_csa1 (.a(pp0_s2), .b(pp1_s2), .c(pp2_s2), .sum(csa1_sum), .carry(csa1_carry));
    wire [39:0] csa2_sum, csa2_carry;
    csa #(.WIDTH(40)) u_csa2 (.a(pp3_s2), .b(pp4_s2), .c(pp5_s2), .sum(csa2_sum), .carry(csa2_carry));
    
    // CSA Layer 2: 6 → 4
    wire [39:0] csa3_sum, csa3_carry;
    csa #(.WIDTH(40)) u_csa3 (.a(csa1_sum), .b({csa1_carry[38:0], 1'b0}), .c(csa2_sum), .sum(csa3_sum), .carry(csa3_carry));
    wire [39:0] csa4_sum, csa4_carry;
    csa #(.WIDTH(40)) u_csa4 (.a({csa2_carry[38:0], 1'b0}), .b(pp6_s2), .c(pp7_s2), .sum(csa4_sum), .carry(csa4_carry));
    
    // Feedback Injection
    wire [39:0] csa5_sum, csa5_carry;
    csa #(.WIDTH(40)) u_csa5 (.a(acc_sum_s2), .b(acc_carry_s2), .c(csa3_sum), .sum(csa5_sum), .carry(csa5_carry));
    
    // S3 Registers: 5 rows for final compression
    reg [39:0] row0_s3, row1_s3, row2_s3, row3_s3, row4_s3;
    reg        valid_s3;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row0_s3 <= 40'b0; row1_s3 <= 40'b0; row2_s3 <= 40'b0;
            row3_s3 <= 40'b0; row4_s3 <= 40'b0;
            valid_s3 <= 1'b0;
        end else if (valid_s2) begin
            row0_s3 <= csa5_sum;
            row1_s3 <= {csa5_carry[38:0], 1'b0};
            row2_s3 <= {csa3_carry[38:0], 1'b0};
            row3_s3 <= csa4_sum;
            row4_s3 <= {csa4_carry[38:0], 1'b0};
            valid_s3 <= 1'b1;
        end else begin
            valid_s3 <= 1'b0;
        end
    end
    
    //=========================================================================
    // Stage 4: 4:2 Compressor + Final CSA (5→2) → Output
    //=========================================================================
    
    wire [39:0] comp_sum, comp_carry;
    compressor_4to2_mux_array #(.WIDTH(40)) u_comp42 (
        .a(row0_s3), .b(row1_s3), .c(row2_s3), .d(row3_s3),
        .sum(comp_sum), .carry(comp_carry)
    );
    
    wire [39:0] csa6_sum, csa6_carry;
    csa #(.WIDTH(40)) u_csa6 (
        .a(comp_sum), .b({comp_carry[38:0], 1'b0}), .c(row4_s3),
        .sum(csa6_sum), .carry(csa6_carry)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result_sum <= 40'b0; result_carry <= 40'b0;
            valid_out <= 1'b0;
        end else if (valid_s3) begin
            result_sum   <= csa6_sum;
            result_carry <= {csa6_carry[38:0], 1'b0};
            valid_out <= 1'b1;
        end else begin
            valid_out <= 1'b0;
        end
    end

endmodule
