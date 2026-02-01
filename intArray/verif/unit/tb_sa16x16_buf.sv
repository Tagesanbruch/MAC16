`timescale 1ns/1ps
//============================================================================
// FIFO/Buffer Unit Test
//============================================================================
module tb_sa16x16_buf;

    parameter WIDTH = 16;
    parameter DEPTH = 16;
    parameter CLK_PERIOD = 1.0;
    
    logic             clk;
    logic             rst_n;
    logic             wr_en;
    logic [WIDTH-1:0] wr_data;
    logic             full;
    logic             rd_en;
    logic [WIDTH-1:0] rd_data;
    logic             empty;
    logic [4:0]       count;
    
    sa16x16_fifo #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH)
    ) dut (.*);
    
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
    int errors = 0;
    logic [WIDTH-1:0] test_data [0:DEPTH-1];
    
    initial begin
        $dumpfile("tb_sa16x16_buf.vcd");
        $dumpvars(0, tb_sa16x16_buf);
        
        rst_n = 0;
        wr_en = 0;
        wr_data = 0;
        rd_en = 0;
        
        repeat(2) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
        
        $display("=== FIFO Unit Test Start ===");
        
        // Test 1: Empty after reset
        if (empty !== 1 || count !== 0) begin
            $display("ERROR: FIFO not empty after reset");
            errors++;
        end else begin
            $display("PASS: FIFO empty after reset");
        end
        
        // Test 2: Write data
        $display("\n--- Test: Write operations ---");
        for (int i = 0; i < DEPTH; i++) begin
            test_data[i] = 16'hA000 + i;
            wr_data = test_data[i];
            wr_en = 1;
            @(posedge clk);
        end
        wr_en = 0;
        @(posedge clk);
        
        if (full !== 1 || count !== DEPTH) begin
            $display("ERROR: FIFO not full after %0d writes, count=%0d", DEPTH, count);
            errors++;
        end else begin
            $display("PASS: FIFO full after %0d writes", DEPTH);
        end
        
        // Test 3: Read data
        $display("\n--- Test: Read operations ---");
        for (int i = 0; i < DEPTH; i++) begin
            // Check data BEFORE asserting rd_en (data is available at rd_ptr)
            if (rd_data !== test_data[i]) begin
                $display("ERROR: Read %0d: expected %h, got %h", i, test_data[i], rd_data);
                errors++;
            end
            rd_en = 1;
            @(posedge clk);
            rd_en = 0;
        end
        @(posedge clk);
        
        if (empty !== 1) begin
            $display("ERROR: FIFO not empty after all reads");
            errors++;
        end else begin
            $display("PASS: FIFO empty after all reads");
        end
        
        // Test 4: Simultaneous read/write
        $display("\n--- Test: Simultaneous read/write ---");
        // First fill half
        for (int i = 0; i < DEPTH/2; i++) begin
            wr_data = 16'hB000 + i;
            wr_en = 1;
            @(posedge clk);
        end
        wr_en = 0;
        @(posedge clk);
        
        // Simultaneous operations
        for (int i = 0; i < 8; i++) begin
            wr_data = 16'hC000 + i;
            wr_en = 1;
            rd_en = 1;
            @(posedge clk);
        end
        wr_en = 0;
        rd_en = 0;
        @(posedge clk);
        
        if (count !== DEPTH/2) begin
            $display("ERROR: Count mismatch after simultaneous ops, expected %0d, got %0d", DEPTH/2, count);
            errors++;
        end else begin
            $display("PASS: Simultaneous read/write");
        end
        
        repeat(5) @(posedge clk);
        
        $display("\n=== FIFO Unit Test Complete ===");
        if (errors == 0) begin
            $display("Simulation Passed");
        end else begin
            $display("Simulation Failed: %0d errors", errors);
        end
        
        $finish;
    end

endmodule

