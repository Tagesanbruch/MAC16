`timescale 1ns/1ps
//============================================================================
// Experiment RF: Balanced 5-Stage Split-Booth Architecture
// 
// Key Optimization: Properly balanced pipeline with CSA in S2
// 
// Stage 1: Booth Encoding → Register Booth signals + A/2A
//          Logic depth: ~4 levels (NOR, XOR for Booth decode)
//          
// Stage 2: PPG MUX + CSA Layer 1 (8→6) → Register 6 vectors
//          Logic depth: ~6 levels (MUX + negate + CSA)
//          Register: 6 × 40bit = 240 bits (vs 320 in exp_re)
//          
// Stage 3: CSA Layer 2 (6→4→2) + Feedback → Register (Sum, Carry)
//          Logic depth: ~4 levels (2 CSA layers + feedback merge)
//          
// Stage 4: Final output (passed to mac16 for VMA)
//
// Total mult latency: 4 cycles internally
// Total MAC latency: 5 cycles (with VMA in mac16)
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
    // Stage 1: Booth Encoding ONLY
    // Logic: Booth decode (~4 gate levels)
    // Output: neg[7:0], zero[7:0], two[7:0], a_ext, a_2x
    //=========================================================================
    
    wire [16:0] b_ext = {b, 1'b0};
    
    wire [7:0] neg_comb, zero_comb, two_comb;
    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : booth_gen
            wire [2:0] group = b_ext[2*i+2 : 2*i];
            assign neg_comb[i]  = group[2];
            assign zero_comb[i] = (group == 3'b000) || (group == 3'b111);
            assign two_comb[i]  = (group == 3'b011) || (group == 3'b100);
        end
    endgenerate
    
    // S1 Registers
    reg [7:0]  neg_s1, zero_s1, two_s1;
    reg [16:0] a_ext_s1;
    reg [17:0] a_2x_s1;
    reg [39:0] acc_sum_s1, acc_carry_s1;
    reg        valid_s1;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            neg_s1 <= 8'b0; zero_s1 <= 8'b0; two_s1 <= 8'b0;
            a_ext_s1 <= 17'b0; a_2x_s1 <= 18'b0;
            acc_sum_s1 <= 40'b0; acc_carry_s1 <= 40'b0;
            valid_s1 <= 1'b0;
        end else if (valid_in) begin
            neg_s1  <= neg_comb;
            zero_s1 <= zero_comb;
            two_s1  <= two_comb;
            a_ext_s1 <= {a[15], a};
            a_2x_s1  <= {a[15], a, 1'b0};
            acc_sum_s1 <= acc_sum_in;
            acc_carry_s1 <= acc_carry_in;
            valid_s1 <= 1'b1;
        end else begin
            valid_s1 <= 1'b0;
        end
    end
    
    //=========================================================================
    // Stage 2: PPG MUX + CSA Layer 1 (8→6)
    // This stage does both PPG and initial compression!
    // Logic: MUX (~3 levels) + CSA (~2 levels) = ~5-6 levels total
    // Output: 6 vectors (csa1_s, csa1_c, csa2_s, csa2_c, pp6, pp7)
    //=========================================================================
    
    function [32:0] gen_pp;
        input [17:0] a_2x_in;
        input [16:0] a_ext_in;
        input neg_in, zero_in, two_in;
        reg [17:0] a_sel, a_neg, a_final;
        begin
            a_sel = two_in ? a_2x_in : {a_ext_in[16], a_ext_in};
            a_neg = neg_in ? (~a_sel + 1'b1) : a_sel;
            a_final = zero_in ? 18'd0 : a_neg;
            gen_pp = {{15{a_final[17]}}, a_final};
        end
    endfunction
    
    // Generate 8 PPs (combinational)
    wire [32:0] pp_w0 = gen_pp(a_2x_s1, a_ext_s1, neg_s1[0], zero_s1[0], two_s1[0]);
    wire [32:0] pp_w1 = gen_pp(a_2x_s1, a_ext_s1, neg_s1[1], zero_s1[1], two_s1[1]);
    wire [32:0] pp_w2 = gen_pp(a_2x_s1, a_ext_s1, neg_s1[2], zero_s1[2], two_s1[2]);
    wire [32:0] pp_w3 = gen_pp(a_2x_s1, a_ext_s1, neg_s1[3], zero_s1[3], two_s1[3]);
    wire [32:0] pp_w4 = gen_pp(a_2x_s1, a_ext_s1, neg_s1[4], zero_s1[4], two_s1[4]);
    wire [32:0] pp_w5 = gen_pp(a_2x_s1, a_ext_s1, neg_s1[5], zero_s1[5], two_s1[5]);
    wire [32:0] pp_w6 = gen_pp(a_2x_s1, a_ext_s1, neg_s1[6], zero_s1[6], two_s1[6]);
    wire [32:0] pp_w7 = gen_pp(a_2x_s1, a_ext_s1, neg_s1[7], zero_s1[7], two_s1[7]);
    
    // Align to 40 bits
    wire [39:0] pp0 = {{7{pp_w0[32]}}, pp_w0};
    wire [39:0] pp1 = {{5{pp_w1[32]}}, pp_w1, 2'b0};
    wire [39:0] pp2 = {{3{pp_w2[32]}}, pp_w2, 4'b0};
    wire [39:0] pp3 = {{1{pp_w3[32]}}, pp_w3, 6'b0};
    wire [39:0] pp4 = {pp_w4[30:0], 8'b0};
    wire [39:0] pp5 = {pp_w5[28:0], 10'b0};
    wire [39:0] pp6 = {pp_w6[26:0], 12'b0};
    wire [39:0] pp7 = {pp_w7[24:0], 14'b0};
    
    // CSA Layer 1: 8→6 (done in S2, BEFORE register!)
    wire [39:0] csa1_sum, csa1_carry;
    csa #(.WIDTH(40)) u_csa1 (.a(pp0), .b(pp1), .c(pp2), .sum(csa1_sum), .carry(csa1_carry));
    wire [39:0] csa2_sum, csa2_carry;
    csa #(.WIDTH(40)) u_csa2 (.a(pp3), .b(pp4), .c(pp5), .sum(csa2_sum), .carry(csa2_carry));
    
    // S2 Registers: Store 6 vectors (NOT 8!)
    // This is the key optimization: 6 × 40bit = 240 bits (vs 320 bits)
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
            pp6_s2 <= pp6;
            pp7_s2 <= pp7;
            acc_sum_s2 <= acc_sum_s1;
            acc_carry_s2 <= acc_carry_s1;
            valid_s2 <= 1'b1;
        end else begin
            valid_s2 <= 1'b0;
        end
    end
    
    //=========================================================================
    // Stage 3: CSA Layer 2 (6→4→2) + Feedback Injection
    // Input: 6 vectors from S2 + 2 feedback = 8 total
    // Output: (Sum, Carry) for result
    //=========================================================================
    
    // CSA Layer 2a: 6→4
    wire [39:0] csa3_sum, csa3_carry;
    csa #(.WIDTH(40)) u_csa3 (.a(csa1_sum_s2), .b(csa1_carry_s2), .c(csa2_sum_s2), .sum(csa3_sum), .carry(csa3_carry));
    wire [39:0] csa4_sum, csa4_carry;
    csa #(.WIDTH(40)) u_csa4 (.a(csa2_carry_s2), .b(pp6_s2), .c(pp7_s2), .sum(csa4_sum), .carry(csa4_carry));
    
    // Feedback Injection + CSA Layer 2b: (4 + 2 = 6)→4
    wire [39:0] csa5_sum, csa5_carry;
    csa #(.WIDTH(40)) u_csa5 (.a(acc_sum_s2), .b(acc_carry_s2), .c(csa3_sum), .sum(csa5_sum), .carry(csa5_carry));
    
    // CSA Layer 3: 5→3 (csa5_s, csa5_c, csa3_c, csa4_s, csa4_c → need 4:2 comp)
    // Use 4:2 compressor for 4 of them
    wire [39:0] comp_sum, comp_carry;
    compressor_4to2_mux_array #(.WIDTH(40)) u_comp42 (
        .a(csa5_sum),
        .b({csa5_carry[38:0], 1'b0}),
        .c({csa3_carry[38:0], 1'b0}),
        .d(csa4_sum),
        .sum(comp_sum),
        .carry(comp_carry)
    );
    
    // Final CSA: 3→2
    wire [39:0] final_sum, final_carry;
    csa #(.WIDTH(40)) u_csa6 (
        .a(comp_sum),
        .b({comp_carry[38:0], 1'b0}),
        .c({csa4_carry[38:0], 1'b0}),
        .sum(final_sum),
        .carry(final_carry)
    );
    
    // S3 Output Registers
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result_sum <= 40'b0; result_carry <= 40'b0;
            valid_out <= 1'b0;
        end else if (valid_s2) begin
            result_sum   <= final_sum;
            result_carry <= {final_carry[38:0], 1'b0};
            valid_out <= 1'b1;
        end else begin
            valid_out <= 1'b0;
        end
    end

endmodule
