`timescale 1ns/1ps
//============================================================================
// Experiment Q: 8-Stage Hyper-Pipeline Booth Multiplier with VMA Isolation
// 
// Key Innovation: VMA (Vector Merging Adder) isolated in dedicated stage
// - Stage 1: Booth Encoding
// - Stage 2: PPG (Partial Product Generation)
// - Stage 3: CSA Layer 1 (8→6 rows)
// - Stage 4: CSA Layer 2 (6→4 rows)
// - Stage 5: 4:2 Compressor (4→2 rows)
// - Stage 6: Final Compressor with feedback merge (4→2 rows)
// - Stage 7: VMA (Carry-Save to Binary conversion) [NEW]
// - Stage 8: Output register [NEW]
//
// Target: Minimal logic depth per stage for maximum SS corner frequency
//============================================================================
module mult16_booth_8stage (
    input  wire         clk,
    input  wire         rst_n,
    input  wire  [15:0] a,
    input  wire  [15:0] b,
    input  wire         valid_in,
    // Feedback from accumulator (carry-save form)
    input  wire  [39:0] acc_sum_in,
    input  wire  [39:0] acc_carry_in,
    // Output in BINARY form (VMA done inside!)
    output reg   [39:0] result,
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
    // Stage 2: PPG (Partial Product Generation)
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
    // Stage 3: CSA Layer 1 (8→6 rows)
    //=========================================================================
    wire [39:0] csa1_sum, csa1_carry;
    csa #(.WIDTH(40)) u_csa1 (
        .a(pp0_s2),
        .b(pp1_s2),
        .c(pp2_s2),
        .sum(csa1_sum),
        .carry(csa1_carry)
    );
    
    wire [39:0] csa2_sum, csa2_carry;
    csa #(.WIDTH(40)) u_csa2 (
        .a(pp3_s2),
        .b(pp4_s2),
        .c(pp5_s2),
        .sum(csa2_sum),
        .carry(csa2_carry)
    );
    
    reg [39:0] row0_s3, row1_s3, row2_s3, row3_s3, row4_s3, row5_s3;
    reg [39:0] acc_sum_s3, acc_carry_s3;
    reg        valid_s3;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row0_s3 <= 40'b0; row1_s3 <= 40'b0;
            row2_s3 <= 40'b0; row3_s3 <= 40'b0;
            row4_s3 <= 40'b0; row5_s3 <= 40'b0;
            acc_sum_s3 <= 40'b0;
            acc_carry_s3 <= 40'b0;
            valid_s3 <= 1'b0;
        end else if (valid_s2) begin
            row0_s3 <= csa1_sum;
            row1_s3 <= {csa1_carry[38:0], 1'b0};
            row2_s3 <= csa2_sum;
            row3_s3 <= {csa2_carry[38:0], 1'b0};
            row4_s3 <= pp6_s2;
            row5_s3 <= pp7_s2;
            acc_sum_s3 <= acc_sum_s2;
            acc_carry_s3 <= acc_carry_s2;
            valid_s3 <= 1'b1;
        end else begin
            valid_s3 <= 1'b0;
        end
    end

    //=========================================================================
    // Stage 4: CSA Layer 2 (6→4 rows)
    //=========================================================================
    wire [39:0] csa3_sum, csa3_carry;
    csa #(.WIDTH(40)) u_csa3 (
        .a(row0_s3),
        .b(row1_s3),
        .c(row2_s3),
        .sum(csa3_sum),
        .carry(csa3_carry)
    );
    
    wire [39:0] csa4_sum, csa4_carry;
    csa #(.WIDTH(40)) u_csa4 (
        .a(row3_s3),
        .b(row4_s3),
        .c(row5_s3),
        .sum(csa4_sum),
        .carry(csa4_carry)
    );
    
    reg [39:0] row0_s4, row1_s4, row2_s4, row3_s4;
    reg [39:0] acc_sum_s4, acc_carry_s4;
    reg        valid_s4;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row0_s4 <= 40'b0; row1_s4 <= 40'b0;
            row2_s4 <= 40'b0; row3_s4 <= 40'b0;
            acc_sum_s4 <= 40'b0;
            acc_carry_s4 <= 40'b0;
            valid_s4 <= 1'b0;
        end else if (valid_s3) begin
            row0_s4 <= csa3_sum;
            row1_s4 <= {csa3_carry[38:0], 1'b0};
            row2_s4 <= csa4_sum;
            row3_s4 <= {csa4_carry[38:0], 1'b0};
            acc_sum_s4 <= acc_sum_s3;
            acc_carry_s4 <= acc_carry_s3;
            valid_s4 <= 1'b1;
        end else begin
            valid_s4 <= 1'b0;
        end
    end

    //=========================================================================
    // Stage 5: 4:2 Compressor (4→2 rows)
    //=========================================================================
    wire [39:0] comp_sum, comp_carry;
    compressor_4to2_array #(.WIDTH(40)) u_comp42 (
        .a(row0_s4),
        .b(row1_s4),
        .c(row2_s4),
        .d(row3_s4),
        .sum(comp_sum),
        .carry(comp_carry)
    );
    
    reg [39:0] comp_sum_s5, comp_carry_s5;
    reg [39:0] acc_sum_s5, acc_carry_s5;
    reg        valid_s5;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            comp_sum_s5 <= 40'b0;
            comp_carry_s5 <= 40'b0;
            acc_sum_s5 <= 40'b0;
            acc_carry_s5 <= 40'b0;
            valid_s5 <= 1'b0;
        end else if (valid_s4) begin
            comp_sum_s5 <= comp_sum;
            comp_carry_s5 <= {comp_carry[38:0], 1'b0};
            acc_sum_s5 <= acc_sum_s4;
            acc_carry_s5 <= acc_carry_s4;
            valid_s5 <= 1'b1;
        end else begin
            valid_s5 <= 1'b0;
        end
    end

    //=========================================================================
    // Stage 6: Final Compressor with feedback merge (4→2 rows)
    //=========================================================================
    wire [39:0] final_sum, final_carry;
    compressor_4to2_array #(.WIDTH(40)) u_comp42_final (
        .a(comp_sum_s5),
        .b(comp_carry_s5),
        .c(acc_sum_s5),
        .d(acc_carry_s5),
        .sum(final_sum),
        .carry(final_carry)
    );
    
    reg [39:0] final_sum_s6, final_carry_s6;
    reg        valid_s6;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            final_sum_s6 <= 40'b0;
            final_carry_s6 <= 40'b0;
            valid_s6 <= 1'b0;
        end else if (valid_s5) begin
            final_sum_s6 <= final_sum;
            final_carry_s6 <= {final_carry[38:0], 1'b0};
            valid_s6 <= 1'b1;
        end else begin
            valid_s6 <= 1'b0;
        end
    end

    //=========================================================================
    // Stage 7: VMA (Vector Merging Adder) - Carry-Save to Binary [NEW]
    //=========================================================================
    wire [39:0] vma_result = final_sum_s6 + final_carry_s6;
    
    reg [39:0] vma_result_s7;
    reg        valid_s7;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vma_result_s7 <= 40'b0;
            valid_s7 <= 1'b0;
        end else if (valid_s6) begin
            vma_result_s7 <= vma_result;
            valid_s7 <= 1'b1;
        end else begin
            valid_s7 <= 1'b0;
        end
    end

    //=========================================================================
    // Stage 8: Output register [NEW]
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result <= 40'b0;
            valid_out <= 1'b0;
        end else if (valid_s7) begin
            result <= vma_result_s7;
            valid_out <= 1'b1;
        end else begin
            valid_out <= 1'b0;
        end
    end

endmodule
