# 2026-01-27 Chisel vs RTL PPA Comparison (exp_d / exp_i)

## Scope
- Target: 1000MHz, PDK `icsprout55`
- Flow: `make verif/synth/sta` (Chisel) vs existing RTL results

## Result Directories
- Chisel exp_d: `syn/yosys-syn-chisel-exp_d-2026-01-27_18-42-17`
- Chisel exp_i: `syn/yosys-syn-chisel-exp_i-2026-01-27_18-43-25`
- RTL exp_d: `syn/yosys-syn-exp_d-2026-01-26_04-52-40`
- RTL exp_i: `syn/yosys-syn-exp_i-2026-01-26_19-40-06`

## PPA Summary
| Experiment | Implementation | Chip Area | Seq Area % | TNS (max) |
| --- | --- | --- | --- | --- |
| exp_d | RTL | 5659.64 | 39.77% | 0.000 |
| exp_d | Chisel | 5578.72 | 39.92% | 0.000 |
| exp_i | RTL | 5801.32 | 42.58% | 0.000 |
| exp_i | Chisel | 6040.44 | 40.76% | 0.000 |

## Verification
- `make verif EXP=exp_d` and `make verif EXP=exp_i` passed.
- Verilator warnings observed (missing `timescale`, width truncation in TB). No functional failures.

## Notes
- Chisel exp_d area is slightly lower than RTL exp_d, seq% nearly identical.
- Chisel exp_i area is higher than RTL exp_i, seq% lower.
- STA `TNS(max)` is clean (0.000) for all listed runs at 1000MHz.

## Logs
- Chisel exp_d STA log: `logs/chisel_exp_d_sta_2026-01-27.log`
- Chisel exp_i synth log: `logs/chisel_exp_i_synth_2026-01-27.log`
- Chisel exp_i STA log: `logs/chisel_exp_i_sta_2026-01-27.log`
