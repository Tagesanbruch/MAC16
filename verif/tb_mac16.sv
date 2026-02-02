`timescale 1ns/1ps

module tb_mac16;

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
    localparam int INPUT_BITS = 16;
    localparam int OUTPUT_BITS = 24;
    localparam int MAX_GAP = 5;
    localparam int MAX_LATENCY = 5;

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    logic [15:0] test_a [0:5];
    logic [15:0] test_b [0:5];

    initial begin
        test_a[0] = 16'd2;   test_a[1] = 16'd8;    test_a[2] = 16'd14;
        test_a[3] = 16'd116; test_a[4] = 16'd1546; test_a[5] = 16'd20698;

        test_b[0] = 16'd6;   test_b[1] = 16'd30;   test_b[2] = 16'd71;
        test_b[3] = 16'd828; test_b[4] = 16'd1152; test_b[5] = 16'd728;
    end

    int cycle_count;
    always @(posedge clk) cycle_count++;

    int errors_data;
    int errors_latency;
    int errors_idle;
    int errors_carry;
    int errors_ready;

    logic [23:0] received_out;

    function automatic int signed mul16(input logic [15:0] a, input logic [15:0] b);
        int signed aa;
        int signed bb;
        begin
            aa = $signed(a);
            bb = $signed(b);
            return aa * bb;
        end
    endfunction

    task automatic wait_idle_and_check_zero(input int cycles);
        for (int i = 0; i < cycles; i++) begin
            @(posedge clk);
            #1ps;
            if (out_ready !== 1'b0) begin
                $display("[READY] out_ready should be 0 during idle, got 1 at cycle %0d", cycle_count);
                errors_ready++;
            end
            if (sum_out !== 1'b0) begin
                $display("[IDLE] sum_out should be 0 during idle, got %0b at cycle %0d", sum_out, cycle_count);
                errors_idle++;
            end
        end
    endtask

    task automatic shift_in_16(input logic [15:0] a, input logic [15:0] b);
        for (int i = INPUT_BITS-1; i >= 0; i--) begin
            inA = a[i];
            inB = b[i];
            @(posedge clk);
        end
        inA = 1'b0;
        inB = 1'b0;
    endtask

    task automatic wait_for_output_and_capture(
        input int input_done_cycle,
        output int output_start_cycle,
        output logic [23:0] out_data,
        output int ready_cycles
    );
        output_start_cycle = -1;
        out_data = '0;
        ready_cycles = 0;

        wait(out_ready == 1'b1);
        #1ps;
        output_start_cycle = cycle_count;
        out_data[OUTPUT_BITS-1] = sum_out;
        ready_cycles++;

        if (^sum_out === 1'bx) begin
            $display("[DATA] sum_out is X at output start cycle %0d", output_start_cycle);
            errors_data++;
        end

        if (output_start_cycle - input_done_cycle > MAX_LATENCY) begin
            $display("[LATENCY] Violated: input_done=%0d output_start=%0d latency=%0d",
                     input_done_cycle, output_start_cycle, output_start_cycle - input_done_cycle);
            errors_latency++;
        end

        for (int i = OUTPUT_BITS-2; i >= 0; i--) begin
            @(posedge clk);
            #1ps;
            if (out_ready !== 1'b1) begin
                $display("[READY] out_ready dropped early at cycle %0d", cycle_count);
                errors_ready++;
            end
            out_data[i] = sum_out;
            ready_cycles++;
        end

        @(posedge clk);
        #1ps;
        if (out_ready !== 1'b0) begin
            $display("[READY] out_ready should deassert after output window at cycle %0d", cycle_count);
            errors_ready++;
        end
        if (sum_out !== 1'b0) begin
            $display("[IDLE] sum_out should be 0 after output window at cycle %0d", cycle_count);
            errors_idle++;
        end
        if (ready_cycles != OUTPUT_BITS) begin
            $display("[READY] out_ready window length mismatch: expected=%0d got=%0d", OUTPUT_BITS, ready_cycles);
            errors_ready++;
        end
    endtask

    task automatic check_carry_latched(
        input logic expected_carry_next,
        inout logic carry_latched
    );
        if (expected_carry_next) begin
            if (carry !== 1'b1) begin
                $display("[CARRY] carry should assert on overflow at cycle %0d, expected=1 got=%0b",
                         cycle_count, carry);
                errors_carry++;
            end
            carry_latched = 1'b1;
        end else begin
            if (carry !== carry_latched) begin
                $display("[CARRY] carry mismatch at cycle %0d, expected=%0b got=%0b",
                         cycle_count, carry_latched, carry);
                errors_carry++;
            end
        end
    endtask

    task automatic run_case_mode0();
        int input_done_cycle;
        int output_start_cycle;
        int ready_cycles;
        int signed prod;
        int signed prev_prod;
        longint signed full_sum;
        logic carry_latched;
        int gap_cycles;

        $display("=== Case 1: mode=0 ===");
        mode = 1'b0;
        prev_prod = 0;
        carry_latched = 1'b0;

        for (int i = 0; i < 6; i++) begin
            gap_cycles = 0;
            wait_idle_and_check_zero(gap_cycles);

            shift_in_16(test_a[i], test_b[i]);
            input_done_cycle = cycle_count;

            prod = mul16(test_a[i], test_b[i]);
            if (i == 0) begin
                full_sum = prod;
            end else begin
                full_sum = prod + prev_prod;
            end
            prev_prod = full_sum;

            wait_for_output_and_capture(input_done_cycle, output_start_cycle, received_out, ready_cycles);

            if (received_out !== full_sum[23:0]) begin
                $display("[DATA] mode0 idx=%0d expected=%0h got=%0h", i, full_sum[23:0], received_out);
                $display("[DEBUG] mode0 idx=%0d start=%0d ready_cycles=%0d got_b=%0b exp_b=%0b",
                         i, output_start_cycle, ready_cycles, received_out, full_sum[23:0]);
                errors_data++;
            end

            check_carry_latched((full_sum >> 24) != 0, carry_latched);
        end
    endtask

    task automatic run_case_mode1();
        int input_done_cycle;
        int output_start_cycle;
        int ready_cycles;
        int signed prod;
        longint signed accum;
        logic carry_latched;
        int gap_cycles;

        $display("=== Case 2: mode=1 ===");
        mode = 1'b1;
        accum = 0;
        carry_latched = 1'b0;

        for (int i = 0; i < 6; i++) begin
            gap_cycles = 0;
            wait_idle_and_check_zero(gap_cycles);

            shift_in_16(test_a[i], test_b[i]);
            input_done_cycle = cycle_count;

            prod = mul16(test_a[i], test_b[i]);
            accum = accum + prod;

            wait_for_output_and_capture(input_done_cycle, output_start_cycle, received_out, ready_cycles);

            if (received_out !== accum[23:0]) begin
                $display("[DATA] mode1 idx=%0d expected=%0h got=%0h", i, accum[23:0], received_out);
                $display("[DEBUG] mode1 idx=%0d start=%0d ready_cycles=%0d got_b=%0b exp_b=%0b",
                         i, output_start_cycle, ready_cycles, received_out, accum[23:0]);
                errors_data++;
            end

            check_carry_latched((accum >> 24) != 0, carry_latched);
        end
    endtask

    task automatic run_case_mode_switch();
        int input_done_cycle;
        int output_start_cycle;
        int ready_cycles;
        int signed prod;
        longint signed accum;
        int signed prev_prod;
        logic carry_latched;
        int gap_cycles;
        bit mode_switched;

        $display("=== Case 3: mode=0 -> 1 after 3rd input ===");
        mode = 1'b0;
        prev_prod = 0;
        accum = 0;
        carry_latched = 1'b0;
        mode_switched = 1'b0;

        for (int i = 0; i < 6; i++) begin
            gap_cycles = 0;
            wait_idle_and_check_zero(gap_cycles);

            shift_in_16(test_a[i], test_b[i]);
            input_done_cycle = cycle_count;

            prod = mul16(test_a[i], test_b[i]);

            if (mode == 1'b0) begin
                if (i == 0) begin
                    accum = prod;
                end else begin
                    accum = prod + prev_prod;
                end
                prev_prod = accum;
            end else begin
                accum = accum + prod;
            end

            wait_for_output_and_capture(input_done_cycle, output_start_cycle, received_out, ready_cycles);

            if (received_out !== accum[23:0]) begin
                $display("[DATA] modeswitch idx=%0d mode=%0d expected=%0h got=%0h", i, mode, accum[23:0], received_out);
                $display("[DEBUG] modeswitch idx=%0d start=%0d ready_cycles=%0d got_b=%0b exp_b=%0b",
                         i, output_start_cycle, ready_cycles, received_out, accum[23:0]);
                errors_data++;
            end

            check_carry_latched((accum >> 24) != 0, carry_latched);

            if (i == 2) begin
                mode = 1'b1;
                accum = 0;
                prev_prod = 0;
                carry_latched = 1'b0;
                mode_switched = 1'b1;
            end

            if (mode_switched && i == 3) begin
                if (carry !== 1'b0) begin
                    $display("[CARRY] carry should clear on mode switch before first mode1 output at cycle %0d", cycle_count);
                    errors_carry++;
                end
                mode_switched = 1'b0;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_mac16.vcd");
        $dumpvars(0, tb_mac16);

        rst_n = 0;
        mode = 0;
        inA = 0;
        inB = 0;
        cycle_count = 0;
        errors_data = 0;
        errors_latency = 0;
        errors_idle = 0;
        errors_carry = 0;
        errors_ready = 0;

        repeat(2) @(posedge clk);
        rst_n = 1;

        run_case_mode0();

        rst_n = 0;
        repeat(2) @(posedge clk);
        rst_n = 1;
        run_case_mode1();

        rst_n = 0;
        repeat(2) @(posedge clk);
        rst_n = 1;
        run_case_mode_switch();

        $display("\n=== Summary ===");
        if (errors_data == 0)
            $display("[PASS] data correctness");
        else
            $display("[FAIL] data correctness: %0d", errors_data);

        if (errors_latency == 0)
            $display("[PASS] latency <= %0d", MAX_LATENCY);
        else
            $display("[FAIL] latency: %0d", errors_latency);

        if (errors_idle == 0)
            $display("[PASS] idle output zero");
        else
            $display("[FAIL] idle output zero: %0d", errors_idle);

        if (errors_ready == 0)
            $display("[PASS] out_ready window");
        else
            $display("[FAIL] out_ready window: %0d", errors_ready);

        if (errors_carry == 0)
            $display("[PASS] carry behavior");
        else
            $display("[FAIL] carry behavior: %0d", errors_carry);

        if ((errors_data + errors_latency + errors_idle + errors_ready + errors_carry) == 0)
            $display("Simulation Passed");
        else
            $display("Simulation Failed");

        #50;
        $finish;
    end

endmodule
