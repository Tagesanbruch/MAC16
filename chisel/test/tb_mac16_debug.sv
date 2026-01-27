`timescale 1ns/1ps
module tb_mac16_debug;
    reg clk = 0;
    reg rst_n = 0;
    reg mode = 0;
    reg inA = 0, inB = 0;
    wire sum_out, carry, out_ready;
    
    localparam INPUT_BITS = 16;
    localparam OUTPUT_BITS = 24;

    always #0.5 clk = ~clk;

    mac16 dut (
        .clk(clk),
        .rst_n(rst_n),
        .mode(mode),
        .inA(inA),
        .inB(inB),
        .sum_out(sum_out),
        .carry(carry),
        .out_ready(out_ready)
    );

    // Task to send one MAC operation with debug
    task automatic do_one_mac(input logic [15:0] a, input logic [15:0] b, output logic [23:0] result);
        int i;
        result = '0;
        
        // Serial input: MSB first
        for (i = INPUT_BITS-1; i >= 0; i--) begin
            inA = a[i];
            inB = b[i];
            @(posedge clk);
        end
        inA = 0;
        inB = 0;
        
        // Wait for output ready (same as original tb_mac16.sv)
        wait(out_ready == 1'b1);
        $display("  Out ready! multReg=%d, shiftA=%d", dut.multReg, dut.shiftA);
        
        // Serial output: MSB first
        for (i = OUTPUT_BITS-1; i >= 0; i--) begin
            @(posedge clk);
            result[i] = sum_out;
        end
        
        wait(out_ready == 1'b0);
    endtask

    logic [23:0] result;

    initial begin
        $dumpfile("tb_mac16_debug.vcd");
        $dumpvars(0, tb_mac16_debug);
        
        rst_n = 0;
        #10 rst_n = 1;
        
        // Test 1: 2 * 6 = 12
        $display("Starting Test 1: 2 * 6");
        do_one_mac(16'd2, 16'd6, result);
        $display("Test 1 Result: %d (expected 12)", result);
        
        // Test 2: 8 * 30 = 240 + 12 = 252
        $display("\nStarting Test 2: 8 * 30");
        do_one_mac(16'd8, 16'd30, result);
        $display("Test 2 Result: %d (expected 252)", result);
        
        #10 $finish;
    end
endmodule
