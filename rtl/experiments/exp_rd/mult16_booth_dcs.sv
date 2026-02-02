`timescale 1ns/1ps
//============================================================================
// Experiment RD: Split-Booth Architecture (5-Stage Pipeline)
// 
// Key Optimization: Register Booth encoding signals in Stage 1
// This splits the 11-gate-level PPG critical path into:
//   - Stage 1: Booth Encoding (~4 levels) + Register
//   - Stage 2: MUX-based PPG + CSA Layer 1 (~6-7 levels)
//
// Pipeline Architecture:
// - Stage 1: Booth Encoding + Register A/2A and control signals
// - Stage 2: MUX-based PPG + CSA Layer 1 (8→6)
// - Stage 3: CSA Layer 2 (6→4) + Feedback Injection
// - Stage 4: 4:2 Compressor + Final CSA (5→2)
// - Stage 5: Output (VMA in mac16.sv)
//
// Expected: >1.0 GHz @ SS by reducing Stage 2 logic depth
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
    // Stage 1: Booth Encoding + Register Control Signals
    // Key Change: Booth signals are registered, not computed in Stage 2
    //=========================================================================
    
    // Booth encoder outputs (combinational)
    wire [7:0] neg_comb, zero_comb, two_comb;
    
    // Extended B with implicit -1 bit = 0
    wire [16:0] b_ext = {b, 1'b0};
    
    // Combinational Booth encoding
    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : booth_gen
            wire [2:0] group = b_ext[2*i+2 : 2*i];
            assign neg_comb[i]  = group[2];
            assign zero_comb[i] = (group == 3'b000) || (group == 3'b111);
            assign two_comb[i]  = (group == 3'b011) || (group == 3'b100);
        end
    endgenerate
    
    // Stage 1 Registers: Booth signals + A/2A + Accumulator
    reg [7:0]  neg_s1, zero_s1, two_s1;
    reg [16:0] a_ext_s1;    // Sign-extended A
    reg [17:0] a_2x_s1;     // 2*A (pre-computed)
    reg [39:0] acc_sum_s1, acc_carry_s1;
    reg        valid_s1;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            neg_s1  <= 8'b0;
            zero_s1 <= 8'b0;
            two_s1  <= 8'b0;
            a_ext_s1 <= 17'b0;
            a_2x_s1  <= 18'b0;
            acc_sum_s1 <= 40'b0;
            acc_carry_s1 <= 40'b0;
            valid_s1 <= 1'b0;
        end else if (valid_in) begin
            // Register Booth control signals (key optimization!)
            neg_s1  <= neg_comb;
            zero_s1 <= zero_comb;
            two_s1  <= two_comb;
            // Register pre-computed A and 2A
            a_ext_s1 <= {a[15], a};              // Sign-extend A
            a_2x_s1  <= {a[15], a, 1'b0};        // 2*A
            acc_sum_s1 <= acc_sum_in;
            acc_carry_s1 <= acc_carry_in;
            valid_s1 <= 1'b1;
        end else begin
            valid_s1 <= 1'b0;
        end
    end
    
    //=========================================================================
    // Stage 2: MUX-based PPG (using registered Booth signals)
    // Critical path is now ONLY: MUX + CSA Layer 1
    //=========================================================================
    
    // PP generation function using registered signals
    function [32:0] gen_pp;
        input [17:0] a_2x_in;
        input [16:0] a_ext_in;
        input neg_in, zero_in, two_in;
        reg [17:0] a_sel, a_neg, a_final;
        begin
            // Simple MUX: select A or 2A
            a_sel = two_in ? a_2x_in : {a_ext_in[16], a_ext_in};
            // Conditional negate
            a_neg = neg_in ? (~a_sel + 1'b1) : a_sel;
            // Zero masking
            a_final = zero_in ? 18'd0 : a_neg;
            gen_pp = {{15{a_final[17]}}, a_final};
        end
    endfunction
    
    // Generate 8 partial products (combinational, using S1 registered signals)
    wire [32:0] pp_w0 = gen_pp(a_2x_s1, a_ext_s1, neg_s1[0], zero_s1[0], two_s1[0]);
    wire [32:0] pp_w1 = gen_pp(a_2x_s1, a_ext_s1, neg_s1[1], zero_s1[1], two_s1[1]);
    wire [32:0] pp_w2 = gen_pp(a_2x_s1, a_ext_s1, neg_s1[2], zero_s1[2], two_s1[2]);
    wire [32:0] pp_w3 = gen_pp(a_2x_s1, a_ext_s1, neg_s1[3], zero_s1[3], two_s1[3]);
    wire [32:0] pp_w4 = gen_pp(a_2x_s1, a_ext_s1, neg_s1[4], zero_s1[4], two_s1[4]);
    wire [32:0] pp_w5 = gen_pp(a_2x_s1, a_ext_s1, neg_s1[5], zero_s1[5], two_s1[5]);
    wire [32:0] pp_w6 = gen_pp(a_2x_s1, a_ext_s1, neg_s1[6], zero_s1[6], two_s1[6]);
    wire [32:0] pp_w7 = gen_pp(a_2x_s1, a_ext_s1, neg_s1[7], zero_s1[7], two_s1[7]);
    
    // Align partial products to 40 bits
    wire [39:0] pp_aligned0 = {{7{pp_w0[32]}}, pp_w0};
    wire [39:0] pp_aligned1 = {{5{pp_w1[32]}}, pp_w1, 2'b0};
    wire [39:0] pp_aligned2 = {{3{pp_w2[32]}}, pp_w2, 4'b0};
    wire [39:0] pp_aligned3 = {{1{pp_w3[32]}}, pp_w3, 6'b0};
    wire [39:0] pp_aligned4 = {pp_w4[30:0], 8'b0};
    wire [39:0] pp_aligned5 = {pp_w5[28:0], 10'b0};
    wire [39:0] pp_aligned6 = {pp_w6[26:0], 12'b0};
    wire [39:0] pp_aligned7 = {pp_w7[24:0], 14'b0};
    
    // CSA Layer 1: 8 → 6 (performed in Stage 2)
    wire [39:0] csa1_sum, csa1_carry;
    csa #(.WIDTH(40)) u_csa1 (
        .a(pp_aligned0), .b(pp_aligned1), .c(pp_aligned2),
        .sum(csa1_sum), .carry(csa1_carry)
    );
    wire [39:0] csa2_sum, csa2_carry;
    csa #(.WIDTH(40)) u_csa2 (
        .a(pp_aligned3), .b(pp_aligned4), .c(pp_aligned5),
        .sum(csa2_sum), .carry(csa2_carry)
    );
    
    // Stage 2 Registers: CSA L1 outputs + remaining PPs + Accumulator
    reg [39:0] csa1_sum_s2, csa1_carry_s2;
    reg [39:0] csa2_sum_s2, csa2_carry_s2;
    reg [39:0] pp6_s2, pp7_s2;
    reg [39:0] acc_sum_s2, acc_carry_s2;
    reg        valid_s2;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            csa1_sum_s2 <= 40'b0; csa1_carry_s2 <= 40'b0;
            csa2_sum_s2 <= 40'b0; csa2_carry_s2 <= 40'b0;
            pp6_s2 <= 40'b0; pp7_s2 <= 40'b0;
            acc_sum_s2 <= 40'b0; acc_carry_s2 <= 40'b0;
            valid_s2 <= 1'b0;
        end else if (valid_s1) begin
            csa1_sum_s2   <= csa1_sum;
            csa1_carry_s2 <= {csa1_carry[38:0], 1'b0};
            csa2_sum_s2   <= csa2_sum;
            csa2_carry_s2 <= {csa2_carry[38:0], 1'b0};
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
    // Stage 3: CSA Layer 2 (6→4) + Feedback Injection
    //=========================================================================
    
    // CSA Layer 2: 6 → 4
    wire [39:0] csa3_sum, csa3_carry;
    csa #(.WIDTH(40)) u_csa3 (
        .a(csa1_sum_s2), 
        .b(csa1_carry_s2), 
        .c(csa2_sum_s2),
        .sum(csa3_sum), 
        .carry(csa3_carry)
    );
    wire [39:0] csa4_sum, csa4_carry;
    csa #(.WIDTH(40)) u_csa4 (
        .a(csa2_carry_s2), 
        .b(pp6_s2), 
        .c(pp7_s2),
        .sum(csa4_sum), 
        .carry(csa4_carry)
    );
    
    // Inject Feedback: 4 + 2 = 6 → CSA → 5 rows
    wire [39:0] csa5_sum, csa5_carry;
    csa #(.WIDTH(40)) u_csa5 (
        .a(acc_sum_s2),
        .b(acc_carry_s2),
        .c(csa3_sum),
        .sum(csa5_sum), 
        .carry(csa5_carry)
    );
    
    // Stage 3 Registers: 5 rows for final compression
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
    // Stage 4: MUX 4:2 Compressor + Final CSA (5→2)
    //=========================================================================
    
    wire [39:0] comp_sum, comp_carry;
    compressor_4to2_mux_array #(.WIDTH(40)) u_comp42 (
        .a(row0_s3),
        .b(row1_s3),
        .c(row2_s3),
        .d(row3_s3),
        .sum(comp_sum),
        .carry(comp_carry)
    );
    
    wire [39:0] csa6_sum, csa6_carry;
    csa #(.WIDTH(40)) u_csa6 (
        .a(comp_sum),
        .b({comp_carry[38:0], 1'b0}),
        .c(row4_s3),
        .sum(csa6_sum),
        .carry(csa6_carry)
    );

    // Stage 4 Output Registers
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
