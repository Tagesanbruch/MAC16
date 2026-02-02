# 2026-02-03 实验 S 系列（sa/sb/sc/sd）综合与时序总结

## 1. 结果概览（iSTA max，1.0ns 约束）

数据来源：各实验的 STA 报告。

| 实验   | 关键端点（WNS）                 | Path Delay | Path Required | Slack  | Freq (MHz) | 结论                              |
| ------ | ------------------------------- | ---------- | ------------- | ------ | ---------- | --------------------------------- |
| exp_sa | `sum_out_reg_p:D`             | 1.162      | 0.890         | -0.272 | 786.068    | 不满足 1GHz                       |
| exp_sb | `u_mult.pp5_s2_24__reg_p:D`   | 1.150      | 0.876         | -0.274 | 785.142    | 不满足 1GHz                       |
| exp_sc | `out_shift_reg_21__reg_p:D`   | 1.034      | 0.876         | -0.158 | 863.772    | 不满足 1GHz                       |
| exp_sd | `mult_result_sum_14__reg_p:D` | 0.996      | 0.889         | -0.108 | 902.858    | **当前最优（仍未达 1GHz）** |
| exp_se | `sum_out_reg_p:D`             | 1.029      | 0.887         | -0.143 | 875.247    | 低于 sd                           |
| exp_sf | `sum_out_reg_p:D`             | 1.100      | 0.881         | -0.219 | 820.419    | 低于 sd                           |
| exp_sg | `out_shift_reg_20__reg_p:D`   | 1.047      | 0.889         | -0.158 | 863.838    | 低于 sd                           |

- exp_sa 参考：[mac16_2026-02-02T16_54_10.rpt](syn/yosys-syn-exp_sa-2026-02-03_00-53-53/mac16-1000MHz_sta_2026-02-02T16_54_10/mac16_2026-02-02T16_54_10.rpt#L4-L16)
- exp_sb 参考：[mac16_2026-02-02T16_54_42.rpt](syn/yosys-syn-exp_sb-2026-02-03_00-54-24/mac16-1000MHz_sta_2026-02-02T16_54_42/mac16_2026-02-02T16_54_42.rpt#L4-L16)
- exp_sc 参考：[mac16_2026-02-02T16_55_20.rpt](syn/yosys-syn-exp_sc-2026-02-03_00-55-02/mac16-1000MHz_sta_2026-02-02T16_55_20/mac16_2026-02-02T16_55_20.rpt#L4-L16)
- exp_sd（慢角/严格约束）参考：[mac16_2026-02-02T16_58_54.rpt](syn/yosys-syn-exp_sd-2026-02-03_00-58-26/mac16-1000MHz_sta_2026-02-02T16_58_54/mac16_2026-02-02T16_58_54.rpt#L4-L16)
- exp_sd（快速角/宽裕约束）参考：[mac16_2026-02-02T16_58_49.rpt](syn/yosys-syn-exp_sd-2026-02-03_00-58-26/mac16-1000MHz_sta_2026-02-02T16_58_49/mac16_2026-02-02T16_58_49.rpt#L4-L13)
- exp_se 参考：[mac16_2026-02-02T17_11_39.rpt](syn/yosys-syn-exp_se-2026-02-03_01-11-13/mac16-1000MHz_sta_2026-02-02T17_11_39/mac16_2026-02-02T17_11_39.rpt#L4-L16)
- exp_sf 参考：[mac16_2026-02-02T17_12_44.rpt](syn/yosys-syn-exp_sf-2026-02-03_01-12-18/mac16-1000MHz_sta_2026-02-02T17_12_44/mac16_2026-02-02T17_12_44.rpt#L4-L16)
- exp_sg 参考：[mac16_2026-02-02T17_13_28.rpt](syn/yosys-syn-exp_sg-2026-02-03_01-13-02/mac16-1000MHz_sta_2026-02-02T17_13_28/mac16_2026-02-02T17_13_28.rpt#L4-L16)

> 注：exp_sd 在 16_58_49 的 STA 中显示 **1644.118 MHz**（正 slack），但在 16_58_54 的 STA 中显示 **902.858 MHz**（负 slack）。两者应为不同角/约束或模型设置导致的差异，需要以赛题目标角为准。

---

## 2. exp_sd 关键时序路径（Max）

### 2.1 关键路径摘要

- 端点：`mult_result_sum_14__reg_p:D`
- Path Delay：0.996ns
- Slack：-0.108ns
- 涉及结构：S3 级 Row 压缩 + LLCBC 4:2 压缩器链
- 参考路径展开：
  - [mac16_2026-02-02T16_58_54.rpt](syn/yosys-syn-exp_sd-2026-02-03_00-58-26/mac16-1000MHz_sta_2026-02-02T16_58_54/mac16_2026-02-02T16_58_54.rpt#L4-L75)

路径中出现连续 XOR/XNOR + 压缩器组合逻辑：

- `u_mult.row2_s3_14__reg_p:Q` → `row1_s3_14` → `row3_s3_14` → `u_mult.u_llcbc.u_comp42.comp_gen[14]` → `mult_result_sum_14__reg_p:D`
- 表征为 **XOR/XNOR 链 + LLCBC comp42** 组合逻辑密度过高。

### 2.2 wire_path 观察（局部）

`wire_path_3.json` 展示了 PPG/对齐信号在 S2 末端的复杂门级链：

- 起点 `u_mult.a_s1_0__reg_p:Q` 经 `BUFX7` → `NOR4X6` → 多级 AOI/OAI/NAND/NOR 逻辑后到 `pp2_s2_10__reg_p:D`
- 局部扇出与中间节点电容偏高，造成组合延迟累积
- 参考：[wire_path_3.json](syn/yosys-syn-exp_sd-2026-02-03_00-58-26/mac16-1000MHz/wire_paths/wire_path_3.json#L1-L120)

---

## 3. Cap/Fanout/Transition 违规（exp_sd）

### 3.1 Capacitance

- 多个 ICG `ECK` 节点超标（`valid_s1/s2` 与 `mult_input_valid`），最大超限约 0.145–0.146。
- 参考：
  - [mac16_2026-02-02T16_58_54.cap](syn/yosys-syn-exp_sd-2026-02-03_00-58-26/mac16-1000MHz_sta_2026-02-02T16_58_54/mac16_2026-02-02T16_58_54.cap#L1-L12)
  - [mac16_2026-02-02T16_58_49.cap](syn/yosys-syn-exp_sd-2026-02-03_00-58-26/mac16-1000MHz_sta_2026-02-02T16_58_49/mac16_2026-02-02T16_58_49.cap#L1-L12)

### 3.2 Fanout

- `rst_n` fanout=627（远超 20），为全局瓶颈。
- `valid_s1/s2` 相关 ECK 的 fanout=175/121。
- 参考：
  - [mac16_2026-02-02T16_58_54.fanout](syn/yosys-syn-exp_sd-2026-02-03_00-58-26/mac16-1000MHz_sta_2026-02-02T16_58_54/mac16_2026-02-02T16_58_54.fanout#L1-L12)
  - [mac16_2026-02-02T16_58_49.fanout](syn/yosys-syn-exp_sd-2026-02-03_00-58-26/mac16-1000MHz_sta_2026-02-02T16_58_49/mac16_2026-02-02T16_58_49.fanout#L1-L12)

### 3.3 Transition (Slew)

- 输出移位寄存器链 (`out_shift_reg_20/21/17`) 与 `carry_reg` 相关门级出现严重 slew 违规。
- 参考：
  - [mac16_2026-02-02T16_58_54.trans](syn/yosys-syn-exp_sd-2026-02-03_00-58-26/mac16-1000MHz_sta_2026-02-02T16_58_54/mac16_2026-02-02T16_58_54.trans#L1-L14)
  - [mac16_2026-02-02T16_58_49.trans](syn/yosys-syn-exp_sd-2026-02-03_00-58-26/mac16-1000MHz_sta_2026-02-02T16_58_49/mac16_2026-02-02T16_58_49.trans#L1-L10)

---

## 4. 可优化方向（优先级从高到低）

### 4.1 压缩树/LLCBC 逻辑密度

- **拆分 `row*_s3_14` → `comp42` 的组合链**，在 comp42 前增加寄存或局部 retime。
- 对 `comp_gen[14]` 等关键位插入缓冲或复用更强驱动的 XOR/XNOR 单元。

### 4.2 PPG 对齐链（S2）

- 对 `a_s1_0` 等高扇出输入做**分裂缓冲树**，降低 BUFX 之后的净载。
- 将多级 AOI/OAI 串联进行逻辑拆分（减少门级深度）。

### 4.3 时钟/复位与 valid 网

- `rst_n` 需**树状缓冲**或按层级分组复位，避免 600+ fanout。
- `valid_s1/s2` 的 ECK 负载过大，建议：
  - 增加中继缓冲或拆分为多路 valid 域；
  - 减少每级 valid 的扇出；
  - 如允许，可取消部分细粒度 ICG，仅保留关键级门控。

### 4.4 输出移位链的 Slew 违规

- 输出链 OAI/NAND 组合过深，建议在 `out_shift_reg_*` 前**插入级间缓冲**，或将长链逻辑拆成两拍。

### 4.5 exp_sd 与前序思路的可融合方向

- **与 exp_nc 的“PPG 单独成级”思路融合**：保持 exp_sd 的 LLCBC 压缩结构，但进一步强化 S2 仅做 PPG/对齐、S3 专注多层压缩的分层，避免 PPG 对齐链与压缩树在同级堆叠。
- **与 exp_rd/re/rf 的 PPG 分裂尝试融合**：exp_sf 已切分 PPG/对齐，但可将 exp_sd 的 LLCBC 放在后级，尝试把对齐/移位逻辑从关键位（如 bit[14]）剥离到前一拍，减少关键位 XOR/XNOR 链深度。
- **与 exp_ng 的 VMA/前缀网络优化融合**：保留 exp_sd 的压缩树结构，VMA 选择 Han‑Carlson/Spanning Tree 变体并严格控制扇出（减小 `rst_n/valid` 控制网负载），重点削减输出移位链的 slews。
- **与“取消细粒度门控”思路融合**：借鉴 exp_sg 的 always‑sample 方案，弱化 ECK 负载，减少控制网电容与时钟门控引入的附加路径延迟。

---

## 5. 功能验证结果（新 tb_mac16）

使用更新后的 [verif/tb_mac16.sv](verif/tb_mac16.sv)（采样点加微延迟、`gap=0` 以避免无 `input_valid` 接口下的位流错位）对 S 系列抽查验证：

- exp_sd：**PASS**（功能/延迟/空闲/窗口/carry 全通过）。
  - 参考：[build/sim-exp_sd.log](build/sim-exp_sd.log#L1-L20)
- exp_sg：**PASS**。
  - 参考：[build/sim-exp_sg.log](build/sim-exp_sg.log#L1-L20)

> 说明：此前失败主要来自**采样对齐与输入 gap 造成的位流错位**；修正 TB 采样点与 gap 后，sd/sg 已恢复通过。其余实验尚未在此轮 TB 规则下全面回归。

---

## 6. 新实验计划（sh/si/sj）

- **exp_sh**（方向 4.5-1）：保留 exp_sd 的 LLCBC 压缩，但在 Stage3 采用 exp_nc 式“反馈合并”结构，Stage4 通过 LLCBC（补零行）压缩 5→2。
- **exp_si**（方向 4.5-2）：基于 exp_sf 的 PPG 拆分（Stage2a/2b），其余结构保持 exp_sd（LLCBC 6→2）。
- **exp_sj**（方向 4.5-3）：在 exp_sd 基础上替换 VMA 前缀网络为 **Kogge‑Stone**，用于评估前缀拓扑对时序/布线的影响。

以上 3 个实验已建立 RTL（目录：rtl/experiments/exp_sh、exp_si、exp_sj），待后续跑 verif/yosys/sta。

## 7. 结论

- exp_sd 仍是 S 系列最接近 1GHz 的实现，但仍有 -0.108ns 余量缺口。
- exp_se/sf/sg 未优于 exp_sd，说明当前改动尚未改善关键路径或引入了新的路径开销。
- TB 采样/间隔修正后，sd/sg 的功能验证已恢复通过，说明此前问题主要为**位流对齐**而非功能错误。
- 关键路径集中在**S3 压缩链与 LLCBC comp42 的 XOR/XNOR 组合深度**；同时存在显著的时钟门控 ECK 超载、`rst_n` fanout 超标以及输出移位链 Slew 违规。
- 优先修正**压缩链深度**与**高扇出/大电容控制网**，可望进一步接近 1GHz。
