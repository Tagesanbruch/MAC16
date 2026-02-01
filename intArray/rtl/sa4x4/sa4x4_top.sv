`timescale 1ns/1ps
//============================================================================
// 4x4 Systolic Array Top Module
// 
// Simplified version for faster synthesis and verification
// Fixed N=4 to reduce complexity
//============================================================================
module sa4x4_top #(
    parameter DATA_W = 16,
    parameter ACC_W  = 40
)(
    input  wire                 clk,
    input  wire                 rst_n,
    
    // Control
    input  wire                 start,
    output wire                 busy,
    output wire                 done,
    
    // AXI-Stream input for Matrix A (4x4)
    input  wire [DATA_W-1:0]    s_axis_a_tdata,
    input  wire                 s_axis_a_tvalid,
    output wire                 s_axis_a_tready,
    input  wire                 s_axis_a_tlast,
    
    // AXI-Stream input for Matrix B (4x4)
    input  wire [DATA_W-1:0]    s_axis_b_tdata,
    input  wire                 s_axis_b_tvalid,
    output wire                 s_axis_b_tready,
    input  wire                 s_axis_b_tlast,
    
    // AXI-Stream output for Result C (4x4)
    output wire [ACC_W-1:0]     m_axis_c_tdata,
    output wire                 m_axis_c_tvalid,
    input  wire                 m_axis_c_tready,
    output wire                 m_axis_c_tlast
);
    localparam N = 4;

    // Controller signals
    wire        pe_enable;
    wire        pe_clear;
    wire        load_a_en;
    wire        load_b_en;
    wire [1:0]  load_row, load_col;
    wire        drain_en;
    wire [1:0]  drain_row, drain_col;
    wire [4:0]  phase_cnt;
    wire [4:0]  total_cnt;
    
    // Input matrices storage
    reg [DATA_W-1:0] mat_a [0:N-1][0:N-1];
    reg [DATA_W-1:0] mat_b [0:N-1][0:N-1];
    
    // PE array connections
    wire [DATA_W-1:0] a_wire [0:N-1][0:N];
    wire [DATA_W-1:0] b_wire [0:N][0:N-1];
    wire [ACC_W-1:0]  acc_out [0:N-1][0:N-1];
    wire              acc_valid [0:N-1][0:N-1];
    wire              v_in [0:N-1][0:N-1];
    
    // Output collection
    reg [ACC_W-1:0]  result_buffer [0:N-1][0:N-1];
    reg              result_valid;
    reg [4:0]        out_cnt;
    
    //=========================================================================
    // Controller
    //=========================================================================
    sa4x4_ctrl u_ctrl (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .busy(busy),
        .done(done),
        .pe_enable(pe_enable),
        .pe_clear(pe_clear),
        .load_a_en(load_a_en),
        .load_b_en(load_b_en),
        .load_row(load_row),
        .load_col(load_col),
        .drain_en(drain_en),
        .drain_row(drain_row),
        .drain_col(drain_col),
        .phase_cnt(phase_cnt),
        .total_cnt(total_cnt)
    );
    
    //=========================================================================
    // Input Matrix Loading
    //=========================================================================
    assign s_axis_a_tready = load_a_en;
    
    integer i_a, j_a;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i_a = 0; i_a < N; i_a = i_a + 1)
                for (j_a = 0; j_a < N; j_a = j_a + 1)
                    mat_a[i_a][j_a] <= {DATA_W{1'b0}};
        end else if (load_a_en && s_axis_a_tvalid) begin
            mat_a[load_row][load_col] <= s_axis_a_tdata;
        end
    end
    
    assign s_axis_b_tready = load_b_en;
    
    integer i_b, j_b;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i_b = 0; i_b < N; i_b = i_b + 1)
                for (j_b = 0; j_b < N; j_b = j_b + 1)
                    mat_b[i_b][j_b] <= {DATA_W{1'b0}};
        end else if (load_b_en && s_axis_b_tvalid) begin
            mat_b[load_row][load_col] <= s_axis_b_tdata;
        end
    end
    
    //=========================================================================
    // A/B Input Generation
    //=========================================================================
    genvar r, c;
    generate
        for (r = 0; r < N; r = r + 1) begin : a_input_gen
            wire [4:0] a_phase_raw = phase_cnt - r[4:0];
            wire a_in_range = pe_enable && (phase_cnt >= r[4:0]) && (a_phase_raw < N);
            assign a_wire[r][0] = a_in_range ? mat_a[r][a_phase_raw[1:0]] : {DATA_W{1'b0}};
        end
    endgenerate
    
    generate
        for (c = 0; c < N; c = c + 1) begin : b_input_gen
            wire [4:0] b_phase_raw = phase_cnt - c[4:0];
            wire b_in_range = pe_enable && (phase_cnt >= c[4:0]) && (b_phase_raw < N);
            assign b_wire[0][c] = b_in_range ? mat_b[b_phase_raw[1:0]][c] : {DATA_W{1'b0}};
        end
    endgenerate
    
    //=========================================================================
    // PE valid_in computation
    //=========================================================================
    generate
        for (r = 0; r < N; r = r + 1) begin : v_in_row_gen
            for (c = 0; c < N; c = c + 1) begin : v_in_col_gen
                wire [4:0] pe_start = r[4:0] + c[4:0];
                wire [4:0] pe_end = r[4:0] + c[4:0] + N[4:0];
                assign v_in[r][c] = pe_enable && 
                                    (phase_cnt >= pe_start) && 
                                    (phase_cnt < pe_end);
            end
        end
    endgenerate
    
    //=========================================================================
    // PE Array
    //=========================================================================
    generate
        for (r = 0; r < N; r = r + 1) begin : pe_row_gen
            for (c = 0; c < N; c = c + 1) begin : pe_col_gen
                sa4x4_pe #(
                    .DATA_W(DATA_W),
                    .ACC_W(ACC_W)
                ) u_pe (
                    .clk(clk),
                    .rst_n(rst_n),
                    .enable(pe_enable),
                    .clear_acc(pe_clear),
                    .a_in(a_wire[r][c]),
                    .b_in(b_wire[r][c]),
                    .valid_in(v_in[r][c]),
                    .a_out(a_wire[r][c+1]),
                    .b_out(b_wire[r+1][c]),
                    .valid_out(),
                    .acc_out(acc_out[r][c]),
                    .acc_valid(acc_valid[r][c])
                );
            end
        end
    endgenerate
    
    //=========================================================================
    // Result Collection
    //=========================================================================
    reg drain_en_d;
    wire drain_start = drain_en && !drain_en_d;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            drain_en_d <= 1'b0;
        else
            drain_en_d <= drain_en;
    end
    
    integer i_r, j_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i_r = 0; i_r < N; i_r = i_r + 1)
                for (j_r = 0; j_r < N; j_r = j_r + 1)
                    result_buffer[i_r][j_r] <= {ACC_W{1'b0}};
            result_valid <= 1'b0;
        end else if (drain_start) begin
            for (i_r = 0; i_r < N; i_r = i_r + 1)
                for (j_r = 0; j_r < N; j_r = j_r + 1)
                    result_buffer[i_r][j_r] <= acc_out[i_r][j_r];
            result_valid <= 1'b1;
        end else if (out_cnt >= N*N) begin
            result_valid <= 1'b0;
        end
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_cnt <= 5'd0;
        end else if (!result_valid) begin
            out_cnt <= 5'd0;
        end else if (m_axis_c_tvalid && m_axis_c_tready) begin
            out_cnt <= out_cnt + 5'd1;
        end
    end
    
    wire [1:0] out_row = out_cnt / N;
    wire [1:0] out_col = out_cnt % N;
    
    assign m_axis_c_tdata  = result_buffer[out_row][out_col];
    assign m_axis_c_tvalid = result_valid && (out_cnt < N*N);
    assign m_axis_c_tlast  = result_valid && (out_cnt == N*N - 1);

endmodule
