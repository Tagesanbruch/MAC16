`timescale 1ns/1ps
//============================================================================
// Synchronous FIFO for AXI-Stream buffering
//============================================================================
module sa16x16_fifo #(
    parameter WIDTH = 16,
    parameter DEPTH = 16,
    parameter ADDR_W = $clog2(DEPTH)
)(
    input  logic             clk,
    input  logic             rst_n,
    
    // Write interface
    input  logic             wr_en,
    input  logic [WIDTH-1:0] wr_data,
    output logic             full,
    
    // Read interface
    input  logic             rd_en,
    output logic [WIDTH-1:0] rd_data,
    output logic             empty,
    
    // Status
    output logic [ADDR_W:0]  count
);

    logic [WIDTH-1:0] mem [0:DEPTH-1];
    logic [ADDR_W-1:0] wr_ptr, rd_ptr;
    logic [ADDR_W:0] cnt;
    
    assign count = cnt;
    assign full  = (cnt == DEPTH);
    assign empty = (cnt == 0);
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
            cnt    <= '0;
        end else begin
            if (wr_en && !full) begin
                mem[wr_ptr] <= wr_data;
                wr_ptr <= wr_ptr + 1'b1;
            end
            
            if (rd_en && !empty) begin
                rd_ptr <= rd_ptr + 1'b1;
            end
            
            case ({wr_en && !full, rd_en && !empty})
                2'b10:   cnt <= cnt + 1'b1;
                2'b01:   cnt <= cnt - 1'b1;
                default: cnt <= cnt;
            endcase
        end
    end
    
    assign rd_data = mem[rd_ptr];

endmodule

//============================================================================
// Line Buffer for skewing input data
//============================================================================
module sa16x16_line_buffer #(
    parameter WIDTH = 16,
    parameter N     = 16
)(
    input  logic             clk,
    input  logic             rst_n,
    input  logic             enable,
    
    // Input: sequential elements
    input  logic [WIDTH-1:0] data_in,
    input  logic             valid_in,
    
    // Output: skewed elements for systolic array
    output logic [N-1:0][WIDTH-1:0] data_out,
    output logic [N-1:0]            valid_out
);

    // Shift registers for skewing (row i delayed by i cycles)
    logic [WIDTH-1:0] shift_regs [0:N-1][0:N-1];
    logic [N-1:0]     valid_regs [0:N-1];
    
    genvar i, j;
    generate
        for (i = 0; i < N; i++) begin : row_gen
            // Row i needs i+1 delay stages
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    for (int k = 0; k <= i; k++) begin
                        shift_regs[i][k] <= '0;
                    end
                    valid_regs[i] <= '0;
                end else if (enable) begin
                    // Shift chain
                    shift_regs[i][0] <= data_in;
                    valid_regs[i][0] <= valid_in;
                    for (int k = 1; k <= i; k++) begin
                        shift_regs[i][k] <= shift_regs[i][k-1];
                        valid_regs[i][k] <= valid_regs[i][k-1];
                    end
                end
            end
            
            assign data_out[i]  = shift_regs[i][i];
            assign valid_out[i] = valid_regs[i][i];
        end
    endgenerate

endmodule

