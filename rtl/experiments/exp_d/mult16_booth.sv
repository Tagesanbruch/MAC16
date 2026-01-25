`timescale 1ns/1ps
//============================================================================
// Experiment D: Structural Booth Multiplier with Wallace Tree
// 
// Architecture:
//   - Radix-4 Booth encoding (16 PP -> 8 PP)
//   - Wallace tree compression (8:2)
//   - 3-stage pipeline for timing
//
// Pipeline stages:
//   Stage 1: Booth encode + Generate partial products
//   Stage 2: First level compression (8->4)  
//   Stage 3: Second level compression (4->2) + Final add
//============================================================================
module mult16_booth (
    input  wire         clk,
    input  wire         rst_n,
    input  wire  [15:0] a,
    input  wire  [15:0] b,
    input  wire         valid_in,
    output reg   [31:0] product,
    output reg          valid_out
);

    //=========================================================================
    // Stage 1: Booth Encoding + Partial Product Generation
    //=========================================================================
    reg [7:0]  neg_s1, zero_s1, two_s1;
    reg        valid_s1;
    reg [15:0] a_s1;
    
    // Booth encoder (combinational)
    wire [7:0]  neg_w, zero_w, two_w;
    booth_encoder u_booth (
        .b(b),
        .neg(neg_w),
        .zero(zero_w),
        .two(two_w)
    );
    
    // Pipeline register - Stage 1
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            neg_s1  <= 8'b0;
            zero_s1 <= 8'b0;
            two_s1  <= 8'b0;
            a_s1    <= 16'b0;
            valid_s1 <= 1'b0;
        end else begin
            neg_s1  <= neg_w;
            zero_s1 <= zero_w;
            two_s1  <= two_w;
            a_s1    <= a;
            valid_s1 <= valid_in;
        end
    end
    
    // Partial product generation (combinational, uses registered Booth signals)
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

    //=========================================================================
    // Stage 2: Align and First Level Compression (8->4)
    //=========================================================================
    // Align partial products to their correct bit positions
    // PP[i] should be shifted left by 2*i bits
    wire [39:0] pp_aligned0, pp_aligned1, pp_aligned2, pp_aligned3;
    wire [39:0] pp_aligned4, pp_aligned5, pp_aligned6, pp_aligned7;
    
    // Manual alignment for each partial product
    assign pp_aligned0 = {{7{pp_w0[32]}}, pp_w0};        // << 0
    assign pp_aligned1 = {{5{pp_w1[32]}}, pp_w1, 2'b0};  // << 2
    assign pp_aligned2 = {{3{pp_w2[32]}}, pp_w2, 4'b0};  // << 4
    assign pp_aligned3 = {{1{pp_w3[32]}}, pp_w3, 6'b0};  // << 6
    assign pp_aligned4 = {pp_w4[30:0], 8'b0};            // << 8  (truncate sign bits)
    assign pp_aligned5 = {pp_w5[28:0], 10'b0};           // << 10
    assign pp_aligned6 = {pp_w6[26:0], 12'b0};           // << 12
    assign pp_aligned7 = {pp_w7[24:0], 14'b0};           // << 14
    
    // First level CSA compression: 8 -> 6 -> 4
    wire [39:0] csa1_sum, csa1_carry;
    wire [39:0] csa2_sum, csa2_carry;
    wire [39:0] csa3_sum, csa3_carry;
    wire [39:0] csa4_sum, csa4_carry;
    
    // CSA tree level 1 (8->6)
    csa #(.WIDTH(40)) u_csa1 (
        .a(pp_aligned0),
        .b(pp_aligned1),
        .c(pp_aligned2),
        .sum(csa1_sum),
        .carry(csa1_carry)
    );
    
    csa #(.WIDTH(40)) u_csa2 (
        .a(pp_aligned3),
        .b(pp_aligned4),
        .c(pp_aligned5),
        .sum(csa2_sum),
        .carry(csa2_carry)
    );
    
    // CSA tree level 2 (6->4)
    csa #(.WIDTH(40)) u_csa3 (
        .a(csa1_sum),
        .b({csa1_carry[38:0], 1'b0}),  // Carry shifted left by 1
        .c(pp_aligned6),
        .sum(csa3_sum),
        .carry(csa3_carry)
    );
    
    csa #(.WIDTH(40)) u_csa4 (
        .a(csa2_sum),
        .b({csa2_carry[38:0], 1'b0}),
        .c(pp_aligned7),
        .sum(csa4_sum),
        .carry(csa4_carry)
    );
    
    // Pipeline register - Stage 2
    reg [39:0] row0_s2, row1_s2, row2_s2, row3_s2;
    reg        valid_s2;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row0_s2 <= 40'b0;
            row1_s2 <= 40'b0;
            row2_s2 <= 40'b0;
            row3_s2 <= 40'b0;
            valid_s2 <= 1'b0;
        end else begin
            row0_s2 <= csa3_sum;
            row1_s2 <= {csa3_carry[38:0], 1'b0};
            row2_s2 <= csa4_sum;
            row3_s2 <= {csa4_carry[38:0], 1'b0};
            valid_s2 <= valid_s1;
        end
    end

    //=========================================================================
    // Stage 3: Second Level Compression (4->2) + Final Addition
    //=========================================================================
    // 4:2 compression
    wire [39:0] comp_sum, comp_carry;
    
    compressor_4to2_array #(.WIDTH(40)) u_comp42 (
        .a(row0_s2),
        .b(row1_s2),
        .c(row2_s2),
        .d(row3_s2),
        .sum(comp_sum),
        .carry(comp_carry)
    );
    
    // Final addition
    wire [39:0] final_product = comp_sum + {comp_carry[38:0], 1'b0};
    
    // Pipeline register - Stage 3 (output)
    reg [31:0] product_s3;
    reg        valid_s3;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            product_s3 <= 32'b0;
            valid_s3 <= 1'b0;
        end else begin
            product_s3 <= final_product[31:0];
            valid_s3 <= valid_s2;
        end
    end
    
    assign product = product_s3;
    assign valid_out = valid_s3;

endmodule
