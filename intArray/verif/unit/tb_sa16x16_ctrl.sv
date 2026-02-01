`timescale 1ns/1ps
//============================================================================
// Controller Unit Test
// 
// Tests systolic array controller state machine
//============================================================================
module tb_sa16x16_ctrl;

    parameter N = 16;
    parameter CLK_PERIOD = 1.0;
    
    logic        clk;
    logic        rst_n;
    logic        start;
    logic        busy;
    logic        done;
    logic        pe_enable;
    logic        pe_clear;
    logic        load_a_en;
    logic        load_b_en;
    logic [3:0]  load_row;
    logic [3:0]  load_col;
    logic        drain_en;
    logic [3:0]  drain_row;
    logic [3:0]  drain_col;
    logic [5:0]  phase_cnt;
    logic [8:0]  total_cnt;
    
    sa16x16_ctrl #(.N(N)) dut (.*);
    
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
    int errors = 0;
    
    initial begin
        $dumpfile("tb_sa16x16_ctrl.vcd");
        $dumpvars(0, tb_sa16x16_ctrl);
        
        rst_n = 0;
        start = 0;
        
        repeat(2) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
        
        $display("=== Controller Unit Test Start ===");
        
        // Test 1: Idle state
        if (busy !== 0 || done !== 0) begin
            $display("ERROR: Not in idle state");
            errors++;
        end else begin
            $display("PASS: Initial idle state");
        end
        
        // Test 2: Start operation
        start = 1;
        @(posedge clk);
        start = 0;
        
        // Wait for clear phase
        @(posedge clk);
        if (pe_clear !== 1) begin
            $display("ERROR: pe_clear not asserted in clear phase");
            errors++;
        end else begin
            $display("PASS: Clear phase");
        end
        
        // Test 3: Load A phase
        @(posedge clk);
        if (load_a_en !== 1) begin
            $display("ERROR: load_a_en not asserted");
            errors++;
        end else begin
            $display("PASS: Load A phase started");
        end
        
        // Wait for load A to complete (256 cycles)
        repeat(N*N) @(posedge clk);
        
        // Test 4: Load B phase
        if (load_b_en !== 1) begin
            $display("ERROR: load_b_en not asserted");
            errors++;
        end else begin
            $display("PASS: Load B phase started");
        end
        
        // Wait for load B to complete
        repeat(N*N) @(posedge clk);
        
        // Test 5: Compute phase
        if (pe_enable !== 1) begin
            $display("ERROR: pe_enable not asserted in compute phase");
            errors++;
        end else begin
            $display("PASS: Compute phase started");
        end
        
        // Wait for compute to complete
        repeat(2*N + 5) @(posedge clk);
        
        // Test 6: Drain phase
        if (drain_en !== 1) begin
            $display("ERROR: drain_en not asserted");
            errors++;
        end else begin
            $display("PASS: Drain phase started");
        end
        
        // Wait for drain to complete - watch for done signal
        $display("Waiting for drain to complete...");
        fork
            begin
                wait(done);
            end
            begin
                #1000000;
                $display("ERROR: Timeout waiting for done");
                errors++;
            end
        join_any
        disable fork;
        
        // Test 7: Done
        if (done !== 1) begin
            $display("ERROR: done not asserted");
            errors++;
        end else begin
            $display("PASS: Operation complete");
        end
        
        @(posedge clk);
        if (busy !== 0) begin
            $display("ERROR: busy still asserted after done");
            errors++;
        end else begin
            $display("PASS: Returned to idle");
        end
        
        repeat(5) @(posedge clk);
        
        $display("\n=== Controller Unit Test Complete ===");
        if (errors == 0) begin
            $display("Simulation Passed");
        end else begin
            $display("Simulation Failed: %0d errors", errors);
        end
        
        $finish;
    end

endmodule

