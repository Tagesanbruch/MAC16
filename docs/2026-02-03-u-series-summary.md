# U 系列实验总结报告

**日期**: 2026-02-03  
**目标**: 在 5-cycle latency 限制下，突破 1GHz @ SS Corner

---

## 1. 实验总览

| 实验 | 架构特点 | Latency | SS Corner WNS | SS Freq | 结果 |
|------|---------|---------|---------------|---------|------|
| exp_sd (Baseline) | 4级MAC + VMA组合 | 4 | -0.108ns | 902 MHz | 基线 |
| exp_ua | 5级MAC + VMA组合 | 5 | -0.123ns | 890 MHz | ❌ 更差 |
| exp_ub | 4级MAC + 1级VMA | 5 | -0.422ns | 703 MHz | ❌ S1过重 |
| exp_uc | 4级MAC + G/P预计算 | 5 | -0.273ns | 785 MHz | ❌ 综合差异 |
| exp_ud | 4级MAC + MUX压缩器 | 4 | -0.108ns | 902 MHz | = 基线 |
| exp_ue v1 | 3级MAC + 2级VMA | 5 | ~1.4ns | 646 MHz | ❌ S1过重 |
| exp_ue v2 | 3级MAC + 2级VMA (S1 Lite) | 5 | ~1.1ns | 782 MHz | ❌ S3过重 |
| exp_ue v3 | 3级MAC + 2级VMA (CSA Split) | 5 | ~1.08ns | 845 MHz | ❌ S2过重 |
| exp_ue v4 | 3级MAC + 2级VMA (No Align S1) | 5 | ~1.05ns | 862 MHz | ❌ S2过重 |

---

## 2. 关键发现

### 2.1 瓶颈分析

exp_sd 在 SS 角有**三个并列瓶颈**：

| 路径 | 位置 | Slack | Freq |
|------|------|-------|------|
| `mult_result_sum_14__reg_p:D` | MAC Stage 4 (LLCBC) | -0.108ns | 902 MHz |
| `out_shift_reg_11__reg_p:D` | VMA + Output | -0.105ns | 905 MHz |
| `u_mult.pp2_s2_10__reg_p:D` | MAC Stage 2 (PPG) | -0.103ns | 906 MHz |

三条路径非常接近，任何单一优化都会暴露其他瓶颈。

### 2.2 优化尝试分析

#### Exp_UA (5级 MAC)
- **策略**: 将压缩树拆分到更多级，使用 MUX-based 4:2
- **结果**: 压缩树不再是瓶颈 ✅
- **问题**: VMA 成为新瓶颈，且 latency 用满 (5 cycles)
- **教训**: 优化一个瓶颈会暴露另一个

#### Exp_UB (4级 MAC + 1级 VMA)
- **策略**: 压缩 MAC 到 4 级，VMA 打拍
- **结果**: 失败 ❌
- **问题**: Stage 1 (Booth+PPG+CSA1) 过重，高扇出导致 703 MHz
- **教训**: 流水级合并需要考虑扇出

#### Exp_UC (G/P 预计算)
- **策略**: 将 VMA 的 G/P 生成吸收到 MAC 输出
- **结果**: 失败 ❌
- **问题**: Stage 2 PPG 路径反而变差（785 MHz vs 906 MHz）
- **教训**: 可能是综合差异或额外扇出

#### Exp_UD (MUX 压缩器)
- **策略**: 只替换 4:2 压缩器为 MUX 版本
- **结果**: 无改善 (= exp_sd)
- **教训**: Yosys 综合器可能已做类似优化

#### Exp_UE (3级 MAC + 2级 VMA)
- **策略**: 将 MAC 压缩为 3 级，腾出 2 级给 VMA 流水线
- **结果**: 最佳尝试 862 MHz (v4) ❌
- **问题**: SS Corner 下，Booth+PPG 自身已接近 1ns。想要在 3 级内完成压缩（即便做了各种拆分）都会导致某一级超过 1ns。
- **教训**: 在此工艺和 SS Corner 下，MAC 及其压缩逻辑至少需要 4 级流水线。

---

## 3. 根本限制分析

### 3.1 Latency 预算与流水线级数

要达到 SCC Corner 1GHz (1ns):
- **Booth+PPG**: 自带 ~0.9ns 延迟 -> 必须独占 Stage 1
- **CSA Tree**: 8层压缩到2层，至少需 2ns -> 必须占 Stage 2, 3
- **VMA**: 40-bit 加法，~0.9ns -> 必须占 Stage 4 (or 4+5)

结论：**MAC 核心部分至少需要 4 级流水线** (与 exp_sd 一致)。试图压缩到 3 级必然失败。

### 3.2 时序裕量

目标 1GHz = 1ns 周期。
SS 角实际最差路径 = 1.108ns (exp_sd)。
**差距 = 10.8%**。

这 10.8% 的差距难以仅通过 RTL 优化弥补。

---

## 4. 推荐下一步：定量分析与局部验证

既然定性尝试（根据架构图移动模块）已经遇到瓶颈，现在的关键是**定量数据**。

我们需要精确回答：
1. **Stage 1 (Booth+PPG)** 到底有多快？是 0.9ns 还是 1.1ns？能塞进任何逻辑吗？
2. **LLCBC** 到底需要多少时间？
3. **CSA 树** 的每一级延迟是多少？

**计划执行方案**:
- **STA 挖掘**: 从现有报告中提取精确的 Stage 延迟数据。
- **探针模块 (Probe Modules)**: 编写单独的小模块（如仅包含 Booth+PPG），单独综合并 STA，排除顶层布线干扰，获取"物理极限"数据。

---

## 总结

U 系列实验表明，在 SS Corner 下，MAC16 核心逻辑的物理极限就在 ~900 MHz 左右。要突破 1GHz，必须依赖更细致的定量分析来寻找哪怕 50ps 的优化空间，或者转向后端物理优化。

