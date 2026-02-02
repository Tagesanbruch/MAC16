# Exp_UA 实验总结报告

**日期**: 2026-02-03  
**实验名称**: exp_ua (U-Series Architecture Optimization)  
**基线**: exp_sd (902.858 MHz @ SS Corner)

---

## 1. 实验目标

基于 exp_sd 的关键路径分析结果，实施两项核心优化：

1. **流水线重平衡 (Pipeline Rebalancing)**：
   - 合并 Booth 编码 + PPG 生成到单一周期（逻辑浅）
   - 拆分原 Stage4 的 LLCBC 压缩，增加一级流水
   - 目标：将每级 FO4 深度从 ~6 级降低到 ~2-3 级

2. **MUX-Based 4:2 压缩器**：
   - 优化 `compressor_4to2.sv`，使用 MUX 结构引导综合
   - 关键优化：`Cout` 不依赖 `Cin`，减少关键路径延迟
   - 目标：从 4 级 XOR 延迟降低到 3 级

---

## 2. 架构变更

### 2.1 流水线结构对比

| Stage | Exp_SD (4-Stage) | Exp_UA (5-Stage) |
|-------|------------------|------------------|
| 1     | Booth Encode     | Booth + PPG (合并) |
| 2     | PPG Only         | CSA Layer 1 (8→6) |
| 3     | CSA 8→6 + 6→4    | CSA Layer 2 (6→4) + Feedback |
| 4     | LLCBC 6→2        | CSA Layer 3 (6→4) |
| 5     | —                | 4:2 Compressor (4→2) |

### 2.2 关键文件修改

| 文件 | 变更内容 |
|------|----------|
| `mult16_booth_dcs.sv` | 5 级流水线重构，每级只有 1 层 CSA 或 1 个 4:2 压缩器 |
| `compressor_4to2.sv` | MUX-based 实现，`cout = axorb ? c : a` |

---

## 3. 验证结果

### 3.1 功能验证
```
make verif EXP=exp_ua
[PASS] data correctness
[PASS] latency <= 5
[PASS] idle output zero
[PASS] out_ready window
[PASS] carry behavior
```

**Latency**: 5 cycles (用满预算，符合预期)

### 3.2 时序分析 (STA)

#### SS Corner (1.08V / 125°C / RCWorst) - Worst Case

| 端点 | Path Delay | Slack | Freq (MHz) |
|------|------------|-------|------------|
| `out_shift_reg_15__reg_p:D` | 1.011ns | **-0.123** | 890.425 |
| `out_shift_reg_19__reg_p:D` | 0.995ns | -0.119 | 893.581 |
| `out_shift_reg_15__reg_p:D` | 1.025ns | -0.119 | 893.780 |
| `out_shift_reg_17__reg_p:D` | 1.018ns | -0.116 | 895.752 |
| `out_shift_reg_16__reg_p:D` | 1.008ns | -0.109 | 901.944 |
| `carry_reg_p_CK_ICGX0P5H7L_ECK:E` | 1.009ns | -0.110 | N/A |

**WNS (Worst Negative Slack)**: -0.123ns  
**Max Frequency**: 890.425 MHz  
**TNS (Total Negative Slack)**: -7.078ns

#### TT/FF Corners (参考)

| Corner | WNS | Max Freq |
|--------|-----|----------|
| TT (1.2V/27°C) | -0.123ns | 890.4 MHz |
| FF (1.32V/-40°C) | +0.385ns | **1626.6 MHz** |

---

## 4. 关键发现

### 4.1 ✅ 优化成功：压缩树不再是瓶颈

在 exp_sd 中，关键路径是：
```
row2_s3_14__reg_p → 6级 XOR/XNOR → mult_result_sum_14__reg_p
```

在 exp_ua 中，**压缩树完全消失于 Top 5 关键路径**！

### 4.2 ❌ 新瓶颈：输出移位寄存器 + VMA

现在的关键路径变成了：
```
mult_result_sum_16__reg_p:Q 
  → XNOR2 (VMA 加法链) 
  → NOR2/NOR4/AOAI211/AOI31 (进位传播)
  → MUX2 (输出选择)
  → out_shift_reg_15__reg_p:D
```

**路径分析**:
| 延迟段 | 逻辑 | 延迟 |
|--------|------|------|
| DFF Q→XNOR | VMA 第一级 | ~0.17ns |
| XNOR Chain | VMA 进位 | ~0.22ns |
| NOR/AOAI/AOI | 进位传播 | ~0.35ns |
| MUX→DFF D | 输出选择 | ~0.27ns |
| **Total** | | **~1.01ns** |

### 4.3 根因分析

问题在于 `mac16.sv` 中的设计：

```systemverilog
// Line 166: VMA 输出直接写入 out_shift_reg
out_shift_reg <= mac_result;  // mac_result = vma_result[23:0]
```

VMA（Spanning Tree Adder）是 **40-bit 的加法器**，从 `mult_result_sum` 和 `mult_result_carry` 直接组合逻辑到输出寄存器。即使我们优化了乘法器核心，VMA 的长组合路径仍然会成为瓶颈。

---

## 5. 对比分析

| 指标 | Exp_SD | Exp_UA | 变化 |
|------|--------|--------|------|
| 流水线级数 | 4 | 5 | +1 |
| Latency (cycles) | 4 | 5 | +1 |
| WNS @ SS | -0.108ns | -0.123ns | ❌ -0.015ns |
| Max Freq @ SS | 902.858 MHz | 890.425 MHz | ❌ -12.4 MHz |
| 关键路径位置 | 压缩树 (LLCBC) | 输出链 (VMA) | ✅ 转移 |
| Max Freq @ FF | ~1644 MHz | 1626.6 MHz | ≈ |

**结论**：虽然 SS 角频率略有下降，但**压缩树优化已生效**，瓶颈成功转移到 VMA 输出路径。

---

## 6. 下一步优化建议

### 方案 A：VMA 流水化（推荐）
将 VMA 结果打一拍，把 VMA 计算和输出移位分开：
```
Cycle N:   mult_result_sum/carry → VMA Reg (内部打拍)
Cycle N+1: VMA Reg → out_shift_reg
```
- **优点**: 彻底切断长组合路径
- **缺点**: Latency +1 cycle（可能超出 5 cycle 限制）

### 方案 B：VMA 设为 Multicycle Path
如果 VMA 只在输出阶段使用（不在 MAC 循环内），可以设置 SDC 约束：
```tcl
set_multicycle_path 2 -setup -to [get_pins out_shift_reg_*/D]
```
- **优点**: 不改 RTL，只改约束
- **缺点**: 需确认 VMA 确实不在循环关键路径

### 方案 C：优化 VMA 结构
使用更快的加法器结构（如 Ling Adder）或拆分 VMA 为高低位分段加法：
- 低 24 位：快速加法输出
- 高 16 位：延迟计算（不影响输出）

### 方案 D：输出逻辑重构
分析输出移位寄存器的逻辑深度，考虑使用更简单的移位结构或并行输出。

---

## 7. 文件清单

| 路径 | 说明 |
|------|------|
| `rtl/experiments/exp_ua/mult16_booth_dcs.sv` | 5 级流水线乘法器 |
| `rtl/experiments/exp_ua/compressor_4to2.sv` | MUX-based 4:2 压缩器 |
| `syn/yosys-syn-exp_ua-2026-02-03_04-10-27/` | 综合输出目录 |
| `syn/.../mac16_2026-02-02T20_11_33.rpt` | SS 角 STA 报告 |

---

## 8. 总结

Exp_UA 成功验证了"流水线重平衡 + MUX-based 4:2"的优化思路：

- ✅ 压缩树从关键路径消失
- ✅ 功能验证通过，Latency = 5 cycles
- ❌ 频率反而略有下降（890 MHz vs 902 MHz）
- ❓ 新瓶颈在 VMA + 输出移位寄存器

**关键洞察**: 优化压缩树后，**VMA 成为新的瓶颈**。由于 DCS 架构中 VMA 只在输出阶段使用，不在 MAC 累加循环内，可以考虑 Multicycle Path 或 VMA 流水化来进一步优化。
