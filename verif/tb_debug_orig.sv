`timescale 1ns/1ps
module tb_debug_orig;
    logic clk, rst_n, mode, inA, inB, sum_out, carry, out_ready;
    mac16 dut (.*);
    initial clk = 0;
    always #0.5 clk = ~clk;
    logic [23:0] result;
    
    always @(posedge clk) begin
        if (dut.state == 0) 
            $display("T=%0t: S_INPUT cnt=%0d, shift_a=%0d shift_b=%0d, inA=%b inB=%b", 
                     $time, dut.cnt, dut.shift_a, dut.shift_b, inA, inB);
        if (dut.state == 1) 
            $display("T=%0t: S_MULT_STAGE1, shift_a=%0d shift_b=%0d", $time, dut.shift_a, dut.shift_b);
    end
    
    task automatic do_one_mac(input logic [15:0] a, input logic [15:0] b);
        $display("\n--- Starting MAC: A=%0d, B=%0d ---", a, b);
        for (int i = 15; i >= 0; i--) begin
            inA = a[i]; inB = b[i]; @(posedge clk);
        end
        inA = 0; inB = 0;
        wait(out_ready == 1'b1);
        result = 0;
        for (int i = 23; i >= 0; i--) begin
            @(posedge clk); result[i] = sum_out;
        end
        $display("T=%0t: Result = %0d", $time, result);
        wait(out_ready == 1'b0);
    endtask
    
    initial begin
        rst_n = 0; mode = 0; inA = 0; inB = 0;
        repeat(3) @(posedge clk);
        rst_n = 1;
        $display("T=%0t: Reset released", $time);
        do_one_mac(16'd8, 16'd30);
        do_one_mac(16'd5, 16'd7);
        #20; $finish;
    end
endmodule
