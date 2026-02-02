`timescale 1ns/1ps
//============================================================================
// Two's Complement to Sign-Magnitude Converter
// 
// For low-power Booth multiplication: convert TC input to {sign, magnitude}
// Optimization: negative numbers use ~input with +1 injected to CSA as hot-1
//============================================================================
module tc2sm #(
    parameter WIDTH = 16
)(
    input  wire [WIDTH-1:0] tc_in,      // Two's complement input
    output wire             sign,        // Sign bit (1 = negative)
    output wire [WIDTH-1:0] magnitude,   // Unsigned magnitude
    output wire             hot_one      // +1 correction signal for CSA injection
);

    assign sign = tc_in[WIDTH-1];
    
    // For negative numbers: magnitude = ~tc_in (and hot_one provides +1)
    // For positive numbers: magnitude = tc_in
    assign magnitude = sign ? ~tc_in : tc_in;
    assign hot_one = sign; // Inject +1 into CSA when input was negative

endmodule

//============================================================================
// Sign-Magnitude to Two's Complement Converter
//============================================================================
module sm2tc #(
    parameter WIDTH = 40
)(
    input  wire             sign,
    input  wire [WIDTH-1:0] magnitude,
    output wire [WIDTH-1:0] tc_out
);

    // If sign=1 (negative), output = -magnitude = ~magnitude + 1
    // If sign=0 (positive), output = magnitude
    assign tc_out = sign ? (~magnitude + 1'b1) : magnitude;

endmodule
