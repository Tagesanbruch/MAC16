`timescale 1ns/1ps
module tb_adder;
    reg [7:0] a, b;
    wire [8:0] sum;

    adder dut (.a(a), .b(b), .sum(sum));

    initial begin
        a = 8'd10; b = 8'd20;
        #10;
        $display("a=%d, b=%d, sum=%d", a, b, sum);
        if (sum == 30)
            $display("TEST PASSED");
        else
            $display("TEST FAILED");
        $finish;
    end
endmodule
