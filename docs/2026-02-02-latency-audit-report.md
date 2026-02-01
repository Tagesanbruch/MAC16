# MAC16 延迟约束审计报告

**日期**: 2026-02-02  
**约束来源**: Plan.md 第23行  
**约束要求**: "从输入串行数据完全采样完、至开始输出串行数据的时间差不超过**5个clk周期**"

## 测试方法

使用 `make -f iEDA.mk EXP=<exp> latency_check` 运行专用测试台 `verif/tb_latency_check.sv`，测量从输入完成到 `out_ready` 置高的时钟周期数。

---

## 审计结果汇总

| 实验 | 延迟(周期) | 结果 | 备注 |
|------|-----------|------|------|
| exp_a | 4 | ✅ PASS | |
| exp_b | 4 | ✅ PASS | |
| exp_baseline | 3 | ✅ PASS | 基础移位寄存器方案 |
| exp_c | 5 | ✅ PASS | 刚好满足约束 |
| exp_d | 4 | ✅ PASS | |
| exp_e | 2 | ✅ PASS | |
| exp_f | 3 | ✅ PASS | |
| exp_g | 3 | ✅ PASS | |
| exp_h | 4 | ✅ PASS | |
| exp_i | 4 | ✅ PASS | |
| exp_j | 16 | ❌ FAIL | 超标11周期 |
| **exp_k** | 6 | ❌ FAIL | 5级Booth乘法器，超标1周期 |
| exp_l | 7 | ❌ FAIL | 6级流水线，超标2周期 |
| exp_m | 9 | ❌ FAIL | 带SM编码，超标4周期 |
| **exp_n** | **4** | ✅ **PASS** | **DCS 5级流水，满足约束** |
| **exp_o** | 7 | ❌ FAIL | 7级超深流水，超标2周期 |
| exp_p | 8 | ❌ FAIL | 基于exp_o，超标3周期 |
| exp_q | 8 | ❌ FAIL | 8级VMA隔离，超标3周期 |

---

## 关键发现

### 1. 满足约束的高频实验

| 实验 | 延迟 | TT频率 | SS频率(估) | 状态 |
|------|------|--------|-----------|------|
| exp_n | 4 cycles | 1270 MHz | 691 MHz | ✅ **推荐基准** |
| exp_d | 4 cycles | 1175 MHz | ~640 MHz | ✅ |
| exp_c | 5 cycles | ~1100 MHz | ~600 MHz | ✅ 边界 |

### 2. 违规实验分析

**exp_k/l/m/o/p/q 均违反延迟约束**，虽然部分达到了更高的 TT 频率（如 exp_o 达到 1624 MHz），但因超出5周期延迟限制而**不符合赛题要求**。

### 3. 问题根源

深流水线架构（6-8级）虽然提升了频率，但每增加一级流水线就增加1周期延迟。要满足5周期约束，**最多只能使用5级流水线**。

---

## 结论与建议

### 当前最佳方案: **exp_n** (DCS 5级流水)

- ✅ 延迟: 4 cycles (满足 ≤5 约束)
- ✅ TT频率: 1270 MHz
- ⚠️ SS频率: ~691 MHz (未达1GHz目标)

### 后续优化方向

要在满足5周期延迟约束的前提下达到1GHz SS目标，需要：

1. **保持5级或更少的流水线级数**
2. **优化每级的组合逻辑深度**（使用MUX压缩器、优化PPG等）
3. **在exp_n基础上进行物理级优化**

---

## 命令参考

```bash
# 检查单个实验
make -f iEDA.mk EXP=exp_n latency_check

# 批量检查所有实验
for exp in exp_{a..q}; do make -f iEDA.mk EXP=$exp latency_check 2>&1 | grep LATENCY; done
```
