`timescale 1ns/1ps
//============================================================================
// Exp G: Optimized Partial Product Generator
// Yosys-compatible Verilog
// 
// KEY FIX: Remove +1 from negation path (was causing 17-bit adder in Stage 1)
// The neg signal (Hot 1) is now output separately to be injected into
// the compression tree as carry-ins
//
// This eliminates the hidden adder chain in PPG, reducing critical path.
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
    output wire [32:0] pp7,
    output wire [7:0]  neg_out  // Hot-1 bits to inject into compression tree
);

    // Extended A for 2A calculation
    wire [16:0] a_ext  = {a[15], a};       // Sign extend A to 17 bits
    wire [17:0] a_2x   = {a[15], a, 1'b0}; // 2*A (shift left, 18 bits)
    
    // Internal wires for each PP
    wire [17:0] a_sel0, a_sel1, a_sel2, a_sel3, a_sel4, a_sel5, a_sel6, a_sel7;
    wire [17:0] a_inv0, a_inv1, a_inv2, a_inv3, a_inv4, a_inv5, a_inv6, a_inv7;
    wire [17:0] a_fin0, a_fin1, a_fin2, a_fin3, a_fin4, a_fin5, a_fin6, a_fin7;
    
    // PP0: Select A or 2A, then invert if neg (NO +1!)
    assign a_sel0 = two[0] ? a_2x : {a_ext[16], a_ext};
    assign a_inv0 = neg[0] ? ~a_sel0 : a_sel0;
    assign a_fin0 = zero[0] ? 18'd0 : a_inv0;
    assign pp0 = {{15{a_fin0[17]}}, a_fin0};
    
    // PP1
    assign a_sel1 = two[1] ? a_2x : {a_ext[16], a_ext};
    assign a_inv1 = neg[1] ? ~a_sel1 : a_sel1;
    assign a_fin1 = zero[1] ? 18'd0 : a_inv1;
    assign pp1 = {{15{a_fin1[17]}}, a_fin1};
    
    // PP2
    assign a_sel2 = two[2] ? a_2x : {a_ext[16], a_ext};
    assign a_inv2 = neg[2] ? ~a_sel2 : a_sel2;
    assign a_fin2 = zero[2] ? 18'd0 : a_inv2;
    assign pp2 = {{15{a_fin2[17]}}, a_fin2};
    
    // PP3
    assign a_sel3 = two[3] ? a_2x : {a_ext[16], a_ext};
    assign a_inv3 = neg[3] ? ~a_sel3 : a_sel3;
    assign a_fin3 = zero[3] ? 18'd0 : a_inv3;
    assign pp3 = {{15{a_fin3[17]}}, a_fin3};
    
    // PP4
    assign a_sel4 = two[4] ? a_2x : {a_ext[16], a_ext};
    assign a_inv4 = neg[4] ? ~a_sel4 : a_sel4;
    assign a_fin4 = zero[4] ? 18'd0 : a_inv4;
    assign pp4 = {{15{a_fin4[17]}}, a_fin4};
    
    // PP5
    assign a_sel5 = two[5] ? a_2x : {a_ext[16], a_ext};
    assign a_inv5 = neg[5] ? ~a_sel5 : a_sel5;
    assign a_fin5 = zero[5] ? 18'd0 : a_inv5;
    assign pp5 = {{15{a_fin5[17]}}, a_fin5};
    
    // PP6
    assign a_sel6 = two[6] ? a_2x : {a_ext[16], a_ext};
    assign a_inv6 = neg[6] ? ~a_sel6 : a_sel6;
    assign a_fin6 = zero[6] ? 18'd0 : a_inv6;
    assign pp6 = {{15{a_fin6[17]}}, a_fin6};
    
    // PP7
    assign a_sel7 = two[7] ? a_2x : {a_ext[16], a_ext};
    assign a_inv7 = neg[7] ? ~a_sel7 : a_sel7;
    assign a_fin7 = zero[7] ? 18'd0 : a_inv7;
    assign pp7 = {{15{a_fin7[17]}}, a_fin7};
    
    // Output neg signals (Hot 1) - masked by zero
    // These will be injected into compression tree at proper LSB positions
    assign neg_out[0] = neg[0] & ~zero[0];
    assign neg_out[1] = neg[1] & ~zero[1];
    assign neg_out[2] = neg[2] & ~zero[2];
    assign neg_out[3] = neg[3] & ~zero[3];
    assign neg_out[4] = neg[4] & ~zero[4];
    assign neg_out[5] = neg[5] & ~zero[5];
    assign neg_out[6] = neg[6] & ~zero[6];
    assign neg_out[7] = neg[7] & ~zero[7];

endmodule
