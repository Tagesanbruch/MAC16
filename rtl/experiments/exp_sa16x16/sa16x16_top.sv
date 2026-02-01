`timescale 1ns/1ps
//============================================================================
// 16x16 Systolic Array Top Module (iverilog compatible)
// 
// Architecture:
//   - 16x16 PE array in systolic configuration
//   - Each PE contains 5-stage pipelined Booth multiplier
//   - AXI-Stream interfaces for matrix input and result output
//   - Controller manages phases: LOAD_A → LOAD_B → COMPUTE → DRAIN
//
// Data Flow:
//   - Matrix A flows horizontally (left to right)
//   - Matrix B flows vertically (top to bottom)
//   - Results are collected after 2N-1 cycles
//============================================================================
module sa16x16_top #(
    parameter N      = 16,          // Array dimension
    parameter DATA_W = 16,          // Data width
    parameter ACC_W  = 40           // Accumulator width
)(
    input  wire                 clk,
    input  wire                 rst_n,
    
    // Control
    input  wire                 start,
    output wire                 busy,
    output wire                 done,
    
    // AXI-Stream input for Matrix A (N x N)
    input  wire [DATA_W-1:0]    s_axis_a_tdata,
    input  wire                 s_axis_a_tvalid,
    output wire                 s_axis_a_tready,
    input  wire                 s_axis_a_tlast,
    
    // AXI-Stream input for Matrix B (N x N)
    input  wire [DATA_W-1:0]    s_axis_b_tdata,
    input  wire                 s_axis_b_tvalid,
    output wire                 s_axis_b_tready,
    input  wire                 s_axis_b_tlast,
    
    // AXI-Stream output for Result C (N x N)
    output wire [ACC_W-1:0]     m_axis_c_tdata,
    output wire                 m_axis_c_tvalid,
    input  wire                 m_axis_c_tready,
    output wire                 m_axis_c_tlast
);

    // Controller signals
    wire        pe_enable;
    wire        pe_clear;
    wire        load_a_en;
    wire        load_b_en;
    wire [3:0]  load_row, load_col;
    wire        drain_en;
    wire [3:0]  drain_row, drain_col;
    wire [5:0]  phase_cnt;
    wire [8:0]  total_cnt;
    
    // Input matrices storage
    reg [DATA_W-1:0] mat_a [0:N-1][0:N-1];
    reg [DATA_W-1:0] mat_b [0:N-1][0:N-1];
    
    // PE array connections
    wire [DATA_W-1:0] a_wire [0:N-1][0:N];   // Horizontal A flow
    wire [DATA_W-1:0] b_wire [0:N][0:N-1];   // Vertical B flow
    wire [ACC_W-1:0]  acc_out [0:N-1][0:N-1];
    wire              acc_valid [0:N-1][0:N-1];
    
    // PE input valid signals (directly computed)
    wire              v_in [0:N-1][0:N-1];   // valid_in for each PE
    
    // Output collection
    reg [ACC_W-1:0]  result_buffer [0:N-1][0:N-1];
    reg              result_valid;
    reg [8:0]        out_cnt;
    
    //=========================================================================
    // Controller
    //=========================================================================
    sa16x16_ctrl #(.N(N)) u_ctrl (
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
    
    // Accept A matrix data
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
    
    // Accept B matrix data
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
    // A Input Generation (to left edge of array only)
    // A[r][k] enters PE[r][0] at phase k+r, then propagates right through PEs
    //=========================================================================
    genvar r, c;
    generate
        for (r = 0; r < N; r = r + 1) begin : a_input_gen
            // Compute which A element to inject: a_phase = phase_cnt - r
            wire [5:0] a_phase_raw = phase_cnt - r[5:0];
            wire a_in_range = pe_enable && (phase_cnt >= r[5:0]) && (a_phase_raw < N);
            
            // Inject A[r][a_phase] to left edge PE[r][0]
            assign a_wire[r][0] = a_in_range ? mat_a[r][a_phase_raw[3:0]] : {DATA_W{1'b0}};
        end
    endgenerate
    
    //=========================================================================
    // B Input Generation (to top edge of array only)
    // B[k][c] enters PE[0][c] at phase k+c, then propagates down through PEs
    //=========================================================================
    generate
        for (c = 0; c < N; c = c + 1) begin : b_input_gen
            // Compute which B element to inject: b_phase = phase_cnt - c
            wire [5:0] b_phase_raw = phase_cnt - c[5:0];
            wire b_in_range = pe_enable && (phase_cnt >= c[5:0]) && (b_phase_raw < N);
            
            // Inject B[b_phase][c] to top edge PE[0][c]
            assign b_wire[0][c] = b_in_range ? mat_b[b_phase_raw[3:0]][c] : {DATA_W{1'b0}};
        end
    endgenerate
    
    //=========================================================================
    // Valid signal generation for edge PEs
    // Data flows through PEs, valid propagates with data
    //=========================================================================
    // Left edge valid (for A input)
    wire v_a_edge [0:N-1];
    generate
        for (r = 0; r < N; r = r + 1) begin : v_a_gen
            wire [5:0] a_phase_raw = phase_cnt - r[5:0];
            assign v_a_edge[r] = pe_enable && (phase_cnt >= r[5:0]) && (a_phase_raw < N);
        end
    endgenerate
    
    // Top edge valid (for B input)
    wire v_b_edge [0:N-1];
    generate
        for (c = 0; c < N; c = c + 1) begin : v_b_gen
            wire [5:0] b_phase_raw = phase_cnt - c[5:0];
            assign v_b_edge[c] = pe_enable && (phase_cnt >= c[5:0]) && (b_phase_raw < N);
        end
    endgenerate
    
    //=========================================================================
    // PE valid_in computation (diagonal wavefront)
    // PE[r][c] receives valid data when both A and B inputs are valid
    //=========================================================================
    generate
        for (r = 0; r < N; r = r + 1) begin : v_in_row_gen
            for (c = 0; c < N; c = c + 1) begin : v_in_col_gen
                // PE[r][c] gets valid when:
                // phase_cnt >= r + c (wavefront has reached this PE)
                // AND phase_cnt < r + c + N (wavefront hasn't passed)
                wire [5:0] pe_start = r[5:0] + c[5:0];
                wire [5:0] pe_end = r[5:0] + c[5:0] + N[5:0];
                
                assign v_in[r][c] = pe_enable && 
                                    (phase_cnt >= pe_start) && 
                                    (phase_cnt < pe_end);
            end
        end
    endgenerate
    
    //=========================================================================
    // PE Array Instantiation
    //=========================================================================
    generate
        for (r = 0; r < N; r = r + 1) begin : pe_row_gen
            for (c = 0; c < N; c = c + 1) begin : pe_col_gen
                sa16x16_pe #(
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
                    .valid_out(),  // Internal use only
                    
                    .acc_out(acc_out[r][c]),
                    .acc_valid(acc_valid[r][c])
                );
            end
        end
    endgenerate
    
    //=========================================================================
    // Result Collection & Output
    //=========================================================================
    
    // Detect rising edge of drain_en
    reg drain_en_d;
    wire drain_start = drain_en && !drain_en_d;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            drain_en_d <= 1'b0;
        else
            drain_en_d <= drain_en;
    end
    
    // Store results when drain phase starts (only once)
    integer i_r, j_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i_r = 0; i_r < N; i_r = i_r + 1)
                for (j_r = 0; j_r < N; j_r = j_r + 1)
                    result_buffer[i_r][j_r] <= {ACC_W{1'b0}};
            result_valid <= 1'b0;
        end else if (drain_start) begin
            // Copy all results when drain starts (one-shot)
            for (i_r = 0; i_r < N; i_r = i_r + 1)
                for (j_r = 0; j_r < N; j_r = j_r + 1)
                    result_buffer[i_r][j_r] <= acc_out[i_r][j_r];
            result_valid <= 1'b1;
        end else if (out_cnt >= N*N) begin
            result_valid <= 1'b0;
        end
    end
    
    // Output counter
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_cnt <= 9'd0;
        end else if (!result_valid) begin
            out_cnt <= 9'd0;
        end else if (m_axis_c_tvalid && m_axis_c_tready) begin
            out_cnt <= out_cnt + 9'd1;
        end
    end
    
    // Output data selection (row-major order)
    wire [3:0] out_row = out_cnt / N;
    wire [3:0] out_col = out_cnt % N;
    
    assign m_axis_c_tdata  = result_buffer[out_row][out_col];
    assign m_axis_c_tvalid = result_valid && (out_cnt < N*N);
    assign m_axis_c_tlast  = result_valid && (out_cnt == N*N - 1);

endmodule
