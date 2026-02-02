`timescale 1ns/1ps
//============================================================================
// LLCBC-style 6:2 Compression (pairwise CSA + 4:2)
// Compresses 6 input rows into 2 output rows (sum, carry)
//============================================================================
module llcbc_compressor_array #(
    parameter WIDTH = 32
)(
    input  logic [WIDTH-1:0] a,
    input  logic [WIDTH-1:0] b,
    input  logic [WIDTH-1:0] c,
    input  logic [WIDTH-1:0] d,
    input  logic [WIDTH-1:0] e,
    input  logic [WIDTH-1:0] f,
    output logic [WIDTH-1:0] sum,
    output logic [WIDTH-1:0] carry
);
    // First layer: two CSAs (3:2)
    wire [WIDTH-1:0] s1, c1;
    wire [WIDTH-1:0] s2, c2;
    csa #(.WIDTH(WIDTH)) u_csa1 (
        .a(a), .b(b), .c(c),
        .sum(s1), .carry(c1)
    );
    csa #(.WIDTH(WIDTH)) u_csa2 (
        .a(d), .b(e), .c(f),
        .sum(s2), .carry(c2)
    );

    // Second layer: 4:2 compressor on (s1, s2, c1<<1, c2<<1)
    compressor_4to2_array #(.WIDTH(WIDTH)) u_comp42 (
        .a(s1),
        .b(s2),
        .c({c1[WIDTH-2:0], 1'b0}),
        .d({c2[WIDTH-2:0], 1'b0}),
        .sum(sum),
        .carry(carry)
    );
endmodule
