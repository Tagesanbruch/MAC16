`timescale 1ns/1ps
//============================================================================
// 4x4 Systolic Array Controller
// Fixed N=4 for simplified synthesis
//============================================================================
module sa4x4_ctrl (
    input  logic        clk,
    input  logic        rst_n,
    
    input  logic        start,
    output logic        busy,
    output logic        done,
    
    output logic        pe_enable,
    output logic        pe_clear,
    
    output logic        load_a_en,
    output logic        load_b_en,
    output logic [1:0]  load_row,
    output logic [1:0]  load_col,
    
    output logic        drain_en,
    output logic [1:0]  drain_row,
    output logic [1:0]  drain_col,
    
    output logic [4:0]  phase_cnt,
    output logic [4:0]  total_cnt
);
    localparam N = 4;
    
    typedef enum logic [2:0] {
        S_IDLE    = 3'd0,
        S_CLEAR   = 3'd1,
        S_LOAD_A  = 3'd2,
        S_LOAD_B  = 3'd3,
        S_COMPUTE = 3'd4,
        S_DRAIN   = 3'd5,
        S_DONE    = 3'd6
    } state_t;
    
    state_t state, next_state;
    
    logic [4:0]  cnt;
    logic [1:0]  row_cnt;
    logic [1:0]  col_cnt;
    logic [4:0]  compute_phase;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= next_state;
    end
    
    always_comb begin
        next_state = state;
        case (state)
            S_IDLE: begin
                if (start)
                    next_state = S_CLEAR;
            end
            
            S_CLEAR: begin
                next_state = S_LOAD_A;
            end
            
            S_LOAD_A: begin
                if (cnt == N*N - 1)
                    next_state = S_LOAD_B;
            end
            
            S_LOAD_B: begin
                if (cnt == N*N - 1)
                    next_state = S_COMPUTE;
            end
            
            S_COMPUTE: begin
                // 3*N + 2 cycles for complete computation
                if (compute_phase == 3*N + 2)
                    next_state = S_DRAIN;
            end
            
            S_DRAIN: begin
                if (cnt == N*N - 1)
                    next_state = S_DONE;
            end
            
            S_DONE: begin
                next_state = S_IDLE;
            end
        endcase
    end
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= '0;
            row_cnt <= '0;
            col_cnt <= '0;
            compute_phase <= '0;
        end else begin
            case (next_state)
                S_IDLE, S_DONE: begin
                    cnt <= '0;
                    row_cnt <= '0;
                    col_cnt <= '0;
                    compute_phase <= '0;
                end
                
                S_CLEAR: begin
                    cnt <= '0;
                    row_cnt <= '0;
                    col_cnt <= '0;
                    compute_phase <= '0;
                end
                
                S_LOAD_A, S_LOAD_B, S_DRAIN: begin
                    if (state != next_state) begin
                        cnt <= '0;
                        row_cnt <= '0;
                        col_cnt <= '0;
                    end else begin
                        if (col_cnt == N - 1) begin
                            col_cnt <= '0;
                            row_cnt <= row_cnt + 1'b1;
                        end else begin
                            col_cnt <= col_cnt + 1'b1;
                        end
                        cnt <= cnt + 1'b1;
                    end
                end
                
                S_COMPUTE: begin
                    if (state != next_state) begin
                        compute_phase <= '0;
                    end else begin
                        compute_phase <= compute_phase + 1'b1;
                    end
                end
            endcase
        end
    end
    
    assign busy = (state != S_IDLE) && (state != S_DONE);
    assign done = (state == S_DONE);
    
    assign pe_enable = (state == S_COMPUTE);
    assign pe_clear  = (state == S_CLEAR);
    
    assign load_a_en = (state == S_LOAD_A);
    assign load_b_en = (state == S_LOAD_B);
    assign load_row  = row_cnt;
    assign load_col  = col_cnt;
    
    assign drain_en  = (state == S_DRAIN);
    assign drain_row = row_cnt;
    assign drain_col = col_cnt;
    
    assign phase_cnt = compute_phase;
    assign total_cnt = cnt;

endmodule
