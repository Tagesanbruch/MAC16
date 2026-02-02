`timescale 1ns/1ps
//============================================================================
// 7:3 Counter Array
// For each bit position, counts 7 input bits into 3 output bits
// sum (weight 1), carry1 (weight 2), carry2 (weight 4)
//============================================================================
module counter_7to3_array #(
    parameter WIDTH = 32
)(
    input  logic [WIDTH-1:0] a,
    input  logic [WIDTH-1:0] b,
    input  logic [WIDTH-1:0] c,
    input  logic [WIDTH-1:0] d,
    input  logic [WIDTH-1:0] e,
    input  logic [WIDTH-1:0] f,
    input  logic [WIDTH-1:0] g,
    output logic [WIDTH-1:0] sum,
    output logic [WIDTH-1:0] carry1,
    output logic [WIDTH-1:0] carry2
);
    genvar i;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : cnt73
            wire [2:0] count = a[i] + b[i] + c[i] + d[i] + e[i] + f[i] + g[i];
            assign sum[i]    = count[0];
            assign carry1[i] = count[1];
            assign carry2[i] = count[2];
        end
    endgenerate
endmodule
