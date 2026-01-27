`timescale 1ns/1ps
module tb_mac16_compare;
    logic clk = 0;
    logic rst_n = 0;
    logic mode = 0;
    logic inA = 0;
    logic inB = 0;

    wire sum_out_chisel, carry_chisel, out_ready_chisel;
    wire sum_out_orig, carry_orig, out_ready_orig;

    localparam real CLK_PERIOD = 1.0;
    localparam INPUT_BITS = 16;
    localparam OUTPUT_BITS = 24;

    always #(CLK_PERIOD/2) clk = ~clk;

    mac16 dut_chisel (
        .clk(clk),
        .rst_n(rst_n),
        .mode(mode),
        .inA(inA),
        .inB(inB),
        .sum_out(sum_out_chisel),
        .carry(carry_chisel),
        .out_ready(out_ready_chisel)
    );

    mac16_orig dut_orig (
        .clk(clk),
        .rst_n(rst_n),
        .mode(mode),
        .inA(inA),
        .inB(inB),
        .sum_out(sum_out_orig),
        .carry(carry_orig),
        .out_ready(out_ready_orig)
    );

    logic [15:0] test_a [0:1];
    logic [15:0] test_b [0:1];

    initial begin
        test_a[0] = 16'd2;  test_b[0] = 16'd6;
        test_a[1] = 16'd8;  test_b[1] = 16'd30;
    end

    int errors;
    logic [23:0] result_chisel;
    logic [23:0] result_orig;

    task automatic do_one_mac_compare(input logic [15:0] a, input logic [15:0] b);
        int i;
        result_chisel = '0;
        result_orig = '0;

        for (i = INPUT_BITS-1; i >= 0; i--) begin
            inA = a[i];
            inB = b[i];
            @(posedge clk);
        end
        inA = 0;
        inB = 0;

        wait(out_ready_chisel || out_ready_orig);

        for (i = OUTPUT_BITS-1; i >= 0; i--) begin
            @(posedge clk);
            if (out_ready_chisel !== out_ready_orig) begin
                $display("OUT_READY MISMATCH: chisel=%0b orig=%0b at bit %0d", out_ready_chisel, out_ready_orig, i);
                errors++;
            end
            if (out_ready_chisel) begin
                result_chisel[i] = sum_out_chisel;
                result_orig[i] = sum_out_orig;
                if (sum_out_chisel !== sum_out_orig) begin
                    $display("SUM_OUT MISMATCH: chisel=%0b orig=%0b at bit %0d", sum_out_chisel, sum_out_orig, i);
                    errors++;
                end
            end
        end

        wait(!out_ready_chisel && !out_ready_orig);

        if (result_chisel !== result_orig) begin
            $display("RESULT MISMATCH: chisel=%0h orig=%0h", result_chisel, result_orig);
            errors++;
        end else begin
            $display("RESULT MATCH: %0h", result_chisel);
        end
    endtask

    initial begin
        errors = 0;
        rst_n = 0;
        repeat(2) @(posedge clk);
        rst_n = 1;

        $display("=== Compare Mode 0 ===");
        mode = 0;
        do_one_mac_compare(test_a[0], test_b[0]);
        do_one_mac_compare(test_a[1], test_b[1]);

        $display("=== Compare Mode 1 ===");
        rst_n = 0;
        repeat(2) @(posedge clk);
        rst_n = 1;
        mode = 1;
        do_one_mac_compare(test_a[0], test_b[0]);
        do_one_mac_compare(test_a[1], test_b[1]);

        if (errors == 0)
            $display("COMPARE PASSED");
        else
            $display("COMPARE FAILED with %0d errors", errors);

        #10 $finish;
    end
endmodule
