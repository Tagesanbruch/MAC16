这是基于检索到的文献为您整理的一份专注设计导向的摘要，重点在于如何在 55nm 工艺下实现约 1GHz SS 性能的 16 位 MAC 的现实可操作性。我将按您的四个主题进行组织，并在每个主题中给出：(1) 关键论文/结果；(2) 它们对您的设计的意义；(3) 您可以采用的具体架构/物理技术。

1. 高速累加器架构（打破循环）
1.1 保持累加器为冗余/保留进位形式

冗余二进制和双重保留进位 MAC

一种高速、高能效的双周期乘累加 (MAC) 架构及其在双倍吞吐量 MAC 单元中的应用 (A High-Speed, Energy-Efficient Two-Cycle Multiply-Accumulate (MAC) Architecture and Its Application to a Double-Throughput MAC Unit) – 2010, IEEE TCAS‑I [65 nm]

节点: 65 nm, 1.1 V 标准单元库。

关键思想: 第一个周期仅进行部分积 (PP) 生成和 CSA 树归约；第二个周期执行最终累加和所有其他逻辑，并使用一种特殊的符号扩展方案，使得“累加器 + CPA”不在第一个周期的关键路径中 [1]。

第一级流水线：PP 生成 + 归约树（保留进位）。

第二级：符号扩展、进位传播加法器 (CPA)、饱和处理等。

报告结果：与乘法器馈送独立累加加法器的参考双周期 MAC 相比，速度提高了 31%，每次操作的能量减少了 32% [1]。

适用于基于 6 输入 LUT 的可重构系统的双重保留进位方案 MAC 单元 (A MAC unit with double carry-save scheme suitable for 6-input LUT based reconfigurable systems) – 2015, IEEE ICECS [FPGA]
以及
适用于基于 6 输入 LUT 的可重构系统的具有双重保留进位方案的高性能乘累加单元 (A high performance multiply-accumulate unit with double carry-save scheme for 6-input LUT based reconfigurable systems) – 2015, ELECO [FPGA]

节点: 基于 LUT 的 FPGA（Stratix III；非 ASIC 节点）[2][3]。

关键思想: 对累加结果使用双重保留进位编码——输出保持为两个（在某些作品中实际上是三个）冗余向量，而不在每个周期合并为二进制。仅在需要时（例如，最终读出）才使用二进制 CPA。

他们在 PP 归约和累加中仅使用 (6,3) 计数器，最小化了逻辑深度并完全避免了 MAC 循环中的进位传播。

虽然面向 FPGA，但其基本原理（累加器状态作为 (Sum, Carry) 向量，而非二进制）与技术节点无关。

高性能 CMOS 冗余二进制乘累加 (MAC) 单元 (A high-performance CMOS redundant binary multiplication-and-accumulation (MAC) unit) – 1994, IEEE TCAS‑I [0.8 µm]

节点: 0.8 µm 双层金属 CMOS [4]。

关键思想: 使用与改进的 Booth 重编码相结合的冗余二进制表示，使 PP 归约和累加均以冗余形式进行；只有一个最终的“向量合并加法器”(CPA) 转换为二进制。

即使在 0.8 µm 工艺下，通过平衡流水线级数并从 MAC 循环中移除进位链，他们也超过了 200 MHz。

对您设计的意义

与“融合”或冗余 MAC 相比，具有二进制累加器的单周期 MAC 处于根本劣势。每个周期都要付出 CPA 延迟的代价；在 SS 工艺角下，这变得致命。

架构 [1][2][3][4] 表明，将最终 CPA 推迟到最后一个周期是标准做法：

将运行中的和保持为保留进位或冗余格式（两个或多个向量）。

每个 MAC 周期：
CSA_Reduction(Acc_sum, Acc_carry, Product) → 新的 (sum, carry)。

只有当您必须读出（点积/滤波器窗口结束）时，才应用单个快速 CPA（例如，Kogge–Stone / Han‑Carlson / carry‑select）。

可操作的架构变更

对于 16 位 55 nm MAC：

将 Accumulator = Accumulator + Product (二进制) 替换为：

一个 融合 CSA 树，其每个周期的输入为：

当前 16×16 Booth 编码乘法器的部分积

前一个周期的累加器 和 (Sum) 与 进位 (Carry) 向量

该树输出更新后的累加器 Sum/Carry。此阶段无 CPA。

添加一个 单个“向量合并加法器” (VMA)：

一个并行前缀 CPA，将两个向量合并为最终的 32 位（或更宽）结果。

此 VMA 仅在 read_out_valid 为真时启用时钟，而不是每个周期都启用。

流水线边界：

第 N‑1 级：最后一层压缩器 → (Acc_sum, Acc_carry) 寄存器

最终级：VMA → 输出寄存器。

这既减少了每个周期的组合逻辑深度，又消除了频繁的 CPA 翻转 → 有助于提升 频率 并降低 动态功耗。

1.2 “向量合并加法器” (VMA) 选择

VMA 在乘法器文献中有充分讨论：

关于“向量合并加法器”的通用资料指出，它只是合并 CSA 输出的最终 CPA [5]。

为了在 55 nm 下达到 1 GHz 的最高速度：

使用 并行前缀加法器 (Kogge–Stone, Sklansky, Han–Carlson) 或经过良好调优的 平方根进位选择加法器 (square-root carry-select adder)，如最近的 VMA 优化所示 [6]。

将其放置在一个 单独的、靠后的流水线级 中，具有较短的组合逻辑深度，并根据需要进行大量缓冲/尺寸放大。

2. 乘法器的深度流水线与重定时
2.1 什么样的频率是现实的，每级深度多少？

在公开文献中，直接针对 1 GHz SS 的 55 nm MAC 很少见，但我们可以推断：

65 nm 下的双周期 MAC [1]：

完整的 16–64 位 MAC 在 两级 中达到了高时钟速率（65 nm, 1.1 V）。他们的“第一级” PP+CSA 树大约是一个深的组合逻辑块。

波浪流水线乘法器 (Wave-pipelined multipliers) (180 nm/0.35 µm) 在内部层级之间没有寄存器的情况下达到了数 GHz，但需要极其严格的延迟平衡，且对 PVT 不鲁棒，尤其是在旧节点上 [7][8]。对于您的 1.84× TT→SS 因子，波浪流水线是不可取的。

来自 65 nm–40 nm 约 1 GHz 数字设计实践的经验法则：

全定制或高端 CPU 数据通路通常在最差情况下目标为 10–12 FO4 每流水线级，在 SS 下通常更少。

一个 CSA 压缩层（3:2 或 4:2）只有几个门延迟；布线和扇出占主导地位。

针对您 55 nm SS=1 GHz 目标的实用指标

假设 TT 必须达到 ≈1.8 GHz (0.56 ns)。SS 慢 ~1.84× → 您希望每级 ≤0.56 ns @ TT。

在 55 nm 中，一个 FO4 延迟在标称 Vdd 下大约为 ~25–35 ps（粗略估计；很大程度上取决于您的库）。

0.56 ns / 30 ps ≈ 18 FO4 (TT)。

考虑到 SS 减速，您必须保持 有效 SS 深度 ~10 FO4 或更好。

结论：设计每个 MAC 流水线级 为：

在 SS 下 ≈ 10 FO4 或更少 → 在 TT 下可能是 12–14 FO4。

2.2 如何将 Booth+Wallace/列压缩树切分为 6–8 级

来自列压缩和流水线乘法器的工作：

列压缩流水线乘法器 (Column Compression Pipelined Multipliers) [9] 展示了自然的结构：

PP 生成（Booth 编码器 + PP 生成）。

多层 CSA（3:2, 4:2 压缩器）。

最终 VMA (CPA)。

他们在 CSA 层之间 插入寄存器以减少逻辑深度。

Wallace 树乘法器（FPGA 和异步变体）中的 细粒度流水线 有效地每隔 1–2 个压缩器级别就打断一次树 [10]。

阵列乘法器的 二维流水线门控 [11] 同样依赖于分离水平和垂直流水线级。

对于 55 nm 的 16×16 Booth+Wallace：

部分积：8 个 Booth 行 (基数-4) 或 5–6 行 (基数-8)，每行 16–17 位。

典型的压缩至 2 行的调度需要 ~3–4 个压缩器“层级”。

具体的切分策略（总共 6–8 级）

假设您希望从输入到 CSA 累加器有 6–7 级：

第 0 级（可选，如果输入时序宽松）：

寄存器 A, B。

第 1 级：

Booth 编码 (基数-4 或 基数-8) + PP 生成。

目标是编码器 + AND 门约 2–3 FO4。寄存 PP 行。

第 2 级：

CSA 第 1 层：使用 3:2/4:2 压缩器压缩 PP 行以减少高度。

保持 1 个压缩器层级 + 短的局部布线 → ~4–6 FO4。

第 3 级：

CSA 第 2 层：进一步压缩。

同样，1 个压缩器层级 → ~4–6 FO4。

第 4 级：

CSA 第 3 层 + 将累加器 (sum, carry) 加入树中（如果使用融合 MAC）。

此级输出的流水线寄存器产生更新后的 (sum, carry)。

第 5 级：

可选：最终压缩为两个向量 + 部分和；如果您的 CSA 树足够短，可以在第 4 级停止。

第 6 级：

VMA (CPA 级) 仅 用于最终读出；可以进行时钟门控。

注意事项：

寄存器放置：确保每一级具有 平衡的逻辑深度和扇出：

避免一级有 2 个压缩器而另一级没有；必要时重新定时 (retime) 寄存器。

谨慎使用综合重定时：

允许工具在 PP/CSA 内部 移动寄存器，但 固定 您的 Acc_Sum/Acc_Carry 寄存器，以保持清晰的 MAC 循环边界。

物理上：

将每一级的压缩器放置在一个 紧密的簇 中，与其他级分开，以限制级间线长和寄生参数。

鉴于您当前的 5 级设计 (1.15 GHz TT, 0.6 GHz SS)，主要可能的问题是：

一个或两个关键级（特别是“乘法器+累加器”级）中的门级数太多（以及长线）。

MAC 循环中存在 CPA。

转向具有后期 VMA 和仔细重定时的 7 级融合 CSA MAC 是接近 SS 下 1 GHz 的最现实途径。

3. 高活动性结构的低功耗技术

您的功耗差距（~2 mW vs <300 µW）很大；需要多种正交技术。文献指出：

3.1 操作数隔离与时钟门控

使用流水线 Vedic 乘法器的低功耗计算单元设计 (Design of a Low-power Computational Unit using a Pipelined Vedic Multiplier) – ICONAT 2023 [45 nm, 90 nm]

在流水线乘法器、加法器/减法器和逻辑单元周围使用操作数隔离以降低功耗 [12]。

在 45 nm 和 90 nm 库中验证；动态功耗明显降低。

通过受控网表扰动自动综合时钟门控逻辑 (Automatic Synthesis of Clock Gating Logic with Controlled Netlist Perturbation) – DAC 2008 [与节点无关]

自动综合 时钟门控条件，在基准测试中将动态 时钟功耗降低约 14.5 % [13]。

概念上等同于“有效信号门控”流水线寄存器：当启用条件为假时，寄存器不翻转。

基于二维流水线门控的功耗感知流水线乘法器设计 (Power-aware Pipelined Multiplier Design Based on 2-Dimensional Pipeline Gating) – GLSVLSI 2003 [节点未指定]

引入 2D 流水线门控：在垂直方向（跨流水线级）和水平方向（级内）都门控时钟 [11]。

使用此技术的 16 位阵列乘法器比非门控设计实现了 ≈66 % 的平均功耗节省 和 47 % 的延迟减少 [11]。

可操作的用法

添加每级 有效 (valid) 信号：

当没有新的 MAC 操作进行时（例如，流水线气泡或空闲），禁用：

级寄存器的时钟（时钟门控）。

组合逻辑的输入（操作数隔离），将其保持为常数（零）。

进行细粒度门控：

例如，如果操作数为零（在稀疏工作负载中很常见），则在该周期完全门控 部分积生成和 CSA 逻辑。

3.2 乘法器/CSA 树中的虚假翻转抑制

具有减少虚假翻转的微功率低压乘法器 (A micropower low-voltage multiplier with reduced spurious switching) – IEEE TVLSI 2005 [0.35 µm]

将小锁存器集成到加法器中（“锁存加法器”），以同步输入并减少加法器块中的 毛刺和虚假翻转 [14]。

实现：

16×16 乘法器功耗降低 ~32 %。

每个加法器的转换次数大幅减少（从 ≈5.6–10 降至 ≈2）。

一般列压缩研究 [15] 观察到：

随着乘法器扩展，寄生参数和毛刺主导功耗。

更多的压缩层级和更长的导线会增加动态功耗。

可操作的用法

门控或锁存 进入每个 CSA 层的输入：

如果高位 PP 位为零（Booth 编码有许多零），跳过这些加法器切片的翻转。

考虑使用 门控半/全加器，当其操作数不活动时，可以将一个输入强制为零。

平衡到达时间 进入压缩器以最小化毛刺：

匹配线长/扇出，或使用简单的输入锁存器（如 [14] 中所示）来均衡时序。

限制 CSA 级之间的 扇出和布线拥塞 —— 长线 = 大寄生参数 = 功耗。

3.3 Booth 编码和列压缩调整

用于低功耗乘法器的改进 Booth 编码 (Improved-Booth encoding for low-power multipliers) – ISCAS 1999 [未给出节点]

修改 Booth 编码以 增加零数字的概率，从而：

减少部分积转换约 3.75 %。

减少进位位转换 3.75–7 %。

HSPICE：对于 16×16 二进制补码阵列和 Wallace 乘法器，功耗降低 >4 % [16]。

低功耗 Booth 编码阵列乘法器 (专利) (Low-power Booth‑encoded array multiplier) – 2007, 0.5 µm [17]

重新排序部分积，使得低转换的部分积首先被相加，从而尽早吸收翻转并减少更深层加法器级的功耗。

可操作的用法

使用 偏向零代码的基数-4 或 基数-8 Booth：

设计您的 Booth 编码器，使“00”和“11”模式对于典型数据（例如，具有零或小幅值的权重/激活）更频繁。

在压缩树中：

对 PP 列进行排序，使得具有固有低活动性的列 较早归约，而高活动性列在剩余级数较少的地方合并。

3.4 位串行和混合精度 MAC

具有改进面积和能效的 Booth 编码位串行乘累加单元 (Booth Encoded Bit-Serial Multiply-Accumulate Units with Improved Area and Energy Efficiencies) – Electronics 2023 [TSMC 90 nm]

具有基数-2 和基数-4 Booth 编码的位串行 MAC；90 nm 下 150–500 MHz 的 16 位基数-4 位串行 MAC 显示面积-功耗乘积 (APP) 比基准位串行设计降低高达 ≈96 % [18]。

适用于超低功耗、低吞吐量。

用于面积、功耗和成本受限传感器的机器学习计算的高效位串行加速器架构 (A Bit Serial Accelerator Architecture for Efficient ML Compute in Area, Power and Cost Constrained Sensors) – ICECS 2024 [40 nm]

40 nm 中的位串行 MAC，在 0.65 V, 15 MHz 下达到 12.5 TOPS/W [19]。

对您的意义

纯位串行 MAC 无法满足 1 GHz 吞吐量约束：每个 16×16 MAC 需要 ≥16 个周期。

但是，您可以：

探索 混合架构 以用于较低频率/低功耗模式。

当应用有余量或较低精度需求时，时分复用 位串行子 MAC。

3.5 符号-幅值 (Sign-Magnitude) vs 二进制补码 (Two’s Complement)

29.3 利用位稀疏符号-幅值乘法和双加法器树的 8.09TOPS/W 神经引擎 (29.3 An 8.09TOPS/W Neural Engine Leveraging Bit-Sparsified Sign-Magnitude Multiplications and Dual Adder Trees) – ISSCC 2023 [65 nm 生态系统]

表明对于典型的神经网络操作数分布，符号-幅值 (SM) 乘法的能效比二进制补码乘法高 35–67 % [20]。

问题：SM 加法更昂贵（符号比较，在加/减之间进行 mux 选择），如果在每个周期都这样做，会抵消收益。

显式符号-幅值编码器实现高能效乘法器 (Explicit Sign-Magnitude Encoders Enable Power-Efficient Multipliers) – arXiv 2025 [节点未指定]

建议 前端编码器 将 2C 输入转换为符号-幅值，然后在 SM 中相乘并转换回 2C [21]。

实现：对于现实的正态分布输入，开关减少高达 12.9 %；对于较窄范围，高达 33 %；通过感知开关活动的综合，额外节省 5–10 %。

可操作的意义

对于您的 16 位 MAC：

如果操作数是 以零为中心或稀疏的，SM 乘法可以显着减少内部翻转。

您可以：

保持 累加器为 2C，但使用前端编码器和后端转换器 在 SM 中实现乘法器核心，如 [21] 所示。

或者使用混合模式，其中 权重为符号-幅值，但激活保持为 2C。

注意 SM 加法开销：

由于您的累加器处于保留进位冗余形式（sum/carry），SM 符号比较开销主要在乘法器的 入口；冗余累加器可以保持大部分与格式无关。

4. 55 nm/65 nm 特定的设计收敛与变异处理

您的关键挑战：55 nm 中 1.84× TT→SS 减速；您必须达到 ≈1.8 GHz TT 才能达到 ≈1 GHz SS。

4.1 原位时序监视器和 AVS

用于变异容忍数字电路的具有宽电压范围转换检测器的低开销原位时序错误预测技术 (A Low-Overhead In-Situ Timing-Error Prediction Technique with Wide-Voltage-Range Transition-Detector for Variation-Tolerant Digital Circuits) – ELEX 2023 [55 nm SMIC]

在 SMIC 55 nm 中实现了与 CORDIC 集成的原位时序监视器（转换检测器）[22]。

与传统的预留最坏情况余量的设计相比，实现了高达 53.2 % 的节能，面积开销约为 6.1 %。

通过 基于原位错误预测动态调整电压 来处理 SS 工艺角，而不是静态设计余量。

通过超低电压下的鲁棒时序错误检测消除设计余量 (Design margin elimination through robust timing error detection at ultra-low voltage) – S3S 2017 [40 nm]

在 40 nm 的 ARM Cortex‑M0 上，路径内时序错误检测允许在“首次故障点”而不是 SS 余量下运行，从而减少约 75 % 的能量 [23]。

意义

如果您的 SoC 可以容忍一些轻量级 AVS/时钟控制：

在 MAC 的最长路径（例如，VMA 之前的最后 CSA 层/向量）上添加 原位时序监视器。

使用它们来调整本地电源或时钟（在您的域内），而不是针对绝对最差的 SS 进行静态设计。

4.2 55 nm/65 nm 中的工艺/温度变异传感器

基于弱偏置电压下亚阈值漏电流的片上工艺变异传感器 (On-Chip Process Variation Sensor Based on Sub-Threshold Leakage Current with Weak Bias Voltages) – IEEE 2019 [SMIC 55 nm]

传感器使用基于亚阈值漏电流的可重构环形振荡器测量 N- 和 P-MOS 的阈值电压变化 [24]。

在 SMIC 55 nm 中实现；总面积 ≈37 µm²。

使用可重构环形振荡器的片上温度和工艺变异感测 (On-chip temperature and process variation sensing using a reconfigurable Ring Oscillator) – 2017 [65 nm]

65 nm 测试芯片；基于环形振荡器的传感器可估计温度和工艺变化 [25]。

用法

在您的 MAC 附近集成此类传感器：

使用它们对 部件进行分箱 (bin) 并为每个芯片设置工作点（Vdd，频率）。

结合 AVS 或至少每芯片频率微调，而不是使用一个全局“SS 余量”。

4.3 有用偏斜 (Useful Skew) 时钟树综合与 CTS

用于有用偏斜时钟树综合的触发器聚类 (Clustering of flip-flops for useful-skew clock tree synthesis) – ASP‑DAC 2018 [摘要；节点未指定]

结合触发器聚类与 有用偏斜 CTS，可减少时钟线长和总功耗高达 34 %，同时仍满足时序 [26]。

关于有用偏斜和时钟树的一般资料 [27][28] 以及 55 nm 低功耗入门 [29] 指出：

有用偏斜 故意 不平衡时钟到达时间，以牺牲非关键路径为代价来放宽关键路径的时序：

延迟关键路径发射 FF 的时钟，或提前捕获 FF 的到达时间。

在 55 nm 设计中，有用偏斜是与重定时、多位触发器和缓冲器尺寸调整一起使用的标准手段。

针对您的 MAC 的可操作 CTS 实践

在 MAC 块（或 MAC 簇）的布局布线期间：

使用 启用有用偏斜的 CTS：

识别您最差的 SS 路径（可能是 PP→最后 CSA 层或 CSA→累加器寄存器）。

允许时钟树 引入受控偏斜，在这些路径上增加 20–30 ps 的余量，同时保留其他路径的保持余量。

聚类触发器 MAC 数据通路（如 [26] 所示）：

将相邻流水线级的寄存器分组在一个小的物理区域中，以减少级间时钟偏斜和线长。

结合：

多位触发器 以减少本地时钟功耗并改善时钟缓冲。

紧密放置 CSA/VMA 逻辑以最小化数据通路的可变性。

5. 迈向目标的具体计划

将所有这些结合起来，针对您的具体约束（16 位，55 nm，1 GHz SS，<300 µW）：

5.1 架构与微架构

切换到具有延迟 CPA 的融合 CSA MAC

将累加器保持在保留进位（和/进位）状态；MAC 循环中没有 CPA。

添加一个仅用于读出的最终 CPA (VMA) 级。

这直接解决了您的关键路径和功耗问题（无需每个周期全宽加法）。

增加流水线深度并平衡各级（7–8 级）

将现有的“乘法器+累加器”拆分为 2–3 个单独的级：

A 级：Booth 编码 + PP 生成。

B–C 级：CSA 压缩层。

D 级：整合累加器和/进位。

E 级：最终 VMA（仅在读出时）。

将每一级保持在 SS 下 ≲10 FO4；通过重定时进行调整。

如果工作负载允许，考虑基于 SM 的乘法器核心

对于类似 ML 的流量，具有前端编码器 [21] 的 SM 乘法器核心可以使乘法器核心的动态功耗降低 10–20 %。

保持累加器为冗余/2C，以避免循环中的 SM 加法开销。

5.2 降低功耗

激进的操作数隔离和每级时钟门控

门控：

当流水线气泡/空闲时的级时钟。

当输入为零或未更改时的 PP 生成。

尽可能使用自动时钟门控推断，但在知道功能启用处手动编写清除逻辑。

虚假翻转控制

延迟平衡进入每个 CSA 层的 PP 信号（短、等长导线；局部缓冲）。

考虑对特别容易产生毛刺的节点使用轻量级“锁存加法器”结构（受 [14] 启发）。

编码和压缩调整

使用偏向零数字的改进 Booth 编码变体 [16]。

排序列和压缩器，以首先吸收低转换的部分积 [17]。

5.3 变异和物理设计

具有有用偏斜 + 聚类的 CTS

启用有用偏斜 CTS 并聚类 MAC 流水线寄存器。

明确约束偏斜窗口，使得：

关键 MAC 路径在 SS 下获得正时序余量 (slack)。

在 FF 和工艺角下检查保持余量。

片上工艺/温度感测和（可选）AVS

在 MAC 附近集成一个微型基于环形振荡器的工艺传感器 [24]。

使用其读数来：

选择几个编译好的频率/电压工作点之一。

或者驱动自适应 AVS 环路（如果您的 SoC 支持）。

保护带分配

设计 MAC 流水线在 TT 下 ≈1.8 GHz，具有适度的 TT 保护带 (~5–10 %) 并依赖：

有用偏斜 + 关键单元的局部尺寸放大。

针对异常芯片的工艺分箱 / AVS。

关键参考文献（代表性）

[1] A HIGH-SPEED, ENERGY-EFFICIENT TWO-CYCLE MULTIPLY-ACCUMULATE (MAC) ARCHITECTURE AND ITS APPLICATION TO A DOUBLE-THROUGHPUT MAC UNIT. https://www.sjalander.com/research/pdf/sjalander-tcas2010.pdf
[2] A MAC UNIT WITH DOUBLE CARRY-SAVE SCHEME SUITABLE FOR 6-INPUT LUT BASED RECONFIGURABLE SYSTEMS. https://ieeexplore.ieee.org/document/7440400/
[3] A HIGH PERFORMANCE MULTIPLY-ACCUMULATE UNIT WITH DOUBLE CARRY-SAVE SCHEME FOR 6-INPUT LUT BASED RECONFIGURABLE SYSTEMS. https://ieeexplore.ieee.org/document/7394625/
[4] A HIGH-PERFORMANCE CMOS REDUNDANT BINARY MULTIPLICATION-AND-ACCUMULATION (MAC) UNIT. http://ieeexplore.ieee.org/document/260217/
[5] MULTIPLIER LECTURE NOTES (VECTOR MERGING ADDER DISCUSSION). https://www.ee.iitm.ac.in/vinita/pdf/digic/multipliers.pdf
[6] AN EFFICIENT ARCHITECTURE FOR SIGNED CARRY SAVE MULTIPLICATION. https://ieeexplore.ieee.org/iel7/8012254/8416766/08979361.pdf
[7] A HIGH PERFORMANCE HYBRID WAVE-PIPELINED MULTIPLIER. https://ieeexplore.ieee.org/document/1430156/
[8] LOW-POWER 6-GHZ WAVE-PIPELINED 8B × 8B MULTIPLIER. https://ietresearch.onlinelibrary.wiley.com/doi/10.1049/iet-cds.2012.0221
[9] COLUMN COMPRESSION PIPELINED MULTIPLIERS. https://piurilabs.di.unimi.it/Papers/asap_1995_column.pdf
[10] A HIGH-SPEED MULTIPLEXER-BASED FINE-GRAIN PIPELINED ARCHITECTURE… (MODIFIED WALLACE TREE). https://www.tandfonline.com/doi/abs/10.1080/00207217.2015.1017844
[11] POWER-AWARE PIPELINED MULTIPLIER DESIGN BASED ON 2-DIMENSIONAL PIPELINE GATING. https://www.cecs.uci.edu/~papers/compendium94-03/papers/2003/glsvlsi03/pdffiles/p1_01.pdf
[12] DESIGN OF A LOW-POWER COMPUTATIONAL UNIT USING A PIPELINED VEDIC MULTIPLIER. https://ieeexplore.ieee.org/document/10080520/
[13] AUTOMATIC SYNTHESIS OF CLOCK GATING LOGIC WITH CONTROLLED NETLIST PERTURBATION. https://people.eecs.berkeley.edu/~alanmi/publications/2008/dac08_hurst2.pdf
[14] A MICROPOWER LOW-VOLTAGE MULTIPLIER WITH REDUCED SPURIOUS SWITCHING. https://ieeexplore.ieee.org/document/1393025/
[15] ANALYSIS OF COLUMN COMPRESSION MULTIPLIERS. https://ieeexplore.ieee.org/abstract/document/930101
[16] IMPROVED-BOOTH ENCODING FOR LOW-POWER MULTIPLIERS. http://ieeexplore.ieee.org/document/777806/
[17] LOW-POWER BOOTH-ENCODED ARRAY MULTIPLIER. https://patents.google.com/patent/US7225217
[18] BOOTH ENCODED BIT-SERIAL MULTIPLY-ACCUMULATE UNITS WITH IMPROVED AREA AND ENERGY EFFICIENCIES. https://www.mdpi.com/2079-9292/12/10/2177
[19] A BIT SERIAL ACCELERATOR ARCHITECTURE FOR EFFICIENT ML COMPUTE IN AREA, POWER AND COST CONSTRAINED SENSORS. https://ieeexplore.ieee.org/document/10849332/
[20] 29.3 AN 8.09TOPS/W NEURAL ENGINE LEVERAGING BIT-SPARSIFIED SIGN-MAGNITUDE MULTIPLICATIONS AND DUAL ADDER TREES. https://ieeexplore.ieee.org/document/10067269/
[21] EXPLICIT SIGN-MAGNITUDE ENCODERS ENABLE POWER-EFFICIENT MULTIPLIERS. https://arxiv.org/html/2507.18179v1
[22] A LOW-OVERHEAD IN-SITU TIMING-ERROR PREDICTION TECHNIQUE WITH WIDE-VOLTAGE-RANGE TRANSITION-DETECTOR. https://www.jstage.jst.go.jp/article/elex/advpub/0/advpub_20.20230145/_pdf
[23] DESIGN MARGIN ELIMINATION THROUGH ROBUST TIMING ERROR DETECTION AT ULTRA-LOW VOLTAGE. https://ieeexplore.ieee.org/document/8308743/
[24] ON-CHIP PROCESS VARIATION SENSOR BASED ON SUB-THRESHOLD LEAKAGE CURRENT WITH WEAK BIAS VOLTAGES. https://ieeexplore.ieee.org/document/8790891/
[25] ON-CHIP TEMPERATURE AND PROCESS VARIATION SENSING USING A RECONFIGURABLE RING OSCILLATOR. https://ieeexplore.ieee.org/document/7939649/
[26] CLUSTERING OF FLIP-FLOPS FOR USEFUL-SKEW CLOCK TREE SYNTHESIS. https://ieeexplore.ieee.org/document/8297374/
[27] SYNTHESIS OF CLOCK TREES WITH USEFUL SKEW BASED ON SPARSE GRAPHS. https://docs.lib.purdue.edu/dissertations/AAI10170556/
[28] USEFUL-SKEW CLOCK SYNTHESIS BOOSTS ASIC PERFORMANCE (CHAPTER). http://ndl.ethernet.edu.et/bitstream/123456789/58431/1/10pdf.pdf
[29] AN ASIC LOW POWER PRIMER. https://picture.iczhiku.com/resource/eetop/SyiERehJITsdJbNM.pdf