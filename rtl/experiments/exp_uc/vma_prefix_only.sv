`timescale 1ns/1ps
//============================================================================
// VMA Prefix Only (Optimized for Pre-computed G/P)
// 
// This module takes pre-computed Generate (G) and Propagate (P) signals
// and only performs the prefix tree computation + final sum.
// 
// Optimization: G/P generation is moved to previous pipeline stage,
// reducing this module's critical path by 1 gate level (AND/XOR).
// 
// Structure: Han-Carlson Prefix Tree (6 levels for 40-bit)
//============================================================================
module vma_prefix_only #(
    parameter WIDTH = 40
) (
    input  wire [WIDTH-1:0] g_in,  // Pre-computed Generate
    input  wire [WIDTH-1:0] p_in,  // Pre-computed Propagate
    output wire [WIDTH-1:0] sum,
    output wire             cout
);

    // Use input G/P directly (no computation needed)
    wire [WIDTH-1:0] g = g_in;
    wire [WIDTH-1:0] p = p_in;
    
    // Level 1: Stride 1 (odd indices only)
    wire [WIDTH-1:0] g1, p1;
    genvar i;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : L1
            if (i == 0) begin
                assign g1[i] = g[i];
                assign p1[i] = p[i];
            end else if (i % 2 == 1) begin
                assign g1[i] = g[i] | (p[i] & g[i-1]);
                assign p1[i] = p[i] & p[i-1];
            end else begin
                assign g1[i] = g[i];
                assign p1[i] = p[i];
            end
        end
    endgenerate
    
    // Level 2: Stride 2
    wire [WIDTH-1:0] g2, p2;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : L2
            if (i < 3) begin
                assign g2[i] = g1[i];
                assign p2[i] = p1[i];
            end else if (i % 2 == 1) begin
                assign g2[i] = g1[i] | (p1[i] & g1[i-2]);
                assign p2[i] = p1[i] & p1[i-2];
            end else begin
                assign g2[i] = g1[i];
                assign p2[i] = p1[i];
            end
        end
    endgenerate
    
    // Level 3: Stride 4
    wire [WIDTH-1:0] g3, p3;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : L3
            if (i < 7) begin
                assign g3[i] = g2[i];
                assign p3[i] = p2[i];
            end else if (i % 2 == 1) begin
                assign g3[i] = g2[i] | (p2[i] & g2[i-4]);
                assign p3[i] = p2[i] & p2[i-4];
            end else begin
                assign g3[i] = g2[i];
                assign p3[i] = p2[i];
            end
        end
    endgenerate
    
    // Level 4: Stride 8
    wire [WIDTH-1:0] g4, p4;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : L4
            if (i < 15) begin
                assign g4[i] = g3[i];
                assign p4[i] = p3[i];
            end else if (i % 2 == 1) begin
                assign g4[i] = g3[i] | (p3[i] & g3[i-8]);
                assign p4[i] = p3[i] & p3[i-8];
            end else begin
                assign g4[i] = g3[i];
                assign p4[i] = p3[i];
            end
        end
    endgenerate
    
    // Level 5: Stride 16
    wire [WIDTH-1:0] g5, p5;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : L5
            if (i < 31) begin
                assign g5[i] = g4[i];
                assign p5[i] = p4[i];
            end else if (i % 2 == 1) begin
                assign g5[i] = g4[i] | (p4[i] & g4[i-16]);
                assign p5[i] = p4[i] & p4[i-16];
            end else begin
                assign g5[i] = g4[i];
                assign p5[i] = p4[i];
            end
        end
    endgenerate
    
    // Level 6: Stride 32 (for WIDTH > 32)
    wire [WIDTH-1:0] g6, p6;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : L6
            if (i < 39 && i % 2 == 1 && i >= 33) begin
                assign g6[i] = g5[i] | (p5[i] & g5[i-32]);
                assign p6[i] = p5[i] & p5[i-32];
            end else begin
                assign g6[i] = g5[i];
                assign p6[i] = p5[i];
            end
        end
    endgenerate
    
    // Reverse pass: Fill even positions
    wire [WIDTH-1:0] gf;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : REV
            if (i == 0) begin
                assign gf[i] = g6[i];
            end else if (i % 2 == 0) begin
                assign gf[i] = g6[i] | (p6[i] & g6[i-1]);
            end else begin
                assign gf[i] = g6[i];
            end
        end
    endgenerate
    
    // Final sum computation
    assign sum[0] = p[0];
    generate
        for (i = 1; i < WIDTH; i = i + 1) begin : SUM
            assign sum[i] = p[i] ^ gf[i-1];
        end
    endgenerate
    
    assign cout = gf[WIDTH-1];

endmodule
