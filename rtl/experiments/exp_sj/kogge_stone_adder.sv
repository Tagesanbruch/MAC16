`timescale 1ns/1ps
//============================================================================
// Kogge-Stone Parallel Prefix Adder
// 40-bit version with minimum logic depth (Log2 N = 6 levels)
// 
// Properties:
// - Maximum parallelism, minimum logic depth
// - Higher wiring complexity than Han-Carlson
// - Best for speed-critical applications
//============================================================================
module kogge_stone_adder #(
    parameter WIDTH = 40
) (
    input  wire [WIDTH-1:0] a,
    input  wire [WIDTH-1:0] b,
    output wire [WIDTH-1:0] sum,
    output wire             cout
);

    // Generate (G) and Propagate (P) - Level 0
    wire [WIDTH-1:0] g0, p0;
    assign g0 = a & b;
    assign p0 = a ^ b;
    
    // Level 1: stride = 1
    wire [WIDTH-1:0] g1, p1;
    genvar i;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : L1
            if (i == 0) begin
                assign g1[i] = g0[i];
                assign p1[i] = p0[i];
            end else begin
                assign g1[i] = g0[i] | (p0[i] & g0[i-1]);
                assign p1[i] = p0[i] & p0[i-1];
            end
        end
    endgenerate
    
    // Level 2: stride = 2
    wire [WIDTH-1:0] g2, p2;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : L2
            if (i < 2) begin
                assign g2[i] = g1[i];
                assign p2[i] = p1[i];
            end else begin
                assign g2[i] = g1[i] | (p1[i] & g1[i-2]);
                assign p2[i] = p1[i] & p1[i-2];
            end
        end
    endgenerate
    
    // Level 3: stride = 4
    wire [WIDTH-1:0] g3, p3;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : L3
            if (i < 4) begin
                assign g3[i] = g2[i];
                assign p3[i] = p2[i];
            end else begin
                assign g3[i] = g2[i] | (p2[i] & g2[i-4]);
                assign p3[i] = p2[i] & p2[i-4];
            end
        end
    endgenerate
    
    // Level 4: stride = 8
    wire [WIDTH-1:0] g4, p4;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : L4
            if (i < 8) begin
                assign g4[i] = g3[i];
                assign p4[i] = p3[i];
            end else begin
                assign g4[i] = g3[i] | (p3[i] & g3[i-8]);
                assign p4[i] = p3[i] & p3[i-8];
            end
        end
    endgenerate
    
    // Level 5: stride = 16
    wire [WIDTH-1:0] g5, p5;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : L5
            if (i < 16) begin
                assign g5[i] = g4[i];
                assign p5[i] = p4[i];
            end else begin
                assign g5[i] = g4[i] | (p4[i] & g4[i-16]);
                assign p5[i] = p4[i] & p4[i-16];
            end
        end
    endgenerate
    
    // Level 6: stride = 32
    wire [WIDTH-1:0] g6;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : L6
            if (i < 32) begin
                assign g6[i] = g5[i];
            end else begin
                assign g6[i] = g5[i] | (p5[i] & g5[i-32]);
            end
        end
    endgenerate
    
    // Final sum
    assign sum[0] = p0[0];
    generate
        for (i = 1; i < WIDTH; i = i + 1) begin : SUM
            assign sum[i] = p0[i] ^ g6[i-1];
        end
    endgenerate
    
    assign cout = g6[WIDTH-1];

endmodule
