`timescale 1ns/1ps
//============================================================================
// Experiment F: Full MAC16 Wrapper with DCS + Kogge-Stone
// 
// Features:
//   - 3-stage pipeline fused MAC core
//   - Kogge-Stone parallel prefix adder for output
//   - Double Carry-Save accumulation (eliminates adder from feedback)
//
// Target: 1.5 GHz
//============================================================================
module mac16 (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        mode,
    input  logic        inA,
    input  logic        inB,
    output logic        sum_out,
    output logic        carry,
    output logic        out_ready
);

    localparam INPUT_BITS  = 16;
    localparam OUTPUT_BITS = 24;

    // State machine - for 3-stage fused MAC
    localparam S_INPUT    = 2'd0;
    localparam S_COMPUTE1 = 2'd1;  // Stage 1+2
    localparam S_COMPUTE2 = 2'd2;  // Stage 3
    localparam S_OUTPUT   = 2'd3;

    logic [1:0] state;
    
    logic [4:0] cnt;
    logic [INPUT_BITS-1:0] shift_a, shift_b;
    logic [OUTPUT_BITS-1:0] out_shift_reg;
    logic carry_reg;
    logic first_op;
    logic mode_r;

    // Fused MAC signals
    logic [15:0] mac_inA, mac_inB;
    logic        mac_valid_in;
    logic [39:0] mac_result_binary;
    logic        mac_valid_out;
    logic [23:0] mac_result;
    
    // External accumulation registers (for spec compatibility)
    logic [23:0] accum;
    logic [23:0] prev_product;
    logic [24:0] add_result;
    logic [23:0] final_result;
    
    // Kogge-Stone adder for external accumulation
    wire [23:0] ks_accum_sum;
    wire        ks_accum_cout;
    
    kogge_stone_adder #(.WIDTH(24)) u_ks_accum (
        .a(mac_result),
        .b(mode_r ? accum : prev_product),
        .cin(1'b0),
        .sum(ks_accum_sum),
        .cout(ks_accum_cout)
    );

    // Instantiate fused MAC core (multiply only, no internal accumulation)
    mac16_fused_ks u_mac_fused (
        .clk(clk),
        .rst_n(rst_n),
        .mode(1'b0),      // Always multiply-only mode
        .clear(1'b1),     // Always clear internal accumulator
        .inA(mac_inA),
        .inB(mac_inB),
        .valid_in(mac_valid_in),
        .result_sum(),
        .result_carry(),
        .result_binary(mac_result_binary),
        .valid_out(mac_valid_out)
    );
    
    assign mac_result = mac_result_binary[23:0];
    
    // Result selection using Kogge-Stone adder
    always_comb begin
        if (first_op && mode_r == 1'b0) begin
            add_result = {1'b0, mac_result};
            final_result = mac_result;
        end else begin
            add_result = {ks_accum_cout, ks_accum_sum};
            final_result = ks_accum_sum;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_INPUT;
            cnt <= '0;
            shift_a <= '0;
            shift_b <= '0;
            out_shift_reg <= '0;
            carry_reg <= 1'b0;
            first_op <= 1'b1;
            mode_r <= 1'b0;
            sum_out <= 1'b0;
            out_ready <= 1'b0;
            mac_inA <= '0;
            mac_inB <= '0;
            mac_valid_in <= 1'b0;
            prev_product <= '0;
            accum <= '0;
        end else begin
            case (state)
                S_INPUT: begin
                    out_ready <= 1'b0;
                    sum_out <= 1'b0;
                    mode_r <= mode;
                    mac_valid_in <= 1'b0;

                    shift_a <= {shift_a[INPUT_BITS-2:0], inA};
                    shift_b <= {shift_b[INPUT_BITS-2:0], inB};

                    if (cnt == INPUT_BITS - 1) begin
                        cnt <= '0;
                        state <= S_COMPUTE1;
                        mac_inA <= {shift_a[INPUT_BITS-2:0], inA};
                        mac_inB <= {shift_b[INPUT_BITS-2:0], inB};
                        mac_valid_in <= 1'b1;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                S_COMPUTE1: begin
                    mac_valid_in <= 1'b0;
                    state <= S_COMPUTE2;
                end

                S_COMPUTE2: begin
                    // Wait for MAC result (3 cycles total)
                    if (mac_valid_out) begin
                        out_shift_reg <= final_result;
                        
                        if (mode_r == 1'b0) begin
                            prev_product <= final_result;
                        end else begin
                            accum <= final_result;
                        end
                        
                        if ((!first_op || mode_r == 1'b1) && add_result[OUTPUT_BITS]) begin
                            carry_reg <= 1'b1;
                        end
                        
                        first_op <= 1'b0;
                        out_ready <= 1'b1;
                        sum_out <= final_result[OUTPUT_BITS-1];
                        state <= S_OUTPUT;
                    end
                end

                S_OUTPUT: begin
                    out_shift_reg <= {out_shift_reg[OUTPUT_BITS-2:0], 1'b0};
                    sum_out <= out_shift_reg[OUTPUT_BITS-2];

                    if (cnt == OUTPUT_BITS - 2) begin
                        cnt <= '0;
                        state <= S_INPUT;
                        shift_a <= '0;
                        shift_b <= '0;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                default: state <= S_INPUT;
            endcase
        end
    end

    assign carry = carry_reg;

endmodule
