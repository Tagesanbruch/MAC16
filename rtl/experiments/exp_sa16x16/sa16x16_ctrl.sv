`timescale 1ns/1ps
//============================================================================
// Systolic Array Controller
// 
// Controls the 16×16 systolic array operation phases:
//   1. IDLE: Wait for start
//   2. LOAD: Load input matrices (256 elements each for A and B)
//   3. COMPUTE: Execute matrix multiplication (2N-1 cycles)
//   4. DRAIN: Collect results from PE array
//   5. OUTPUT: Stream results out
//============================================================================
module sa16x16_ctrl #(
    parameter N = 16
)(
    input  logic        clk,
    input  logic        rst_n,
    
    // Control interface
    input  logic        start,
    output logic        busy,
    output logic        done,
    
    // PE array control
    output logic        pe_enable,
    output logic        pe_clear,
    
    // Input loading control
    output logic        load_a_en,
    output logic        load_b_en,
    output logic [3:0]  load_row,
    output logic [3:0]  load_col,
    
    // Output draining control  
    output logic        drain_en,
    output logic [3:0]  drain_row,
    output logic [3:0]  drain_col,
    
    // Phase counters (for external use)
    output logic [5:0]  phase_cnt,
    output logic [8:0]  total_cnt
);

    // State machine
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
    
    // Counters
    logic [8:0]  cnt;        // General counter
    logic [3:0]  row_cnt;    // Row counter
    logic [3:0]  col_cnt;    // Column counter
    logic [5:0]  compute_phase; // Compute phase (0 to 2N-2)
    
    // State transition
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= next_state;
    end
    
    // Next state logic
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
                // Last PE[N-1][N-1] receives data at phase (N-1)+(N-1) = 2N-2
                // Last valid input is at phase 2N-2 + (N-1) = 3N-3
                // Need 5 more cycles for pipeline flush
                // Total: 3N-3 + 5 = 3N+2 cycles
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
    
    // Counter logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= '0;
            row_cnt <= '0;
            col_cnt <= '0;
            compute_phase <= '0;
        end else begin
            case (next_state)  // Use next_state to prepare counters
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
                    // Reset counters when entering new phase
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
    
    // Output signals
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

