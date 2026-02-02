`timescale 1ns/1ps
//============================================================================
// Exp UE v4: Optimized 4-Stage Mult + 1-Stage Pipelined VMA
// 
// Key Fix: PP alignment deferred from Stage 1 to Stage 2 (like exp_sd)
// 
// Stage 1: Booth + PPG → 8 raw PPs (33-bit each, no alignment)
// Stage 2: PP Alignment + CSA L1 (8→4)
// Stage 3: CSA L2 (4+2=6 rows → 4) + 4:2 Compressor (4→2)
// Stage 4: VMA Low 20-bit
// Stage 5: VMA High 20-bit
// 
// Total Latency: 5 cycles
//============================================================================
module mult16_booth_dcs_pipelined_vma (
    input  wire         clk,
    input  wire         rst_n,
    input  wire  [15:0] a,
    input  wire  [15:0] b,
    input  wire         valid_in,
    input  wire         mode_in,
    input  wire         first_op_in,
    output reg   [39:0] result_binary,
    output reg          valid_out
);

    reg [39:0] acc_sum, acc_carry;
    reg [39:0] prev_prod_sum, prev_prod_carry;
    reg        mode_s1, mode_s2, mode_s3;

    logic [39:0] fb_sum_node, fb_carry_node;
    always_comb begin
        if (first_op_in) begin
            fb_sum_node = 40'b0;
            fb_carry_node = 40'b0;
        end else if (mode_in == 1'b0) begin
            fb_sum_node = prev_prod_sum;
            fb_carry_node = prev_prod_carry;
        end else begin
            fb_sum_node = acc_sum;
            fb_carry_node = acc_carry;
        end
    end

    //=========================================================================
    // Stage 1: Booth Encoding + PPG (8 raw PPs, 33-bit each)
    // NO alignment here - keep depth shallow
    //=========================================================================
    wire [7:0] neg, zero, two;
    booth_encoder u_booth (.b(b), .neg(neg), .zero(zero), .two(two));

    wire [32:0] pp[7:0];
    partial_product_gen u_ppg (
        .a(a), .neg(neg), .zero(zero), .two(two),
        .pp0(pp[0]), .pp1(pp[1]), .pp2(pp[2]), .pp3(pp[3]),
        .pp4(pp[4]), .pp5(pp[5]), .pp6(pp[6]), .pp7(pp[7])
    );

    reg [32:0] r1_pp[7:0];
    reg [39:0] r1_fb_sum, r1_fb_carry;
    reg        v1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v1 <= 0;
            r1_pp[0] <= '0; r1_pp[1] <= '0; r1_pp[2] <= '0; r1_pp[3] <= '0;
            r1_pp[4] <= '0; r1_pp[5] <= '0; r1_pp[6] <= '0; r1_pp[7] <= '0;
            r1_fb_sum <= '0; r1_fb_carry <= '0;
            mode_s1 <= 0;
        end else begin
            v1 <= valid_in;
            mode_s1 <= mode_in;
            if (valid_in) begin
                r1_pp[0] <= pp[0]; r1_pp[1] <= pp[1];
                r1_pp[2] <= pp[2]; r1_pp[3] <= pp[3];
                r1_pp[4] <= pp[4]; r1_pp[5] <= pp[5];
                r1_pp[6] <= pp[6]; r1_pp[7] <= pp[7];
                r1_fb_sum <= fb_sum_node;
                r1_fb_carry <= fb_carry_node;
            end
        end
    end

    //=========================================================================
    // Stage 2: PP Alignment (combinational) + CSA L1 (8→4)
    // This is where we do alignment + 4-level CSA tree
    //=========================================================================
    wire [39:0] pp_a[7:0];
    assign pp_a[0] = {{7{r1_pp[0][32]}}, r1_pp[0]};
    assign pp_a[1] = {{5{r1_pp[1][32]}}, r1_pp[1], 2'b0};
    assign pp_a[2] = {{3{r1_pp[2][32]}}, r1_pp[2], 4'b0};
    assign pp_a[3] = {{1{r1_pp[3][32]}}, r1_pp[3], 6'b0};
    assign pp_a[4] = {r1_pp[4][30:0], 8'b0};
    assign pp_a[5] = {r1_pp[5][28:0], 10'b0};
    assign pp_a[6] = {r1_pp[6][26:0], 12'b0};
    assign pp_a[7] = {r1_pp[7][24:0], 14'b0};

    wire [39:0] s2_csa1_s, s2_csa1_c;
    csa #(.WIDTH(40)) u_csa1_s2 (.a(pp_a[0]), .b(pp_a[1]), .c(pp_a[2]), .sum(s2_csa1_s), .carry(s2_csa1_c));

    wire [39:0] s2_csa2_s, s2_csa2_c;
    csa #(.WIDTH(40)) u_csa2_s2 (.a(pp_a[3]), .b(pp_a[4]), .c(pp_a[5]), .sum(s2_csa2_s), .carry(s2_csa2_c));

    wire [39:0] s2_csa3_s, s2_csa3_c;
    csa #(.WIDTH(40)) u_csa3_s2 (.a(pp_a[6]), .b(pp_a[7]), .c({s2_csa1_c[38:0], 1'b0}), .sum(s2_csa3_s), .carry(s2_csa3_c));

    wire [39:0] s2_csa4_s, s2_csa4_c;
    csa #(.WIDTH(40)) u_csa4_s2 (.a(s2_csa1_s), .b(s2_csa2_s), .c({s2_csa2_c[38:0], 1'b0}), .sum(s2_csa4_s), .carry(s2_csa4_c));

    reg [39:0] r2_0, r2_1, r2_2, r2_3, r2_4, r2_5;
    reg        v2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v2 <= 0;
            r2_0 <= '0; r2_1 <= '0; r2_2 <= '0; r2_3 <= '0;
            r2_4 <= '0; r2_5 <= '0;
            mode_s2 <= 0;
        end else begin
            v2 <= v1;
            mode_s2 <= mode_s1;
            if (v1) begin
                r2_0 <= s2_csa3_s;
                r2_1 <= {s2_csa3_c[38:0], 1'b0};
                r2_2 <= s2_csa4_s;
                r2_3 <= {s2_csa4_c[38:0], 1'b0};
                r2_4 <= r1_fb_sum;
                r2_5 <= r1_fb_carry;
            end
        end
    end

    //=========================================================================
    // Stage 3: CSA L2 (6→4) + 4:2 Compressor (4→2)
    //=========================================================================
    wire [39:0] s3_csa1_s, s3_csa1_c;
    csa #(.WIDTH(40)) u_csa1_s3 (.a(r2_0), .b(r2_1), .c(r2_2), .sum(s3_csa1_s), .carry(s3_csa1_c));

    wire [39:0] s3_csa2_s, s3_csa2_c;
    csa #(.WIDTH(40)) u_csa2_s3 (.a(r2_3), .b(r2_4), .c(r2_5), .sum(s3_csa2_s), .carry(s3_csa2_c));

    wire [39:0] s3_final_sum, s3_final_carry;
    compressor_4to2_mux_array #(.WIDTH(40)) u_comp42 (
        .a(s3_csa1_s),
        .b({s3_csa1_c[38:0], 1'b0}),
        .c(s3_csa2_s),
        .d({s3_csa2_c[38:0], 1'b0}),
        .sum(s3_final_sum),
        .carry(s3_final_carry)
    );

    reg [39:0] r3_sum, r3_carry;
    reg        v3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v3 <= 0;
            r3_sum <= '0; r3_carry <= '0;
            acc_sum <= '0; acc_carry <= '0;
            prev_prod_sum <= '0; prev_prod_carry <= '0;
            mode_s3 <= 0;
        end else begin
            v3 <= v2;
            mode_s3 <= mode_s2;
            if (v2) begin
                if (mode_s2) begin
                    acc_sum <= s3_final_sum;
                    acc_carry <= {s3_final_carry[38:0], 1'b0};
                end else begin
                    prev_prod_sum <= s3_final_sum;
                    prev_prod_carry <= {s3_final_carry[38:0], 1'b0};
                end
                
                r3_sum <= s3_final_sum;
                r3_carry <= {s3_final_carry[38:0], 1'b0};
            end
        end
    end

    //=========================================================================
    // Stage 4: Pipelined VMA - Part 1 (Low 20 bits)
    //=========================================================================
    reg [19:0] vma_low_sum;
    reg        vma_mid_carry;
    reg [19:0] vma_high_op_a, vma_high_op_b;
    reg        v4;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v4 <= 0;
            vma_low_sum <= '0;
            vma_mid_carry <= 0;
            vma_high_op_a <= '0;
            vma_high_op_b <= '0;
        end else begin
            v4 <= v3;
            if (v3) begin
                {vma_mid_carry, vma_low_sum} <= r3_sum[19:0] + r3_carry[19:0];
                vma_high_op_a <= r3_sum[39:20];
                vma_high_op_b <= r3_carry[39:20];
            end
        end
    end

    //=========================================================================
    // Stage 5: Pipelined VMA - Part 2 (High 20 bits)
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 0;
            result_binary <= '0;
        end else begin
            valid_out <= v4;
            if (v4) begin
                result_binary[19:0] <= vma_low_sum;
                result_binary[39:20] <= vma_high_op_a + vma_high_op_b + vma_mid_carry;
            end
        end
    end

endmodule
