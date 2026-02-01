`ifndef SA16X16_DEFS_SVH
`define SA16X16_DEFS_SVH

//============================================================================
// 16×16 Systolic Array - Common Definitions
//============================================================================

// Array dimensions
parameter SA_N = 16;           // Array size (N×N)
parameter SA_TOTAL_PE = 256;   // Total PEs

// Data widths (aligned with mac16 serial interface)
parameter SA_DATA_W = 16;      // Input element bit width
parameter SA_ACC_W  = 40;      // Accumulator width (for 16 products)
parameter SA_OUT_W  = 40;      // Output element width

// Serial interface timing (aligned with mac16)
parameter SA_SERIAL_IN_BITS  = 16;   // Serial input bits
parameter SA_SERIAL_OUT_BITS = 24;   // Serial output bits (per element)

// AXI-Stream interface widths
parameter SA_AXIS_DATA_W = SA_DATA_W;  // One element per beat
parameter SA_AXIS_USER_W = 8;          // Row/col ID encoding

// Timing parameters
parameter SA_FILL_CYCLES   = 2 * SA_N - 1;  // Time to fill array diagonally
parameter SA_DRAIN_CYCLES  = SA_N;          // Time to drain results

// PE modes (compatible with mac16 mode)
parameter PE_MODE_PASS = 1'b0;    // Pass-through accumulation
parameter PE_MODE_ACCUM = 1'b1;   // Full accumulation

`endif

