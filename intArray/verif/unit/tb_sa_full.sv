`timescale 1ns/1ps
//============================================================================
// Full test for 16x16 systolic array with multiple test cases
//============================================================================
module tb_sa_full;
    parameter N = 16;
    parameter DATA_W = 16;
    parameter ACC_W = 40;
    
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
    
    // DUT - 16x16 array
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
    
    // Clock
    initial clk = 0;
    always #0.5 clk = ~clk;
    
    // Task to initialize matrices for a test
    task init_matrices_identity;
        begin
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    mat_a[i][j] = (i == j) ? 16'd1 : 16'd0;
                    mat_b[i][j] = (i == j) ? 16'd1 : 16'd0;
                end
            end
        end
    endtask
    
    task init_matrices_random;
        input integer seed;
        begin
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    mat_a[i][j] = $random(seed) % 128 - 64;  // -64 to 63
                    mat_b[i][j] = $random(seed) % 128 - 64;
                end
            end
        end
    endtask
    
    task init_matrices_ones;
        begin
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    mat_a[i][j] = 16'd1;
                    mat_b[i][j] = 16'd1;
                end
            end
        end
    endtask
    
    task init_matrices_sequential;
        begin
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    mat_a[i][j] = i * N + j + 1;
                    mat_b[i][j] = (i == j) ? 16'd1 : 16'd0;  // B = I
                end
            end
        end
    endtask
    
    // Task to compute reference result
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
    
    // Task to run one test
    task run_test;
        input string test_name;
        integer out_idx;
        integer errors;
        begin
            test_num = test_num + 1;
            $display("\n========== Test %0d: %s ==========", test_num, test_name);
            
            // Compute reference
            compute_reference();
            
            // Start operation
            @(posedge clk);
            #0.1;
            start = 1;
            @(posedge clk);
            #0.1;
            start = 0;
            
            // Wait for loading phase
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
            
            // Set ready for output collection
            m_axis_c_tready = 1;
            
            // Collect output in parallel with computation
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
            
            // Verify results
            errors = 0;
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    if (mat_c_dut[i][j] !== mat_c_ref[i][j]) begin
                        if (errors < 5) begin
                            $display("ERROR at C[%0d][%0d]: Expected %0d, Got %0d",
                                     i, j, mat_c_ref[i][j], mat_c_dut[i][j]);
                        end
                        errors = errors + 1;
                    end
                end
            end
            
            if (errors == 0) begin
                $display("PASS: All %0d elements match", N*N);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: %0d errors out of %0d elements", errors, N*N);
                fail_count = fail_count + 1;
            end
            
            // Small delay between tests
            repeat(10) @(posedge clk);
        end
    endtask
    
    // Main test
    initial begin
        $dumpfile("build/tb_sa_full.vcd");
        $dumpvars(0, tb_sa_full);
        
        // Init
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
        
        #4;
        rst_n = 1;
        #4;
        
        // Test 1: Identity matrix
        init_matrices_identity();
        run_test("Identity * Identity");
        
        // Test 2: All ones matrix
        init_matrices_ones();
        run_test("Ones * Ones (all results = N)");
        
        // Test 3: Sequential * Identity
        init_matrices_sequential();
        run_test("Sequential * Identity");
        
        // Test 4: Random matrices (small values)
        init_matrices_random(12345);
        run_test("Random matrices (seed 12345)");
        
        // Test 5: Another random test
        init_matrices_random(67890);
        run_test("Random matrices (seed 67890)");
        
        // Summary
        $display("\n========== Test Summary ==========");
        $display("Total tests: %0d", test_num);
        $display("Passed: %0d", pass_count);
        $display("Failed: %0d", fail_count);
        
        if (fail_count == 0) begin
            $display("\n*** ALL TESTS PASSED! ***");
        end else begin
            $display("\n*** SOME TESTS FAILED ***");
        end
        
        $finish;
    end
    
    // Timeout
    initial begin
        #10000000;  // 10ms timeout for 16x16
        $display("TIMEOUT!");
        $finish;
    end

endmodule
