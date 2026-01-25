# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MAC16 is a 16-bit serial input/output Multiply-Accumulate (MAC) digital chip design targeting 55nm technology (icsprout55 PDK). The design operates at 1GHz with 1Gbps serial I/O.

## Build Commands

### iEDA Flow (Open-source, default)

```bash
make verif          # Run functional simulation with Icarus Verilog
make yosys          # Run synthesis with Yosys
make sta            # Run STA on latest synthesis
make sta_all        # Multi-corner STA (TT, SS)
make equiv          # Formal equivalence check (RTL vs netlist)
make pr             # Place & Route with iEDA
make power          # Power analysis
make report         # Generate gap analysis report
```

### Synopsys Flow (Remote)

```bash
make FLOW=synopsys vcs    # VCS simulation
make FLOW=synopsys dc     # Design Compiler synthesis
make FLOW=synopsys fm     # Formality equivalence check
make FLOW=synopsys icc    # IC Compiler P&R
```

## Architecture

### RTL Modules (`rtl/`)

- **mac16.sv**: Top-level MAC unit with 5-state FSM for pipelined multiplication
  - States: S_INPUT → S_MULT_STAGE1 → S_MULT_STAGE2 → S_ADD → S_OUTPUT
  - Serial input: 16 bits each for inA/inB, MSB first at 1Gbps
  - Serial output: 24-bit sum_out, MSB first
  - Two modes: mode=0 outputs current × previous product sum; mode=1 outputs running accumulation
- **mult16_pipeline.sv**: 2-stage pipelined 16×16 multiplier (for timing optimization)
  - Stage 1: Register inputs (a_r, b_r)
  - Stage 2: Perform multiplication and register result
- **mult16.sv**: Combinational 16×16 multiplier (legacy, not used in current design)
- **adder.sv**: Simple 8-bit adder (utility module)

### Testbenches (`verif/`)

- **tb_mac16.sv**: Main testbench covering all test cases from specification
- **tb_mac16_simple.sv**: Simplified testbench
- **tb_mult16_pipeline.sv**: Unit test for pipeline multiplier (109 test cases)
- **tb_mult16.sv**, **tb_adder.sv**: Unit tests for submodules

### Key Directories

- `syn/yosys-syn-<timestamp>/`: Synthesis outputs (netlist, timing reports, power analysis)
- `scripts/`: TCL scripts for iEDA/Synopsys flows, SDC constraints
- `scripts/iEDA_config/`: iEDA tool configuration JSONs
- `docs/`: Design documentation and optimization logs

## Design Constraints

- Target frequency: 1GHz (CLK_FREQ_MHZ=1000)
- Target power: ≤300μW (bonus ≤100μW)
- Target area: ≤90μm × 90μm (8100μm²)
- Metal layers: M1-M5 only
- PVT corners: TT/1.2V/27°C, SS/1.08V/125°C, FF/1.32V/-40°C

## Current Status (2026-01-26)

- **Functional**: All 3 test modes pass (Mode 0, Mode 1, Mode Switch)
- **Timing**: WNS = -0.434ns @ 1GHz TT (achieves ~697MHz)
- **Area**: 4800μm² (59% of target)
- **Optimization log**: `docs/timing_optimization_log.md`

## Dependencies

- **yosys-sta**: Located at `../yosys-sta/` - provides synthesis and STA infrastructure
- **iEDA**: Binary expected at `../yosys-sta/bin/iEDA`
- **icsprout55 PDK**: Located at `../yosys-sta/pdk/icsprout55`
- **Icarus Verilog**: For local simulation (`iverilog`, `vvp`)