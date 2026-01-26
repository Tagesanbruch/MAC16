`timescale 1ns/1ps
//============================================================================
// Exp G: True DCS Fused MAC Core with Hot-1 Injection
// Yosys-compatible Verilog
// 
// KEY IMPROVEMENTS over Exp F:
//   1. PPG no longer has +1 adder (Hot-1 injected into compression tree)
//   2. DCS feedback loop is now properly utilized
//   3. Final adder only used for output (not in critical loop)
//
// Pipeline Structure:
//   Stage 1: Booth encode + PP generation (no adder!)
//   Stage 2: First half compression with DCS feedback
//   Stage 3: Second half compression + accumulator update
//   Output:  Simple ripple-carry adder (multi-cycle allowed)
//
// Target: >1 GHz with true DCS benefits
//============================================================================
module mac16_fused_dcs (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         mode,       // 0: multiply only, 1: accumulate
    input  wire         clear,      // Clear accumulator
    input  wire  [15:0] inA,
    input  wire  [15:0] inB,
    input  wire         valid_in,
    output wire  [39:0] result_sum,
    output wire  [39:0] result_carry,
    output wire  [39:0] result_binary,
    output wire         valid_out
);

    //========================================================================
    // Stage 1: Booth Encoding + Partial Product Generation
    //========================================================================
    wire [7:0] neg, zero, two;
    booth_encoder u_booth (
        .b(inB),
        .neg(neg),
        .zero(zero),
        .two(two)
    );

    // Pipeline register S1
    reg [7:0]  neg_s1, zero_s1, two_s1;
    reg [15:0] a_s1;
    reg        valid_s1, mode_s1, clear_s1;
    
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

    // Partial product generation (NO +1 adder!)
    wire [32:0] pp_s1_0, pp_s1_1, pp_s1_2, pp_s1_3;
    wire [32:0] pp_s1_4, pp_s1_5, pp_s1_6, pp_s1_7;
    wire [7:0]  neg_hot1;  // Hot-1 bits for injection
    
    partial_product_gen u_ppg (
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
        .pp7(pp_s1_7),
        .neg_out(neg_hot1)
    );

    // Align partial products to their correct bit positions
    wire [39:0] pp_aligned0 = {{7{pp_s1_0[32]}}, pp_s1_0};        // << 0
    wire [39:0] pp_aligned1 = {{5{pp_s1_1[32]}}, pp_s1_1, 2'b0};  // << 2
    wire [39:0] pp_aligned2 = {{3{pp_s1_2[32]}}, pp_s1_2, 4'b0};  // << 4
    wire [39:0] pp_aligned3 = {{1{pp_s1_3[32]}}, pp_s1_3, 6'b0};  // << 6
    wire [39:0] pp_aligned4 = {pp_s1_4[30:0], 8'b0};              // << 8
    wire [39:0] pp_aligned5 = {pp_s1_5[28:0], 10'b0};             // << 10
    wire [39:0] pp_aligned6 = {pp_s1_6[26:0], 12'b0};             // << 12
    wire [39:0] pp_aligned7 = {pp_s1_7[24:0], 14'b0};             // << 14
    
    // Create Hot-1 correction row (9th row for compression tree)
    // Each neg bit goes to position 2*i (LSB of each PP's position)
    // Position: [14][12][10][8][6][4][2][0]
    wire [39:0] hot1_row;
    assign hot1_row[0]  = neg_hot1[0];  // PP0's +1 at bit 0
    assign hot1_row[1]  = 1'b0;
    assign hot1_row[2]  = neg_hot1[1];  // PP1's +1 at bit 2
    assign hot1_row[3]  = 1'b0;
    assign hot1_row[4]  = neg_hot1[2];  // PP2's +1 at bit 4
    assign hot1_row[5]  = 1'b0;
    assign hot1_row[6]  = neg_hot1[3];  // PP3's +1 at bit 6
    assign hot1_row[7]  = 1'b0;
    assign hot1_row[8]  = neg_hot1[4];  // PP4's +1 at bit 8
    assign hot1_row[9]  = 1'b0;
    assign hot1_row[10] = neg_hot1[5];  // PP5's +1 at bit 10
    assign hot1_row[11] = 1'b0;
    assign hot1_row[12] = neg_hot1[6];  // PP6's +1 at bit 12
    assign hot1_row[13] = 1'b0;
    assign hot1_row[14] = neg_hot1[7];  // PP7's +1 at bit 14
    assign hot1_row[39:15] = 25'b0;

    //========================================================================
    // Double Carry-Save Accumulator (TRUE DCS!)
    //========================================================================
    reg [39:0] acc_sum, acc_carry;
    
    // Feedback mux: use accumulated values when in accumulate mode and not clearing
    wire [39:0] feedback_sum   = (mode_s1 & ~clear_s1) ? acc_sum   : 40'd0;
    wire [39:0] feedback_carry = (mode_s1 & ~clear_s1) ? acc_carry : 40'd0;

    //========================================================================
    // Stage 2: First Half Compression (10 inputs -> 5)
    // Inputs: 8 PPs + Hot1 row + feedback_sum
    //========================================================================
    wire [39:0] l1_s0, l1_c0, l1_s1, l1_c1, l1_s2, l1_c2;
    
    // CSA Layer 1: Group A (pp0, pp1, pp2)
    csa #(.WIDTH(40)) u_l1_csa0 (
        .a(pp_aligned0),
        .b(pp_aligned1),
        .c(pp_aligned2),
        .sum(l1_s0),
        .carry(l1_c0)
    );
    
    // CSA Layer 1: Group B (pp3, pp4, pp5)
    csa #(.WIDTH(40)) u_l1_csa1 (
        .a(pp_aligned3),
        .b(pp_aligned4),
        .c(pp_aligned5),
        .sum(l1_s1),
        .carry(l1_c1)
    );
    
    // CSA Layer 1: Group C (pp6, pp7, hot1_row)
    csa #(.WIDTH(40)) u_l1_csa2 (
        .a(pp_aligned6),
        .b(pp_aligned7),
        .c(hot1_row),
        .sum(l1_s2),
        .carry(l1_c2)
    );

    // CSA Layer 2: (6 -> 4) with feedback_sum
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

    // Pipeline register S2 (mid-compression)
    reg [39:0] l2_s0_r, l2_c0_r, l2_s1_r, l2_c1_r;
    reg [39:0] fb_sum_r, fb_carry_r;
    reg        valid_s2, mode_s2, clear_s2;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            l2_s0_r    <= 40'b0;
            l2_c0_r    <= 40'b0;
            l2_s1_r    <= 40'b0;
            l2_c1_r    <= 40'b0;
            fb_sum_r   <= 40'b0;
            fb_carry_r <= 40'b0;
            valid_s2   <= 1'b0;
            mode_s2    <= 1'b0;
            clear_s2   <= 1'b0;
        end else begin
            l2_s0_r    <= l2_s0;
            l2_c0_r    <= {l2_c0[38:0], 1'b0};
            l2_s1_r    <= l2_s1;
            l2_c1_r    <= {l2_c1[38:0], 1'b0};
            fb_sum_r   <= feedback_sum;
            fb_carry_r <= feedback_carry;
            valid_s2   <= valid_s1;
            mode_s2    <= mode_s1;
            clear_s2   <= clear_s1;
        end
    end

    //========================================================================
    // Stage 3: Second Half Compression (6 -> 2) with DCS feedback
    //========================================================================
    // CSA Layer 3: Combine multiplication partial results
    wire [39:0] l3_s0, l3_c0;
    
    csa #(.WIDTH(40)) u_l3_csa0 (
        .a(l2_s0_r),
        .b(l2_c0_r),
        .c(l2_s1_r),
        .sum(l3_s0),
        .carry(l3_c0)
    );
    
    // CSA Layer 4: Add remaining carry and first feedback
    wire [39:0] l4_s0, l4_c0;
    
    csa #(.WIDTH(40)) u_l4_csa0 (
        .a(l3_s0),
        .b({l3_c0[38:0], 1'b0}),
        .c(l2_c1_r),
        .sum(l4_s0),
        .carry(l4_c0)
    );
    
    // Final 4:2 compressor with both feedbacks
    wire [39:0] final_sum_w, final_carry_w;
    
    compressor_4to2_array #(.WIDTH(40)) u_final_comp (
        .a(l4_s0),
        .b({l4_c0[38:0], 1'b0}),
        .c(fb_sum_r),
        .d(fb_carry_r),
        .sum(final_sum_w),
        .carry(final_carry_w)
    );

    // Pipeline register S3 / Accumulator update
    reg valid_s3;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_sum   <= 40'b0;
            acc_carry <= 40'b0;
            valid_s3  <= 1'b0;
        end else if (valid_s2) begin
            // Store carry-save result (no adder needed in feedback loop!)
            acc_sum   <= final_sum_w;
            acc_carry <= {final_carry_w[38:0], 1'b0};
            valid_s3  <= 1'b1;
        end else begin
            valid_s3  <= 1'b0;
        end
    end

    //========================================================================
    // Output: Simple Ripple-Carry Adder (NOT in critical loop!)
    // This can be multi-cycle if needed (set_multicycle_path)
    //========================================================================
    // Using simple addition - synthesizer can choose optimal adder
    // For lower power, this is better than Kogge-Stone when not in critical path
    wire [40:0] sum_extended = {1'b0, acc_sum} + {1'b0, acc_carry};
    
    assign result_sum    = acc_sum;
    assign result_carry  = acc_carry;
    assign result_binary = sum_extended[39:0];
    assign valid_out     = valid_s3;

endmodule
