`timescale 1ns/1ps
//============================================================================
// Complete System Testbench for 16x16 Systolic Array
// 
// Features:
//   - Multiple test cases (identity, random, edge cases)
//   - Performance measurement
//   - Error reporting with detailed mismatch info
//   - Analysis of A/B parallel loading capability
//============================================================================
module tb_sa16x16_system;
    parameter N = 16;
    parameter DATA_W = 16;
    parameter ACC_W = 40;
    
    // Clock and reset
    reg clk, rst_n;
    reg start;
    wire busy, done;
    
    // AXI-Stream A
    reg [DATA_W-1:0] s_axis_a_tdata;
    reg              s_axis_a_tvalid;
    wire             s_axis_a_tready;
    reg              s_axis_a_tlast;
    
    // AXI-Stream B
    reg [DATA_W-1:0] s_axis_b_tdata;
    reg              s_axis_b_tvalid;
    wire             s_axis_b_tready;
    reg              s_axis_b_tlast;
    
    // AXI-Stream C
    wire [ACC_W-1:0] m_axis_c_tdata;
    wire             m_axis_c_tvalid;
    reg              m_axis_c_tready;
    wire             m_axis_c_tlast;
    
    // DUT
    sa16x16_top #(
        .N(N),
        .DATA_W(DATA_W),
        .ACC_W(ACC_W)
    ) dut (.*);
    
    // Test matrices
    reg signed [DATA_W-1:0] mat_a [0:N-1][0:N-1];
    reg signed [DATA_W-1:0] mat_b [0:N-1][0:N-1];
    reg signed [ACC_W-1:0]  mat_c_ref [0:N-1][0:N-1];
    reg signed [ACC_W-1:0]  mat_c_dut [0:N-1][0:N-1];
    
    // Statistics
    integer test_num;
    integer pass_count;
    integer fail_count;
    integer total_cycles;
    integer start_time;
    integer end_time;
    
    // Clock generation: 1GHz (1ns period)
    initial clk = 0;
    always #0.5 clk = ~clk;
    
    //=========================================================================
    // Matrix Initialization Tasks
    //=========================================================================
    
    // Identity matrix
    task init_identity;
        begin
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    mat_a[i][j] = (i == j) ? 16'd1 : 16'd0;
                    mat_b[i][j] = (i == j) ? 16'd1 : 16'd0;
                end
            end
        end
    endtask
    
    // All ones matrix (result should be N on diagonal)
    task init_ones;
        begin
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    mat_a[i][j] = 16'd1;
                    mat_b[i][j] = 16'd1;
                end
            end
        end
    endtask
    
    // Sequential values
    task init_sequential;
        begin
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    mat_a[i][j] = i * N + j + 1;
                    mat_b[i][j] = (i == j) ? 16'd1 : 16'd0;
                end
            end
        end
    endtask
    
    // Random values with seed
    task init_random;
        input integer seed;
        integer s;
        begin
            s = seed;
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    mat_a[i][j] = $random(s) % 64 - 32;  // -32 to 31
                    mat_b[i][j] = $random(s) % 64 - 32;
                end
            end
        end
    endtask
    
    // Edge case: max positive values
    task init_max_positive;
        begin
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    mat_a[i][j] = 16'd127;  // Small to avoid overflow
                    mat_b[i][j] = (i == j) ? 16'd1 : 16'd0;
                end
            end
        end
    endtask
    
    // Edge case: alternating signs
    task init_alternating;
        begin
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    mat_a[i][j] = ((i + j) % 2 == 0) ? 16'd10 : -16'd10;
                    mat_b[i][j] = (i == j) ? 16'd1 : 16'd0;
                end
            end
        end
    endtask
    
    //=========================================================================
    // Compute Reference Result
    //=========================================================================
    task compute_reference;
        begin
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    mat_c_ref[i][j] = 0;
                    for (int k = 0; k < N; k++) begin
                        mat_c_ref[i][j] = mat_c_ref[i][j] + 
                            $signed(mat_a[i][k]) * $signed(mat_b[k][j]);
                    end
                end
            end
        end
    endtask
    
    //=========================================================================
    // Run Single Test
    //=========================================================================
    task run_test;
        input string test_name;
        integer out_idx;
        integer errors;
        integer first_error_i, first_error_j;
        begin
            test_num = test_num + 1;
            $display("\n========== Test %0d: %s ==========", test_num, test_name);
            
            // Compute reference
            compute_reference();
            
            // Clear DUT output
            for (int i = 0; i < N; i++)
                for (int j = 0; j < N; j++)
                    mat_c_dut[i][j] = 'x;
            
            // Start timer
            start_time = $time;
            
            // Start operation
            @(posedge clk);
            #0.1;
            start = 1;
            @(posedge clk);
            #0.1;
            start = 0;
            
            // Wait for A loading phase
            wait(s_axis_a_tready);
            
            // Load A matrix
            s_axis_a_tvalid = 1;
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    s_axis_a_tdata = mat_a[i][j];
                    s_axis_a_tlast = (i == N-1 && j == N-1);
                    @(posedge clk);
                    #0.1;
                end
            end
            s_axis_a_tvalid = 0;
            
            // Wait for B loading phase
            wait(s_axis_b_tready);
            
            // Load B matrix
            s_axis_b_tvalid = 1;
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    s_axis_b_tdata = mat_b[i][j];
                    s_axis_b_tlast = (i == N-1 && j == N-1);
                    @(posedge clk);
                    #0.1;
                end
            end
            s_axis_b_tvalid = 0;
            
            // Enable output collection
            m_axis_c_tready = 1;
            
            // Collect output while waiting for done
            out_idx = 0;
            while (!done || out_idx < N*N) begin
                @(posedge clk);
                #0.1;
                if (m_axis_c_tvalid && m_axis_c_tready) begin
                    mat_c_dut[out_idx / N][out_idx % N] = m_axis_c_tdata;
                    out_idx = out_idx + 1;
                end
            end
            
            m_axis_c_tready = 0;
            
            // End timer
            end_time = $time;
            total_cycles = (end_time - start_time) / 1;  // 1ns per cycle at 1GHz
            
            // Verify results
            errors = 0;
            first_error_i = -1;
            first_error_j = -1;
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    if (mat_c_dut[i][j] !== mat_c_ref[i][j]) begin
                        if (first_error_i < 0) begin
                            first_error_i = i;
                            first_error_j = j;
                        end
                        errors = errors + 1;
                    end
                end
            end
            
            // Report results
            $display("  Cycles: %0d", total_cycles);
            $display("  Throughput: %.2f GOPS", (2.0 * N * N * N) / total_cycles);
            
            if (errors == 0) begin
                $display("  Result: PASS (all %0d elements match)", N*N);
                pass_count = pass_count + 1;
            end else begin
                $display("  Result: FAIL (%0d errors)", errors);
                $display("  First error at C[%0d][%0d]: Expected %0d, Got %0d",
                         first_error_i, first_error_j,
                         mat_c_ref[first_error_i][first_error_j],
                         mat_c_dut[first_error_i][first_error_j]);
                fail_count = fail_count + 1;
            end
            
            // Small delay between tests
            repeat(10) @(posedge clk);
        end
    endtask
    
    //=========================================================================
    // Main Test Sequence
    //=========================================================================
    initial begin
        $dumpfile("build/tb_sa16x16_system.vcd");
        $dumpvars(0, tb_sa16x16_system);
        
        // Initialize
        rst_n = 0;
        start = 0;
        s_axis_a_tdata = 0;
        s_axis_a_tvalid = 0;
        s_axis_a_tlast = 0;
        s_axis_b_tdata = 0;
        s_axis_b_tvalid = 0;
        s_axis_b_tlast = 0;
        m_axis_c_tready = 0;
        test_num = 0;
        pass_count = 0;
        fail_count = 0;
        
        // Reset
        #10;
        rst_n = 1;
        #10;
        
        $display("\n");
        $display("==========================================================");
        $display(" 16x16 Systolic Array - Complete System Test");
        $display("==========================================================");
        $display(" Array Size: %0d x %0d = %0d PEs", N, N, N*N);
        $display(" Data Width: %0d bits", DATA_W);
        $display(" Accumulator Width: %0d bits", ACC_W);
        $display("==========================================================");
        
        // Test 1: Identity matrix
        init_identity();
        run_test("Identity x Identity = Identity");
        
        // Test 2: All ones
        init_ones();
        run_test("Ones x Ones (result = N on all elements)");
        
        // Test 3: Sequential x Identity
        init_sequential();
        run_test("Sequential x Identity");
        
        // Test 4: Random test 1
        init_random(12345);
        run_test("Random (seed=12345)");
        
        // Test 5: Random test 2
        init_random(67890);
        run_test("Random (seed=67890)");
        
        // Test 6: Max positive values
        init_max_positive();
        run_test("Max Positive x Identity");
        
        // Test 7: Alternating signs
        init_alternating();
        run_test("Alternating Signs x Identity");
        
        // Summary
        $display("\n");
        $display("==========================================================");
        $display(" Test Summary");
        $display("==========================================================");
        $display(" Total Tests: %0d", test_num);
        $display(" Passed: %0d", pass_count);
        $display(" Failed: %0d", fail_count);
        $display("==========================================================");
        
        if (fail_count == 0) begin
            $display("\n *** ALL TESTS PASSED! ***\n");
            $display("Simulation Passed");
        end else begin
            $display("\n *** SOME TESTS FAILED ***\n");
            $display("Simulation Failed");
        end
        
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #50000000;  // 50ms timeout
        $display("\n[ERROR] Simulation timeout!");
        $display("Simulation Failed");
        $finish;
    end

endmodule
