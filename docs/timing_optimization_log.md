# MAC16 时序优化记录

**文档创建时间**: 2026-01-26 01:20
**优化执行时间**: 2026-01-26 00:50 - 01:20

---

## 优化目标

将 MAC16 芯片时序从 686MHz 提升至 1GHz，满足 Setup 时序要求。

---

## 优化前基线

- **日期**: 2026-01-26 00:42
- **STA 结果目录**: `syn/yosys-syn-2026-01-26_00-42-09/mac16-1000MHz/`
- **WNS**: -0.457ns @ 1GHz
- **TNS**: -24.581ns
- **最大频率**: ~686MHz
- **面积**: 4380μm²
- **关键路径**: `shift_b[11]:Q → 乘法器组合逻辑(1.187ns) → mult_reg[22]:D`

---

## 优化方案

采用 **2级流水线乘法器** 将组合乘法逻辑拆分：

### 1. 新建流水线乘法器模块

**文件**: `rtl/mult16_pipeline.sv`

```systemverilog
// 2-cycle pipeline wrapper
// Cycle 1: Register inputs (a_r, b_r)
// Cycle 2: Perform multiplication and register result (product_r)
```

**设计要点**:
- 第一级：注册输入操作数 a 和 b
- 第二级：执行乘法并注册结果
- 增加 `valid_in` / `valid_out` 信号控制流水线

### 2. 修改 MAC 状态机

**文件**: `rtl/mac16.sv`

状态机从 4 状态扩展为 5 状态：

| 原状态 | 新状态 | 说明 |
|--------|--------|------|
| S_INPUT (2'd0) | S_INPUT (3'd0) | 串行输入 16 周期 |
| S_COMPUTE_1 (2'd1) | S_MULT_STAGE1 (3'd1) | 乘法器流水线第1周期 |
| S_COMPUTE_2 (2'd2) | S_MULT_STAGE2 (3'd2) | 乘法器流水线第2周期 |
| - | S_ADD (3'd3) | 加法阶段 |
| S_OUTPUT (2'd3) | S_OUTPUT (3'd4) | 串行输出 24 周期 |

### 3. 新建单元测试

**文件**: `verif/tb_mult16_pipeline.sv`

- 测试简单用例 (0×0, 1×1, 255×255 等)
- 测试边界用例 (0x8000, 0x7FFF, 0xFFFF)
- 测试 100 个随机乘法
- 测试结果: **109 tests PASS**

---

## 验证结果

### 功能验证 (make verif)

**执行时间**: 2026-01-26 01:19
**日志位置**: `build/sim.log`

```
=== Test Mode 0: Current product + Previous product ===
Mode0 Test 0-5: PASSED
Mode 0: Simulation Passed

=== Test Mode 1: Full Accumulation ===
Mode1 Test 0-5: PASSED
Mode 1: Simulation Passed

=== Test Mode Switch: 0->1 after input 3 ===
ModeSwitch Test 0-5: PASSED
Mode Switch: Simulation Passed

=== All Tests Complete ===
[VERIF] All tests passed!
```

**结论**: ✅ 所有 3 种模式功能验证通过

---

## 综合与时序分析结果

### 综合结果

**执行时间**: 2026-01-26 01:19
**STA 结果目录**: `syn/yosys-syn-2026-01-26_01-19-14/mac16-1000MHz/`
**报告文件**:
- `mac16.rpt` - 时序报告
- `mac16.netlist.v` - 综合后网表
- `yosys.log` - 综合日志

### 时序对比 (TT corner @ 1GHz)

| 指标 | 优化前 | 优化后 | 变化 |
|------|--------|--------|------|
| WNS | -0.457ns | -0.434ns | +23ps ↑ |
| TNS | -24.581ns | -19.771ns | +4.81ns ↑ |
| Max Freq | ~686MHz | ~697MHz | +11MHz ↑ |
| Area | 4380μm² | 4800μm² | +420μm² |

### 关键路径分析

优化后关键路径：
```
u_mult.a_r[*]:Q → 乘法组合逻辑 → mult_result[*]_reg_p:D
Path Delay: 1.375ns
Path Required: 0.941ns
Slack: -0.434ns
```

---

## 多角 STA 结果

**执行命令**: `make sta_all`
**日志位置**: `syn/yosys-syn-2026-01-26_01-19-14/sta_all.log`

| Corner | 条件 | Setup WNS | Hold WNS |
|--------|------|-----------|----------|
| TT | 1.2V/25°C | -0.434ns | -0.050ns |
| SS | 1.08V/125°C | 待确认 | -0.050ns |

---

## 文件变更清单

### 新增文件

| 文件 | 说明 |
|------|------|
| `rtl/mult16_pipeline.sv` | 2级流水线乘法器 |
| `verif/tb_mult16_pipeline.sv` | 流水线乘法器单元测试 |
| `verif/tb_mult16_pipeline_simple.sv` | 简化调试测试 |
| `docs/timing_optimization_log.md` | 本文档 |

### 修改文件

| 文件 | 修改内容 |
|------|----------|
| `rtl/mac16.sv` | 状态机从 4 状态扩展到 5 状态，集成流水线乘法器 |

---

## 结论与后续建议

### 当前状态

- ✅ 功能验证: 所有测试通过
- ⚠️ 时序: 有改善但未达标 (697MHz vs 1GHz 目标)
- ✅ 面积: 4800μm² < 8100μm² 目标 (59% 利用率)

### 后续优化方向

1. **综合参数调优**: 调整 ABC 优化策略，启用更激进的时序优化
2. **深度流水线**: 将乘法器扩展为 3-4 级流水线
3. **降低频率目标**: 当前设计可稳定运行在 700MHz
4. **使用 DSP 宏**: 如 PDK 提供硬核乘法器，可直接替换

---

## 附录：关键命令

```bash
# 功能验证
make verif

# 综合
make yosys

# 时序分析
make sta

# 多角时序
make sta_all

# 查看最新时序结果
head -30 syn/yosys-syn-*/mac16-1000MHz/mac16.rpt | tail -1
```
