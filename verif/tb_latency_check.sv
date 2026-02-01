`timescale 1ns/1ps

module tb_latency_check;

    logic clk;
    logic rst_n;
    logic mode;
    logic inA;
    logic inB;
    logic sum_out;
    logic carry;
    logic out_ready;

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

    localparam real CLK_PERIOD = 1.0;
    localparam INPUT_BITS = 16;
    localparam OUTPUT_BITS = 24;
    localparam MAX_LATENCY = 5;

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    logic [15:0] test_a = 16'd1234;
    logic [15:0] test_b = 16'd5678;

    int input_done_cycle;
    int output_start_cycle;
    int cycle_count;
    int measured_latency;

    always @(posedge clk) cycle_count++;

    initial begin
        $dumpfile("tb_latency_check.vcd");
        $dumpvars(0, tb_latency_check);

        rst_n = 0;
        mode = 0;
        inA = 0;
        inB = 0;
        cycle_count = 0;

        repeat(2) @(posedge clk);
        rst_n = 1;

        $display("\n=== Latency Check Test ===");
        $display("Requirement: Latency from input complete to output start <= %0d cycles", MAX_LATENCY);

        // Shift in 16 bits of data (MSB first)
        for (int i = INPUT_BITS-1; i >= 0; i--) begin
            inA = test_a[i];
            inB = test_b[i];
            @(posedge clk);
        end
        
        // Record cycle when input is complete
        input_done_cycle = cycle_count;
        $display("Input complete at cycle: %0d", input_done_cycle);
        
        inA = 0;
        inB = 0;

        // Wait for out_ready to go high
        fork
            begin
                wait(out_ready == 1'b1);
                output_start_cycle = cycle_count;
            end
            begin
                repeat(20) @(posedge clk);
                if (!out_ready) begin
                    $display("TIMEOUT: out_ready did not go high within 20 cycles!");
                    $finish;
                end
            end
        join_any
        disable fork;

        $display("Output started at cycle: %0d", output_start_cycle);
        
        measured_latency = output_start_cycle - input_done_cycle;
        $display("\n=== LATENCY RESULT ===");
        $display("Measured latency: %0d cycles", measured_latency);
        $display("Required max latency: %0d cycles", MAX_LATENCY);
        
        if (measured_latency <= MAX_LATENCY) begin
            $display("STATUS: PASS - Latency constraint satisfied!");
        end else begin
            $display("STATUS: FAIL - Latency exceeds limit by %0d cycles!", 
                     measured_latency - MAX_LATENCY);
        end

        #10;
        $finish;
    end

endmodule
