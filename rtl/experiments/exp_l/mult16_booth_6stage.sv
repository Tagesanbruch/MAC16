`timescale 1ns/1ps
//============================================================================
// Experiment L: 6-Stage Deep Pipeline Booth Multiplier
// 
// Key Changes from Exp K:
//   1. Split Stage 5 (Final CPA) into two stages:
//      - Stage 5: CPA Part 1 (lower 20 bits)
//      - Stage 6: CPA Part 2 (upper 20 bits with carry-in)
//   2. This reduces the critical path of the 40-bit adder
//
// Pipeline Stages:
//   Stage 1: Booth Encoding
//   Stage 2: PPG + CSA Layer 1 (8→6 rows)
//   Stage 3: CSA Layer 2 (6→4 rows)  
//   Stage 4: 4:2 Compressor (4→2 rows)
//   Stage 5: CPA Part 1 (low bits)
//   Stage 6: CPA Part 2 (high bits) + Output
//
// Target: TT @ 1.3GHz+ for improved SS Corner performance
//============================================================================
module mult16_booth_6stage (
    input  wire         clk,
    input  wire         rst_n,
    input  wire  [15:0] a,
    input  wire  [15:0] b,
    input  wire         valid_in,
    output reg   [31:0] product,
    output reg          valid_out
);

    //=========================================================================
    // Stage 1: Booth Encoding
    //=========================================================================
    reg [7:0]  neg_s1, zero_s1, two_s1;
    reg        valid_s1;
    reg [15:0] a_s1;
    
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
            valid_s1 <= 1'b0;
        end else if (valid_in) begin
            neg_s1  <= neg_w;
            zero_s1 <= zero_w;
            two_s1  <= two_w;
            a_s1    <= a;
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

    wire [39:0] pp_aligned0 = {{7{pp_w0[32]}}, pp_w0};
    wire [39:0] pp_aligned1 = {{5{pp_w1[32]}}, pp_w1, 2'b0};
    wire [39:0] pp_aligned2 = {{3{pp_w2[32]}}, pp_w2, 4'b0};
    wire [39:0] pp_aligned3 = {{1{pp_w3[32]}}, pp_w3, 6'b0};
    wire [39:0] pp_aligned4 = {pp_w4[30:0], 8'b0};
    wire [39:0] pp_aligned5 = {pp_w5[28:0], 10'b0};
    wire [39:0] pp_aligned6 = {pp_w6[26:0], 12'b0};
    wire [39:0] pp_aligned7 = {pp_w7[24:0], 14'b0};
    
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
    
    reg [39:0] row0_s2, row1_s2, row2_s2, row3_s2, row4_s2, row5_s2;
    reg        valid_s2;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row0_s2 <= 40'b0;
            row1_s2 <= 40'b0;
            row2_s2 <= 40'b0;
            row3_s2 <= 40'b0;
            row4_s2 <= 40'b0;
            row5_s2 <= 40'b0;
            valid_s2 <= 1'b0;
        end else if (valid_s1) begin
            row0_s2 <= csa1_sum;
            row1_s2 <= {csa1_carry[38:0], 1'b0};
            row2_s2 <= csa2_sum;
            row3_s2 <= {csa2_carry[38:0], 1'b0};
            row4_s2 <= pp_aligned6;
            row5_s2 <= pp_aligned7;
            valid_s2 <= 1'b1;
        end else begin
            valid_s2 <= 1'b0;
        end
    end

    //=========================================================================
    // Stage 3: CSA Layer 2 (6→4 rows)
    //=========================================================================
    wire [39:0] csa3_sum, csa3_carry;
    csa #(.WIDTH(40)) u_csa3 (
        .a(row0_s2),
        .b(row1_s2),
        .c(row2_s2),
        .sum(csa3_sum),
        .carry(csa3_carry)
    );
    
    wire [39:0] csa4_sum, csa4_carry;
    csa #(.WIDTH(40)) u_csa4 (
        .a(row3_s2),
        .b(row4_s2),
        .c(row5_s2),
        .sum(csa4_sum),
        .carry(csa4_carry)
    );
    
    reg [39:0] row0_s3, row1_s3, row2_s3, row3_s3;
    reg        valid_s3;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row0_s3 <= 40'b0;
            row1_s3 <= 40'b0;
            row2_s3 <= 40'b0;
            row3_s3 <= 40'b0;
            valid_s3 <= 1'b0;
        end else if (valid_s2) begin
            row0_s3 <= csa3_sum;
            row1_s3 <= {csa3_carry[38:0], 1'b0};
            row2_s3 <= csa4_sum;
            row3_s3 <= {csa4_carry[38:0], 1'b0};
            valid_s3 <= 1'b1;
        end else begin
            valid_s3 <= 1'b0;
        end
    end

    //=========================================================================
    // Stage 4: 4:2 Compressor (4→2 rows)
    //=========================================================================
    wire [39:0] comp_sum, comp_carry;
    
    compressor_4to2_array #(.WIDTH(40)) u_comp42 (
        .a(row0_s3),
        .b(row1_s3),
        .c(row2_s3),
        .d(row3_s3),
        .sum(comp_sum),
        .carry(comp_carry)
    );
    
    reg [39:0] final_sum_s4, final_carry_s4;
    reg        valid_s4;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            final_sum_s4   <= 40'b0;
            final_carry_s4 <= 40'b0;
            valid_s4 <= 1'b0;
        end else if (valid_s3) begin
            final_sum_s4   <= comp_sum;
            final_carry_s4 <= {comp_carry[38:0], 1'b0};
            valid_s4 <= 1'b1;
        end else begin
            valid_s4 <= 1'b0;
        end
    end

    //=========================================================================
    // Stage 5: CPA Part 1 (Low 20 bits)
    //=========================================================================
    wire [20:0] low_add = {1'b0, final_sum_s4[19:0]} + {1'b0, final_carry_s4[19:0]};
    wire        carry_out_low = low_add[20];
    
    reg [19:0] product_low_s5;
    reg        carry_to_high_s5;
    reg [19:0] sum_high_s5, carry_high_s5;
    reg        valid_s5;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            product_low_s5   <= 20'b0;
            carry_to_high_s5 <= 1'b0;
            sum_high_s5      <= 20'b0;
            carry_high_s5    <= 20'b0;
            valid_s5         <= 1'b0;
        end else if (valid_s4) begin
            product_low_s5   <= low_add[19:0];
            carry_to_high_s5 <= carry_out_low;
            sum_high_s5      <= final_sum_s4[39:20];
            carry_high_s5    <= final_carry_s4[39:20];
            valid_s5         <= 1'b1;
        end else begin
            valid_s5 <= 1'b0;
        end
    end

    //=========================================================================
    // Stage 6: CPA Part 2 (High 20 bits) + Output
    //=========================================================================
    wire [20:0] high_add = {1'b0, sum_high_s5} + {1'b0, carry_high_s5} + {20'b0, carry_to_high_s5};
    wire [39:0] final_product = {high_add[19:0], product_low_s5};
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            product <= 32'b0;
            valid_out <= 1'b0;
        end else if (valid_s5) begin
            product <= final_product[31:0];
            valid_out <= 1'b1;
        end else begin
            valid_out <= 1'b0;
        end
    end

endmodule
