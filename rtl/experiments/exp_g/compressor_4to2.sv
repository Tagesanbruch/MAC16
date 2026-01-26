`timescale 1ns/1ps
//============================================================================
// Exp G: 4:2 Compressor
// Yosys-compatible Verilog
//
// Compresses 4 input bits + carry_in to 2 output bits (sum, carry) + carry_out
// Critical path: ~3 XOR gate delays
//============================================================================
module compressor_4to2 (
    input  wire a,
    input  wire b,
    input  wire c,
    input  wire d,
    input  wire cin,
    output wire sum,
    output wire carry,
    output wire cout
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
// Yosys-compatible Verilog
//============================================================================
module compressor_4to2_array #(
    parameter WIDTH = 32
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
