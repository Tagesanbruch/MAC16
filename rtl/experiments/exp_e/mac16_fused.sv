`timescale 1ns/1ps
//============================================================================
// Experiment E: Fused MAC with Double Carry-Save (DCS) Accumulation
// 
// KEY INNOVATION: Eliminate the CPA adder from the feedback loop!
//
// Traditional MAC:  mult -> CPA add -> register -> feedback
// DCS MAC:          mult -> CSA compress -> register -> feedback to compressor
//
// The accumulator stores redundant form (sum, carry) instead of binary.
// This reduces critical path from O(log N) adder to O(1) XOR gates.
//
// Architecture:
//   Stage 1: Booth encode + partial product generation
//   Stage 2: 10:2 compression (8 PP + 2 feedback)
//   Output:  Final CPA only when reading result (not in critical loop)
//
// Target: > 1.2 GHz
//============================================================================
module mac16_fused (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        mode,       // 0: multiply only, 1: accumulate
    input  logic        clear,      // Clear accumulator
    input  logic [15:0] inA,
    input  logic [15:0] inB,
    input  logic        valid_in,
    output logic [39:0] result_sum,   // CSA sum output
    output logic [39:0] result_carry, // CSA carry output  
    output logic [39:0] result_binary,// Final binary result (sum + carry)
    output logic        valid_out
);

    //========================================================================
    // Booth Encoder
    //========================================================================
    wire [7:0] neg, zero, two;
    booth_encoder u_booth (
        .b(inB),
        .neg(neg),
        .zero(zero),
        .two(two)
    );

    //========================================================================
    // Stage 1 Pipeline Register: Booth signals + A
    //========================================================================
    reg [7:0]  neg_s1, zero_s1, two_s1;
    reg [15:0] a_s1;
    reg        valid_s1;
    reg        mode_s1, clear_s1;
    
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

    //========================================================================
    // Partial Product Generation (uses registered Booth signals)
    //========================================================================
    wire [32:0] pp_s1_0, pp_s1_1, pp_s1_2, pp_s1_3, pp_s1_4, pp_s1_5, pp_s1_6, pp_s1_7;
    partial_product_gen u_ppg_s1 (
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

    //========================================================================
    // Partial Product Alignment (shift each PP to correct position)
    //========================================================================
    wire [39:0] pp_aligned0, pp_aligned1, pp_aligned2, pp_aligned3;
    wire [39:0] pp_aligned4, pp_aligned5, pp_aligned6, pp_aligned7;
    
    assign pp_aligned0 = {{7{pp_s1_0[32]}}, pp_s1_0};
    assign pp_aligned1 = {{5{pp_s1_1[32]}}, pp_s1_1, 2'b0};
    assign pp_aligned2 = {{3{pp_s1_2[32]}}, pp_s1_2, 4'b0};
    assign pp_aligned3 = {{1{pp_s1_3[32]}}, pp_s1_3, 6'b0};
    assign pp_aligned4 = {pp_s1_4[30:0], 8'b0};
    assign pp_aligned5 = {pp_s1_5[28:0], 10'b0};
    assign pp_aligned6 = {pp_s1_6[26:0], 12'b0};
    assign pp_aligned7 = {pp_s1_7[24:0], 14'b0};

    //========================================================================
    // Double Carry-Save Accumulator Registers
    // KEY: Store redundant form instead of binary!
    //========================================================================
    logic [39:0] acc_sum, acc_carry;
    
    // Feedback to compression tree (gated by mode)
    wire [39:0] feedback_sum   = (mode_s1 && !clear_s1) ? acc_sum   : 40'd0;
    wire [39:0] feedback_carry = (mode_s1 && !clear_s1) ? acc_carry : 40'd0;

    //========================================================================
    // 10:2 Compression Tree
    // Input: 8 partial products + 2 feedback (acc_sum, acc_carry)
    // Output: 2 rows (next_sum, next_carry)
    //
    // Tree structure:
    //   Level 1: 10 -> 7 (using 3 CSAs, each 3:2)
    //   Level 2: 7 -> 5
    //   Level 3: 5 -> 4
    //   Level 4: 4 -> 2 (using 4:2 compressor)
    //========================================================================
    
    // Level 1: 10 -> 7
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
    // Remaining: l1_s0, l1_c0<<1, l1_s1, l1_c1<<1, l1_s2, l1_c2<<1, feedback_carry = 7 rows

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
    // Remaining: l2_s0, l2_c0<<1, l2_s1, l2_c1<<1, feedback_carry = 5 rows

    // Level 3: 5 -> 4
    wire [39:0] l3_s0, l3_c0;
    
    csa #(.WIDTH(40)) u_l3_csa0 (
        .a(l2_s0),
        .b({l2_c0[38:0], 1'b0}),
        .c(l2_s1),
        .sum(l3_s0),
        .carry(l3_c0)
    );
    // Remaining: l3_s0, l3_c0<<1, l2_c1<<1, feedback_carry = 4 rows

    // Level 4: 4 -> 2 (4:2 compressor)
    wire [39:0] final_sum_w, final_carry_w;
    
    compressor_4to2_array #(.WIDTH(40)) u_l4_comp (
        .a(l3_s0),
        .b({l3_c0[38:0], 1'b0}),
        .c({l2_c1[38:0], 1'b0}),
        .d(feedback_carry),
        .sum(final_sum_w),
        .carry(final_carry_w)
    );

    //========================================================================
    // Stage 2 Pipeline: Update Accumulator (DCS)
    // NO ADDER IN THIS PATH! Just register update.
    //========================================================================
    logic valid_s2;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_sum   <= '0;
            acc_carry <= '0;
            valid_s2  <= 1'b0;
        end else if (valid_s1) begin
            // When clear_s1=1, feedback was already zeroed, so this stores
            // just the multiplication result (not accumulated)
            acc_sum   <= final_sum_w;
            acc_carry <= {final_carry_w[38:0], 1'b0};
            valid_s2  <= 1'b1;
        end else begin
            valid_s2  <= 1'b0;
        end
    end

    //========================================================================
    // Output: Final Addition (Only for reading result - NOT in loop!)
    //========================================================================
    assign result_sum    = acc_sum;
    assign result_carry  = acc_carry;
    assign result_binary = acc_sum + acc_carry;  // CPA only for output
    assign valid_out     = valid_s2;

endmodule
