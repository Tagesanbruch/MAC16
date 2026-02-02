`timescale 1ns/1ps
//============================================================================
// MUX-Based 4:2 Compressor
//============================================================================
module compressor_4to2_mux (
    input  wire a, b, c, d,
    input  wire cin,
    output wire sum,
    output wire carry,
    output wire cout
);
    wire w1 = a ^ b;
    wire w2 = c ^ d;
    wire w3 = w1 ^ w2;
    assign cout = w1 ? c : a;
    assign sum = w3 ^ cin;
    assign carry = w3 ? cin : d;
endmodule

module compressor_4to2_mux_array #(
    parameter WIDTH = 40
)(
    input  wire [WIDTH-1:0] a,
    input  wire [WIDTH-1:0] b,
    input  wire [WIDTH-1:0] c,
    input  wire [WIDTH-1:0] d,
    output wire [WIDTH-1:0] sum,
    output wire [WIDTH-1:0] carry
);
    wire [WIDTH:0] cout_chain;
    assign cout_chain[0] = 1'b0;
    genvar i;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : comp_gen
            wire cout_bit;
            wire carry_bit;
            compressor_4to2_mux u_comp (
                .a(a[i]),
                .b(b[i]),
                .c(c[i]),
                .d(d[i]),
                .cin(cout_chain[i]),
                .sum(sum[i]),
                .carry(carry_bit),
                .cout(cout_bit)
            );
            assign cout_chain[i+1] = cout_bit;
            assign carry[i] = carry_bit;
        end
    endgenerate
endmodule
