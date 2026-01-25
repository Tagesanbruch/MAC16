`timescale 1ns/1ps
module mult16_pipeline (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [15:0] a,
    input  logic [15:0] b,
    input  logic        valid_in,   // Start signal
    output logic [31:0] product,
    output logic        valid_out   // Valid signal delayed by 2 cycles
);

    // Simple 2-cycle pipeline wrapper around combinational multiplier
    // This allows the MAC to spread the multiplication timing across 2 cycles
    // Cycle 1: Register inputs
    logic [15:0] a_r, b_r;
    logic valid_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_r <= '0;
            b_r <= '0;
            valid_r <= 1'b0;
        end else begin
            a_r <= a;
            b_r <= b;
            valid_r <= valid_in;
        end
    end

    // Cycle 2: Perform multiplication and register result
    logic [31:0] product_r;
    logic valid_out_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            product_r <= '0;
            valid_out_r <= 1'b0;
        end else begin
            product_r <= a_r * b_r;
            valid_out_r <= valid_r;
        end
    end

    assign product = product_r;
    assign valid_out = valid_out_r;

endmodule
