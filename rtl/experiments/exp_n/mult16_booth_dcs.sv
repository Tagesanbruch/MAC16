`timescale 1ns/1ps
//============================================================================
// Experiment N: Double Carry-Save (DCS) Booth Multiplier
// 
// Key Innovation: Accumulator feedback is injected into the compressor tree
// - Accumulator stays in carry-save form (acc_sum + acc_carry)
// - No CPA in the MAC loop - only on final output
// - 10 inputs to compressor: 8 Booth PPs + 2 feedback vectors
//
// Pipeline Stages:
//   Stage 1: Booth Encoding
//   Stage 2: PPG + CSA Layer 1 (8 PPs → 6 rows)
//   Stage 3: CSA Layer 2 (6→4 rows) + Inject feedback (6→5 with fb)
//   Stage 4: 4:2 Compressor + Final CSA (6→2 rows)
//   Stage 5: Output (sum, carry) - NO CPA in loop!
//============================================================================
module mult16_booth_dcs (
    input  wire         clk,
    input  wire         rst_n,
    input  wire  [15:0] a,
    input  wire  [15:0] b,
    input  wire         valid_in,
    // Feedback from accumulator (carry-save form)
    input  wire  [39:0] acc_sum_in,
    input  wire  [39:0] acc_carry_in,
    // Output in carry-save form (NO CPA)
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
    // Stage 2: PPG + CSA Layer 1 (8 PPs → 6 rows)
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

    // Align partial products to 40 bits
    wire [39:0] pp_aligned0 = {{7{pp_w0[32]}}, pp_w0};
    wire [39:0] pp_aligned1 = {{5{pp_w1[32]}}, pp_w1, 2'b0};
    wire [39:0] pp_aligned2 = {{3{pp_w2[32]}}, pp_w2, 4'b0};
    wire [39:0] pp_aligned3 = {{1{pp_w3[32]}}, pp_w3, 6'b0};
    wire [39:0] pp_aligned4 = {pp_w4[30:0], 8'b0};
    wire [39:0] pp_aligned5 = {pp_w5[28:0], 10'b0};
    wire [39:0] pp_aligned6 = {pp_w6[26:0], 12'b0};
    wire [39:0] pp_aligned7 = {pp_w7[24:0], 14'b0};
    
    // CSA Layer 1: 8→6 rows
    wire [39:0] csa1_sum, csa1_carry;
    csa #(.WIDTH(40)) u_csa1 (
        .a(pp_aligned0),
        .b(pp_aligned1),
        .c(pp_aligned2),
        .sum(csa1_sum),
        .carry(csa1_carry)
    );
    
    wire [39:0] csa2_sum, csa2_carry;
    csa #(.WIDTH(40)) u_csa2 (
        .a(pp_aligned3),
        .b(pp_aligned4),
        .c(pp_aligned5),
        .sum(csa2_sum),
        .carry(csa2_carry)
    );
    
    // Pipeline register - Stage 2
    reg [39:0] row0_s2, row1_s2, row2_s2, row3_s2, row4_s2, row5_s2;
    reg [39:0] acc_sum_s2, acc_carry_s2;
    reg        valid_s2;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row0_s2 <= 40'b0;
            row1_s2 <= 40'b0;
            row2_s2 <= 40'b0;
            row3_s2 <= 40'b0;
            row4_s2 <= 40'b0;
            row5_s2 <= 40'b0;
            acc_sum_s2 <= 40'b0;
            acc_carry_s2 <= 40'b0;
            valid_s2 <= 1'b0;
        end else if (valid_s1) begin
            row0_s2 <= csa1_sum;
            row1_s2 <= {csa1_carry[38:0], 1'b0};
            row2_s2 <= csa2_sum;
            row3_s2 <= {csa2_carry[38:0], 1'b0};
            row4_s2 <= pp_aligned6;
            row5_s2 <= pp_aligned7;
            acc_sum_s2 <= acc_sum_s1;
            acc_carry_s2 <= acc_carry_s1;
            valid_s2 <= 1'b1;
        end else begin
            valid_s2 <= 1'b0;
        end
    end

    //=========================================================================
    // Stage 3: CSA Layer 2 (6→4 rows) + Inject Feedback (total 8→4)
    // Now we have 8 rows: 6 from PPs + 2 from accumulator feedback
    //=========================================================================
    // CSA3: row0 + row1 + row2 → sum3, carry3
    wire [39:0] csa3_sum, csa3_carry;
    csa #(.WIDTH(40)) u_csa3 (
        .a(row0_s2),
        .b(row1_s2),
        .c(row2_s2),
        .sum(csa3_sum),
        .carry(csa3_carry)
    );
    
    // CSA4: row3 + row4 + row5 → sum4, carry4
    wire [39:0] csa4_sum, csa4_carry;
    csa #(.WIDTH(40)) u_csa4 (
        .a(row3_s2),
        .b(row4_s2),
        .c(row5_s2),
        .sum(csa4_sum),
        .carry(csa4_carry)
    );
    
    // CSA5: acc_sum + acc_carry + sum3 → (inject feedback into stream)
    wire [39:0] csa5_sum, csa5_carry;
    csa #(.WIDTH(40)) u_csa5 (
        .a(acc_sum_s2),
        .b(acc_carry_s2),
        .c(csa3_sum),
        .sum(csa5_sum),
        .carry(csa5_carry)
    );
    
    // After Layer 2: 6 rows → {carry3, sum4, carry4, sum5, carry5, ?}
    // We need to continue compression
    
    // Pipeline register - Stage 3
    reg [39:0] row0_s3, row1_s3, row2_s3, row3_s3, row4_s3, row5_s3;
    reg        valid_s3;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row0_s3 <= 40'b0;
            row1_s3 <= 40'b0;
            row2_s3 <= 40'b0;
            row3_s3 <= 40'b0;
            row4_s3 <= 40'b0;
            row5_s3 <= 40'b0;
            valid_s3 <= 1'b0;
        end else if (valid_s2) begin
            row0_s3 <= csa5_sum;
            row1_s3 <= {csa5_carry[38:0], 1'b0};
            row2_s3 <= {csa3_carry[38:0], 1'b0};
            row3_s3 <= csa4_sum;
            row4_s3 <= {csa4_carry[38:0], 1'b0};
            row5_s3 <= 40'b0;  // Padding row
            valid_s3 <= 1'b1;
        end else begin
            valid_s3 <= 1'b0;
        end
    end

    //=========================================================================
    // Stage 4: Final Compression (5→2 rows using 4:2 + CSA)
    //=========================================================================
    // 4:2 Compressor: row0 + row1 + row2 + row3 → comp_sum, comp_carry
    wire [39:0] comp_sum, comp_carry;
    compressor_4to2_array #(.WIDTH(40)) u_comp42 (
        .a(row0_s3),
        .b(row1_s3),
        .c(row2_s3),
        .d(row3_s3),
        .sum(comp_sum),
        .carry(comp_carry)
    );
    
    // CSA6: comp_sum + comp_carry + row4 → final 2 vectors
    wire [39:0] csa6_sum, csa6_carry;
    csa #(.WIDTH(40)) u_csa6 (
        .a(comp_sum),
        .b({comp_carry[38:0], 1'b0}),
        .c(row4_s3),
        .sum(csa6_sum),
        .carry(csa6_carry)
    );
    
    // Pipeline register - Stage 4 (Output in carry-save form!)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result_sum   <= 40'b0;
            result_carry <= 40'b0;
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
