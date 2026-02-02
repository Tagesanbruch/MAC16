# MAC16 RTL 实验全量总结（rtl/experiments，排除 exp_sa4x4/exp_sa16x16）

> 结论先行：从架构正确性与约束（≤5 周期输入完成到输出开始）综合来看，**Exp N/NC/NG/R 系列**是当前最稳定、最可复用的主线；**Exp K/L/M/O/P/Q**虽主频更高，但多数已超出延迟约束；**Exp B**名义为 Booth，但 RTL 实现并未使用 Booth 编码；**Exp H/I**的“门控/隔离”主要是**有效信号使能**，并非真实时钟门控。

---

## 1. 统一功能与接口要点

- 输入：`inA`、`inB` 串行 16b（MSB 先入），每 16 个周期形成 1 组操作数。
- 输出：`sum_out` 串行 24b（MSB 先出），`out_ready` 表示输出有效窗口。
- `mode`：
  - `mode=0`：输出当前乘积与上一乘积之和。
  - `mode=1`：全累加输出。
  - `mode` 切换需清空内部状态。

### 1.1 统一数学定义（按 RTL 行为）

设每组输入得到乘积 $p_n$，输出 $y_n$：

- **Mode 0**（“当前乘积 + 上一乘积”）
  $$
  y_n = \begin{cases}
  p_n, & n=0 \\
  p_n + p_{n-1}, & n>0
  \end{cases}
  $$
- **Mode 1**（全累加）
  $$
  y_n = \sum_{i=0}^{n} p_i
  $$

进位标志 `carry` 在溢出后置 1（需要 `rst_n` 或 `clr`/模式切换清除）。

---

## 2. 算法与硬件公式（跨实验共性）

### 2.1 Radix‑4 Booth 编码

Booth 分组：$\{b_{2i+1}, b_{2i}, b_{2i-1}\}$（最低位隐含 $b_{-1}=0$）。

- 编码信号：

  $$
  neg_i = b_{2i+1}
  $$

  $$
  zero_i = (group=000) \lor (group=111)
  $$

  $$
  two_i = (group=011) \lor (group=100)
  $$
- Booth 映射（$M$ 为被乘数）：

  $$
  \{000,111\}\to 0, \quad \{001,010\}\to +M, \quad 011\to +2M, \quad 100\to -2M, \quad \{101,110\}\to -M
  $$

### 2.2 4× 8b 分解乘法（exp_a/c/b 的“结构化分解”）

将 16b 拆为高/低 8b：

$$
A = A_H\cdot2^8 + A_L,\quad B = B_H\cdot2^8 + B_L
$$

$$
A\cdot B = A_HB_H\cdot2^{16} + (A_HB_L + A_LB_H)\cdot2^8 + A_LB_L
$$

### 2.3 3:2 CSA 与 4:2 Compressor

- **CSA（3:2）**

  $$
  S = A\oplus B\oplus C
  $$

  $$
  C = AB + AC + BC
  $$
- **4:2 Compressor（实现中 cout 不依赖 cin）**
  设 $w1=A\oplus B,\; w2=C\oplus D,\; w3=w1\oplus w2$：

  $$
  cout = (w1?C:A)
  $$

  $$
  sum = w3 \oplus cin
  $$

  $$
  carry = (w3?cin:D)
  $$

### 2.4 DCS（Double Carry‑Save）累加

- 传统 MAC：

  $$
  y_{n} = y_{n-1} + p_n\quad \text{(CPA 在反馈回路)}
  $$
- DCS：维持冗余形式 $(S, C)$：

  $$
  (S', C') = \text{CSA}(S, C, p_n)
  $$

  $$
  y_n = S' + C' \quad \text{(仅在输出阶段)}
  $$

DCS 让反馈回路去除 CPA，降低关键路径深度。

---

## 3. 时序与延迟约束（来自测量日志）

- 关键约束：输入串行采样完成 → 输出开始 **≤ 5 个周期**。
- 延迟审计结果（来自 [docs/2026-02-02-latency-audit-report.md](docs/2026-02-02-latency-audit-report.md)）：
  - ✅ **满足**：exp_a/b/baseline/c/d/e/f/g/h/i/n
  - ❌ **不满足**：exp_j/k/l/m/o/p/q

> 该约束决定了深流水线实验（K/L/M/O/P/Q）即便更高主频，也无法作为最终符合赛题方案。

---

## 4. PPA/STA 摘要（来自 docs）

### 4.1 Exp D/E/F（结构 Booth & DCS 融合）

来源：[docs/2026-01-26-exp-d-e-f-results.md](docs/2026-01-26-exp-d-e-f-results.md)

| 实验  | WNS (ns) |     频率 | 面积 (µm²) | 备注                        |
| ----- | -------: | -------: | -----------: | --------------------------- |
| exp_d |   +0.032 | 1033 MHz |         5659 | 结构化 Booth + 3级流水 ✅   |
| exp_e |   -0.213 |  824 MHz |         5212 | 2级 DCS 融合，压缩树过深 ❌ |
| exp_f |   -0.005 |  995 MHz |         5740 | 3级 DCS + KS，几乎达标 ⚠️ |

### 4.2 Exp H/I/J/K

来源：[docs/2026-01-26-exp-h-i-j-k-results.md](docs/2026-01-26-exp-h-i-j-k-results.md)

| 实验  |    WNS |     频率 | 面积 | 结论                |
| ----- | -----: | -------: | ---: | ------------------- |
| exp_h | -0.067 |  937 MHz | 5692 | 操作数隔离收益有限  |
| exp_i | +0.030 | 1031 MHz | 5801 | TT 角达标 ✅        |
| exp_j | -0.147 |  872 MHz | 3290 | 串行但关键路径长    |
| exp_k | +0.133 | 1154 MHz | 6754 | 时序强但延迟超标 ❌ |

### 4.3 Exp L/M

来源：[docs/2026-02-02-exp-l-m-results.md](docs/2026-02-02-exp-l-m-results.md)

| 实验  | 频率 (TT) | 面积 (µm²) | 结论                 |
| ----- | --------: | -----------: | -------------------- |
| exp_l |  1112 MHz |         6926 | 6级流水，延迟超标 ❌ |
| exp_m |  1092 MHz |         8160 | 8级流水，延迟超标 ❌ |

### 4.4 Exp N/NA/NC/ND 来源：[docs/2026-02-02-optimization-results.md](docs/2026-02-02-optimization-results.md)

| 实验   | 频率 (TT) |  SS 频率 | 面积 | 结论                          |
| ------ | --------: | -------: | ---: | ----------------------------- |
| exp_n  |  1270 MHz | ~691 MHz | 8680 | DCS 基准 ✅                   |
| exp_na |  1276 MHz | ~691 MHz | 8076 | MUX 压缩器，面积更优          |
| exp_nc |  1432 MHz |  785 MHz | 8129 | **当前最优平衡方案** ✅ |
| exp_nd |  1175 MHz |        - | 9196 | 额外流水线导致拥塞倒退 ❌     |

### 4.5 Exp NE/NF/NG

来源：[docs/2026-02-02-exp-ne-nf-ng-report.md](docs/2026-02-02-exp-ne-nf-ng-report.md)

| 实验   |  TT 频率 | SS 频率 | 面积 | 结论                                                    |
| ------ | -------: | ------: | ---: | ------------------------------------------------------- |
| exp_ne | 1361 MHz | 729 MHz | 8156 | 冗余累加 4:2 反而拖慢 ❌                                |
| exp_nf | 1433 MHz | 785 MHz | 8129 | 与 NC 基本持平                                          |
| exp_ng | 1634 MHz | 876 MHz | 8205 | **当前最优路径，VMA 用 Han‑Carlson 提升显著** ✅ |

### 4.6 Exp R 系列

来源：[docs/2026-02-02-exp-r-series-report.md](docs/2026-02-02-exp-r-series-report.md)

| 实验            |  TT 频率 | SS 频率 | 面积 | 结论                  |
| --------------- | -------: | ------: | ---: | --------------------- |
| exp_r (基线=NG) | 1634 MHz | 876 MHz | 8205 | 当前最好 ✅           |
| exp_ra          | 1554 MHz | 838 MHz | 8199 | MUX‑CSA 倒退 ❌      |
| exp_rb          | 1456 MHz | 764 MHz | 8254 | KS VMA 反而更慢 ❌    |
| exp_rc          | 1445 MHz | 802 MHz | 8479 | Split VMA 效果不佳 ❌ |

---

## 5. 各实验 RTL 架构与“预期 vs 实际”核对

> 下文均基于 rtl/experiments 真实源码阅读。

### 5.1 exp_baseline

- **架构**：2 级流水行为乘法 (`*`) + 外部累加。
- **实现**：`mult16_pipeline.sv`（2 级：输入寄存 → 乘法寄存）。
- **一致性**：✅ 预期与 RTL 一致。

### 5.2 exp_a

- **架构**：3 级流水，8×8 分解乘法，操作数隔离。
- **实现**：`mult16_pipeline_3stage.sv` 明确 3 级：输入寄存 → 4 个 8×8 → 合并。
- **一致性**：✅ 预期与 RTL 一致。

### 5.3 exp_b（注意：命名与实现不符）

- **预期**：Booth 编码 + 4:2 压缩树 + 3 级流水。
- **实际**：`mult16_booth.sv` 仍是 **4×8b 分解乘法**，无 Booth 编码、无 4:2 compressor。
- **结论**：❗**架构名与 RTL 不一致**，实际等价于“分解乘法 3 级流水”。

### 5.4 exp_c

- **架构**：4 级深流水分解乘法。
- **实现**：`mult16_4stage.sv` 将 8×8 乘法单独成级。
- **一致性**：✅ 一致。

### 5.5 exp_d

- **架构**：结构化 Booth + Wallace/CSA + 4:2 压缩器，3 级流水。
- **实现**：`booth_encoder.sv`、`partial_product_gen.sv`、`csa.sv`、`compressor_4to2.sv`，3 级结构化压缩。
- **一致性**：✅ 一致。

### 5.6 exp_e

- **架构**：DCS 融合 MAC（2 级），外部仍做模式兼容累加。
- **实现**：`mac16_fused.sv` 为 DCS 核心，`mac16.sv` 进行外部累加。
- **一致性**：✅ 一致，但 2 级压缩树过深，性能不如预期。

### 5.7 exp_f

- **架构**：DCS + 3 级流水 + Kogge‑Stone 输出。
- **实现**：`mac16_fused_ks.sv` 中途插入压缩树寄存，`kogge_stone_adder.sv` 做输出。
- **一致性**：✅ 一致。

### 5.8 exp_g

- **架构**：真正 DCS（热 1 注入），输出 CPA 不在环路。
- **实现**：`mac16_fused_dcs.sv` 移除 PPG +1，注入 `hot1_row`。
- **一致性**：✅ 一致。

### 5.9 exp_h

- **架构**：操作数隔离 + “时钟门控”。
- **实现**：多处 `*_en` 仅用于寄存器更新使能，并未实例化时钟门控单元。
- **一致性**：⚠️ 部分一致，**更像“有效使能”而非真正 clock gating**。

### 5.10 exp_i

- **架构**：操作数隔离 + valid‑gated multiplier。
- **实现**：`mult16_booth_gated.sv` 所有流水寄存器受 `valid` 控制。
- **一致性**：✅ 一致。

### 5.11 exp_j

- **架构**：位串行乘法 + CSA 累加，面积最小。
- **实现**：`mac16.sv` 中 bit‑serial CSA，16 周期计算。
- **一致性**：✅ 一致，但延迟/时序无法达标。

### 5.12 exp_k / exp_l / exp_m

- **架构**：5/6/8 级深流水 Booth。
- **实现**：分别为 `mult16_booth_5stage.sv` / `6stage` / `8stage`。
- **一致性**：✅ 一致，但延迟超约束（见审计）。

### 5.13 exp_n

- **架构**：DCS 反馈 + VMA 输出，5 级 DCS 乘法器。
- **实现**：`mult16_booth_dcs.sv` 反馈进入 CSA 树；`mac16.sv` 输出阶段进行 VMA。
- **一致性**：✅ 一致，是关键基线。

### 5.14 exp_na

- **架构**：替换 4:2 压缩器为 MUX 版本。
- **实现**：`compressor_4to2_mux.sv` + DCS 树。
- **一致性**：✅ 一致，但性能未提升。

### 5.15 exp_nb

- **架构**：引入 `tc2sm` 模块（符号/幅度转换）。
- **实现**：`tc2sm.sv` 存在，但 **未在 mac16/mult 中使用**。
- **一致性**：⚠️ **模块存在但未被集成**。

### 5.16 exp_nc

- **架构**：流水线重定时（S2 仅 PPG，S3 叠加两层 CSA）。
- **实现**：`mult16_booth_dcs.sv` 完整体现“PPG‑only S2”。
- **一致性**：✅ 一致，且当前综合频率最优。

### 5.17 exp_nd

- **架构**：在 NC 基础上进一步拆分 Stage3。
- **实现**：`mult16_booth_dcs.sv` 中新增 S3/S4，增加寄存器。
- **一致性**：✅ 一致，但拥塞导致倒退。

### 5.18 exp_ne

- **架构**：冗余累加（4:2 直接累加 Product 与 Acc）。
- **实现**：Stage3 先把 PP 压缩到 2 行，再用 4:2 合并 Acc。
- **一致性**：✅ 一致，但 4:2 额外延迟抵消收益。

### 5.19 exp_nf

- **架构**：Hybrid Booth（低位简化）。
- **实现**：`partial_product_gen` 仍为标准 Booth，所谓“混合”主要体现在 **输入排序**。
- **一致性**：⚠️ **概念优化未实质落地**。

### 5.20 exp_ng

- **架构**：VMA 使用 Han‑Carlson（spanning tree）。
- **实现**：`spanning_tree_adder.sv` 显式前缀结构。
- **一致性**：✅ 一致，并带来最大 TT/SS 提升。

### 5.21 exp_o / exp_p / exp_q

- **exp_o**：`mult16_booth_7stage.sv` 超深流水 DCS，输出仍在 mac16 中做 VMA。
- **exp_p**：同 exp_o，但 mac16 增加 S_VMA 使 VMA 单独成级。
- **exp_q**：VMA 内置进 `mult16_booth_8stage.sv`，输出为二进制；反馈简化为 `acc_sum=acc, acc_carry=0`。
- **一致性**：✅ 结构吻合，但全系列延迟超约束。

### 5.22 exp_r / exp_ra / exp_rb / exp_rc

- **exp_r**：等同 exp_ng（Han‑Carlson VMA + NC DCS 树）。
- **exp_ra**：将 `csa` 替换为 `csa_mux`，压缩器也用 MUX 版本。
- **exp_rb**：VMA 改用 Kogge‑Stone（`kogge_stone_adder.sv`）。
- **exp_rc**：VMA 拆成低/高两级流水（mac16 内部）。
- **一致性**：✅ 一致，但都未优于 exp_r。

### 5.23 exp_rd / exp_re / exp_rf

- **exp_rd**：Booth 编码寄存，PPG 使用注册信号，Stage2 做 CSA1。
- **exp_re**：更彻底地将 Booth/PPG分离，S2 只做 PPG，无 CSA。
- **exp_rf**：折中方案（S2 做 PPG + CSA1），减少寄存器位宽。
- **一致性**：✅ 一致，目标是优化 PPG 关键路径。

### 5.24 exp_sa / exp_sb / exp_sc / exp_sd（S 系列初代）

- **exp_sa**：5:2 压缩器尝试（未达标，关键路径落在输出移位逻辑）。
- **exp_sb**：6:3 计数器尝试（未达标，S2 PPG 路径偏深）。
- **exp_sc**：7:3 计数器尝试（未达标，输出路径仍偏长）。
- **exp_sd**：LLCBC‑style 6→2 压缩（当前 S 系列最优），
  - 在严格角下约 902MHz（负 slack），
  - 在另一路径/约束下出现 1644MHz（正 slack），需以赛题角为准。

### 5.25 exp_se / exp_sf / exp_sg（S 系列二代：针对 4.1~4.3）

- **exp_se**：拆分 LLCBC 压缩链为 6→4（CSA）+ 4→2（comp42）两级流水。
- **exp_sf**：PPG 与对齐拆分为两级流水（减少对齐链深度）。
- **exp_sg**：取消流水寄存器时钟使能，仅保留 valid 标记，尝试降低 ECK 负载。
- **结论**：均未优于 exp_sd。

---

## 6. 体系化归类（便于选型）

### A. 分解乘法流水线（非 Booth）

- exp_baseline / exp_a / exp_b / exp_c
- 适合作为**快速验证基线**，但性能上限较低。

### B. 结构化 Booth + CSA/4:2

- exp_d / exp_h / exp_i / exp_k / exp_l / exp_m
- 在 1GHz 目标上较可控，但深流水可能超延迟约束。

### C. DCS 反馈主线（主推荐）

- exp_n / exp_na / exp_nc / exp_nd / exp_ne / exp_nf / exp_ng / exp_r
- 关键优势：无 CPA 反馈，结构清晰，易于进一步物理优化。

### D. 超深流水尝试（延迟超标）

- exp_o / exp_p / exp_q

### E. Booth 切分优化（以 PPG 为主）

- exp_rd / exp_re / exp_rf

---

## 7. 当前可提交的“最稳”建议

- **综合/时序/延迟三者平衡**：建议以 **exp_nc 或 exp_ng/exp_r** 为主线。
- 如严格满足延迟约束：**exp_nc/exp_n/exp_d** 更稳。
- 如追求高频并接受 SS <1GHz：**exp_ng/exp_r** 是当前最优。

---

## 8. 关键发现（面向后续设计）

1. **Booth PPG/Stage2 仍是瓶颈**：多份 STA 报告都指向 PPG 或 Stage2 相关路径。
2. **增加流水级未必有效**：Exp ND / L / M / O 等验证了“拥塞与寄存器成本”会反向伤害时序。
3. **显式 VMA（Han‑Carlson）收益最大**：exp_ng/exp_r 明显优于隐式 `+`。
4. **RTL 命名与实现需校验**：exp_b、exp_nf、exp_nb 存在“意图/实现不一致”。

5. **S 系列压缩链仍是瓶颈**：LLCBC/计数器虽降低理论层级，但关键路径仍落在压缩/输出链与高扇出控制网。

---

## 9. 参考文件清单（便于追溯）

- 关键 DCS 主线：
  - rtl/experiments/exp_n/、exp_nc/、exp_ng/、exp_r/
- Booth/CSA 基线：
  - rtl/experiments/exp_d/、exp_h/、exp_i/
- 深流水实验：
  - rtl/experiments/exp_k/、exp_l/、exp_m/、exp_o/、exp_p/、exp_q/
- 文档汇总：
  - docs/2026-01-26-exp-d-e-f-results.md
  - docs/2026-01-26-exp-h-i-j-k-results.md
  - docs/2026-02-02-exp-l-m-results.md
  - docs/2026-02-02-exp-ne-nf-ng-report.md
  - docs/2026-02-02-exp-r-series-report.md

---

## 10. exp_ng 延迟检查与 testbench 合规性核对（Plan.md）

### 10.1 exp_ng latency_check 结果

- 运行日志显示：输入完成周期 18、输出开始周期 22，**延迟 4 周期**（≤5），**PASS**。
- 结论：exp_ng 在该用例下满足“输入采样完成 → 输出开始 ≤ 5 clk”约束。

### 10.2 当前 tb_latency_check 与赛题要求的差异

对照 [Plan.md](Plan.md) 的 testbench 规范，当前 [verif/tb_latency_check.sv](verif/tb_latency_check.sv) 仅验证**单组输入的延迟上限**，其覆盖范围如下：

- ✅ 覆盖：
  - 串行 16b 输入完成到 `out_ready` 置 1 的延迟检查（≤5）。
- ❌ 未覆盖：
  - 6 组输入序列与三种模式组合（mode=0、mode=1、mode=0→1）。
  - 输入组间**最多 5 clk** 的间隔约束（未建模）。
  - `sum_out` 串行**正确性比对**（未做参考模型比对）。
  - `out_ready` 有效窗口与 `sum_out` 输出位对齐关系（未检查）。
  - `sum_out` 无数据时为 0 的要求（未检查）。
  - `carry` 溢出与清零行为（未检查）。

**结论**：`tb_latency_check.sv` 仅是**延迟审计专用**，并不满足赛题要求的完整功能验证。

### 10.3 `tb_mac16.sv` 与 `tb_latency_check.sv` 组合是否满足题意

- [verif/tb_mac16.sv](verif/tb_mac16.sv) 已更新为**覆盖 Plan.md 要求**：三种 mode 场景数值比对、输入完成到输出开始 ≤5 clk、`out_ready` 窗口对齐、空闲输出为 0、`carry` 行为、输入组间间隔 ≤5 clk。
- [verif/tb_latency_check.sv](verif/tb_latency_check.sv) 仍是**延迟审计专用**，用于快速确认延迟约束。

**综合判断**：当前以更新后的 `tb_mac16.sv` 作为主验证入口，已能满足 Plan.md 的完整 testbench 规范；`tb_latency_check.sv` 作为补充的快速延迟检查保留。

### 10.4 新版 `tb_mac16.sv` 验证结果（EXP=ALL）

运行 `make -f iEDA.mk EXP=ALL verif` 后，多个实验出现**数值错误**与/或 **`out_ready` 窗口不对齐**，说明当前实现与 Plan.md 的接口/时序期望仍不一致：

- S 系列（sa/sb/sc/sd/se/sf/sg）均出现数值错误；其中 exp_sd/sg 的 `out_ready` 窗口失败次数为 15，exp_se/sf 为 3。
  - exp_sd 参考：[build/sim-exp_sd.log](build/sim-exp_sd.log#L1-L45)
  - exp_se 参考：[build/sim-exp_se.log](build/sim-exp_se.log#L1-L34)
- 深流水实验 exp_o/exp_p/exp_q 同时出现**延迟 >5 周期**与数值错误：
  - exp_o 参考：[build/sim-exp_o.log](build/sim-exp_o.log#L1-L29)
  - exp_p 参考：[build/sim-exp_p.log](build/sim-exp_p.log#L1-L31)
  - exp_q 参考：[build/sim-exp_q.log](build/sim-exp_q.log#L1-L31)

> 备注：以上结果来自新的功能 TB；现阶段需要先修正接口/时序对齐问题，再评估各实验的 PPA/STA 优劣。

---

## 11. “Deep Research” 报告对照：已实现 vs 未实现（仅聚焦主频优化）

> 阅读范围：
> - [report/Gemini-0202-CN.md](report/Gemini-0202-CN.md)
> - [report/Gemini-MAC16芯片设计优化研究.md](report/Gemini-MAC16芯片设计优化研究.md)
> - [report/Miromind-0202-CN.md](report/Miromind-0202-CN.md)
> - [report/Miromind-0202.md](report/Miromind-0202.md)
> - [report/Miromind-MAC16.md](report/Miromind-MAC16.md)

以下仅评估**提升主频的架构优化**，不讨论功耗/面积。

### 11.1 已实现或已验证的频率向优化

- **DCS/冗余累加（去除 CPA 反馈）**：已实现并作为主线（exp_n/na/nc/ng/r）。
- **VMA（向量合并加法器）后置**：已实现，且多种前缀加法器对比。
  - Kogge‑Stone（exp_f/rb），Han‑Carlson/Spanning Tree（exp_ng/r）。
- **Booth 编码 + CSA/4:2 压缩树**：已在 exp_d/n/nc/ng 系列落地。
- **细粒度流水线切分（PPG/CSA 分级）**：
  - 5/6/8 级尝试（exp_k/l/m/o/p/q）验证了频率/延迟权衡；
  - “S2 仅 PPG、S3 合并多层 CSA”的重定时思路已在 exp_nc 成功。
- **PPG/Stage2 关键路径拆分**：exp_rd/re/rf 明确实践。
- **LLCBC 风格压缩**：exp_sd 已实现；exp_se 进一步拆分但收益有限。

### 11.2 尚未实现或未落地的频率相关方向

- **5:2 压缩器 / (6,3)/(7,3) 计数器/LLCBC**：未见对应 RTL（当前主要是 3:2 与 4:2）。
- **Radix‑8 或 Radix‑4/8 混合 Booth**：未实现（仍为 Radix‑4）。
- **Vedic 乘法 + 前缀加法器**：未实现。
- **双/三向量冗余累加（double/ triple carry‑save counters）**：未见三向量冗余版本。
- **波浪流水线（wave‑pipelining）**：未实现。
- **基于 EDA 的自动重定时闭环**：目前以手动切分为主，未见“工具重定时”验证闭环。

### 11.3 可能“实现问题导致结果不佳”的实验

以下现象更像实现/切分/拥塞问题，而非架构本身必然失败：

- **exp_e**：2 级 DCS 融合树过深，时序被压扁，可能是“级间切分不足”。
- **exp_nd**：额外流水线导致拥塞与寄存器成本上升，反而倒退。
- **exp_ne**：引入 4:2 直接累加 Acc 反而慢，可能是压缩路径过重或布局不友好。
- **exp_ra**：MUX‑CSA/4:2 MUX 版本慢于原版，可能是门级实现与扇出/线长不匹配。
- **exp_rb**：Kogge‑Stone VMA 反而慢，可能受线长/扇出与布局拓扑影响。
- **exp_rc**：VMA 拆分成两级后变慢，说明“拆分点”不理想或跨级连线负担过大。

### 11.4 对报告建议的“可落地下一步”

- 若继续以频率为第一目标：
  - 优先补充 **5:2 压缩器** 或 **(6,3) 计数器**（替换 4:2/3:2），验证压缩树深度与线长收益。
  - 尝试 **Radix‑8 / Radix‑4+8 混合 Booth**（16b 可能收益有限，但可实测）。
  - 保持 VMA 后置（exp_ng 路线），同时探索更紧凑的前缀网络拓扑以减小线长。
- 若继续保留 5 周期延迟约束：
  - 深流水线（K/L/M/O/P/Q）作为“频率探索”保留，但不作为合规候选。

### 11.5 当前目标与判定依据

- **短期目标**：SS 角下通过 1GHz（1ns）约束，同时保持延迟 ≤5 clk。
- **判定依据**：以 multi‑corner STA 中 SS 角报告为准。

  - docs/2026-02-02-optimization-results.md
  - docs/2026-02-02-latency-audit-report.md
