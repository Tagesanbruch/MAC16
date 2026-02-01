`timescale 1ns/1ps
//============================================================================
// Complete Testbench for 4x4 Systolic Array
//============================================================================
module tb_sa4x4;
    parameter N = 4;
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
    
    // DUT
    sa4x4_top #(
        .DATA_W(DATA_W),
        .ACC_W(ACC_W)
    ) dut (.*);
    
    // Test matrices
    reg signed [DATA_W-1:0] mat_a [0:N-1][0:N-1];
    reg signed [DATA_W-1:0] mat_b [0:N-1][0:N-1];
    reg signed [ACC_W-1:0]  mat_c_ref [0:N-1][0:N-1];
    reg signed [ACC_W-1:0]  mat_c_dut [0:N-1][0:N-1];
    
    integer test_num, pass_count, fail_count;
    integer start_time, end_time;
    
    // Clock: 1ns period
    initial clk = 0;
    always #0.5 clk = ~clk;
    
    // Compute reference
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
    
    // Run test
    task run_test;
        input string test_name;
        integer out_idx, errors;
        begin
            test_num = test_num + 1;
            $display("\n=== Test %0d: %s ===", test_num, test_name);
            
            compute_reference();
            
            for (int i = 0; i < N; i++)
                for (int j = 0; j < N; j++)
                    mat_c_dut[i][j] = 'x;
            
            start_time = $time;
            
            @(posedge clk); #0.1;
            start = 1;
            @(posedge clk); #0.1;
            start = 0;
            
            wait(s_axis_a_tready);
            
            s_axis_a_tvalid = 1;
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    s_axis_a_tdata = mat_a[i][j];
                    s_axis_a_tlast = (i == N-1 && j == N-1);
                    @(posedge clk); #0.1;
                end
            end
            s_axis_a_tvalid = 0;
            
            wait(s_axis_b_tready);
            
            s_axis_b_tvalid = 1;
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    s_axis_b_tdata = mat_b[i][j];
                    s_axis_b_tlast = (i == N-1 && j == N-1);
                    @(posedge clk); #0.1;
                end
            end
            s_axis_b_tvalid = 0;
            
            m_axis_c_tready = 1;
            
            out_idx = 0;
            while (!done || out_idx < N*N) begin
                @(posedge clk); #0.1;
                if (m_axis_c_tvalid && m_axis_c_tready) begin
                    mat_c_dut[out_idx / N][out_idx % N] = m_axis_c_tdata;
                    out_idx = out_idx + 1;
                end
            end
            
            m_axis_c_tready = 0;
            end_time = $time;
            
            errors = 0;
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    if (mat_c_dut[i][j] !== mat_c_ref[i][j]) begin
                        if (errors < 3)
                            $display("  ERROR C[%0d][%0d]: exp=%0d got=%0d",
                                     i, j, mat_c_ref[i][j], mat_c_dut[i][j]);
                        errors = errors + 1;
                    end
                end
            end
            
            $display("  Cycles: %0d", (end_time - start_time) / 1);
            
            if (errors == 0) begin
                $display("  PASS");
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL (%0d errors)", errors);
                fail_count = fail_count + 1;
            end
            
            repeat(5) @(posedge clk);
        end
    endtask
    
    // Main test
    initial begin
        $dumpfile("build/tb_sa4x4.vcd");
        $dumpvars(0, tb_sa4x4);
        
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
        
        #10;
        rst_n = 1;
        #10;
        
        $display("\n======================================");
        $display(" 4x4 Systolic Array Test Suite");
        $display("======================================");
        
        // Test 1: Identity
        for (int i = 0; i < N; i++) begin
            for (int j = 0; j < N; j++) begin
                mat_a[i][j] = (i == j) ? 16'd1 : 16'd0;
                mat_b[i][j] = (i == j) ? 16'd1 : 16'd0;
            end
        end
        run_test("Identity x Identity");
        
        // Test 2: All ones
        for (int i = 0; i < N; i++) begin
            for (int j = 0; j < N; j++) begin
                mat_a[i][j] = 16'd1;
                mat_b[i][j] = 16'd1;
            end
        end
        run_test("Ones x Ones");
        
        // Test 3: Sequential x Identity
        for (int i = 0; i < N; i++) begin
            for (int j = 0; j < N; j++) begin
                mat_a[i][j] = i * N + j + 1;
                mat_b[i][j] = (i == j) ? 16'd1 : 16'd0;
            end
        end
        run_test("Sequential x Identity");
        
        // Test 4: Simple non-trivial
        mat_a[0][0] = 1; mat_a[0][1] = 2; mat_a[0][2] = 3; mat_a[0][3] = 4;
        mat_a[1][0] = 5; mat_a[1][1] = 6; mat_a[1][2] = 7; mat_a[1][3] = 8;
        mat_a[2][0] = 9; mat_a[2][1] = 10; mat_a[2][2] = 11; mat_a[2][3] = 12;
        mat_a[3][0] = 13; mat_a[3][1] = 14; mat_a[3][2] = 15; mat_a[3][3] = 16;
        
        mat_b[0][0] = 16; mat_b[0][1] = 15; mat_b[0][2] = 14; mat_b[0][3] = 13;
        mat_b[1][0] = 12; mat_b[1][1] = 11; mat_b[1][2] = 10; mat_b[1][3] = 9;
        mat_b[2][0] = 8; mat_b[2][1] = 7; mat_b[2][2] = 6; mat_b[2][3] = 5;
        mat_b[3][0] = 4; mat_b[3][1] = 3; mat_b[3][2] = 2; mat_b[3][3] = 1;
        run_test("Simple non-trivial");
        
        // Test 5: Negative values
        for (int i = 0; i < N; i++) begin
            for (int j = 0; j < N; j++) begin
                mat_a[i][j] = ((i + j) % 2 == 0) ? 16'd5 : -16'd5;
                mat_b[i][j] = (i == j) ? 16'd1 : 16'd0;
            end
        end
        run_test("Alternating signs");
        
        // Summary
        $display("\n======================================");
        $display(" Summary: %0d/%0d tests passed", pass_count, test_num);
        $display("======================================");
        
        if (fail_count == 0) begin
            $display("\n*** ALL TESTS PASSED! ***");
            $display("Simulation Passed");
        end else begin
            $display("\n*** SOME TESTS FAILED ***");
            $display("Simulation Failed");
        end
        
        $finish;
    end
    
    // Timeout
    initial begin
        #500000;
        $display("\nTIMEOUT!");
        $display("Simulation Failed");
        $finish;
    end

endmodule
