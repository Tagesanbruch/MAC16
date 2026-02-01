`timescale 1ns/1ps
module tb_mult_simple;
    reg clk, rst_n;
    reg [15:0] a, b;
    reg valid_in;
    wire [31:0] product;
    wire valid_out;
    
    mult16_booth_5stage dut(.*);
    
    initial clk = 0;
    always #0.5 clk = ~clk;
    
    initial begin
        $dumpfile("build/test_mult.vcd");
        $dumpvars(0, tb_mult_simple);
        rst_n = 0;
        a = 0; b = 0;
        valid_in = 0;
        #2;
        rst_n = 1;
        #2;
        
        // Test 10 * 20 = 200
        a = 16'd10;
        b = 16'd20;
        valid_in = 1;
        #1;
        valid_in = 0;
        a = 0; b = 0;
        
        // Wait and check
        repeat(10) begin
            #1;
            $display("t=%0t: valid_out=%b, product=%d", $time, valid_out, $signed(product));
        end
        
        $finish;
    end
endmodule
