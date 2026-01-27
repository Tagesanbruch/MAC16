# Chisel MAC16

生成 Chisel 版本 MAC16（`exp_d`/`exp_i`）的 Verilog 到 `vsrc/`。

## 生成 Verilog

```bash
./mill mac16.run --exp exp_d --out vsrc/exp_d
./mill mac16.run --exp exp_i --out vsrc/exp_i
```

## Makefile 快捷命令

```bash
make gen_exp_d
make gen_exp_i
```
