# VMA 时序差异深度分析

**日期**: 2026-02-03  
**问题**: 为什么 exp_ua (5级) 的 VMA 路径比 exp_sd (4级) 更差？

---

## 1. 核心数据对比

### SS Corner 关键路径对比

| 设计 | VMA 路径终点 | Path Delay | Slack | Freq |
|------|-------------|------------|-------|------|
| **exp_sd** | `out_shift_reg_11__reg_p:D` | 0.993ns | -0.105ns | 904 MHz |
| **exp_ua** | `out_shift_reg_15__reg_p:D` | **1.011ns** | **-0.123ns** | 890 MHz |

差异: **0.018ns** (约 2%)

---

## 2. 路径起点分析

两个设计的 VMA 输入都来自乘法器输出寄存器:

| 设计 | 起点寄存器 | Q→D 延迟 | 扇出 |
|------|-----------|---------|------|
| exp_sd | `mult_result_carry_4__reg_p:Q` | 0.174ns | 6 |
| exp_ua | `mult_result_sum_8__reg_p:Q` | 0.182ns | 6 |

起点延迟差异: 0.008ns

### VMA 组合逻辑延迟计算

| 设计 | 总路径延迟 | 起点延迟 | VMA 延迟 |
|------|----------|---------|---------|
| exp_sd | 0.993ns | 0.174ns | **0.819ns** |
| exp_ua | 1.011ns | 0.182ns | **0.829ns** |

VMA 组合逻辑差异: 0.010ns

---

## 3. 为什么 VMA 延迟会增加?

### 3.1 VMA RTL 完全相同
```
diff rtl/experiments/exp_sd/spanning_tree_adder.sv rtl/experiments/exp_ua/spanning_tree_adder.sv
(无差异)
```

### 3.2 mac16.sv 完全相同
```
diff rtl/experiments/exp_sd/mac16.sv rtl/experiments/exp_ua/mac16.sv
(无差异)
```

### 3.3 综合后网表不同

| 指标 | exp_sd | exp_ua |
|------|--------|--------|
| 网表行数 | 5090 | **5362** (+5%) |
| XOR/XNOR 门 | ~980 | ~1030 (+5%) |

**原因**: exp_ua 的 5 级流水线增加了更多流水寄存器。

### 3.4 关键差异: 压缩结构

| 设计 | 最后一级压缩 | 输入行数 |
|------|------------|---------|
| **exp_sd** | LLCBC (6:2) | 6 行 |
| **exp_ua** | 4:2 Compressor | 4 行 |

exp_ua 在 Stage 4 做 CSA (6→4)，Stage 5 做 4:2 (4→2)。
exp_sd 在 Stage 4 用 LLCBC 直接 6→2。

---

## 4. 真正的问题根源

**综合器行为差异**:

当整体设计变大时 (exp_ua 5级 vs exp_sd 4级):
1. Yosys 的逻辑优化有不同的选择空间
2. VMA 被 flatten 后，其门级实现可能略有不同
3. 更多的流水寄存器增加了时钟树扇出，可能影响时钟到达时间计算

**关键点**: VMA 本身没有变化，但综合器在更大的设计上下文中做出了略微不同的优化决策，导致 VMA 组合逻辑延迟增加了 **~0.01ns**。

---

## 5. 为什么 VMA 在 exp_sd 能 MET 而在 exp_ua 不能?

**答案**: VMA 在 exp_sd 也是 **VIOLATED** (-0.105ns)，只是比 exp_ua (-0.123ns) 轻微一些。

两个设计的 VMA 都没有 MET，只是:
- exp_sd: LLCBC 路径是最差的 (-0.108ns)，VMA 路径第二差 (-0.105ns)
- exp_ua: 压缩树不再是瓶颈，VMA 路径成为最差 (-0.123ns)

---

## 6. 结论

1. **VMA 实现没有变化**，RTL 完全相同
2. **综合差异**导致 VMA 组合逻辑延迟增加 ~0.01ns
3. **更重要的是**：exp_ua 的流水线重构消除了压缩树瓶颈，暴露了原本就存在的 VMA 瓶颈
4. **两个设计的 VMA 都违规**，只是严重程度不同

---

## 7. 当前 STA 是 Pre-Layout

**重要提醒**: 当前所有分析都基于 **Pre-Layout STA**（无 P&R）。

Post-Route STA 通常会因为:
- 连线 RC 延迟
- 时钟树 Skew
- 信号串扰

而变得**更差**。如果 Pre-Layout 已经 violated，Post-Route 情况只会更糟。

---

## 附录: 流水线结构对比

### Exp_SD (4 级 MAC)
```
Stage 1: Booth Encoding
Stage 2: PPG (8 rows)
Stage 3: CSA L1+L2 (8→6→4) + Feedback (4+2=6)
Stage 4: LLCBC (6→2) → result_sum/carry [寄存器]
      ↓
VMA (组合逻辑, ~0.82ns)
      ↓
out_shift_reg [寄存器]
```

### Exp_UA (5 级 MAC)
```
Stage 1: Booth + PPG (8 rows)
Stage 2: CSA L1 (8→6)
Stage 3: CSA L2 (6→4) + Feedback (4+2=6)
Stage 4: CSA L3 (6→4)
Stage 5: 4:2 Comp (4→2) → result_sum/carry [寄存器]
      ↓
VMA (组合逻辑, ~0.83ns)
      ↓
out_shift_reg [寄存器]
```
