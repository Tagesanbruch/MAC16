`timescale 1ns/1ps
//============================================================================
// Unit Test for 4:2 Compressor
// Validates that sum of outputs equals sum of inputs for all combinations
//============================================================================
module tb_compressor_4to2;

    logic a, b, c, d, cin;
    logic sum, carry, cout;
    
    // Standard reference compressor
    logic ref_sum, ref_carry, ref_cout;
    
    int errors;
    int tests;

    // Device Under Test - MUX-based compressor
    compressor_4to2_mux dut (
        .a(a), .b(b), .c(c), .d(d), .cin(cin),
        .sum(sum), .carry(carry), .cout(cout)
    );
    
    // Reference implementation (standard XOR-based)
    wire w1 = a ^ b;
    wire w2 = c ^ d;
    wire w3 = w1 ^ w2;
    assign ref_cout = w1 ? c : a;
    assign ref_sum = w3 ^ cin;
    assign ref_carry = w3 ? cin : d;

    initial begin
        $dumpfile("tb_compressor_4to2.vcd");
        $dumpvars(0, tb_compressor_4to2);
        
        errors = 0;
        tests = 0;
        
        $display("=== 4:2 Compressor Unit Test ===");
        $display("Testing all 32 input combinations...");
        
        // Test all 32 combinations (5 inputs)
        for (int i = 0; i < 32; i++) begin
            {a, b, c, d, cin} = i[4:0];
            #1;
            
            tests++;
            
            // Check against reference
            if (sum !== ref_sum || carry !== ref_carry || cout !== ref_cout) begin
                errors++;
                $display("FAIL: a=%b b=%b c=%b d=%b cin=%b", a, b, c, d, cin);
                $display("      DUT:  sum=%b carry=%b cout=%b", sum, carry, cout);
                $display("      REF:  sum=%b carry=%b cout=%b", ref_sum, ref_carry, ref_cout);
            end
            
            // Also verify arithmetic correctness
            // sum + 2*carry + 2*cout should equal a + b + c + d + cin
            begin
                reg [2:0] input_sum_val;
                reg [2:0] output_sum_val;
                input_sum_val = a + b + c + d + cin;
                output_sum_val = sum + (carry << 1) + (cout << 1);
                if (input_sum_val !== output_sum_val) begin
                    $display("ARITH FAIL: a=%b b=%b c=%b d=%b cin=%b", a, b, c, d, cin);
                    $display("      input_sum=%d output_sum=%d", input_sum_val, output_sum_val);
                end
            end
        end
        
        $display("\n=== Test Complete ===");
        $display("Tests: %0d, Errors: %0d", tests, errors);
        
        if (errors == 0)
            $display("STATUS: PASS");
        else
            $display("STATUS: FAIL");
            
        $finish;
    end

endmodule
