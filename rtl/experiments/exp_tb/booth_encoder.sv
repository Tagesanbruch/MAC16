`timescale 1ns/1ps
//============================================================================
// Radix-4 Booth Encoder
// Generates encoding signals for 8 partial products from 16-bit input B
//============================================================================
module booth_encoder (
    input  logic [15:0] b,
    output logic [7:0]  neg,
    output logic [7:0]  zero,
    output logic [7:0]  two
);
    wire [16:0] b_ext = {b, 1'b0};
    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : booth_gen
            wire [2:0] group = b_ext[2*i+2 : 2*i];
            assign neg[i]  = group[2];
            assign zero[i] = (group == 3'b000) || (group == 3'b111);
            assign two[i]  = (group == 3'b011) || (group == 3'b100);
        end
    endgenerate
endmodule
