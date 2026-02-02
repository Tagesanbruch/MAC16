`timescale 1ns/1ps
//============================================================================
// Experiment SA: DCS Booth Multiplier with 5:2 Compressor (Stage4)
// 
// Optimization: Balanced Pipeline Stages
// - Stage 1: Booth Encoding (unchanged)
// - Stage 2: PPG Only (8 PPs registered). Logic depth: ~2 (MUX/XOR).
//             Moved CSA Layer 1 to Stage 3 to reduce S2 critical path.
// - Stage 3: CSA Layer 1 (8→6) + CSA Layer 2 (6→4) + Feedback.
//             Logic depth: 2 levels of CSA. Balanced with S2.
// - Stage 4: 5:2 Compressor (5→2) using CSA layers.
// - Stage 5: Output.
//
// Area Impact: S2 registers increase from 6 rows (240b) to 8 rows (320b).
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
    // Stage 2: PPG Only (8 PPs Generated and Registered)
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
    
    // Pipeline register - Stage 2 (Register 8 PPs directly)
    // Optimization: Retiming - moved CSA to next stage
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
    // Stage 3: CSA Layer 1 (8→6) + CSA Layer 2 (6→4) + Feedback (4+2=6)
    //=========================================================================
    
    // CSA Layer 1: 8->6
    wire [39:0] csa1_sum, csa1_carry;
    csa #(.WIDTH(40)) u_csa1 (
        .a(pp0_s2), .b(pp1_s2), .c(pp2_s2),
        .sum(csa1_sum), .carry(csa1_carry)
    );
    wire [39:0] csa2_sum, csa2_carry;
    csa #(.WIDTH(40)) u_csa2 (
        .a(pp3_s2), .b(pp4_s2), .c(pp5_s2),
        .sum(csa2_sum), .carry(csa2_carry)
    );
    // Rows after L1: csa1_s, csa1_c, csa2_s, csa2_c, pp6, pp7 (6 rows)
    
    // CSA Layer 2: 6->4
    wire [39:0] csa3_sum, csa3_carry;
    csa #(.WIDTH(40)) u_csa3 (
        .a(csa1_sum), 
        .b({csa1_carry[38:0], 1'b0}), 
        .c(csa2_sum),
        .sum(csa3_sum), 
        .carry(csa3_carry)
    );
    wire [39:0] csa4_sum, csa4_carry;
    csa #(.WIDTH(40)) u_csa4 (
        .a({csa2_carry[38:0], 1'b0}), 
        .b(pp6_s2), 
        .c(pp7_s2),
        .sum(csa4_sum), 
        .carry(csa4_carry)
    );
    // Rows after L2: csa3_s, csa3_c, csa4_s, csa4_c (4 rows)
    
    // Inject Feedback: We have 4 rows + 2 feedback = 6 rows total.
    // We can compress this to 4 rows using another CSA?
    // Or we register 6 rows? 
    // If we register 6 rows, S4 needs to reduce 6->2.
    // Exp_n S4 does: Comp4:2 (4->2) then CSA (3->2). 
    // Exp_n S4 input was 5 rows (fb already merged in S3).
    
    // Let's merge feedback here in S3: 
    // Inputs: csa3_s, csa3_c, csa4_s, csa4_c, acc_sum, acc_carry.
    // CSA5: acc_sum + acc_carry + csa3_s -> sum5, carry5
    wire [39:0] csa5_sum, csa5_carry;
    csa #(.WIDTH(40)) u_csa5 (
        .a(acc_sum_s2),
        .b(acc_carry_s2),
        .c(csa3_sum),
        .sum(csa5_sum), 
        .carry(csa5_carry)
    );
    
    // Outputs to register:
    // csa5_s, csa5_c, csa3_c, csa4_s, csa4_c. (5 rows).
    // Wait, csa3_s was used. csa3_c remains.
    
    // Pipeline register - Stage 3 (Register 5 rows)
    reg [39:0] row0_s3, row1_s3, row2_s3, row3_s3, row4_s3;
    reg        valid_s3;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row0_s3 <= 40'b0; row1_s3 <= 40'b0;
            row2_s3 <= 40'b0; row3_s3 <= 40'b0;
            row4_s3 <= 40'b0;
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
    // Stage 4: 5:2 Compressor (5→2)
    //=========================================================================
    wire [39:0] csa6_sum, csa6_carry;
    compressor_5to2_array #(.WIDTH(40)) u_comp52 (
        .a(row0_s3),
        .b(row1_s3),
        .c(row2_s3),
        .d(row3_s3),
        .e(row4_s3),
        .sum(csa6_sum),
        .carry(csa6_carry)
    );

    // Pipeline register - Stage 4 (Output)
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
