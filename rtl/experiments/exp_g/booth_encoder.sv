`timescale 1ns/1ps
//============================================================================
// Exp G: Radix-4 Booth Encoder
// Yosys-compatible Verilog
// 
// Generates encoding signals for 8 partial products from 16-bit input B
// Booth recoding reduces partial products from 16 to 8
//============================================================================
module booth_encoder (
    input  wire [15:0] b,
    output wire [7:0]  neg,    // Negate partial product
    output wire [7:0]  zero,   // Zero partial product
    output wire [7:0]  two     // Double partial product
);

    // Extended B with implicit -1 bit = 0
    wire [16:0] b_ext = {b, 1'b0};
    
    // Manual unrolling for Yosys compatibility (no genvar in function)
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
    
    // Group 0: bits [2:0]
    assign neg[0]  = b_ext[2];
    assign zero[0] = (b_ext[2:0] == 3'b000) | (b_ext[2:0] == 3'b111);
    assign two[0]  = (b_ext[2:0] == 3'b011) | (b_ext[2:0] == 3'b100);
    
    // Group 1: bits [4:2]
    assign neg[1]  = b_ext[4];
    assign zero[1] = (b_ext[4:2] == 3'b000) | (b_ext[4:2] == 3'b111);
    assign two[1]  = (b_ext[4:2] == 3'b011) | (b_ext[4:2] == 3'b100);
    
    // Group 2: bits [6:4]
    assign neg[2]  = b_ext[6];
    assign zero[2] = (b_ext[6:4] == 3'b000) | (b_ext[6:4] == 3'b111);
    assign two[2]  = (b_ext[6:4] == 3'b011) | (b_ext[6:4] == 3'b100);
    
    // Group 3: bits [8:6]
    assign neg[3]  = b_ext[8];
    assign zero[3] = (b_ext[8:6] == 3'b000) | (b_ext[8:6] == 3'b111);
    assign two[3]  = (b_ext[8:6] == 3'b011) | (b_ext[8:6] == 3'b100);
    
    // Group 4: bits [10:8]
    assign neg[4]  = b_ext[10];
    assign zero[4] = (b_ext[10:8] == 3'b000) | (b_ext[10:8] == 3'b111);
    assign two[4]  = (b_ext[10:8] == 3'b011) | (b_ext[10:8] == 3'b100);
    
    // Group 5: bits [12:10]
    assign neg[5]  = b_ext[12];
    assign zero[5] = (b_ext[12:10] == 3'b000) | (b_ext[12:10] == 3'b111);
    assign two[5]  = (b_ext[12:10] == 3'b011) | (b_ext[12:10] == 3'b100);
    
    // Group 6: bits [14:12]
    assign neg[6]  = b_ext[14];
    assign zero[6] = (b_ext[14:12] == 3'b000) | (b_ext[14:12] == 3'b111);
    assign two[6]  = (b_ext[14:12] == 3'b011) | (b_ext[14:12] == 3'b100);
    
    // Group 7: bits [16:14]
    assign neg[7]  = b_ext[16];
    assign zero[7] = (b_ext[16:14] == 3'b000) | (b_ext[16:14] == 3'b111);
    assign two[7]  = (b_ext[16:14] == 3'b011) | (b_ext[16:14] == 3'b100);

endmodule
