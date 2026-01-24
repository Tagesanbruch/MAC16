`timescale 1ns/1ps

module tb_mult16;

    logic [15:0] a;
    logic [15:0] b;
    logic [31:0] product;
    logic [31:0] expected;

    mult16 dut (
        .a(a),
        .b(b),
        .product(product)
    );

    int errors;

    initial begin
        $dumpfile("tb_mult16.vcd");
        $dumpvars(0, tb_mult16);
        errors = 0;

        // Test Case 1: Simple
        a = 16'd2; b = 16'd6;
        #1;
        check_result();

        // Test Case 2: Max values
        a = 16'hFFFF; b = 16'hFFFF;
        #1;
        check_result();

        // Test Case 3: Zero
        a = 16'd0; b = 16'd1234;
        #1;
        check_result();

        // Test Case 4: Random
        repeat(100) begin
            a = $random;
            b = $random;
            #1;
            check_result();
        end

        if (errors == 0)
            $display("Multiplier Verification PASSED");
        else
            $display("Multiplier Verification FAILED with %0d errors", errors);
            
        $finish;
    end

    task check_result();
        expected = a * b;
        if (product !== expected) begin
            $display("Error: %d * %d = %d (Expected %d)", a, b, product, expected);
            errors++;
        end
    endtask

endmodule
