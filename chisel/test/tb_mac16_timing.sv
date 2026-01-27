`timescale 1ns/1ps
module tb_mac16_timing;
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

    always @(posedge clk) begin
        if (dut.multValidIn) begin
            $display("MULT launch cycle=%0t state=%0d cnt=%0d shiftA=%0d shiftB=%0d", $time, dut.state, dut.cnt, dut.shiftA, dut.shiftB);
        end
        if (dut.mult.validS1) begin
            $display("MULT S1 cycle=%0t aS1=%0d b_in=%0d io_a=%0d io_b=%0d", $time, dut.mult.aS1, dut.mult.io_b, dut.mult.io_a, dut.mult.io_b);
        end
    end

    task automatic send_input(input logic [15:0] a, input logic [15:0] b);
        int i;
        for (i = INPUT_BITS-1; i >= 0; i--) begin
            inA = a[i];
            inB = b[i];
            @(posedge clk);
            $display("IN  cycle=%0t state=%0d cnt=%0d inA=%0b inB=%0b shiftA=%0d shiftB=%0d", $time, dut.state, dut.cnt, inA, inB, dut.shiftA, dut.shiftB);
        end
        inA = 0;
        inB = 0;
    endtask

    task automatic read_output(output logic [23:0] result);
        int i;
        result = '0;
        wait(out_ready == 1'b1);
        $display("OUT start cycle=%0t state=%0d cnt=%0d multReg=%0d outShiftReg=%0d aS1=%0d b_in=%0d", $time, dut.state, dut.cnt, dut.multReg, dut.outShiftReg, dut.mult.aS1, dut.mult.io_b);
        for (i = OUTPUT_BITS-1; i >= 0; i--) begin
            @(posedge clk);
            result[i] = sum_out;
            $display("OUT cycle=%0t state=%0d cnt=%0d sum_out=%0b", $time, dut.state, dut.cnt, sum_out);
        end
        wait(out_ready == 1'b0);
        $display("OUT end cycle=%0t state=%0d cnt=%0d", $time, dut.state, dut.cnt);
    endtask

    logic [23:0] result;

    initial begin
        rst_n = 0;
        #10 rst_n = 1;

        $display("--- OP1 ---");
        send_input(16'd2, 16'd6);
        read_output(result);
        $display("OP1 result=%0d", result);

        $display("--- OP2 ---");
        send_input(16'd8, 16'd30);
        read_output(result);
        $display("OP2 result=%0d", result);

        #10 $finish;
    end
endmodule
