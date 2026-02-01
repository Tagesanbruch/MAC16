# MAC16 Experiment L & M Results Summary

## Overview

This document summarizes the synthesis and STA results for two new MAC16 architectures:
- **Exp L**: 6-stage pipelined multiplier (split CPA)
- **Exp M**: 8-stage super-deep pipelined multiplier (separated PPG + 3-way CPA split)

Both architectures build upon exp_k (5-stage baseline) to improve timing margins.

## Verification Results

| Experiment | Mode 0 | Mode 1 | Mode Switch | Status |
|------------|--------|--------|-------------|--------|
| exp_l | ✅ PASS | ✅ PASS | ✅ PASS | All tests passed |
| exp_m | ✅ PASS | ✅ PASS | ✅ PASS | All tests passed |

## Synthesis Results

| Metric | Exp K (baseline) | Exp L | Exp M |
|--------|------------------|-------|-------|
| Pipeline Stages | 5 | 6 | 8 |
| Total Area (µm²) | 6,754 | 6,926 | 8,160 |
| Seq. Elements (%) | ~53% | 54.34% | 60.92% |
| Instance Count | ~1,915 | 2,166 | 2,361 |

## Static Timing Analysis (TT Corner @ 1GHz target)

### Exp L (6-stage)

| Metric | Value |
|--------|-------|
| WNS (Worst Negative Slack) | **+0.101 ns** |
| TNS (Total Negative Slack) | 0.000 ns |
| Max Frequency | **1112 MHz** |
| Critical Path | `accum_23__reg_p:D` (accumulator) |
| Path Delay | 0.840 ns |

### Exp M (8-stage)

| Metric | Value |
|--------|-------|
| WNS (Worst Negative Slack) | **+0.084 ns** |
| TNS (Total Negative Slack) | 0.000 ns |
| Max Frequency | **1092 MHz** |
| Critical Path | `u_mult.pp1_s2_17__reg_p:D` (PPG Stage 2) |
| Path Delay | 0.854 ns |

## Analysis

### Key Findings

1. **Exp L outperforms Exp M at TT corner**: 
   - Exp L achieves 1112 MHz vs Exp M's 1092 MHz
   - The extra pipeline stages in Exp M add more delay than they reduce the critical path

2. **Area vs Performance Tradeoff**:
   - Exp M has 18% larger area (8160 vs 6926 µm²)
   - But achieves 2% lower frequency
   - The additional PPG pipeline stage creates new timing challenges

3. **Critical Path Analysis**:
   - Exp L: Limited by accumulator addition (expected)
   - Exp M: Limited by partial product generation stage connection
   - Both designs meet 1GHz target with margin

4. **Sequential Element Distribution**:
   - Exp M: 60.9% sequential elements (vs 54.3% in exp_l)
   - Higher register count expected due to deeper pipeline

### Comparison with Exp K (Baseline)

| Experiment | Freq (TT) | Area | Improvement |
|------------|-----------|------|-------------|
| Exp K | 1154 MHz | 6,754 µm² | Baseline |
| Exp L | 1112 MHz | 6,926 µm² | -3.6% freq, +2.5% area |
| Exp M | 1092 MHz | 8,160 µm² | -5.4% freq, +20.8% area |

> **Note**: The lower frequency compared to exp_k is unexpected and may indicate:
> - The 6-stage split created suboptimal cut points
> - ABC optimization chose different gate mappings
> - Additional stage crossings added unexpected delays

## Recommendations

1. **For TT Corner Target (1GHz)**: Both exp_l and exp_m are viable, but **exp_l** is preferred due to smaller area and higher frequency.

2. **For SS Corner Target**: Need to run STA at SS corner to evaluate. The deeper pipeline (exp_m) may provide better SS corner margins despite lower TT frequency.

3. **Next Steps**:
   - Run SS corner STA for both architectures
   - Investigate exp_k's PPG and CPA to understand why it achieved higher frequency
   - Consider hybrid approach: exp_l's CPA split + direct PPG stage

## Files

- **Exp L RTL**: `rtl/experiments/exp_l/`
  - `mult16_booth_6stage.sv` - 6-stage multiplier
  - `mac16.sv` - MAC wrapper

- **Exp M RTL**: `rtl/experiments/exp_m/`
  - `mult16_booth_8stage.sv` - 8-stage multiplier
  - `mac16.sv` - MAC wrapper

- **Synthesis Outputs**:
  - `syn/yosys-syn-exp_l-2026-02-02_*/`
  - `syn/yosys-syn-exp_m-2026-02-02_*/`
