`timescale 1ns/1ps
//============================================================================
// Radix-4 Booth Encoder
// Generates encoding signals for 8 partial products from 16-bit input B
//
// Booth recoding reduces partial products from 16 to 8
// Encoding: examines groups of 3 bits (b[2i+1], b[2i], b[2i-1])
//============================================================================
module booth_encoder (
    input  logic [15:0] b,
    output logic [7:0]  neg,    // Negate partial product
    output logic [7:0]  zero,   // Zero partial product
    output logic [7:0]  two     // Double partial product
);

    // Extended B with implicit -1 bit = 0
    wire [16:0] b_ext = {b, 1'b0};
    
    // Generate 8 Booth encodings
    // Each group examines bits: b[2i+1], b[2i], b[2i-1]
    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : booth_gen
            wire [2:0] group = b_ext[2*i+2 : 2*i];
            
            // Booth decoding truth table:
            // group | action | neg | zero | two
            // 000   |   0    |  0  |   1  |  0
            // 001   |  +1    |  0  |   0  |  0
            // 010   |  +1    |  0  |   0  |  0
            // 011   |  +2    |  0  |   0  |  1
            // 100   |  -2    |  1  |   0  |  1
            // 101   |  -1    |  1  |   0  |  0
            // 110   |  -1    |  1  |   0  |  0
            // 111   |   0    |  0  |   1  |  0
            
            assign neg[i]  = group[2];
            assign zero[i] = (group == 3'b000) || (group == 3'b111);
            assign two[i]  = (group == 3'b011) || (group == 3'b100);
        end
    endgenerate

endmodule
