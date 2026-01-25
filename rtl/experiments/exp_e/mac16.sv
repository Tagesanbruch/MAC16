`timescale 1ns/1ps
//============================================================================
// Experiment E: Full MAC16 Wrapper with Double Carry-Save Multiplier
// 
// This wraps the fused MAC core and adds:
//   - Serial input/output interface (for compatibility)
//   - State machine control
//   - External accumulation (for spec compatibility with mode switching)
//
// Note: The fused MAC core uses DCS internally for the multiply operation.
//       External accumulation is used for mode compatibility with original spec.
//
// Key benefit: The multiplier itself uses Booth encoding + CSA compression,
//              which is much faster than behavioral multiplication.
//
// Target: > 1.2 GHz
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

    // State machine - simplified for 2-stage fused MAC
    localparam S_INPUT       = 2'd0;
    localparam S_COMPUTE     = 2'd1;  // Fused MAC (2 cycles)
    localparam S_OUTPUT      = 2'd2;

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
    
    // Accumulation registers (external - for spec compatibility)
    logic [23:0] accum;
    logic [23:0] prev_product;
    logic [24:0] add_result;
    logic [23:0] final_result;

    // Instantiate fused MAC core (mode=0: no internal accumulation)
    mac16_fused u_mac_fused (
        .clk(clk),
        .rst_n(rst_n),
        .mode(1'b0),      // Always multiply-only mode internally
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
    
    // External accumulation logic (matches original spec)
    always_comb begin
        if (mode_r == 1'b0) begin
            // Mode 0: current_product + prev_product
            if (first_op) begin
                add_result = {1'b0, mac_result};
            end else begin
                add_result = {1'b0, mac_result} + {1'b0, prev_product};
            end
        end else begin
            // Mode 1: accumulate into accum register
            add_result = {1'b0, mac_result} + {1'b0, accum};
        end
        final_result = add_result[23:0];
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
                        state <= S_COMPUTE;
                        // Launch MAC
                        mac_inA <= {shift_a[INPUT_BITS-2:0], inA};
                        mac_inB <= {shift_b[INPUT_BITS-2:0], inB};
                        mac_valid_in <= 1'b1;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                S_COMPUTE: begin
                    mac_valid_in <= 1'b0;
                    
                    // Wait for MAC result
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
