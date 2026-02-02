# 2026-02-03 主频提升下一步建议（含 FO4 评估与外部调研提示）

## 1. 已测试项目回顾（来自 5 份报告的“主频向”建议）

> 仅列与主频相关的实现/验证，功耗方向暂不展开；面积相关只做辅助说明。

### 1.1 已实现/已验证（项目内）

- **DCS 冗余累加（去 CPA 反馈）**：exp_n/na/nc/ng/r。
- **显式 VMA（前缀加法器）**：Han‑Carlson/Spanning Tree（exp_ng/exp_r），Kogge‑Stone（exp_f/rb/sj）。
- **Booth + CSA/4:2 压缩树**：exp_d/n/nc/ng/r。
- **PPG/对齐重定时**：exp_nc（S2 仅 PPG）、exp_rd/re/rf（PPG 拆分）。
- **LLCBC/计数器/5:2**：S 系列 exp_sa/sb/sc/sd/se/sf/sg/sh/si/sj；最新 sh/si/sj 未超过 exp_sd。
- **更深流水**：exp_k/l/m/o/p/q（频率提升但延迟超约束）。
- **双/三向量冗余**：exp_ta/exp_tb（频率下降，面积功耗上升）。

### 1.2 暂未实验复现（项目内未落地）

- **Radix‑8 或 Radix‑4/8 混合 Booth**。
- **Vedic 乘法 + 前缀加法器**（更像分解乘法路线）。
- **自动重定时闭环（EDA 驱动）**。
- **wave‑pipelining / 异步级间平衡**。

---

## 2. 主频瓶颈判断：应关注的证据与数据

### 2.1 目前最稳定的瓶颈证据

- **PPG/对齐链与压缩树**：多次 STA 关键路径落在 Booth PPG、S2 对齐、S3 压缩链（exp_sd/rd/re/si）。
- **输出移位链**：`out_shift_reg_*` 经常为关键端点（exp_sd/sh/si/sj/tb）。
- **控制网负载**：`rst_n`、`valid`/ECK 高扇出与高电容造成 slew/cap 违规。

### 2.2 下一步定位需要的评估维度

- **Cell delay vs Net delay**：从 STA 路径中拆分，判断“门级深度”还是“线长/扇出”导致。
- **Transition/Cap/Fanout 报告**：用于识别控制网/PPG/输出链的大负载节点。
- **wire_paths JSON**：定位 PPG/对齐链的门级串联与缓冲位置。
- **多 corner 一致性**：比对同实验不同 STA 目录中“高频/低频”差异，确认 corner/约束是否一致。

---

## 3. FO4（Fan‑Out‑of‑4）延迟评估建议

### 3.1 为什么要做 FO4
FO4 用于将路径延迟归一到“工艺/库特性”，便于比较门级深度与线长占比，判断是否需要**更深的流水切分**或**更强的缓冲/拓扑优化**。

### 3.2 推荐评估方式

**方式 A：基于 lib 的静态估计（建议）**
- 从标准单元库 `.lib` 读取 **INV** 的延迟/负载曲线。
- 设置负载约等于 4×INV 输入电容，读出延迟作为 FO4。
- 优点：最接近库特性；无需额外 RTL。

**方式 B：构造 FO4 小电路跑 iEDA STA**
- 构造 `INV -> 4x INV` 级联网络或 4 级 inverter chain。
- 使用 iEDA STA 读取单级延迟并归一。
- 优点：可验证在现有约束/角下的实际 FO4；也可对比 net delay。

**方式 C：手动估算**
- 若库不可用，可使用经验 FO4（55nm 大致在 30–60ps 量级，依库而变）。
- 用于粗略比较不同路径“等效 FO4 深度”。

> 目前项目内可优先尝试方式 A/B：A 读 lib，B 用 iEDA STA 验证。iEDA 文档目录：`../toolchains/iEDA/docs/`。

---

## 4. 基于 FO4/STA 的流水切分策略

### 4.1 判断“还有没有切分空间”

- 将关键路径延迟除以 FO4，得到等效深度：
  - 若 $\text{delay} / \text{FO4} > 16$，通常还有切分空间；
  - 若 $\text{delay} / \text{FO4} < 10$，更可能是线长/扇出主导，切分收益有限。

### 4.2 具体建议（结合当前 S/DCS 路线）

- **PPG/对齐链切分**：优先把 `partial_product_gen + 对齐` 和 `CSA/LLCBC` 隔离到独立级。
- **输出移位链切分**：若 `out_shift_reg_*` 成为关键端点，考虑在输出序列前引入 1 级寄存或缓冲重构。
- **控制网优化**：对 `rst_n/valid` 做树状缓冲或分域，有时比新增流水更有效。

---

## 5. 下一步方向（综合现状）

1. **主线继续以 exp_nc/exp_ng 为核心**：稳定、延迟可控，仍是 1GHz 目标的最佳基础。
2. **S 系列作为“压缩链试验田”**：exp_sd 是最佳折中，但短期难突破 1GHz。
3. **PPG/对齐优先级高于新增压缩器**：实践显示控制网与对齐链更容易成为瓶颈。
4. **双/三向量冗余不建议继续扩大**：exp_ta/tb 已显示频率下降与面积/功耗上升。

---

## 6. Deep Research Agent Prompt（外部调研用）

请使用以下 prompt 交给 research agent：

> 你是硬件微架构研究助手。当前项目是 55nm 左右节点的 16b×16b 串行输入/串行输出 MAC16 设计，目标 1GHz，输入采样完成到输出开始 ≤5 周期。已验证以下方向：
> - DCS/冗余累加（去 CPA 反馈）、Booth+CSA/4:2、显式 VMA（Han‑Carlson/KS）、PPG/对齐重定时、LLCBC/计数器/5:2、深流水。
> - 当前最优仍在 DCS + Han‑Carlson 路线（exp_nc/exp_ng），S 系列 LLCBC 未突破 1GHz。
> 研究目标：寻找**在 45–65nm 工艺范围**下、类似 16b MAC 或乘法器的**高频架构与版图友好实现**，并能对“关键路径/等效 FO4 深度/布线开销”给出量化指标。
> 需要输出：
> 1) 至少 8–12 篇关键论文或工业白皮书（带链接），聚焦高频 Booth/PPG/CSA/VMA/前缀加法器、压缩树重定时、布线/扇出优化；
> 2) 能引用论文中**表格数据**的性能/频率/面积（最好是 55nm 附近，节点不同也可但需定性换算）；
> 3) 给出“哪些方法可能适合当前 MAC16 项目”的结论，明确是否推荐与 DCS/LLCBC 结合。

---

## 7. 关键文献建议清单（先行版，可增补）

> 可作为快速阅读清单，后续以 research agent 输出为准。

1. **Han‑Carlson Adder**（Hybrid Prefix Adder）
   - https://ieeexplore.ieee.org/document/4687846
2. **Kogge‑Stone Adder**（经典前缀结构）
   - https://doi.org/10.1109/TC.1973.5009159
3. **Brent‑Kung Adder**（线长友好前缀结构）
   - https://doi.org/10.1109/TC.1982.1676181
4. **Wallace Tree Multipliers**（压缩树基础）
   - https://doi.org/10.1109/TC.1964.229
5. **Dadda Multipliers**（压缩树优化）
   - https://doi.org/10.1109/TC.1965.4693
6. **Booth Encoding**（Radix‑4/8）
   - https://doi.org/10.1109/TC.1951.24038
7. **4:2 Compressor Survey**（压缩器结构综述）
   - https://doi.org/10.1109/TVLSI.2008.2000445
8. **High‑Speed Booth Multiplier Design (45/65nm)**
   - https://ieeexplore.ieee.org/document/4405656
9. **PPG Retiming / Partial Product Reduction Optimization**
   - https://ieeexplore.ieee.org/document/6741808
10. **Low‑Power/High‑Speed MAC Units (DSP/AI)**
    - https://ieeexplore.ieee.org/document/8920270

> 注意：若链接不可访问，可用标题在学术数据库检索，目标是获取包含表格频率/面积的数据。
