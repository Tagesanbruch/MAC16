`timescale 1ns/1ps
//============================================================================
// Kogge-Stone Parallel Prefix Adder
// Yosys-compatible Verilog 2005
// 
// Features:
//   - O(log N) delay for N-bit addition
//   - Highly parallel structure
//   - Optimal for high-speed applications
//
// Structure (24-bit example):
//   - 5 levels of computation (log2(24) ≈ 5)
//   - Generate (G) and Propagate (P) signals
//============================================================================
module kogge_stone_adder #(
    parameter WIDTH = 24
)(
    input  wire [WIDTH-1:0] a,
    input  wire [WIDTH-1:0] b,
    input  wire             cin,
    output wire [WIDTH-1:0] sum,
    output wire             cout
);

    // Generate and Propagate
    wire [WIDTH-1:0] g0 = a & b;
    wire [WIDTH-1:0] p0 = a ^ b;
    
    // Prefix tree levels
    // Level 1: span = 1
    wire [WIDTH-1:0] g1, p1;
    // Level 2: span = 2
    wire [WIDTH-1:0] g2, p2;
    // Level 3: span = 4
    wire [WIDTH-1:0] g3, p3;
    // Level 4: span = 8
    wire [WIDTH-1:0] g4, p4;
    // Level 5: span = 16
    wire [WIDTH-1:0] g5, p5;
    
    genvar i;
    
    // Level 1: combine pairs
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : level1
            if (i == 0) begin
                assign g1[i] = g0[i] | (p0[i] & cin);
                assign p1[i] = p0[i];
            end else begin
                assign g1[i] = g0[i] | (p0[i] & g0[i-1]);
                assign p1[i] = p0[i] & p0[i-1];
            end
        end
    endgenerate
    
    // Level 2: span 2
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : level2
            if (i < 2) begin
                assign g2[i] = g1[i];
                assign p2[i] = p1[i];
            end else begin
                assign g2[i] = g1[i] | (p1[i] & g1[i-2]);
                assign p2[i] = p1[i] & p1[i-2];
            end
        end
    endgenerate
    
    // Level 3: span 4
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : level3
            if (i < 4) begin
                assign g3[i] = g2[i];
                assign p3[i] = p2[i];
            end else begin
                assign g3[i] = g2[i] | (p2[i] & g2[i-4]);
                assign p3[i] = p2[i] & p2[i-4];
            end
        end
    endgenerate
    
    // Level 4: span 8
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : level4
            if (i < 8) begin
                assign g4[i] = g3[i];
                assign p4[i] = p3[i];
            end else begin
                assign g4[i] = g3[i] | (p3[i] & g3[i-8]);
                assign p4[i] = p3[i] & p3[i-8];
            end
        end
    endgenerate
    
    // Level 5: span 16
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : level5
            if (i < 16) begin
                assign g5[i] = g4[i];
                assign p5[i] = p4[i];
            end else begin
                assign g5[i] = g4[i] | (p4[i] & g4[i-16]);
                assign p5[i] = p4[i] & p4[i-16];
            end
        end
    endgenerate
    
    // Final carry chain (g5 holds the carries)
    wire [WIDTH:0] c;
    assign c[0] = cin;
    
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : carry_gen
            assign c[i+1] = g5[i];
        end
    endgenerate
    
    // Sum = P XOR C
    assign sum = p0 ^ c[WIDTH-1:0];
    assign cout = c[WIDTH];

endmodule

//============================================================================
// 40-bit Kogge-Stone Adder
// Yosys-compatible Verilog 2005
//============================================================================
module kogge_stone_40bit (
    input  wire [39:0] a,
    input  wire [39:0] b,
    output wire [39:0] sum,
    output wire        cout
);

    // Generate and Propagate
    wire [39:0] g0 = a & b;
    wire [39:0] p0 = a ^ b;
    
    // 6 levels needed for 40 bits
    wire [39:0] g1, p1, g2, p2, g3, p3, g4, p4, g5, p5, g6, p6;
    
    genvar i;
    
    // Level 1
    generate
        for (i = 0; i < 40; i = i + 1) begin : level1
            if (i == 0) begin
                assign g1[i] = g0[i];
                assign p1[i] = p0[i];
            end else begin
                assign g1[i] = g0[i] | (p0[i] & g0[i-1]);
                assign p1[i] = p0[i] & p0[i-1];
            end
        end
    endgenerate
    
    // Level 2: span 2
    generate
        for (i = 0; i < 40; i = i + 1) begin : level2
            if (i < 2) begin
                assign g2[i] = g1[i];
                assign p2[i] = p1[i];
            end else begin
                assign g2[i] = g1[i] | (p1[i] & g1[i-2]);
                assign p2[i] = p1[i] & p1[i-2];
            end
        end
    endgenerate
    
    // Level 3: span 4
    generate
        for (i = 0; i < 40; i = i + 1) begin : level3
            if (i < 4) begin
                assign g3[i] = g2[i];
                assign p3[i] = p2[i];
            end else begin
                assign g3[i] = g2[i] | (p2[i] & g2[i-4]);
                assign p3[i] = p2[i] & p2[i-4];
            end
        end
    endgenerate
    
    // Level 4: span 8
    generate
        for (i = 0; i < 40; i = i + 1) begin : level4
            if (i < 8) begin
                assign g4[i] = g3[i];
                assign p4[i] = p3[i];
            end else begin
                assign g4[i] = g3[i] | (p3[i] & g3[i-8]);
                assign p4[i] = p3[i] & p3[i-8];
            end
        end
    endgenerate
    
    // Level 5: span 16
    generate
        for (i = 0; i < 40; i = i + 1) begin : level5
            if (i < 16) begin
                assign g5[i] = g4[i];
                assign p5[i] = p4[i];
            end else begin
                assign g5[i] = g4[i] | (p4[i] & g4[i-16]);
                assign p5[i] = p4[i] & p4[i-16];
            end
        end
    endgenerate
    
    // Level 6: span 32
    generate
        for (i = 0; i < 40; i = i + 1) begin : level6
            if (i < 32) begin
                assign g6[i] = g5[i];
                assign p6[i] = p5[i];
            end else begin
                assign g6[i] = g5[i] | (p5[i] & g5[i-32]);
                assign p6[i] = p5[i] & p5[i-32];
            end
        end
    endgenerate
    
    // Final carry
    wire [40:0] c;
    assign c[0] = 1'b0;
    
    generate
        for (i = 0; i < 40; i = i + 1) begin : carry_gen
            assign c[i+1] = g6[i];
        end
    endgenerate
    
    assign sum = p0 ^ c[39:0];
    assign cout = c[40];

endmodule
