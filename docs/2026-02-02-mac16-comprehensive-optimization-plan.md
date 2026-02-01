# MAC16 综合优化与开发计划 (2026-02-02)

本文档基于 `exp_k` 实验结果及 `design_report.md`，针对 MAC16 芯片在 55nm 工艺下冲击 1GHz (SS Corner) 及 1.5GHz (TT Corner) 的目标，制定详细的优化与开发计划。

---

## 1. 当前状态与差距分析

| 指标 | 目标 (Bonus) | 当前最佳 (Exp K) | 差距 | 关键瓶颈 |
| :--- | :--- | :--- | :--- | :--- |
| **频率 (TT)** | 1.0 GHz (1.5 GHz) | **1.154 GHz** | -24% (vs 1.5G) | 流水线级间延迟不平衡 |
| **频率 (SS)** | 1.0 GHz | **0.627 GHz** | -37% | 55nm SS Corner 延迟剧增 (~1.84x) |
| **功耗** | ≤ 300 µW (100 µW) | ~2.57 mW | >8x | iEDA 默认翻转率过高；未做精细门控 |
| **面积** | ≤ 90x90 µm² | ~6754 µm² | ✅ 达标 | 无 (面积裕量充足) |
| **验证** | 完备 Sign-off | ❌ CTS/Route 失败 | 严重 | iEDA 工具链 Bug (SIGSEGV) |

### 关键结论
1. **物理极限挑战**：55nm 工艺下，SS Corner 相比 TT Corner 有近 2 倍的性能衰减。要在 SS 下达到 1GHz，意味着 TT 设计需接近 2GHz，这对 16-bit MAC 来说极具挑战，必须采用**超深流水线 (Super-Pipelining)**。
2. **CTS/Flow 阻碍**：iEDA 的崩溃导致后端物理验证无法闭环，无法获取准确的寄生参数 (SPEF)，导致 STA 结果（尤其是 Hold）不可信。
3. **架构瓶颈**：`exp_k` 虽然用了 5 级流水，但在 `S_ADD` 状态下仍进行单周期的 24-bit+ 累加，这很可能是 SS Corner 下的关键路径之一。

---

## 2. 架构优化路线图 (Architecture Roadmap)

### 2.1 短期优化：累加器流水化 (Exp L - 6 Stage)
**目标**：解决 24-bit 累加器的时序瓶颈，冲击 TT 1.3GHz+。

*   **现状**：`exp_k` 中乘法器是 5 级流水，但累加器 `accum = mult_res + accum` 在 `S_ADD` 状态单周期完成。
*   **优化方案**：
    1.  **引入 Carry-Save Accumulator (CSA)**：将累加器改为保留进位形式 (Sum, Carry)，避免每一拍都进行 24-bit 进位传播。仅在最终输出时合并 (Vector Merging Adder)。
    2.  **累加器切分 (6-Stage)**：如果 CSA 复杂度过高，可简单将累加器切分为 2 级 (低 12 位，高 12 位)，形成 6 级流水线。

### 2.2 中期探索：超深流水线与重定时 (Exp M - 8 Stage)
**目标**：尝试接近 SS 1GHz 的物理极限。

*   **理论分析**：
    *   1GHz @ SS ≈ 1ns 周期。
    *   DFF Setup + CQ延时 @ SS ≈ 250ps。
    *   留给组合逻辑的时间 = 750ps。
    *   55nm SS 门延迟 ≈ 60ps。
    *   **最大逻辑深度 ≈ 12级门**。
    *   传统 Booth 乘法器 + 压缩树深度通常 > 20级门。
*   **行动**：
    *   **Retiming (重定时)**：利用 Yosys 的 `retiming` 命令或手动在关键路径插入寄存器，打破压缩树的长路径。
    *   **8级流水线**：
        *   Stage 1: Booth Encode
        *   Stage 2-5: Wallace Tree (切得更细)
        *   Stage 6: CPA Part 1
        *   Stage 7: CPA Part 2
        *   Stage 8: Accumulate

### 2.3 论文检索方向
建议检索以下关键词以获取灵感：
*   *"55nm/65nm multiplier 1GHz GHz timing closure"*
*   *"Wave pipelining multiplier design"* (波形流水线，可能不需要那么多寄存器)
*   *"Retiming optimization for high-speed MAC"*

---

## 3. 工具与物理验证修复计划 (Tool & Flow)

### 3.1 解决 CTS SIGSEGV 问题 (Priority: High)
根据日志，iEDA 在 `run_cts` 报 `basic_string::_M_construct null not valid`，这通常是**配置缺失**导致的。

**调试步骤**：
1.  **检查 JSON 配置**：检查 `scripts/iEDA_config/cts_default_config.json`。确认是否有 `"clock_nets"` 字段且非空。iEDA 可能期望显式指定时钟网络名称。
2.  **SDC 约束检查**：确认 SDC 文件中 `create_clock` 的端口名称与 Netlist 中的端口名称完全一致（`clk` vs `clock`）。
3.  **Bypass 方案 (OpenROAD)**：如果 iEDA 持续崩溃且无法修复，建议**立即尝试 OpenROAD Flow**。OpenROAD 对 55nm 支持较好，且有成熟的 CTS (TritonCTS)。
    *   *Action*: 编写 `scripts/openroad_flow.tcl`，复用 iEDA 的 LEF/Lib 文件。

### 3.2 功耗评估修正
当前 2.57mW 远超 300µW，原因是工具默认假设 100% 翻转率 (0.5 toggle probability)。

**修正流程**：
1.  **Gate-Level Simulation (GLS)**：使用 iVerilog 运行综合后的网表 `mac16_pr.v`，配合 Testbench 生成 **VCD 文件**。
2.  **VCD 转 SAIF**：使用工具将 VCD 转换为 SAIF 格式 (Switching Activity Interchange Format)。
3.  **反标功耗分析**：在 iEDA 或 Yosys 中读入 SAIF 文件进行功耗计算。
    *   *预估*：MAC 实际运算时的翻转率远低于 100%，实际功耗可能在 0.5mW - 1mW 左右。结合 **Clock Gating (ICG)** 优化，有望达成 300µW 目标。

---

## 4. 可视化分析与报告增强

为了从综合日志中提取更多信息，建议开发以下 Python 脚本工具：

**1. 时序路径可视化 (`scripts/analyze_timing.py`)**
*   **功能**：解析 STA 报告（iEDA 或 OpenSTA 格式）。
*   **输出**：生成 Mermaid 或 Graphviz 图，展示关键路径经过的 Cell 链条。这比纯文本报告更直观，能一眼看出是“压缩树”太深还是“加法器”太长。

**2. 实验数据看板 (`scripts/exp_dashboard.py`)**
*   **功能**：自动读取所有 `syn/exp_*/report` 下的日志。
*   **输出**：生成 Markdown 表格，横向对比 Frequency (TT/SS), Power, Area, Tool Status。

---

## 5. 验证环境升级 (Verification)

### 5.1 Cocotb 引入
目前的 Verilog Testbench (`tb_mac16.sv`) 较难进行复杂的边界测试和随机约束。
*   **建议**：引入 **Cocotb** (Python-based verification)。
*   **优势**：
    *   可以利用 Python 的 `random` 和 `numpy` 快速生成大量浮点/定点测试向量。
    *   更容易实现 Scoreboard 和 Covergroup。
    *   环境搭建极快，只需 Python + iVerilog。

### 5.2 形式验证补充
Yosys 的 `equiv` 已通过 95%。剩下的 5% 是因为它不知道某些 PDK Cell 的逻辑功能（缺少模型）。
*   **行动**：手动为缺失的 Cell (如 `DFF` 的某些特殊端口，或 ICG Cell) 编写简单的 Verilog 行为模型 (`primitives.v`)，并在形式验证时 `read_verilog` 进去。

---

## 6. 详细时间表 (Timeline)

| 阶段 | 时间 | 任务 | 交付物 |
| :--- | :--- | :--- | :--- |
| **Phase 1: Flow Fix** | 2/3 - 2/4 | 调试 iEDA CTS 配置 / 搭建 OpenROAD Flow 备选 | 完整的 P&R Netlist + SPEF |
| **Phase 2: Power Viz** | 2/4 - 2/5 | 跑通 Gate Sim + SAIF 流程；开发可视化脚本 | 真实功耗报告 + 时序路径图 |
| **Phase 3: Arch Opt** | 2/5 - 2/8 | 实现 `exp_l` (累加器流水) 和 `exp_m` (重定时) | 优化的 RTL + 综合报告 |
| **Phase 4: Synthesis** | 2/9 - 2/10 | 在 SS Corner 下进行时序收敛；文档汇总 | 最终 Design Report |

---

## 7. 物理极限分析 (Physical Limits Summary)

针对用户关于“物理极限”的疑问：
*   **FO4 Delay**：55nm 工艺 FO4 约为 25ps - 35ps。
*   **1.5GHz (666ps)**：约 20-25 FO4。这是典型的高性能 CPU 流水线深度。对于 MAC 这种逻辑密集的单元，需要精细的流水线切分。
*   **1.0GHz @ SS**：这是真正的难点。由于 SS 的巨大降速，**纯逻辑延迟不能超过 12-15 FO4**。这已经接近了数字逻辑设计的极限（通常少于 12 FO4 就被认为是 Super-pipelined）。
*   **结论**：在不更换工艺库 (使用 LVT/ULVT 单元) 的前提下，要在 SS Corner 达到 1GHz 是**极度困难的**，可能需要牺牲面积换取极深的流水线 (8-10级) 或者接受降频。

**建议赛题策略**：优先保证 **TT Corner 1.5GHz** (加分项) 和 **功耗 < 300µW** (加分项)，对于 SS Corner 尽力而为，达到 700-800MHz 即为优秀。
