`timescale 1ns/1ps

module tb_mac16;

    logic clk;
    logic rst_n;
    logic mode;
    logic inA;
    logic inB;
    logic sum_out;
    logic carry;
    logic out_ready;

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

    localparam real CLK_PERIOD = 1.0;
    localparam INPUT_BITS = 16;
    localparam OUTPUT_BITS = 24;

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    logic [15:0] test_a [0:5];
    logic [15:0] test_b [0:5];

    initial begin
        test_a[0] = 16'd2; test_a[1] = 16'd8; test_a[2] = 16'd14;
        test_a[3] = 16'd116; test_a[4] = 16'd1546; test_a[5] = 16'd20698;
        
        test_b[0] = 16'd6; test_b[1] = 16'd30; test_b[2] = 16'd71;
        test_b[3] = 16'd828; test_b[4] = 16'd1152; test_b[5] = 16'd728;
    end

    logic [23:0] expected_out;
    logic [23:0] received_out;
    logic [31:0] accum_ref;
    logic [31:0] prev_product_ref;
    int errors;

    task automatic do_one_mac(input logic [15:0] a, input logic [15:0] b, output logic [23:0] result);
        int i;
        result = '0;
        
        for (i = INPUT_BITS-1; i >= 0; i--) begin
            inA = a[i];
            inB = b[i];
            @(posedge clk);
        end
        inA = 0;
        inB = 0;
        
        wait(out_ready == 1'b1);
        
        for (i = OUTPUT_BITS-1; i >= 0; i--) begin
            @(posedge clk);
            result[i] = sum_out;
        end
        
        wait(out_ready == 1'b0);
    endtask

    task automatic run_test_mode0();
        int i;
        $display("=== Test Mode 0: Current product + Previous product ===");
        errors = 0;
        prev_product_ref = 0;

        for (i = 0; i < 6; i++) begin
            do_one_mac(test_a[i], test_b[i], received_out);

            if (i == 0) begin
                expected_out = (test_a[i] * test_b[i]) & 24'hFFFFFF;
            end else begin
                expected_out = ((test_a[i] * test_b[i]) + prev_product_ref) & 24'hFFFFFF;
            end
            prev_product_ref = expected_out;

            if (received_out !== expected_out) begin
                $display("Mode0 Test %0d FAILED: A=%0d, B=%0d, Expected=%0h, Got=%0h",
                         i, test_a[i], test_b[i], expected_out, received_out);
                errors++;
            end else begin
                $display("Mode0 Test %0d PASSED: A=%0d, B=%0d, Result=%0h",
                         i, test_a[i], test_b[i], received_out);
            end
        end

        if (errors == 0)
            $display("Mode 0: Simulation Passed");
        else
            $display("Mode 0: Simulation Failed");
    endtask

    task automatic run_test_mode1();
        int i;
        $display("\n=== Test Mode 1: Full Accumulation ===");
        errors = 0;
        accum_ref = 0;

        for (i = 0; i < 6; i++) begin
            do_one_mac(test_a[i], test_b[i], received_out);

            accum_ref = accum_ref + (test_a[i] * test_b[i]);
            expected_out = accum_ref[23:0];

            if (received_out !== expected_out) begin
                $display("Mode1 Test %0d FAILED: A=%0d, B=%0d, Expected=%0h, Got=%0h",
                         i, test_a[i], test_b[i], expected_out, received_out);
                errors++;
            end else begin
                $display("Mode1 Test %0d PASSED: A=%0d, B=%0d, Result=%0h, Accum=%0h",
                         i, test_a[i], test_b[i], received_out, accum_ref);
            end
        end

        if (errors == 0)
            $display("Mode 1: Simulation Passed");
        else
            $display("Mode 1: Simulation Failed");
    endtask

    task automatic run_test_mode_switch();
        int i;
        $display("\n=== Test Mode Switch: 0->1 after input 3 ===");
        errors = 0;
        prev_product_ref = 0;
        accum_ref = 0;

        for (i = 0; i < 6; i++) begin
            if (i == 3) begin
                mode = 1;
                accum_ref = 0;
            end

            do_one_mac(test_a[i], test_b[i], received_out);

            if (mode == 0) begin
                if (i == 0) begin
                    expected_out = (test_a[i] * test_b[i]) & 24'hFFFFFF;
                end else begin
                    expected_out = ((test_a[i] * test_b[i]) + prev_product_ref) & 24'hFFFFFF;
                end
                prev_product_ref = expected_out;
            end else begin
                accum_ref = accum_ref + (test_a[i] * test_b[i]);
                expected_out = accum_ref[23:0];
            end

            if (received_out !== expected_out) begin
                $display("ModeSwitch Test %0d FAILED: mode=%0d, A=%0d, B=%0d, Expected=%0h, Got=%0h",
                         i, mode, test_a[i], test_b[i], expected_out, received_out);
                errors++;
            end else begin
                $display("ModeSwitch Test %0d PASSED: mode=%0d, A=%0d, B=%0d, Result=%0h",
                         i, mode, test_a[i], test_b[i], received_out);
            end
        end

        if (errors == 0)
            $display("Mode Switch: Simulation Passed");
        else
            $display("Mode Switch: Simulation Failed");
    endtask

    initial begin
        $dumpfile("tb_mac16.vcd");
        $dumpvars(0, tb_mac16);

        rst_n = 0;
        mode = 0;
        inA = 0;
        inB = 0;
        errors = 0;

        repeat(2) @(posedge clk);
        rst_n = 1;

        run_test_mode0();

        rst_n = 0;
        repeat(2) @(posedge clk);
        rst_n = 1;
        mode = 1;

        run_test_mode1();

        rst_n = 0;
        repeat(2) @(posedge clk);
        rst_n = 1;
        mode = 0;

        run_test_mode_switch();

        #100;
        $display("\n=== All Tests Complete ===");
        $finish;
    end

endmodule
