# Exp G 综合分析报告

**日期**: 2026-01-26  
**实验**: exp_g (基于 Exp D 架构 + Exp F Hot-1 注入优化)

---

## 1. 设计目标

根据用户提供的深入代码审查，Exp G 试图解决 Exp F 中的两个"致命弱点"：

1. **PPG 隐藏的加法器链**：Exp F 的 PPG 使用 `~a_sel + 1'b1` 进行取反，产生了 17-bit 的加法器链
2. **DCS 循环被旁路**：由于 `mode=0, clear=1` 硬编码，DCS 的反馈循环未被启用

### Exp G 的改进方案

| 模块 | Exp F 问题 | Exp G 修复 |
|------|-----------|-----------|
| PPG | `~a_sel + 1'b1` (17-bit 加法器) | `~a_sel` + Hot-1 单独输出 |
| Fused Core | DCS 未使用 | Hot-1 注入压缩树 |
| Wrapper | 外部 KS 加法器 | 内部使用 DCS 进行累加 |

---

## 2. 功能验证结果

```
=== Verification Results ===
✅ Test 1: Basic Multiply       - PASSED
✅ Test 2: Mode Switch          - PASSED  
✅ Test 3: Continuous MAC       - PASSED
```

所有功能测试通过，验证了 Exp G 的功能正确性。

---

## 3. 综合结果对比

### 3.1 面积对比

| 指标 | Exp D | Exp G | 变化 |
|------|-------|-------|------|
| 总面积 | 5659.64 μm² | 5740.00 μm² | **+1.4%** |
| 时序单元占比 | ~42% | 42.21% | 基本持平 |
| 标准单元数 | ~1850 | 1919 | +3.7% |
| DFF 数量 | ~300 | 307 | +2.3% |

### 3.2 时序结果 (TT Corner @ 1000 MHz)

| 指标 | Exp D | Exp G | 评估 |
|------|-------|-------|------|
| WNS | **+0.032 ns** | **-0.011 ns** | ❌ Exp G 退化 |
| 达成频率 | ~1033 MHz | ~989 MHz | -4.3% |
| 关键路径 | out_shift_reg | accum_23__reg_p | 路径变化 |
| TNS | ~0 | -0.048 ns | ❌ 违规 |

### 3.3 SS Corner 结果 (关键工艺角 @ 1000 MHz)

| 指标 | Exp G |
|------|-------|
| WNS | **-0.857 ns** |
| 达成频率 | ~538 MHz |
| 关键路径时延 | 1.734 ns |

⚠️ **SS Corner 严重违规**：距离 1 GHz 目标差距巨大

---

## 4. 关键路径分析

### Exp G 关键路径 (TT Corner)

```
mode_r_reg_p:Q → BUFX16 → MUX2X12 → XOR2X3 → MUX2X3 → OA22X3 → OA31X3 
    → AOAI211X2 → AOAI211X2 → AOI21BX6 → OAOI211X4 → OA211X3 → OR3X1P4 
    → XOR2X3 → accum_23__reg_p:D
```

**总时延**: 0.952 ns (TT corner)

### 问题分析

1. **关键路径从 `mode_r` 寄存器开始**：这是外部累加逻辑的控制信号，表明 Wrapper 层的累加 MUX 成为瓶颈

2. **路径深度约 14 级逻辑门**：比预期的更长

3. **SS Corner 放大效应**：
   - TT → SS 时延放大约 1.82x (0.952 → 1.734 ns)
   - 这表明关键路径对工艺变化敏感

---

## 5. 问题根因分析

### 5.1 设计决策的影响

由于 testbench 要求 mode 切换行为与 Exp D 兼容，我们被迫：

```verilog
// Exp G Wrapper 设计决策
// MAC core 始终运行在乘法模式 (mode=0, clear=1)
// 累加在 Wrapper 层进行
assign mac_clear = 1'b1;    // 禁用内部 DCS
assign mac_mode = 1'b0;     // 纯乘法模式
```

**结果**：
- ❌ Hot-1 注入的优化被浪费（内部 DCS 未使用）
- ❌ 外部累加需要完整的加法器 `sum_out + carry + prev_product/accum`
- ❌ 关键路径被推到 Wrapper 层的累加逻辑

### 5.2 架构矛盾

Exp G 设计目标与实际实现存在矛盾：

| 设计目标 | 实际实现 |
|---------|---------|
| 使用内部 DCS 进行累加 | 内部 DCS 被禁用 (clear=1) |
| Hot-1 注入优化 | Hot-1 参与乘法但不参与累加 |
| 移除外部加法器 | 外部仍需要加法器进行累加 |

---

## 6. 与 Exp D 的差异总结

| 特性 | Exp D | Exp G |
|------|-------|-------|
| 乘法器架构 | Radix-4 Booth + 3级流水 | Radix-4 Booth + Hot-1 + 3级流水 |
| PPG 实现 | 标准 2's complement | ~a_sel + Hot-1 注入 |
| 累加方式 | Wrapper 外部 | Wrapper 外部 (内部 DCS 未使用) |
| TT 频率 | ~1033 MHz | ~989 MHz |
| 面积 | 5659 μm² | 5740 μm² |

---

## 7. 结论与建议

### 7.1 实验结论

**Exp G 未能达成预期目标**：

1. ✅ **功能正确**：所有测试通过
2. ❌ **时序退化**：TT corner 从 +32ps → -11ps slack
3. ❌ **SS Corner 严重违规**：仅达到 538 MHz
4. ❌ **内部 DCS 未被利用**：由于兼容性要求，Hot-1 优化被浪费

### 7.2 改进建议

要真正发挥 Hot-1 注入和 DCS 架构的优势，需要：

1. **重新设计 Testbench**：允许 MAC core 内部处理累加
2. **启用内部 DCS**：设置 `clear=0` 让 DCS 循环工作
3. **简化 Wrapper**：仅做输入/输出寄存器，不做累加
4. **添加多周期约束**：如果使用门控加法器进行最终输出

### 7.3 最终评估

| 指标 | 目标 | Exp D | Exp G | 评价 |
|------|------|-------|-------|------|
| 频率 (SS) | >1 GHz | ~700 MHz* | ~538 MHz | ❌❌ |
| 频率 (TT) | >1 GHz | ~1033 MHz | ~989 MHz | ❌ |
| 面积 | 最小化 | 5659 μm² | 5740 μm² | ≈ |
| 功能 | 正确 | ✅ | ✅ | ✅ |

*注：Exp D 的 SS corner 数据需要单独运行验证

**结论**：Exp G 的架构改动方向正确，但由于 Wrapper 层的兼容性约束，Hot-1/DCS 优化未能发挥作用。建议回退到 Exp D 基线，或重新设计接口以充分利用内部 DCS 累加。

---

## 附录：文件列表

```
rtl/experiments/exp_g/
├── booth_encoder.sv      # Radix-4 Booth 编码器
├── partial_product_gen.sv # PPG (Hot-1 输出，无 +1 加法器)
├── csa.sv                # 3:2 CSA
├── compressor_4to2.sv    # 4:2 压缩器阵列
├── mac16_fused_dcs.sv    # Fused MAC Core (Hot-1 注入)
└── mac16.sv              # 顶层 Wrapper
```
