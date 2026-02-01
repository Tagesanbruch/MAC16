`timescale 1ns/1ps
//============================================================================
// Debug test for systolic array with 4x4 size
//============================================================================
module tb_sa_debug;
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
    
    // DUT - use 4x4 for debugging
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
    
    // Clock
    initial clk = 0;
    always #0.5 clk = ~clk;
    
    // Test
    initial begin
        $dumpfile("build/tb_sa_debug.vcd");
        $dumpvars(0, tb_sa_debug);
        
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
        
        // Simple test: A = I (identity), B = I
        // Result should be C = I
        for (int i = 0; i < N; i++) begin
            for (int j = 0; j < N; j++) begin
                mat_a[i][j] = (i == j) ? 16'd1 : 16'd0;
                mat_b[i][j] = (i == j) ? 16'd1 : 16'd0;
            end
        end
        
        // Compute reference
        for (int i = 0; i < N; i++) begin
            for (int j = 0; j < N; j++) begin
                mat_c_ref[i][j] = 0;
                for (int k = 0; k < N; k++) begin
                    mat_c_ref[i][j] = mat_c_ref[i][j] + mat_a[i][k] * mat_b[k][j];
                end
            end
        end
        
        #4;
        rst_n = 1;
        #4;
        
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
        $display("Loading A matrix...");
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
        $display("Loading B matrix...");
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
        
        // IMPORTANT: Set ready BEFORE drain starts so we don't miss data
        m_axis_c_tready = 1;
        
        $display("Waiting for computation and collecting output in parallel...");
        
        // Collect output in parallel with computation
        begin
            integer out_idx;
            out_idx = 0;
            
            // Wait for computation to complete while collecting output
            while (!done || out_idx < N*N) begin
                @(posedge clk);
                #0.1;
                if (m_axis_c_tvalid && m_axis_c_tready) begin
                    integer row_idx, col_idx;
                    row_idx = out_idx / N;
                    col_idx = out_idx % N;
                    mat_c_dut[row_idx][col_idx] = m_axis_c_tdata;
                    out_idx = out_idx + 1;
                end
            end
            $display("Collection complete: %0d values collected", out_idx);
        end
        
        $display("Done detected at t=%0t", $time);
        
        // Print internal result_buffer directly
        $display("\n=== Internal result_buffer (acc_out at drain_start) ===");
        for (int i = 0; i < N; i++) begin
            $write("  ");
            for (int j = 0; j < N; j++) begin
                $write("%4d ", $signed(dut.result_buffer[i][j]));
            end
            $write("\n");
        end
        
        // Verify
        $display("\n=== Results ===");
        $display("Reference matrix C:");
        for (int i = 0; i < N; i++) begin
            $write("  ");
            for (int j = 0; j < N; j++) begin
                $write("%4d ", mat_c_ref[i][j]);
            end
            $write("\n");
        end
        
        $display("\nDUT matrix C:");
        for (int i = 0; i < N; i++) begin
            $write("  ");
            for (int j = 0; j < N; j++) begin
                $write("%4d ", mat_c_dut[i][j]);
            end
            $write("\n");
        end
        
        $finish;
    end
    
    // Timeout
    initial begin
        #100000;
        $display("TIMEOUT!");
        
        // Still print what we have
        $display("\n=== Partial Results ===");
        $display("DUT matrix C:");
        for (int i = 0; i < N; i++) begin
            $write("  ");
            for (int j = 0; j < N; j++) begin
                $write("%4d ", mat_c_dut[i][j]);
            end
            $write("\n");
        end
        
        $finish;
    end

endmodule
