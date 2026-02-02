`timescale 1ns/1ps
//============================================================================
// 5:2 Compressor (implemented with CSA layers)
// Compresses 5 input rows into 2 output rows (sum, carry)
// Note: carry output is unshifted; shift left by 1 where required.
//============================================================================
module compressor_5to2_array #(
    parameter WIDTH = 32
)(
    input  logic [WIDTH-1:0] a,
    input  logic [WIDTH-1:0] b,
    input  logic [WIDTH-1:0] c,
    input  logic [WIDTH-1:0] d,
    input  logic [WIDTH-1:0] e,
    output logic [WIDTH-1:0] sum,
    output logic [WIDTH-1:0] carry
);
    // First reduction: 3:2 CSA on (a,b,c)
    wire [WIDTH-1:0] s1, c1;
    csa #(.WIDTH(WIDTH)) u_csa1 (
        .a(a), .b(b), .c(c),
        .sum(s1), .carry(c1)
    );

    // Second reduction: 3:2 CSA on (d,e,s1)
    wire [WIDTH-1:0] s2, c2;
    csa #(.WIDTH(WIDTH)) u_csa2 (
        .a(d), .b(e), .c(s1),
        .sum(s2), .carry(c2)
    );

    // Final reduction to 2 rows: s2 + (c1<<1) + (c2<<1)
    csa #(.WIDTH(WIDTH)) u_csa3 (
        .a(s2),
        .b({c1[WIDTH-2:0], 1'b0}),
        .c({c2[WIDTH-2:0], 1'b0}),
        .sum(sum), .carry(carry)
    );

endmodule
