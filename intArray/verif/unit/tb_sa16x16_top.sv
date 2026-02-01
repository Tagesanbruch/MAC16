`timescale 1ns/1ps
//============================================================================
// Systolic Array Top-Level System Test
// 
// Tests complete 16x16 matrix multiplication:
//   - Input loading via AXI-Stream-like interface
//   - Computation
//   - Result verification against reference
//============================================================================
module tb_sa16x16_top;

    parameter N      = 16;
    parameter DATA_W = 16;
    parameter ACC_W  = 40;
    parameter CLK_PERIOD = 1.0;
    
    // Clock and reset
    logic clk;
    logic rst_n;
    
    // Control
    logic start;
    logic busy;
    logic done;
    
    // Input A interface
    logic [DATA_W-1:0] s_axis_a_tdata;
    logic              s_axis_a_tvalid;
    logic              s_axis_a_tready;
    logic              s_axis_a_tlast;
    
    // Input B interface
    logic [DATA_W-1:0] s_axis_b_tdata;
    logic              s_axis_b_tvalid;
    logic              s_axis_b_tready;
    logic              s_axis_b_tlast;
    
    // Output C interface
    logic [ACC_W-1:0]  m_axis_c_tdata;
    logic              m_axis_c_tvalid;
    logic              m_axis_c_tready;
    logic              m_axis_c_tlast;
    
    // DUT
    sa16x16_top #(
        .N(N),
        .DATA_W(DATA_W),
        .ACC_W(ACC_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .busy(busy),
        .done(done),
        .s_axis_a_tdata(s_axis_a_tdata),
        .s_axis_a_tvalid(s_axis_a_tvalid),
        .s_axis_a_tready(s_axis_a_tready),
        .s_axis_a_tlast(s_axis_a_tlast),
        .s_axis_b_tdata(s_axis_b_tdata),
        .s_axis_b_tvalid(s_axis_b_tvalid),
        .s_axis_b_tready(s_axis_b_tready),
        .s_axis_b_tlast(s_axis_b_tlast),
        .m_axis_c_tdata(m_axis_c_tdata),
        .m_axis_c_tvalid(m_axis_c_tvalid),
        .m_axis_c_tready(m_axis_c_tready),
        .m_axis_c_tlast(m_axis_c_tlast)
    );
    
    // Clock generation
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
    // Test matrices
    logic signed [DATA_W-1:0] mat_a [0:N-1][0:N-1];
    logic signed [DATA_W-1:0] mat_b [0:N-1][0:N-1];
    logic signed [ACC_W-1:0]  mat_c_ref [0:N-1][0:N-1];
    logic signed [ACC_W-1:0]  mat_c_dut [0:N-1][0:N-1];
    
    int errors = 0;
    int test_num = 0;
    
    // Initialize test matrices
    task automatic init_test_matrices(int mode);
        case (mode)
            0: begin // Identity test
                $display("Test mode: Identity matrices");
                for (int i = 0; i < N; i++) begin
                    for (int j = 0; j < N; j++) begin
                        mat_a[i][j] = (i == j) ? 16'd1 : 16'd0;
                        mat_b[i][j] = (i == j) ? 16'd1 : 16'd0;
                    end
                end
            end
            1: begin // Small values
                $display("Test mode: Small sequential values");
                for (int i = 0; i < N; i++) begin
                    for (int j = 0; j < N; j++) begin
                        mat_a[i][j] = 16'(i + j);
                        mat_b[i][j] = 16'(i * N + j);
                    end
                end
            end
            2: begin // Random values (deterministic)
                $display("Test mode: Pseudo-random values");
                for (int i = 0; i < N; i++) begin
                    for (int j = 0; j < N; j++) begin
                        mat_a[i][j] = 16'((i * 17 + j * 31) % 256 - 128);
                        mat_b[i][j] = 16'((i * 23 + j * 41) % 256 - 128);
                    end
                end
            end
            default: begin // Zeros
                for (int i = 0; i < N; i++) begin
                    for (int j = 0; j < N; j++) begin
                        mat_a[i][j] = 16'd0;
                        mat_b[i][j] = 16'd0;
                    end
                end
            end
        endcase
        
        // Compute reference
        compute_reference();
    endtask
    
    // Compute reference result
    task automatic compute_reference();
        for (int i = 0; i < N; i++) begin
            for (int j = 0; j < N; j++) begin
                mat_c_ref[i][j] = 0;
                for (int k = 0; k < N; k++) begin
                    mat_c_ref[i][j] = mat_c_ref[i][j] + 
                        $signed(mat_a[i][k]) * $signed(mat_b[k][j]);
                end
            end
        end
    endtask
    
    // Run single test
    task automatic run_test(int mode);
        int out_cnt;
        
        $display("\n========================================");
        $display("Running Test %0d", test_num);
        $display("========================================");
        
        init_test_matrices(mode);
        
        // Start operation
        start = 1;
        @(posedge clk);
        start = 0;
        
        // Wait for input loading to start
        wait(s_axis_a_tready);
        
        // Feed A matrix
        $display("Loading matrix A...");
        s_axis_a_tvalid = 1;
        for (int i = 0; i < N; i++) begin
            for (int j = 0; j < N; j++) begin
                s_axis_a_tdata = mat_a[i][j];
                s_axis_a_tlast = (i == N-1 && j == N-1);
                @(posedge clk);
                while (!s_axis_a_tready) @(posedge clk);
            end
        end
        s_axis_a_tvalid = 0;
        
        // Feed B matrix
        wait(s_axis_b_tready);
        $display("Loading matrix B...");
        s_axis_b_tvalid = 1;
        for (int i = 0; i < N; i++) begin
            for (int j = 0; j < N; j++) begin
                s_axis_b_tdata = mat_b[i][j];
                s_axis_b_tlast = (i == N-1 && j == N-1);
                @(posedge clk);
                while (!s_axis_b_tready) @(posedge clk);
            end
        end
        s_axis_b_tvalid = 0;
        
        // Collect output
        $display("Waiting for computation...");
        m_axis_c_tready = 1;
        out_cnt = 0;
        
        begin
            int timeout_cnt;
            timeout_cnt = 0;
            
            while (out_cnt < N*N && timeout_cnt < 100000) begin
                @(posedge clk);
                timeout_cnt++;
                if (m_axis_c_tvalid && m_axis_c_tready) begin
                    int row, col;
                    row = out_cnt / N;
                    col = out_cnt % N;
                    mat_c_dut[row][col] = m_axis_c_tdata;
                    out_cnt++;
                end
            end
            
            if (timeout_cnt >= 100000) begin
                $display("ERROR: Timeout waiting for output");
                errors++;
            end
        end
        
        // Wait for done
        wait(done);
        @(posedge clk);
        
        // Verify results
        verify_results();
        test_num++;
    endtask
    
    // Verify results against reference
    task automatic verify_results();
        int local_errors = 0;
        
        $display("Verifying results...");
        for (int i = 0; i < N; i++) begin
            for (int j = 0; j < N; j++) begin
                if (mat_c_dut[i][j] !== mat_c_ref[i][j]) begin
                    if (local_errors < 10) begin
                        $display("MISMATCH [%0d][%0d]: expected %0d, got %0d",
                                 i, j, mat_c_ref[i][j], mat_c_dut[i][j]);
                    end
                    local_errors++;
                end
            end
        end
        
        if (local_errors == 0) begin
            $display("Test %0d: PASSED (all %0d elements match)", test_num, N*N);
        end else begin
            $display("Test %0d: FAILED (%0d/%0d mismatches)", test_num, local_errors, N*N);
            errors += local_errors;
        end
    endtask
    
    initial begin
        $dumpfile("tb_sa16x16_top.vcd");
        $dumpvars(0, tb_sa16x16_top);
        
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
        
        // Reset
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);
        
        $display("===========================================");
        $display("  Systolic Array 16x16 System Test");
        $display("===========================================");
        
        // Run tests
        run_test(0);  // Identity
        run_test(1);  // Small sequential
        run_test(2);  // Pseudo-random
        
        // Summary
        repeat(10) @(posedge clk);
        $display("\n===========================================");
        $display("  Test Summary");
        $display("===========================================");
        if (errors == 0) begin
            $display("Simulation Passed - All tests passed!");
        end else begin
            $display("Simulation Failed - %0d total errors", errors);
        end
        $display("===========================================");
        
        $finish;
    end

endmodule

