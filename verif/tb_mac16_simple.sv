`timescale 1ns/1ps
module tb_mac16;
    logic clk;
    logic rst_n;
    logic mode;
    logic inA, inB;
    logic sum_out, carry, out_ready;

    mac16 dut (
        .clk(clk),
        .rst_n(rst_n),
        .mode(mode),
        .inA(inA),
        .inB(inB),
        .sum_out(sum_out),
        .carry(carry),
        .out_ready(out_ready)
    );

    initial begin
        clk = 0;
        forever #0.5 clk = ~clk;
    end

    initial begin
        rst_n = 0;
        #10 rst_n = 1;
        #100 $finish;
    end
endmodule
