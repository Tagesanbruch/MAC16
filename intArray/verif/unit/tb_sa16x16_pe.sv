`timescale 1ns/1ps
//============================================================================
// PE Unit Test
// 
// Tests single Processing Element functionality:
//   - Basic multiply-accumulate
//   - Data forwarding
//   - Reset and clear behavior
//============================================================================
module tb_sa16x16_pe;

    parameter DATA_W = 16;
    parameter ACC_W  = 40;
    parameter CLK_PERIOD = 1.0;  // 1 GHz
    
    // Signals
    logic                clk;
    logic                rst_n;
    logic                enable;
    logic                clear_acc;
    logic [DATA_W-1:0]   a_in;
    logic [DATA_W-1:0]   b_in;
    logic                valid_in;
    logic [DATA_W-1:0]   a_out;
    logic [DATA_W-1:0]   b_out;
    logic                valid_out;
    logic [ACC_W-1:0]    acc_out;
    logic                acc_valid;
    
    // DUT
    sa16x16_pe #(
        .DATA_W(DATA_W),
        .ACC_W(ACC_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .enable(enable),
        .clear_acc(clear_acc),
        .a_in(a_in),
        .b_in(b_in),
        .valid_in(valid_in),
        .a_out(a_out),
        .b_out(b_out),
        .valid_out(valid_out),
        .acc_out(acc_out),
        .acc_valid(acc_valid)
    );
    
    // Clock generation
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
    // Test variables
    int errors = 0;
    int test_num = 0;
    logic signed [ACC_W-1:0] expected_acc;
    
    // Test task - single MAC operation
    task automatic test_single_mac(
        input logic signed [DATA_W-1:0] a,
        input logic signed [DATA_W-1:0] b,
        input logic signed [ACC_W-1:0] expected_product
    );
        int timeout;
        
        // Apply inputs AFTER clock edge with small delay for proper sampling
        @(posedge clk);
        #0.1;
        a_in = a;
        b_in = b;
        valid_in = 1'b1;
        
        @(posedge clk);
        #0.1;
        valid_in = 1'b0;
        a_in = '0;
        b_in = '0;
        
        // Wait for mult_valid_out to go high
        timeout = 0;
        while (!dut.mult_valid_out && timeout < 20) begin
            @(posedge clk);
            timeout++;
        end
        
        // At this point mult_valid_out is high
        // Accumulator will be updated on the NEXT clock edge
        // Wait for that update
        @(posedge clk);
        // Now accumulator has the new value, wait a small delta for combinational output
        #0.1;
        
        expected_acc = expected_acc + expected_product;
        
        if (acc_out !== expected_acc) begin
            $display("ERROR Test %0d: a=%0d, b=%0d, expected acc=%0d, got %0d",
                     test_num, $signed(a), $signed(b), expected_acc, $signed(acc_out));
            errors++;
        end else begin
            $display("PASS Test %0d: a=%0d, b=%0d, acc=%0d",
                     test_num, $signed(a), $signed(b), $signed(acc_out));
        end
        test_num++;
    endtask
    
    // Test task - verify data forwarding
    task automatic test_forwarding(
        input logic [DATA_W-1:0] a,
        input logic [DATA_W-1:0] b
    );
        // Apply inputs AFTER clock edge
        @(posedge clk);
        #0.1;
        a_in = a;
        b_in = b;
        valid_in = 1'b1;
        
        // Wait for one clock cycle (inputs get registered)
        @(posedge clk);
        #0.1;
        // Don't clear inputs yet - a_out/b_out reflect what was registered on last edge
        // At this point, a_reg = a, b_reg = b
        
        // Check forwarded values (they should now be available)
        if (a_out !== a || b_out !== b) begin
            $display("ERROR Forwarding: expected a_out=%h, b_out=%h, got a_out=%h, b_out=%h",
                     a, b, a_out, b_out);
            errors++;
        end else begin
            $display("PASS Forwarding: a_out=%h, b_out=%h", a_out, b_out);
        end
        
        // Now clear inputs
        valid_in = 1'b0;
        a_in = '0;
        b_in = '0;
        
        // Wait for the triggered multiplication to complete before next test
        // This prevents the result from corrupting the accumulator in subsequent tests
        repeat(6) @(posedge clk);
    endtask
    
    initial begin
        $dumpfile("tb_sa16x16_pe.vcd");
        $dumpvars(0, tb_sa16x16_pe);
        
        // Initialize
        rst_n = 0;
        enable = 0;
        clear_acc = 0;
        a_in = '0;
        b_in = '0;
        valid_in = 0;
        expected_acc = 0;
        
        // Reset
        repeat(2) @(posedge clk);
        rst_n = 1;
        enable = 1;
        repeat(2) @(posedge clk);
        
        $display("=== PE Unit Test Start ===");
        
        // Test 1: Basic multiplication (positive * positive)
        $display("\n--- Test 1: Positive * Positive ---");
        test_single_mac(16'd10, 16'd20, 40'd200);
        
        // Test 2: Accumulation
        $display("\n--- Test 2: Accumulation ---");
        test_single_mac(16'd5, 16'd10, 40'd50);
        
        // Test 3: Negative numbers
        $display("\n--- Test 3: Negative * Positive ---");
        test_single_mac(-16'sd100, 16'd10, -40'sd1000);
        
        // Test 4: Clear accumulator
        $display("\n--- Test 4: Clear Accumulator ---");
        @(posedge clk);
        #0.1;
        clear_acc = 1;
        @(posedge clk);
        #0.1;
        clear_acc = 0;
        expected_acc = 0;
        @(posedge clk);
        #0.1;
        
        if (acc_out !== 0) begin
            $display("ERROR Clear: expected acc=0, got %0d", $signed(acc_out));
            errors++;
        end else begin
            $display("PASS Clear: acc=%0d", $signed(acc_out));
        end
        
        // Test 5: Data forwarding
        $display("\n--- Test 5: Data Forwarding ---");
        test_forwarding(16'hABCD, 16'h1234);
        
        // Test 6: Multiple MACs
        $display("\n--- Test 6: Multiple MACs ---");
        // Clear accumulator first
        @(posedge clk);
        #0.1;
        clear_acc = 1;
        @(posedge clk);
        #0.1;
        clear_acc = 0;
        @(posedge clk);
        #0.1;
        
        $display("After clear: acc_out=%d, expected_acc=%d", $signed(acc_out), expected_acc);
        expected_acc = 0;  // Reset expected_acc AFTER clearing
        $display("After reset expected: acc_out=%d, expected_acc=%d", $signed(acc_out), expected_acc);
        
        for (int i = 0; i < 5; i++) begin
            test_single_mac(16'(i+1), 16'(i+2), (i+1) * (i+2));
        end
        
        // Summary
        repeat(10) @(posedge clk);
        $display("\n=== PE Unit Test Complete ===");
        if (errors == 0) begin
            $display("Simulation Passed");
        end else begin
            $display("Simulation Failed: %0d errors", errors);
        end
        
        $finish;
    end

endmodule

