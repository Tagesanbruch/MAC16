`timescale 1ns/1ps
module tb_mult16_pipeline_simple;

    logic        clk;
    logic        rst_n;
    logic [15:0] a, b;
    logic        valid_in;
    logic [31:0] product;
    logic        valid_out;

    // Instantiate the pipeline multiplier
    mult16_pipeline u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .a(a),
        .b(b),
        .valid_in(valid_in),
        .product(product),
        .valid_out(valid_out)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #0.5 clk = ~clk;
    end

    // Test procedure
    initial begin
        $dumpfile("build/tb_mult16_pipe_simple.vcd");
        $dumpvars(0, tb_mult16_pipeline_simple);

        $display("Simple Pipeline Test");

        // Reset
        rst_n = 0;
        a = 0;
        b = 0;
        valid_in = 0;

        repeat(3) @(posedge clk);
        rst_n = 1;
        $display("T=%0t: Reset complete", $time);

        @(posedge clk);

        // Test: 3 * 4 = 12
        $display("\nT=%0t: Starting test 3*4", $time);
        a = 16'd3;
        b = 16'd4;
        valid_in = 1;

        @(posedge clk);
        $display("T=%0t: Cycle 1 - valid_in=%b, valid_s1=%b, valid_out=%b, product=%0d",
                 $time, valid_in, u_dut.valid_s1, valid_out, product);
        valid_in = 0;

        @(posedge clk);
        $display("T=%0t: Cycle 2 - valid_in=%b, valid_s1=%b, valid_s2=%b, valid_out=%b, product=%0d",
                 $time, valid_in, u_dut.valid_s1, u_dut.valid_s2, valid_out, product);

        @(posedge clk);
        $display("T=%0t: Cycle 3 - valid_in=%b, valid_s1=%b, valid_s2=%b, valid_out=%b, product=%0d",
                 $time, valid_in, u_dut.valid_s1, u_dut.valid_s2, valid_out, product);

        if (valid_out == 1 && product == 12) begin
            $display("*** TEST PASSED ***");
        end else begin
            $display("*** TEST FAILED *** (expected valid_out=1, product=12)");
        end

        #10;
        $finish;
    end

endmodule
