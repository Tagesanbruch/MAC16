`timescale 1ns/1ps
//============================================================================
// Experiment ND: 6-Stage High-Performance DCS Multiplier
// 
// Optimization: Split Critical Path in Exp NC's Stage 3
// - Exp NC Stage 3 had 3 logic levels: CSA1 -> CSA2 -> Feedback CSA.
// - Exp ND splits this into two stages:
//   - Stage 3: CSA Layer 1 Only (8->6 rows). Logic depth: 1 level.
//   - Stage 4: CSA Layer 2 (6->4) + Feedback (4+2->5). Logic depth: 2 levels.
//
// Pipeline Stages (Latency 5 internal cycles -> 5 cycles start-to-valid):
//   1. Booth Encoding (Reg)
//   2. PPG Only (Reg 8 PPs)
//   3. CSA Layer 1 (8->6) (Reg 6 rows)
//   4. CSA Layer 2 (6->4) + Feedback Merge (Reg 5 rows)
//   5. MUX Compressor + Final CSA (5->2) -> Output (Reg)
//
// Total Latency: meets "Input Done -> Output Start <= 5 cycles" constraint.
//   (Input Done at T, S1 at T+1, S2 at T+2, S3 at T+3, S4 at T+4, Output at T+5).
//   Wait, Exp NC was 4. So T+4. Exp ND is T+5.
//   Constraint says <= 5. So T+5 is ALLOWED.
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
    // Stage 1: Booth Encoding
    //=========================================================================
    reg [7:0]  neg_s1, zero_s1, two_s1;
    reg        valid_s1;
    reg [15:0] a_s1;
    reg [39:0] acc_sum_s1, acc_carry_s1;
    
    wire [7:0]  neg_w, zero_w, two_w;
    booth_encoder u_booth (
        .b(b),
        .neg(neg_w),
        .zero(zero_w),
        .two(two_w)
    );
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            neg_s1  <= 8'b0;
            zero_s1 <= 8'b0;
            two_s1  <= 8'b0;
            a_s1    <= 16'b0;
            acc_sum_s1 <= 40'b0;
            acc_carry_s1 <= 40'b0;
            valid_s1 <= 1'b0;
        end else if (valid_in) begin
            neg_s1  <= neg_w;
            zero_s1 <= zero_w;
            two_s1  <= two_w;
            a_s1    <= a;
            acc_sum_s1 <= acc_sum_in;
            acc_carry_s1 <= acc_carry_in;
            valid_s1 <= 1'b1;
        end else begin
            valid_s1 <= 1'b0;
        end
    end
    
    //=========================================================================
    // Stage 2: PPG Only (8 PPs via MUX/XOR)
    //=========================================================================
    wire [32:0] pp_w0, pp_w1, pp_w2, pp_w3, pp_w4, pp_w5, pp_w6, pp_w7;
    partial_product_gen u_ppg (
        .a(a_s1),
        .neg(neg_s1),
        .zero(zero_s1),
        .two(two_s1),
        .pp0(pp_w0),
        .pp1(pp_w1),
        .pp2(pp_w2),
        .pp3(pp_w3),
        .pp4(pp_w4),
        .pp5(pp_w5),
        .pp6(pp_w6),
        .pp7(pp_w7)
    );

    wire [39:0] pp_aligned0 = {{7{pp_w0[32]}}, pp_w0};
    wire [39:0] pp_aligned1 = {{5{pp_w1[32]}}, pp_w1, 2'b0};
    wire [39:0] pp_aligned2 = {{3{pp_w2[32]}}, pp_w2, 4'b0};
    wire [39:0] pp_aligned3 = {{1{pp_w3[32]}}, pp_w3, 6'b0};
    wire [39:0] pp_aligned4 = {pp_w4[30:0], 8'b0};
    wire [39:0] pp_aligned5 = {pp_w5[28:0], 10'b0};
    wire [39:0] pp_aligned6 = {pp_w6[26:0], 12'b0};
    wire [39:0] pp_aligned7 = {pp_w7[24:0], 14'b0};
    
    // Pipeline register - Stage 2
    reg [39:0] pp0_s2, pp1_s2, pp2_s2, pp3_s2, pp4_s2, pp5_s2, pp6_s2, pp7_s2;
    reg [39:0] acc_sum_s2, acc_carry_s2;
    reg        valid_s2;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pp0_s2 <= 40'b0; pp1_s2 <= 40'b0; pp2_s2 <= 40'b0; pp3_s2 <= 40'b0;
            pp4_s2 <= 40'b0; pp5_s2 <= 40'b0; pp6_s2 <= 40'b0; pp7_s2 <= 40'b0;
            acc_sum_s2 <= 40'b0;
            acc_carry_s2 <= 40'b0;
            valid_s2 <= 1'b0;
        end else if (valid_s1) begin
            pp0_s2 <= pp_aligned0;
            pp1_s2 <= pp_aligned1;
            pp2_s2 <= pp_aligned2;
            pp3_s2 <= pp_aligned3;
            pp4_s2 <= pp_aligned4;
            pp5_s2 <= pp_aligned5;
            pp6_s2 <= pp_aligned6;
            pp7_s2 <= pp_aligned7;
            acc_sum_s2 <= acc_sum_s1;
            acc_carry_s2 <= acc_carry_s1;
            valid_s2 <= 1'b1;
        end else begin
            valid_s2 <= 1'b0;
        end
    end
    
    //=========================================================================
    // Stage 3: CSA Layer 1 Only (8->6)
    //=========================================================================
    // CSA 1: row0/1/2 -> sum, carry
    wire [39:0] csa1_sum, csa1_carry;
    csa #(.WIDTH(40)) u_csa1 (
        .a(pp0_s2), .b(pp1_s2), .c(pp2_s2),
        .sum(csa1_sum), .carry(csa1_carry)
    );
    // CSA 2: row3/4/5 -> sum, carry
    wire [39:0] csa2_sum, csa2_carry;
    csa #(.WIDTH(40)) u_csa2 (
        .a(pp3_s2), .b(pp4_s2), .c(pp5_s2),
        .sum(csa2_sum), .carry(csa2_carry)
    );
    // Result: csa1_s, csa1_c, csa2_s, csa2_c, pp6, pp7. (6 rows)
    
    // Pipeline register - Stage 3 (Register 6 rows + Feedback)
    reg [39:0] r0_s3, r1_s3, r2_s3, r3_s3, r4_s3, r5_s3;
    reg [39:0] acc_sum_s3, acc_carry_s3;
    reg        valid_s3;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r0_s3 <= 40'b0; r1_s3 <= 40'b0;
            r2_s3 <= 40'b0; r3_s3 <= 40'b0;
            r4_s3 <= 40'b0; r5_s3 <= 40'b0;
            acc_sum_s3 <= 40'b0;
            acc_carry_s3 <= 40'b0;
            valid_s3 <= 1'b0;
        end else if (valid_s2) begin
            r0_s3 <= csa1_sum;
            r1_s3 <= {csa1_carry[38:0], 1'b0};
            r2_s3 <= csa2_sum;
            r3_s3 <= {csa2_carry[38:0], 1'b0};
            r4_s3 <= pp6_s2;
            r5_s3 <= pp7_s2;
            acc_sum_s3 <= acc_sum_s2;
            acc_carry_s3 <= acc_carry_s2;
            valid_s3 <= 1'b1;
        end else begin
            valid_s3 <= 1'b0;
        end
    end
    
    //=========================================================================
    // Stage 4: CSA Layer 2 (6->4) + Feedback Merge (4+2->5)
    //=========================================================================
    // CSA 3: r0/1/2 -> sum, carry (reduce 6->4 part 1)
    wire [39:0] csa3_sum, csa3_carry;
    csa #(.WIDTH(40)) u_csa3 (
        .a(r0_s3), .b(r1_s3), .c(r2_s3),
        .sum(csa3_sum), .carry(csa3_carry)
    );
    // CSA 4: r3/4/5 -> sum, carry (reduce 6->4 part 2)
    wire [39:0] csa4_sum, csa4_carry;
    csa #(.WIDTH(40)) u_csa4 (
        .a(r3_s3), .b(r4_s3), .c(r5_s3),
        .sum(csa4_sum), .carry(csa4_carry)
    );
    // Rows: csa3_s, csa3_c, csa4_s, csa4_c (4 rows).
    
    // Merge Feedback: acc_sum, acc_carry + csa3_s (uses CSA5)
    wire [39:0] csa5_sum, csa5_carry;
    csa #(.WIDTH(40)) u_csa5 (
        .a(acc_sum_s3), .b(acc_carry_s3), .c(csa3_sum),
        .sum(csa5_sum), .carry(csa5_carry)
    );
    // Result rows: csa5_s, csa5_c, csa3_c, csa4_s, csa4_c. (5 rows).
    
    // Pipeline register - Stage 4 (Register 5 rows)
    reg [39:0] r0_s4, r1_s4, r2_s4, r3_s4, r4_s4;
    reg        valid_s4;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r0_s4 <= 40'b0; r1_s4 <= 40'b0;
            r2_s4 <= 40'b0; r3_s4 <= 40'b0;
            r4_s4 <= 40'b0;
            valid_s4 <= 1'b0;
        end else if (valid_s3) begin
            r0_s4 <= csa5_sum;
            r1_s4 <= {csa5_carry[38:0], 1'b0};
            r2_s4 <= {csa3_carry[38:0], 1'b0};
            r3_s4 <= csa4_sum;
            r4_s4 <= {csa4_carry[38:0], 1'b0};
            valid_s4 <= 1'b1;
        end else begin
            valid_s4 <= 1'b0;
        end
    end
    
    //=========================================================================
    // Stage 5: MUX Compressor + Final CSA (5->2) -> Output
    //=========================================================================
    // MUX Comp: r0..r3 -> sum, carry
    wire [39:0] comp_sum, comp_carry;
    compressor_4to2_mux_array #(.WIDTH(40)) u_comp42 (
        .a(r0_s4), .b(r1_s4), .c(r2_s4), .d(r3_s4),
        .sum(comp_sum), .carry(comp_carry)
    );
    
    // CSA 6: comp_s/c + r4 -> sum, carry
    wire [39:0] csa6_sum, csa6_carry;
    csa #(.WIDTH(40)) u_csa6 (
        .a(comp_sum), .b({comp_carry[38:0], 1'b0}), .c(r4_s4),
        .sum(csa6_sum), .carry(csa6_carry)
    );

    // Pipeline register - Stage 5 (Output)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result_sum   <= 40'b0;
            result_carry <= 40'b0;
            valid_out    <= 1'b0;
        end else if (valid_s4) begin
            result_sum   <= csa6_sum;
            result_carry <= {csa6_carry[38:0], 1'b0};
            valid_out    <= 1'b1;
        end else begin
            valid_out    <= 1'b0;
        end
    end

endmodule
