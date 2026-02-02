`timescale 1ns/1ps
//============================================================================
// Exp_UA: MUX-Based 4:2 Compressor (Optimized for Speed)
//
// Key Optimizations:
// 1. Cout does NOT depend on Cin (critical for timing)
// 2. Uses MUX structure to guide synthesis to use MUX2 cells
// 3. Critical path: ~3 XOR gate delays (vs 4 in traditional design)
//
// Truth Table:
//   Cout = (A^B) ? C : A   -- MUX, independent of Cin
//   Sum  = A^B^C^D^Cin     -- 3-level XOR tree
//   Carry = (A^B^C^D) ? Cin : D  -- MUX structure
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
    // Level 1: Parallel XOR pairs (2 gates in parallel)
    wire axorb = a ^ b;
    wire cxord = c ^ d;
    
    // Level 2: XOR of the two pairs
    wire axorb_xor_cxord = axorb ^ cxord;
    
    // Cout: MUX structure, does NOT depend on Cin (critical optimization)
    // When axorb=1, output c; when axorb=0, output a
    // Synthesizes to a single MUX2 cell
    assign cout = axorb ? c : a;
    
    // Sum: 3-level XOR (axorb || cxord already computed, just add cin)
    assign sum = axorb_xor_cxord ^ cin;
    
    // Carry: MUX structure
    // When (a^b^c^d)=1 (odd number of 1s), carry=cin; else carry=d
    assign carry = axorb_xor_cxord ? cin : d;

endmodule

//============================================================================
// N-bit 4:2 Compressor Array
// Optimized: Cout chain is propagated but Cout does not depend on Cin,
// so the critical path is only through the Sum/Carry computation.
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
