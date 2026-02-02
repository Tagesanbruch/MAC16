`timescale 1ns/1ps
//============================================================================
// Carry Save Adder (3:2)
//============================================================================
module csa #(
    parameter WIDTH = 32
)(
    input  logic [WIDTH-1:0] a,
    input  logic [WIDTH-1:0] b,
    input  logic [WIDTH-1:0] c,
    output logic [WIDTH-1:0] sum,
    output logic [WIDTH-1:0] carry
);
    assign sum   = a ^ b ^ c;
    assign carry = (a & b) | (b & c) | (a & c);
endmodule
