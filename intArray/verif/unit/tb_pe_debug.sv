`timescale 1ns/1ps
module tb_pe_debug;
    reg clk, rst_n;
    reg enable, clear_acc;
    reg [15:0] a_in, b_in;
    reg valid_in;
    
    wire [15:0] a_out, b_out;
    wire valid_out;
    wire [39:0] acc_out;
    wire acc_valid;
    
    // Internal probe
    wire [31:0] mult_product = dut.mult_product;
    wire mult_valid_out = dut.mult_valid_out;
    wire mult_start = dut.mult_start;
    
    // Probe multiplier internals
    wire [15:0] mult_a_in = dut.u_mult.a;
    wire [15:0] mult_b_in = dut.u_mult.b;
    wire mult_valid_in = dut.u_mult.valid_in;
    wire mult_valid_s1 = dut.u_mult.valid_s1;
    wire [15:0] mult_a_s1 = dut.u_mult.a_s1;
    
    sa16x16_pe dut (.*);
    
    initial clk = 0;
    always #0.5 clk = ~clk;
    
    initial begin
        $dumpfile("build/tb_pe_debug.vcd");
        $dumpvars(0, tb_pe_debug);
        
        // Init
        rst_n = 0;
        enable = 0;
        clear_acc = 0;
        a_in = 0;
        b_in = 0;
        valid_in = 0;
        
        #2;
        rst_n = 1;
        #2;
        
        // Enable PE and clear accumulator
        enable = 1;
        clear_acc = 1;
        @(posedge clk);
        clear_acc = 0;
        
        $display("Starting test: 10 * 20 = 200");
        
        // Apply input AFTER clock edge
        @(posedge clk);
        #0.1;  // Small delay after clock edge
        a_in = 16'd10;
        b_in = 16'd20;
        valid_in = 1;
        $display("t=%0t: Setting a_in=%d, b_in=%d, valid_in=%b", $time, a_in, b_in, valid_in);
        
        @(posedge clk);
        #0.1;
        $display("t=%0t: mult_start=%b, enable=%b, valid_in=%b, mult_a=%d, mult_b=%d", 
                 $time, mult_start, enable, valid_in, mult_a_in, mult_b_in);
        valid_in = 0;
        a_in = 0;
        b_in = 0;
        
        // Wait and monitor
        repeat(10) begin
            @(posedge clk);
            $display("t=%0t: mult_valid_out=%b, mult_product=%d, acc_out=%d, acc_valid=%b, mult_valid_s1=%b, mult_a_s1=%d", 
                     $time, mult_valid_out, $signed(mult_product), $signed(acc_out), acc_valid, mult_valid_s1, mult_a_s1);
        end
        
        // Check result
        if (acc_out == 200) begin
            $display("PASS: acc_out = %d (expected 200)", acc_out);
        end else begin
            $display("FAIL: acc_out = %d (expected 200)", acc_out);
        end
        
        $finish;
    end
endmodule
