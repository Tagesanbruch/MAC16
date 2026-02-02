`timescale 1ns/1ps
//============================================================================
// Experiment UB: DCS Booth Multiplier with 4-Stage Pipeline
// 
// Use Case: Designed for 5-cycle Total Latency where Stage 5 is external VMA.
// 
// Pipeline Structure (4 stages internal):
// - Stage 1: Booth + PPG + CSA Layer 1 (8→6 rows) → 6 rows registered
//     - Logic: Booth/MUX + 2 XORs. Depth ~4 XORs.
// - Stage 2: CSA Layer 2 (6→4 rows) + Feedback (2 rows) → 6 rows registered
//     - Logic: 2 XORs. Depth ~2 XORs.
// - Stage 3: CSA Layer 3 (6→4 rows) → 4 rows registered
//     - Logic: 2 XORs. Depth ~2 XORs.
// - Stage 4: 4:2 Compressor (4→2 rows) → DCS Output registered
//     - Logic: 3 XORs (MUX-based). Depth ~3 XORs.
//
// Total Internal Latency: 4 Cycles
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
    // Stage 1: Booth Encode + PPG Gen + CSA Layer 1 (Merged)
    // Logic: Booth(~1) + PPG Mux(~1) + CSA(~2) = ~4 XOR levels
    //=========================================================================
    
    // 1. Booth Encoding
    wire [7:0]  neg_w, zero_w, two_w;
    booth_encoder u_booth (
        .b(b),
        .neg(neg_w),
        .zero(zero_w),
        .two(two_w)
    );
    
    // 2. PPG Generation
    wire [32:0] pp_w0, pp_w1, pp_w2, pp_w3, pp_w4, pp_w5, pp_w6, pp_w7;
    partial_product_gen u_ppg (
        .a(a),
        .neg(neg_w),
        .zero(zero_w),
        .two(two_w),
        .pp0(pp_w0), .pp1(pp_w1), .pp2(pp_w2), .pp3(pp_w3),
        .pp4(pp_w4), .pp5(pp_w5), .pp6(pp_w6), .pp7(pp_w7)
    );

    // 3. Alignment
    wire [39:0] pp_a0 = {{7{pp_w0[32]}}, pp_w0};
    wire [39:0] pp_a1 = {{5{pp_w1[32]}}, pp_w1, 2'b0};
    wire [39:0] pp_a2 = {{3{pp_w2[32]}}, pp_w2, 4'b0};
    wire [39:0] pp_a3 = {{1{pp_w3[32]}}, pp_w3, 6'b0};
    wire [39:0] pp_a4 = {pp_w4[30:0], 8'b0};
    wire [39:0] pp_a5 = {pp_w5[28:0], 10'b0};
    wire [39:0] pp_a6 = {pp_w6[26:0], 12'b0};
    wire [39:0] pp_a7 = {pp_w7[24:0], 14'b0};
    
    // 4. CSA Layer 1 (8→6) - Combinational in Stage 1
    wire [39:0] csa1_sum, csa1_carry;
    csa #(.WIDTH(40)) u_csa1 (
        .a(pp_a0), .b(pp_a1), .c(pp_a2),
        .sum(csa1_sum), .carry(csa1_carry)
    );
    
    wire [39:0] csa2_sum, csa2_carry;
    csa #(.WIDTH(40)) u_csa2 (
        .a(pp_a3), .b(pp_a4), .c(pp_a5),
        .sum(csa2_sum), .carry(csa2_carry)
    );
    // Result rows: csa1_s, csa1_c, csa2_s, csa2_c, pp_a6, pp_a7
    
    // Pipeline Register - Stage 1
    reg [39:0] row0_s1, row1_s1, row2_s1, row3_s1, row4_s1, row5_s1;
    reg [39:0] acc_sum_s1, acc_carry_s1;
    reg        valid_s1;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row0_s1 <= 40'b0; row1_s1 <= 40'b0; row2_s1 <= 40'b0;
            row3_s1 <= 40'b0; row4_s1 <= 40'b0; row5_s1 <= 40'b0;
            acc_sum_s1 <= 40'b0; acc_carry_s1 <= 40'b0;
            valid_s1 <= 1'b0;
        end else if (valid_in) begin
            row0_s1 <= csa1_sum;
            row1_s1 <= {csa1_carry[38:0], 1'b0};
            row2_s1 <= csa2_sum;
            row3_s1 <= {csa2_carry[38:0], 1'b0};
            row4_s1 <= pp_a6;
            row5_s1 <= pp_a7;
            acc_sum_s1 <= acc_sum_in;
            acc_carry_s1 <= acc_carry_in;
            valid_s1 <= 1'b1;
        end else begin
            valid_s1 <= 1'b0;
        end
    end
    
    //=========================================================================
    // Stage 2: CSA Layer 2 (6→4) + Feedback (2) = 6 Rows
    // Logic: ~2 XOR levels
    //=========================================================================
    wire [39:0] csa3_sum, csa3_carry;
    csa #(.WIDTH(40)) u_csa3 (
        .a(row0_s1), .b(row1_s1), .c(row2_s1),
        .sum(csa3_sum), .carry(csa3_carry)
    );
    
    wire [39:0] csa4_sum, csa4_carry;
    csa #(.WIDTH(40)) u_csa4 (
        .a(row3_s1), .b(row4_s1), .c(row5_s1),
        .sum(csa4_sum), .carry(csa4_carry)
    );
    
    // Pipeline Register - Stage 2
    reg [39:0] r0_s2, r1_s2, r2_s2, r3_s2, r4_s2, r5_s2;
    reg        valid_s2;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r0_s2 <= 40'b0; r1_s2 <= 40'b0; r2_s2 <= 40'b0;
            r3_s2 <= 40'b0; r4_s2 <= 40'b0; r5_s2 <= 40'b0;
            valid_s2 <= 1'b0;
        end else if (valid_s1) begin
            r0_s2 <= csa3_sum;
            r1_s2 <= {csa3_carry[38:0], 1'b0};
            r2_s2 <= csa4_sum;
            r3_s2 <= {csa4_carry[38:0], 1'b0};
            r4_s2 <= acc_sum_s1;     // Feedback injected here
            r5_s2 <= acc_carry_s1;
            valid_s2 <= 1'b1;
        end else begin
            valid_s2 <= 1'b0;
        end
    end
    
    //=========================================================================
    // Stage 3: CSA Layer 3 (6→4)
    // Logic: ~2 XOR levels
    //=========================================================================
    wire [39:0] csa5_sum, csa5_carry;
    csa #(.WIDTH(40)) u_csa5 (
        .a(r0_s2), .b(r1_s2), .c(r2_s2),
        .sum(csa5_sum), .carry(csa5_carry)
    );
    
    wire [39:0] csa6_sum, csa6_carry;
    csa #(.WIDTH(40)) u_csa6 (
        .a(r3_s2), .b(r4_s2), .c(r5_s2),
        .sum(csa6_sum), .carry(csa6_carry)
    );
    
    // Pipeline Register - Stage 3
    reg [39:0] f0_s3, f1_s3, f2_s3, f3_s3;
    reg        valid_s3;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            f0_s3 <= 40'b0; f1_s3 <= 40'b0;
            f2_s3 <= 40'b0; f3_s3 <= 40'b0;
            valid_s3 <= 1'b0;
        end else if (valid_s2) begin
            f0_s3 <= csa5_sum;
            f1_s3 <= {csa5_carry[38:0], 1'b0};
            f2_s3 <= csa6_sum;
            f3_s3 <= {csa6_carry[38:0], 1'b0};
            valid_s3 <= 1'b1;
        end else begin
            valid_s3 <= 1'b0;
        end
    end
    
    //=========================================================================
    // Stage 4: 4:2 Compressor (4→2)
    // Logic: ~3 XOR levels
    //=========================================================================
    wire [39:0] final_sum, final_carry;
    compressor_4to2_array #(.WIDTH(40)) u_final_comp (
        .a(f0_s3),
        .b(f1_s3),
        .c(f2_s3),
        .d(f3_s3),
        .sum(final_sum),
        .carry(final_carry)
    );

    // Pipeline Register - Stage 4 (Output)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result_sum   <= 40'b0;
            result_carry <= 40'b0;
            valid_out <= 1'b0;
        end else if (valid_s3) begin
            result_sum   <= final_sum;
            result_carry <= {final_carry[38:0], 1'b0};
            valid_out <= 1'b1;
        end else begin
            valid_out <= 1'b0;
        end
    end

endmodule
