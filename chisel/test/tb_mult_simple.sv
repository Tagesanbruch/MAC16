`timescale 1ns/1ps
module tb_mult_simple;
    reg clk = 0;
    reg rst_n = 0;
    reg [15:0] a, b;
    reg valid_in;
    wire [31:0] product;
    wire valid_out;

    always #0.5 clk = ~clk;

    Mult16Booth dut (
        .clock(clk),
        .reset(~rst_n),
        .io_a(a),
        .io_b(b),
        .io_validIn(valid_in),
        .io_product(product),
        .io_validOut(valid_out)
    );

    initial begin
        rst_n = 0;
        a = 0; b = 0; valid_in = 0;
        #10 rst_n = 1;
        
        // Test 1: 2 * 6 = 12
        #2 a = 16'd2; b = 16'd6; valid_in = 1;
        #1 valid_in = 0;
        wait(valid_out);
        #0.1;
        if (product == 12)
            $display("Test 1 PASSED: 2 * 6 = %d", product);
        else
            $display("Test 1 FAILED: 2 * 6 = %d (expected 12)", product);
        
        #2;
        
        // Test 2: 8 * 30 = 240
        a = 16'd8; b = 16'd30; valid_in = 1;
        #1 valid_in = 0;
        wait(valid_out);
        #0.1;
        if (product == 240)
            $display("Test 2 PASSED: 8 * 30 = %d", product);
        else
            $display("Test 2 FAILED: 8 * 30 = %d (expected 240)", product);
        
        #5 $finish;
    end
endmodule
