# Chisel MAC16 调试日志

## 2026-01-27

### 问题现象

使用 `make verif` 运行 Chisel 生成的 MAC16 RTL，发现以下问题：

1. **所有测试结果都少 9（0x9）**：
   - Mode0 Test 0: Expected=0xC, Got=0x3 (差 0x9)
   - Mode0 Test 1: Expected=0xFC, Got=0xF3 (差 0x9)
   - Mode0 Test 2: Expected=0x4DE, Got=0x4D5 (差 0x9)
   - ...所有测试都差 9

2. **模式切换后结果正确**：
   - ModeSwitch Test 3-5 在 mode=1 时 PASSED

### 根因分析

#### 问题 1：4x 乘法错误

**现象**：乘法结果是预期值的 4 倍

**根因**：移位寄存器在输入完成后继续移位，导致乘数被放大

**修复**：添加 `latchedA`/`latchedB` 寄存器，在正确时机锁存输入值

#### 问题 2：结果差 9

**现象**：所有结果与预期值相差 9

**根因**：锁存时机错误

原代码：
```scala
when(cnt === (inputBits - 1).U) {
  latchedA := shiftA  // 错误：shiftA 还没有包含最后一个 bit
  ...
}
```

在 `cnt === 15` 时：
- `shiftA` 是旧值（不含最后一个 bit）
- `shiftANext` 是新值（包含最后一个 bit）
- 我们错误地锁存了 `shiftA`

**修复**：
```scala
when(cnt === (inputBits - 1).U) {
  latchedA := shiftANext  // 正确：锁存包含最后一个 bit 的完整值
  latchedB := shiftBNext
  ...
}
```

### 测试结果（已修复）

✅ **功能验证（make verif）**
- Mode 0 测试：全部通过
- Mode 1 测试：全部通过  
- 模式切换测试：全部通过

✅ **Chisel 单元测试（mill mac16.test）**
- 24/24 测试通过

### 问题 3：后续操作 4x 乘法错误（已解决）

**现象**：第一次操作正确，后续操作结果是预期值的 4 倍

**调试发现**：
通过详细的时序调试，发现问题出在 `out_ready` 信号：

| 信号 | 原始 RTL | Chisel (错误) |
|------|----------|---------------|
| out_ready | 寄存器输出 | 组合逻辑输出 |
| 时序 | 下一周期变化 | 当前周期变化 |

**根因分析**：

Chisel 版本的 `out_ready` 是组合逻辑输出（使用 `:=` 赋值的 Wire），而原始 RTL 的 `out_ready` 是寄存器输出（使用 `<=` 非阻塞赋值）。

这导致 `out_ready` 变低的时机差了一个周期：
- 原始 RTL：T=46000 out_ready 变低
- Chisel：T=45000 out_ready 变低

因此 testbench 提前一个周期开始发送新数据，而 Chisel FSM 还在 sInput 状态处理"垃圾"数据（上次操作的移位寄存器值），导致输入值被多移一位。

**修复**：
将 `out_ready` 和 `sum_out` 改为寄存器输出：

```scala
// 添加输出寄存器
val outReadyReg = RegInit(false.B)
val sumOutReg   = RegInit(false.B)

// 在状态机中使用寄存器
outReadyReg := true.B   // 替代 out_ready := true.B

// 连接到输出端口
out_ready := outReadyReg
sum_out   := sumOutReg
```

### 问题 4：乘法器流水线级数不匹配（已解决）

**现象**：使用 3 级流水线乘法器导致时序不匹配

**修复**：创建 `Mult16Booth2Stage`，将 Booth 乘法器改为 2 级流水线，与原始 RTL 保持一致。

### 总结

Chisel 版本现已与原始 RTL 功能完全一致。关键修复点：

1. **输出寄存器**：`out_ready` 和 `sum_out` 必须是寄存器输出，确保时序与原始 RTL 一致
2. **乘法器流水线**：使用 2 级流水线乘法器，与原始 RTL 的 `mult16_pipeline` 匹配

---

## 调试命令记录

```bash
# 运行 Chisel 生成 + 验证
cd /Volumes/disk/work/ysyx/mac/chisel && make verif

# 运行对比 testbench
cd /Volumes/disk/work/ysyx/mac && verilator --binary --timing --top-module tb_mac16_compare \
  --Mdir chisel/obj_dir -Wno-TIMESCALEMOD -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
  chisel/vsrc/exp_d/mac16.sv chisel/test/mac16_orig_renamed.sv \
  rtl/mult16_pipeline.sv rtl/mult16.sv rtl/adder.sv \
  chisel/test/tb_mac16_compare.sv -o chisel/obj_dir/tb_mac16_compare && \
  chisel/obj_dir/tb_mac16_compare
```
