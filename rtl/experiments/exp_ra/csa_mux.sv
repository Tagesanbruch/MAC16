`timescale 1ns/1ps
//============================================================================
// MUX-optimized 3:2 CSA (Carry-Save Adder)
// 
// Uses MUX-based carry generation for faster critical path.
// Reference: For 3:2 compressor (full adder):
//   sum = a ^ b ^ c
//   carry = (a & b) | (c & (a ^ b))
//        = (ab_xor & c) | (~ab_xor & a)   [MUX form: sel=ab_xor, 1=c, 0=a]
//============================================================================
module csa_mux #(
    parameter WIDTH = 40
) (
    input  wire [WIDTH-1:0] a,
    input  wire [WIDTH-1:0] b,
    input  wire [WIDTH-1:0] c,
    output wire [WIDTH-1:0] sum,
    output wire [WIDTH-1:0] carry
);

    wire [WIDTH-1:0] ab_xor = a ^ b;
    
    assign sum = ab_xor ^ c;
    // Bitwise MUX: when ab_xor[i]=1, carry[i]=c[i]; else carry[i]=a[i]
    assign carry = (ab_xor & c) | (~ab_xor & a);

endmodule
