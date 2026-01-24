`timescale 1ns/1ps
module mult16 (
    input  logic [15:0] a,
    input  logic [15:0] b,
    output logic [31:0] product
);
    assign product = a * b;
endmodule
