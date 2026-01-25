# MAC16 Architecture Experiments

本文档记录了MAC16高性能优化的各个实验版本。

## 实验目录结构

```
rtl/
├── experiments/
│   ├── exp_baseline/     # 基准版本：行为级乘法 + 2级流水线
│   ├── exp_a/            # 实验A：3级流水线 + 操作数隔离
│   └── exp_b/            # 实验B：Radix-4 Booth + 4:2压缩器 + 3级流水线
```

## 使用方法

```bash
# 列出所有可用实验
make -f iEDA.mk list_exp

# 对特定实验运行验证
make -f iEDA.mk EXP=exp_baseline verif
make -f iEDA.mk EXP=exp_a verif
make -f iEDA.mk EXP=exp_b verif

# 对特定实验运行综合
make -f iEDA.mk EXP=exp_b yosys

# 对特定实验运行STA
make -f iEDA.mk EXP=exp_b sta

# 完整流程（验证->综合->STA）
make -f iEDA.mk EXP=exp_b exp_flow

# 对比所有实验结果
make -f iEDA.mk compare
```

---

## 实验详情

### exp_baseline - 基准版本

**文件**:
- `mac16.sv` - 顶层MAC控制逻辑
- `mult16_pipeline.sv` - 2级流水线行为级乘法器

**架构特点**:
- 使用 `*` 算符的行为级乘法
- 2级流水线（输入锁存 -> 乘法+输出）
- 标准状态机控制

**预期性能**: ~700MHz (WNS约-0.4ns)

**用途**: 建立性能基线，对比优化效果

---

### exp_a - 3级流水线版本

**文件**:
- `mac16.sv` - 带操作数隔离的顶层MAC
- `mult16_pipeline_3stage.sv` - 3级流水线乘法器

**架构特点**:
1. **3级流水线乘法器**:
   - Stage 1: 输入寄存器
   - Stage 2: 4个8x8乘法（部分积生成）
   - Stage 3: 部分积合并

2. **操作数隔离**:
   - 在非计算周期强制输入为0
   - 减少乘法器内部无效翻转
   - 降低动态功耗

**关键代码**:
```systemverilog
// 操作数隔离控制
assign mult_enable = (state == S_MULT_STAGE1) || ...;

// 隔离逻辑
.a(mult_enable ? shift_a : 16'd0),
.b(mult_enable ? shift_b : 16'd0),
```

**预期性能**: ~850-950MHz

---

### exp_b - Radix-4 Booth编码版本

**文件**:
- `mac16.sv` - 带操作数隔离的顶层MAC
- `mult16_booth.sv` - Radix-4 Booth乘法器 + 4:2压缩器

**架构特点**:

1. **Radix-4 Modified Booth Encoding**:
   - 将16个部分积减少到8个
   - 编码规则:
     | Booth Bits | 操作 |
     |------------|------|
     | 000, 111   | 0    |
     | 001, 010   | +1M  |
     | 011        | +2M  |
     | 100        | -2M  |
     | 101, 110   | -1M  |

2. **4:2压缩器Wallace树**:
   - 第一级: 8个PP -> 4个（2组4:2压缩器）
   - 第二级: 4个 -> 2个（1组4:2压缩器）
   - 关键优化: `cout`不依赖`cin`，打断进位链

3. **3级流水线**:
   - Stage 1: Booth编码 + PP生成
   - Stage 2: 压缩树
   - Stage 3: 最终CPA加法

**关键代码**:
```systemverilog
// 4:2压缩器核心逻辑 - cout不依赖cin
assign cout = xor_0123 ? cin : in3;  // 关键优化!
assign carry = xor_01 ? in2 : in0;
```

**预期性能**: 1GHz+

**功耗优势**:
- Booth编码减少PP数量，降低压缩树规模
- 4:2压缩器比传统FA级联更规则，走线更短
- 操作数隔离进一步降低动态功耗

---

## 性能对比表 (55nm @ 1GHz目标)

| 实验 | WNS | 实际频率 | 面积 (µm²) | 时序裕度 | 特点 |
|------|-----|----------|-----------|---------|------|
| exp_baseline | -0.434ns | 697 MHz | 4800 | -43.4% | 行为级乘法, 2级流水线 |
| exp_a | -0.216ns | 822 MHz | 5526 | -21.6% | 3级流水线+操作数隔离 |
| exp_b | -0.179ns | 848 MHz | 5598 | -17.9% | 3级流水线+优化分解 |
| **exp_c** | **-0.103ns** | **907 MHz** | 5820 | **-10.3%** | **4级流水线+深度优化** |

**结论**:
- 从baseline到exp_c: 频率提升 **30%** (697→907 MHz)
- 4级流水线设计(exp_c)接近1GHz目标，仅差约100ps
- 面积增加约21% (4800→5820 µm²), 主要是流水线寄存器增加

---

### exp_c - 4级深度流水线版本 (最佳性能)

**文件**:
- `mac16.sv` - 带4级流水线状态机的顶层MAC
- `mult16_4stage.sv` - 4级流水线乘法器

**架构特点**:

1. **4级深度流水线**:
   - Stage 1: 输入寄存器 + 操作数拆分
   - Stage 2: 4个8x8乘法（关键路径）
   - Stage 3: Carry-save组合
   - Stage 4: 最终加法

2. **关键优化**:
   - 将8x8乘法与部分积组合分离到不同流水线级
   - 每级组合逻辑深度均衡，约15-20级门
   - 操作数隔离继续生效

**预期性能**: **907 MHz** (WNS = -0.103ns)

---

## 下一步优化方向

### 冲击1.5GHz
1. **更深的流水线**: 将压缩树拆分为更多级
2. **Retiming**: 让综合工具自动平衡级间延迟
3. **Carry-Save累加器**: 累加结果保持冗余形式

### 功耗优化
1. **时钟门控**: 在移位输入期间关闭MAC核心时钟
2. **MBFF (Multi-Bit Flip-Flop)**: 合并触发器降低时钟网络功耗
3. **HVT替换**: 非关键路径使用高阈值电压单元

---

## 参考文献

1. Radix-4 Booth Encoding: Gemini报告 Ref[1]
2. 4:2 Compressor Architecture: Gemini报告 Ref[5,6]
3. Operand Isolation: Miromind报告 Ref[8]
4. Double Carry-Save MAC: Miromind报告 Ref[5,6]
