`timescale 1ns/1ps
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

    localparam S_INPUT     = 2'd0;
    localparam S_COMPUTE_1 = 2'd1;
    localparam S_COMPUTE_2 = 2'd2;
    localparam S_OUTPUT    = 2'd3;
    
    logic [1:0] state;
    
    logic [4:0] cnt;
    logic [INPUT_BITS-1:0] shift_a, shift_b;
    logic [OUTPUT_BITS-1:0] accum;
    logic [OUTPUT_BITS-1:0] prev_product;
    logic [OUTPUT_BITS-1:0] out_shift_reg;
    logic carry_reg;
    logic first_op;
    logic mode_r;

    logic [31:0] mult_result;
    logic [31:0] mult_reg; // Pipeline register for multiplier result
    logic [24:0] add_result;
    logic [23:0] mac_result;

    mult16 u_mult (
        .a(shift_a),
        .b(shift_b),
        .product(mult_result)
    );

    always_comb begin
        // Adder logic uses PIPELINED multiplier result (mult_reg)
        if (mode_r == 1'b0) begin
            add_result = {1'b0, mult_reg[23:0]} + {1'b0, prev_product};
        end else begin
            add_result = {1'b0, mult_reg[23:0]} + {1'b0, accum};
        end
        
        // Output Mux logic
        if (first_op && mode_r == 1'b0) begin
            mac_result = mult_reg[23:0];
        end else begin
            mac_result = add_result[23:0];
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_INPUT;
            cnt <= '0;
            shift_a <= '0;
            shift_b <= '0;
            accum <= '0;
            prev_product <= '0;
            out_shift_reg <= '0;
            carry_reg <= 1'b0;
            first_op <= 1'b1;
            mode_r <= 1'b0;
            sum_out <= 1'b0;
            out_ready <= 1'b0;
        end else begin
            case (state)
                S_INPUT: begin
                    out_ready <= 1'b0;
                    sum_out <= 1'b0;
                    mode_r <= mode;
                    
                    shift_a <= {shift_a[INPUT_BITS-2:0], inA};
                    shift_b <= {shift_b[INPUT_BITS-2:0], inB};
                    
                    if (cnt == INPUT_BITS - 1) begin
                        cnt <= '0;
                        state <= S_COMPUTE_1;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end
                
                // S_COMPUTE_1: Capture Multiplier Result
                S_COMPUTE_1: begin
                    mult_reg <= mult_result; // mult_result comes from comb mult16 using stable shift_a/b
                    state <= S_COMPUTE_2;
                end

                // S_COMPUTE_2: Perform Addition and Output Setup
                S_COMPUTE_2: begin
                    // Inputs (mult_reg) are stable, capture result
                    out_shift_reg <= mac_result;
                    
                    if (mode_r == 1'b0) begin
                        prev_product <= mac_result;
                    end else begin
                        accum <= mac_result;
                    end
                    
                    if ((!first_op || mode_r == 1'b1) && add_result[OUTPUT_BITS]) begin
                        carry_reg <= 1'b1;
                    end
                    
                    first_op <= 1'b0;
                    
                    // Drive first bit immediately
                    out_ready <= 1'b1;
                    sum_out <= mac_result[OUTPUT_BITS-1];
                    
                    cnt <= '0;
                    state <= S_OUTPUT;
                end
                
                S_OUTPUT: begin
                    out_ready <= 1'b1;
                    sum_out <= out_shift_reg[OUTPUT_BITS-2];
                    out_shift_reg <= {out_shift_reg[OUTPUT_BITS-2:0], 1'b0};
                    
                    if (cnt == OUTPUT_BITS - 2) begin
                        cnt <= '0;
                        out_ready <= 1'b0; // Will be 0 next cycle
                        state <= S_INPUT;
                        
                        if (mode != mode_r) begin
                            accum <= '0;
                            prev_product <= '0;
                            carry_reg <= 1'b0;
                            first_op <= 1'b1;
                        end
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
