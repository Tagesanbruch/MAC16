`timescale 1ns/1ps
//============================================================================
// 4:2 Compressor
// Compresses 4 input bits + carry_in to 2 output bits (sum, carry) + carry_out
//
// Critical path: ~3 XOR gate delays
// Truth: Cout = majority(A,B,C), S = A^B^C^D^Cin, C = D^Cin ? (A^B^C) : D
//============================================================================
module compressor_4to2 (
    input  logic a,
    input  logic b,
    input  logic c,
    input  logic d,
    input  logic cin,
    output logic sum,
    output logic carry,
    output logic cout
);

    wire w1 = a ^ b;
    wire w2 = c ^ d;
    wire w3 = w1 ^ w2;
    
    // Carry out - does not depend on cin (critical for timing)
    assign cout = w1 ? c : a;
    
    // Sum
    assign sum = w3 ^ cin;
    
    // Carry - depends on cin
    assign carry = w3 ? cin : d;

endmodule

//============================================================================
// N-bit 4:2 Compressor Array
//============================================================================
module compressor_4to2_array #(
    parameter WIDTH = 32
)(
    input  logic [WIDTH-1:0] a,
    input  logic [WIDTH-1:0] b,
    input  logic [WIDTH-1:0] c,
    input  logic [WIDTH-1:0] d,
    output logic [WIDTH-1:0] sum,
    output logic [WIDTH-1:0] carry
);

    logic [WIDTH:0] cout_chain;
    assign cout_chain[0] = 1'b0;
    
    genvar i;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : comp_gen
            compressor_4to2 u_comp (
                .a(a[i]),
                .b(b[i]),
                .c(c[i]),
                .d(d[i]),
                .cin(cout_chain[i]),
                .sum(sum[i]),
                .carry(carry[i]),
                .cout(cout_chain[i+1])
            );
        end
    endgenerate

endmodule
