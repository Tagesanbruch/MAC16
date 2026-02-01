# MAC Project

This project contains the RTL and synthesis flow for the `mac` design.

## Structure

- `rtl/`: SystemVerilog source files
- `build/`: Build artifacts
- `docs/`: Documentation
- `scripts/`: Local scripts
- `syn/`: Synthesis results (generated)

## Synthesis Flow

The synthesis flow uses `yosys` and `iEDA` via the `yosys-sta` infrastructure.

### Prerequisites

- `yosys` installed and in PATH (or provided by OSS CAD Suite)
- `iEDA` binary available in `../yosys-sta/bin/` or `toolchains/iEDA`
- `icsprout55` PDK

### Running Synthesis

To run synthesis with Yosys:

```bash
make yosys
```

Results will be located in `syn/yosys-syn-<timestamp>/`.

### Running Static Timing Analysis (STA)

To run STA:

```bash
make sta
```

## Recent Notes

- 2026-02-01: SA4x4 PPA/验证计划与讨论纪要: [docs/2026-02-01-sa4x4-ppa-verify-plan.md](docs/2026-02-01-sa4x4-ppa-verify-plan.md)
