`timescale 1ns/1ps
//============================================================================
// Partial Product Generator for Radix-4 Booth Multiplier
// Generates 8 partial products from 16-bit inputs A and B
//
// Each partial product is:
//   - A, 2A, -A, -2A, or 0 based on Booth encoding
//   - Sign extended to 33 bits (to handle signed multiplication)
//============================================================================
module partial_product_gen (
    input  wire [15:0] a,
    input  wire [7:0]  neg,    // Booth encoding signals
    input  wire [7:0]  zero,
    input  wire [7:0]  two,
    output wire [32:0] pp0,
    output wire [32:0] pp1,
    output wire [32:0] pp2,
    output wire [32:0] pp3,
    output wire [32:0] pp4,
    output wire [32:0] pp5,
    output wire [32:0] pp6,
    output wire [32:0] pp7
);

    // Extended A for 2A calculation
    wire [16:0] a_ext  = {a[15], a};      // Sign extend A
    wire [17:0] a_2x   = {a[15], a, 1'b0}; // 2*A (shift left)
    
    // Generate function for each PP
    function [32:0] gen_pp;
        input [17:0] a_2x_in;
        input [16:0] a_ext_in;
        input neg_in, zero_in, two_in;
        reg [17:0] a_sel, a_neg, a_final;
        begin
            a_sel = two_in ? a_2x_in : {a_ext_in[16], a_ext_in};
            a_neg = neg_in ? (~a_sel + 1'b1) : a_sel;
            a_final = zero_in ? 18'd0 : a_neg;
            gen_pp = {{15{a_final[17]}}, a_final};
        end
    endfunction
    
    assign pp0 = gen_pp(a_2x, a_ext, neg[0], zero[0], two[0]);
    assign pp1 = gen_pp(a_2x, a_ext, neg[1], zero[1], two[1]);
    assign pp2 = gen_pp(a_2x, a_ext, neg[2], zero[2], two[2]);
    assign pp3 = gen_pp(a_2x, a_ext, neg[3], zero[3], two[3]);
    assign pp4 = gen_pp(a_2x, a_ext, neg[4], zero[4], two[4]);
    assign pp5 = gen_pp(a_2x, a_ext, neg[5], zero[5], two[5]);
    assign pp6 = gen_pp(a_2x, a_ext, neg[6], zero[6], two[6]);
    assign pp7 = gen_pp(a_2x, a_ext, neg[7], zero[7], two[7]);

endmodule
