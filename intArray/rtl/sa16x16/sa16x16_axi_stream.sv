`timescale 1ns/1ps
//============================================================================
// AXI-Stream Interface Wrapper
// 
// Handles AXI-Stream protocol for input/output data
// Supports backpressure via TREADY
//============================================================================
module sa16x16_axi_stream #(
    parameter DATA_W = 16,
    parameter N      = 16
)(
    input  logic                    clk,
    input  logic                    rst_n,
    
    // AXI-Stream Slave - Input A (row-major)
    input  logic [DATA_W-1:0]       s_axis_a_tdata,
    input  logic                    s_axis_a_tvalid,
    output logic                    s_axis_a_tready,
    input  logic                    s_axis_a_tlast,
    
    // AXI-Stream Slave - Input B (column-major)
    input  logic [DATA_W-1:0]       s_axis_b_tdata,
    input  logic                    s_axis_b_tvalid,
    output logic                    s_axis_b_tready,
    input  logic                    s_axis_b_tlast,
    
    // AXI-Stream Master - Output C
    output logic [39:0]             m_axis_c_tdata,
    output logic                    m_axis_c_tvalid,
    input  logic                    m_axis_c_tready,
    output logic                    m_axis_c_tlast,
    
    // Internal interface to array
    output logic [DATA_W-1:0]       a_data,
    output logic                    a_valid,
    input  logic                    a_ready,
    
    output logic [DATA_W-1:0]       b_data,
    output logic                    b_valid,
    input  logic                    b_ready,
    
    input  logic [39:0]             c_data,
    input  logic                    c_valid,
    output logic                    c_ready,
    input  logic                    c_last
);

    // Input A FIFO
    logic        a_fifo_full, a_fifo_empty;
    logic [4:0]  a_fifo_count;
    
    sa16x16_fifo #(.WIDTH(DATA_W), .DEPTH(16)) u_fifo_a (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(s_axis_a_tvalid && s_axis_a_tready),
        .wr_data(s_axis_a_tdata),
        .full(a_fifo_full),
        .rd_en(a_ready && !a_fifo_empty),
        .rd_data(a_data),
        .empty(a_fifo_empty),
        .count(a_fifo_count)
    );
    
    assign s_axis_a_tready = !a_fifo_full;
    assign a_valid = !a_fifo_empty;
    
    // Input B FIFO
    logic        b_fifo_full, b_fifo_empty;
    logic [4:0]  b_fifo_count;
    
    sa16x16_fifo #(.WIDTH(DATA_W), .DEPTH(16)) u_fifo_b (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(s_axis_b_tvalid && s_axis_b_tready),
        .wr_data(s_axis_b_tdata),
        .full(b_fifo_full),
        .rd_en(b_ready && !b_fifo_empty),
        .rd_data(b_data),
        .empty(b_fifo_empty),
        .count(b_fifo_count)
    );
    
    assign s_axis_b_tready = !b_fifo_full;
    assign b_valid = !b_fifo_empty;
    
    // Output C FIFO
    logic        c_fifo_full, c_fifo_empty;
    logic [4:0]  c_fifo_count;
    logic [39:0] c_fifo_data;
    
    sa16x16_fifo #(.WIDTH(40), .DEPTH(16)) u_fifo_c (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(c_valid && !c_fifo_full),
        .wr_data(c_data),
        .full(c_fifo_full),
        .rd_en(m_axis_c_tvalid && m_axis_c_tready),
        .rd_data(c_fifo_data),
        .empty(c_fifo_empty),
        .count(c_fifo_count)
    );
    
    assign c_ready = !c_fifo_full;
    assign m_axis_c_tdata  = c_fifo_data;
    assign m_axis_c_tvalid = !c_fifo_empty;
    
    // TLAST tracking (simplified - last element of result)
    logic [8:0] out_cnt;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            out_cnt <= '0;
        else if (m_axis_c_tvalid && m_axis_c_tready)
            out_cnt <= (out_cnt == N*N - 1) ? '0 : out_cnt + 1'b1;
    end
    
    assign m_axis_c_tlast = (out_cnt == N*N - 1) && m_axis_c_tvalid;

endmodule

