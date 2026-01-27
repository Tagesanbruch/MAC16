`timescale 1ns/1ps

module tb_debug_shift;
    logic clk;
    logic rst_n;
    logic mode;
    logic inA, inB;
    logic sum_out, carry, out_ready;

    mac16 dut (.*);

    initial clk = 0;
    always #0.5 clk = ~clk;

    // Monitor shiftA value at key moments
    always @(posedge clk) begin
        // Access internal signals
        if (dut.state == 0) begin
            $display("T=%0t: sInput cnt=%0d, shiftA=%0d shiftB=%0d, inA=%b inB=%b", 
                     $time, dut.cnt, dut.shiftA, dut.shiftB, inA, inB);
        end
        if (dut.state == 1) begin
            $display("T=%0t: sMultStage1, shiftA=%0d shiftB=%0d", 
                     $time, dut.shiftA, dut.shiftB);
        end
    end

    task automatic send_operand(input logic [15:0] val, input string name);
        for (int i = 15; i >= 0; i--) begin
            if (name == "A") inA = val[i]; else inB = val[i];
            @(posedge clk);
        end
    endtask

    logic [23:0] result;
    
    task automatic do_one_mac(input logic [15:0] a, input logic [15:0] b);
        $display("\n--- Starting MAC: A=%0d, B=%0d ---", a, b);
        
        for (int i = 15; i >= 0; i--) begin
            inA = a[i];
            inB = b[i];
            @(posedge clk);
        end
        inA = 0;
        inB = 0;
        
        $display("T=%0t: Input done, waiting for out_ready", $time);
        wait(out_ready == 1'b1);
        
        result = 0;
        for (int i = 23; i >= 0; i--) begin
            @(posedge clk);
            result[i] = sum_out;
        end
        
        $display("T=%0t: Result = %0d (0x%h)", $time, result, result);
        wait(out_ready == 1'b0);
        $display("T=%0t: out_ready went low", $time);
    endtask

    initial begin
        $dumpfile("tb_debug_shift.vcd");
        $dumpvars(0, tb_debug_shift);
        
        rst_n = 0;
        mode = 0;
        inA = 0;
        inB = 0;
        
        repeat(3) @(posedge clk);
        rst_n = 1;
        $display("T=%0t: Reset released", $time);
        
        // First operation
        do_one_mac(16'd8, 16'd30);  // Expected: 240
        
        // Second operation  
        do_one_mac(16'd5, 16'd7);   // Expected: 35
        
        #20;
        $finish;
    end
endmodule
