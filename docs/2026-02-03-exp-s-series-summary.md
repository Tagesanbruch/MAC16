# 2026-02-03 实验 S 系列（sa/sb/sc/sd）综合与时序总结

## 1. 结果概览（iSTA max，1.0ns 约束）

数据来源：各实验的 STA 报告。

| 实验 | 关键端点（WNS） | Path Delay | Path Required | Slack | Freq (MHz) | 结论 |
| --- | --- | --- | --- | --- | --- | --- |
| exp_sa | `sum_out_reg_p:D` | 1.162 | 0.890 | -0.272 | 786.068 | 不满足 1GHz |
| exp_sb | `u_mult.pp5_s2_24__reg_p:D` | 1.150 | 0.876 | -0.274 | 785.142 | 不满足 1GHz |
| exp_sc | `out_shift_reg_21__reg_p:D` | 1.034 | 0.876 | -0.158 | 863.772 | 不满足 1GHz |
| exp_sd | `mult_result_sum_14__reg_p:D` | 0.996 | 0.889 | -0.108 | 902.858 | **当前最优（仍未达 1GHz）** |

- exp_sa 参考：[mac16_2026-02-02T16_54_10.rpt](syn/yosys-syn-exp_sa-2026-02-03_00-53-53/mac16-1000MHz_sta_2026-02-02T16_54_10/mac16_2026-02-02T16_54_10.rpt#L4-L16)
- exp_sb 参考：[mac16_2026-02-02T16_54_42.rpt](syn/yosys-syn-exp_sb-2026-02-03_00-54-24/mac16-1000MHz_sta_2026-02-02T16_54_42/mac16_2026-02-02T16_54_42.rpt#L4-L16)
- exp_sc 参考：[mac16_2026-02-02T16_55_20.rpt](syn/yosys-syn-exp_sc-2026-02-03_00-55-02/mac16-1000MHz_sta_2026-02-02T16_55_20/mac16_2026-02-02T16_55_20.rpt#L4-L16)
- exp_sd 参考：[mac16_2026-02-02T16_58_54.rpt](syn/yosys-syn-exp_sd-2026-02-03_00-58-26/mac16-1000MHz_sta_2026-02-02T16_58_54/mac16_2026-02-02T16_58_54.rpt#L4-L16)

> 注：当前报告中未发现 1644 MHz 的 TT 频率记录；exp_sd 仅在 STA 表中显示 902.858 MHz。

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

### 3.2 Fanout

- `rst_n` fanout=627（远超 20），为全局瓶颈。
- `valid_s1/s2` 相关 ECK 的 fanout=175/121。
- 参考：
  - [mac16_2026-02-02T16_58_54.fanout](syn/yosys-syn-exp_sd-2026-02-03_00-58-26/mac16-1000MHz_sta_2026-02-02T16_58_54/mac16_2026-02-02T16_58_54.fanout#L1-L12)

### 3.3 Transition (Slew)

- 输出移位寄存器链 (`out_shift_reg_20/21/17`) 与 `carry_reg` 相关门级出现严重 slew 违规。
- 参考：
  - [mac16_2026-02-02T16_58_54.trans](syn/yosys-syn-exp_sd-2026-02-03_00-58-26/mac16-1000MHz_sta_2026-02-02T16_58_54/mac16_2026-02-02T16_58_54.trans#L1-L14)

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

---

## 5. 结论

- exp_sd 是 sa/sb/sc/sd 中最接近 1GHz 的实现，但仍有 -0.108ns 余量缺口。
- 关键路径集中在**S3 压缩链与 LLCBC comp42 的 XOR/XNOR 组合深度**；同时存在显著的时钟门控 ECK 超载、`rst_n` fanout 超标以及输出移位链 Slew 违规。
- 优先修正**压缩链深度**与**高扇出/大电容控制网**，可望进一步接近 1GHz。
