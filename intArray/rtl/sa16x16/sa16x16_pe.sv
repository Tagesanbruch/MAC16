`timescale 1ns/1ps
//============================================================================
// Systolic Array PE (Processing Element)
// 
// Based on exp_k's high-performance multiplier (1154 MHz capable)
// 
// PE Function:
//   - Receives a_in, b_in from neighbors
//   - Computes: acc += a_in * b_in
//   - Forwards a_out, b_out to next PE
//
// Interface: Parallel input/output (not serial like mac16)
// This simplifies the systolic array design while reusing the fast multiplier.
//============================================================================
module sa16x16_pe #(
    parameter DATA_W = 16,
    parameter ACC_W  = 40
)(
    input  logic                clk,
    input  logic                rst_n,
    input  logic                enable,      // PE enable (for gating)
    input  logic                clear_acc,   // Clear accumulator
    
    // Data inputs (from left/top neighbor)
    input  logic [DATA_W-1:0]   a_in,
    input  logic [DATA_W-1:0]   b_in,
    input  logic                valid_in,
    
    // Data outputs (to right/bottom neighbor)
    output logic [DATA_W-1:0]   a_out,
    output logic [DATA_W-1:0]   b_out,
    output logic                valid_out,
    
    // Accumulator output (for result collection)
    output logic [ACC_W-1:0]    acc_out,
    output logic                acc_valid
);

    // Pipeline registers for forwarding (1 cycle delay)
    logic [DATA_W-1:0] a_reg, b_reg;
    logic              valid_reg;
    
    // Multiplier interface
    logic [31:0] mult_product;
    logic        mult_valid_out;
    logic        mult_start;
    
    // Accumulator
    logic [ACC_W-1:0] accumulator;
    logic             acc_updated;
    
    // 5-stage pipelined multiplier (from exp_k)
    mult16_booth_5stage u_mult (
        .clk(clk),
        .rst_n(rst_n),
        .a(a_in),
        .b(b_in),
        .valid_in(mult_start),
        .product(mult_product),
        .valid_out(mult_valid_out)
    );
    
    // Start multiplication when valid input arrives and PE is enabled
    assign mult_start = valid_in && enable;
    
    // Forward data to next PE (registered for pipelining)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_reg     <= '0;
            b_reg     <= '0;
            valid_reg <= 1'b0;
        end else if (enable) begin
            a_reg     <= a_in;
            b_reg     <= b_in;
            valid_reg <= valid_in;
        end else begin
            valid_reg <= 1'b0;
        end
    end
    
    assign a_out     = a_reg;
    assign b_out     = b_reg;
    assign valid_out = valid_reg;
    
    // Accumulator logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accumulator <= '0;
            acc_updated <= 1'b0;
        end else if (clear_acc) begin
            accumulator <= '0;
            acc_updated <= 1'b0;
        end else if (mult_valid_out) begin
            accumulator <= accumulator + {{(ACC_W-32){mult_product[31]}}, mult_product};
            acc_updated <= 1'b1;
        end
    end
    
    assign acc_out   = accumulator;
    assign acc_valid = acc_updated;

endmodule

