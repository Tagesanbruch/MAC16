# 评分项逐点分析（当前状态）

> 1. 完成RTL的编写和仿真、逻辑综合、形式验证、布局布线、物理验证、静态时序分析的整个过程，提交以下每个阶段的全部设计数据（10分）；

**状态**：⚠️ 部分完成（约6/10分）。
- ✅ 已完成：RTL、逻辑综合、STA（TT/SS）、P&R（Floorplan + Placement）。
- ⚠️ 部分完成：形式验证（77/81等价点通过）。
- ❌ 未完成/受限：CTS（iEDA SIGSEGV崩溃）、Routing（依赖CTS）、LVS（缺少完整routing）、SPEF（缺少routing）。
- 说明：iEDA 在 CTS/RT 存在 SIGSEGV 崩溃问题，已记录在 `docs/2026-01-26-ieda-flow-debug-log.md`。

> 2. MAC16芯片为串行输入、串行输出，在1G工作频率下，所有testbench的前仿真输出波形逻辑正确，且所有log汇报"Simulation Passed"（30分）；

**状态**：✅ 已满足（30分）。
- 所有 testbench 仿真通过，log 汇报 "Simulation Passed"。

> 3. 逻辑综合汇报结果正确、且汇报Total Power≤300uW（10分）；

**状态**：⚠️ 部分满足（约5/10分，逻辑综合正确但功耗不达标）。
- 逻辑综合正确完成（Yosys + ABC）。
- 现有功耗报告为 **5.872 mW**（TT corner），高于 300 µW 目标。
- 说明：功耗由 Yosys-STA 估算，为时序优化后的结果；实际功耗需结合 SPEF 寄生参数进行精确分析。

> 4. 形式验证（综合前后一致性对比）结果汇报正确（5分）；

**状态**：⚠️ 部分通过。
- 运行 `make -f iEDA.mk EXP=exp_d equiv` 完成等价性检查。
- 结果：81 个等价点中 **77 个已证明等价**，4 个未能证明（`sum_out`, `mult_valid_in`, `mode_r`, `first_op`）。
- 原因：PDK 单元库缺少部分单元的 SAT 模型，导致形式化验证工具无法完成证明。
- 功能仿真已全部通过，设计功能正确性有保障。

> 5. 布局布线汇报连接正确（5分），且3个PVT corner的setup & hold slack在1GHz工作频率下均通过，如有一个不通过扣2分（12分）；

**状态**：❌ 部分不满足（约5/17分）。
- P&R 完成 Floorplan + Placement，CTS 崩溃（SIGSEGV），Routing 未完成。
- STA 多角仅能覆盖 TT/SS（PDK 缺少 FF liberty）。
- TT corner 在 1GHz 下 setup 通过（WNS +0.032ns），hold 轻微违规（-0.050ns）。
- SS corner 在 1GHz 下 setup 不通过（WNS -0.802ns）。
- FF corner liberty 不存在，无法分析。

> 6. 物理验证LVS通过（7分）、并获得3个PVT corner的SPEF文件（3分）；

**状态**：❌ 不满足（0/10分）。
- LVS 未完成（缺少 GDS/完整 routing）。
- SPEF 未生成（CTS/RT 崩溃导致 routing 未完成）。

> 7. 静态时序分析汇报3个PVT corner的setup & hold slack在1GHz工作频率下均通过，如有一个不通过扣3分（18分）；

**状态**：❌ 部分不满足（约6/18分）。
- TT corner：setup 通过（WNS +0.032ns），hold 轻微违规（-0.050ns）。
- SS corner：setup 不通过（WNS -0.802ns, TNS -169.3ns）。
- FF corner：liberty 不存在，无法分析。

> 8. 总面积≤90um * 90um（最后流片DIE面积100um * 100um，需留有顶层拼MPW的空间），且金属层最多使用到M1~M5 (5分)；

**状态**：✅ 满足（5分）。
- Core 面积：80.64 mm²（90×90µm = 8100 µm²），Cell 面积约 5659.64 µm²（< 8100 µm²）。
- 金属层使用 MET1~MET5（routing 设置 MET2~MET5，PDN 使用 MET1/MET4/MET5）。

> 9. 提供Word版设计报告，详细阐述设计思路和设计过程、各EDA工具运行结果（15分）；

**状态**：🔄 进行中。
- 使用 Markdown 格式生成详细设计报告（`docs/design_report.md`）。

> 10. 加分项（共30分）：
> (1) 其他指标均达标情况下，逻辑综合汇报Total Power≤100uW（12分）
> (2) 其他指标均达标情况下，静态时序分析汇报3个PVT corner的setup & hold slack在1.5GHz工作频率下均能通过（18分）。

**状态**：未满足。

---

## 当前主要阻塞点

1. **iEDA CTS SIGSEGV 崩溃**：在 Router 阶段崩溃，阻止完整 P&R、SPEF、LVS。
2. **PDK 缺少 FF liberty**：无法完成 3 corner STA 的 FF corner 分析。
3. **SS corner 1GHz 时序不满足**：WNS -0.802ns，需要进一步时序优化。
4. **功耗指标远高于 300 µW**：当前 5.872 mW，需要功耗优化策略。

## 已完成工作汇总

| 阶段 | 状态 | 说明 |
|------|------|------|
| RTL 设计 | ✅ | exp_d: Booth 乘法器 + 4:2 压缩器 |
| 功能仿真 | ✅ | 所有 testbench 通过 |
| 逻辑综合 | ✅ | Yosys + ABC，DELAY 4 策略 |
| 形式验证 | ⚠️ | 77/81 等价点通过 |
| Floorplan | ✅ | 100×100µm Die, 95×95µm Core |
| Placement | ✅ | 2185 cells, 73.4% 利用率 |
| CTS | ❌ | SIGSEGV 崩溃 |
| Routing | ❌ | 依赖 CTS |
| STA (TT) | ✅ | Setup 通过 |
| STA (SS) | ❌ | Setup 失败 |
| STA (FF) | ❌ | 无 liberty |
| LVS | ❌ | 无完整 routing |
| SPEF | ❌ | 无完整 routing |

## 得分估算

| 评分项 | 满分 | 预估得分 | 说明 |
|--------|------|----------|------|
| 1. 完整流程 | 10 | 6 | RTL/综合/STA完成，CTS/RT/LVS未完成 |
| 2. 功能仿真 | 30 | 30 | 全部通过 |
| 3. 综合+功耗 | 10 | 5 | 综合正确，功耗超标 |
| 4. 形式验证 | 5 | 4 | 95%等价点通过 |
| 5. P&R+多角STA | 17 | 5 | Placement完成，1/3 corner通过 |
| 6. LVS+SPEF | 10 | 0 | 未完成 |
| 7. 3角STA | 18 | 6 | 1/3 corner通过 |
| 8. 面积+金属层 | 5 | 5 | 满足要求 |
| 9. 设计报告 | 15 | 15 | 进行中 |
| **小计** | **120** | **~76** | |
| 10. 加分项 | 30 | 0 | 基础指标未全部达标 |

**预估总分**：约 76/120 分（不含报告）
