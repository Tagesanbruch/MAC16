`timescale 1ns/1ps
//============================================================================
// 4x4 Systolic Array Processing Element
// Reuses the same mult16_booth_5stage as sa16x16 for consistency
//============================================================================
module sa4x4_pe #(
    parameter DATA_W = 16,
    parameter ACC_W  = 40
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 enable,
    input  wire                 clear_acc,
    
    // Data flow
    input  wire [DATA_W-1:0]    a_in,
    input  wire [DATA_W-1:0]    b_in,
    input  wire                 valid_in,
    
    output reg  [DATA_W-1:0]    a_out,
    output reg  [DATA_W-1:0]    b_out,
    output reg                  valid_out,
    
    // Accumulator output
    output wire [ACC_W-1:0]     acc_out,
    output wire                 acc_valid
);

    // Pipeline registers for data propagation
    reg [DATA_W-1:0] a_reg, b_reg;
    reg              valid_reg;
    
    // Multiplier signals
    wire             mult_start;
    wire [31:0]      mult_result;
    wire             mult_valid_out;
    
    // Accumulator
    reg [ACC_W-1:0]  accumulator;
    reg              acc_valid_reg;
    
    // Data propagation (1 cycle delay)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_reg <= {DATA_W{1'b0}};
            b_reg <= {DATA_W{1'b0}};
            valid_reg <= 1'b0;
        end else if (enable) begin
            a_reg <= a_in;
            b_reg <= b_in;
            valid_reg <= valid_in;
        end else begin
            valid_reg <= 1'b0;
        end
    end
    
    assign a_out = a_reg;
    assign b_out = b_reg;
    assign valid_out = valid_reg;
    
    // Multiplier control
    assign mult_start = valid_in && enable;
    
    // Reuse sa16x16's 5-stage pipelined Booth multiplier
    mult16_booth_5stage u_mult (
        .clk(clk),
        .rst_n(rst_n),
        .a(a_in),
        .b(b_in),
        .valid_in(mult_start),
        .product(mult_result),
        .valid_out(mult_valid_out)
    );
    
    // Accumulator
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accumulator <= {ACC_W{1'b0}};
            acc_valid_reg <= 1'b0;
        end else if (clear_acc) begin
            accumulator <= {ACC_W{1'b0}};
            acc_valid_reg <= 1'b0;
        end else if (mult_valid_out) begin
            accumulator <= accumulator + {{(ACC_W-32){mult_result[31]}}, mult_result};
            acc_valid_reg <= 1'b1;
        end
    end
    
    assign acc_out = accumulator;
    assign acc_valid = acc_valid_reg;

endmodule
