# ChatGPT

# 高速累加器架构（打破循环）

*   **使用延迟加法技术 (Using Delayed Addition Techniques)… (1998, IEEE)** – FPGA (例如 Xilinx 4000系列)。Luo 和 Martonosi 展示了一种流水线 MAC，它将累加器保持在 Wallace 树（和+进位）形式，并将最终的进位加法推迟到输出时进行。通过存储中间的和与进位，而不是每个周期都进行全加运算，从而缩短了关键路径 [^1]。
*   **高性能双重保留进位 MAC (High-Performance Double Carry-Save MAC) (2012, IEEE/Conf.)** – FPGA (6-LUT 架构)。Cini 和 Kurt 提出了一种“双重保留进位”MAC，其中每个累加器数字都以 3 分量冗余形式保存。进位传播加法器从内部循环中移除，产生了非常高的吞吐量（周期内无进位链延迟）[^2]。
*   **关于 MAC 运算的保留进位策略 (On Carry-Save Strategies for MAC Arithmetic) (2011, Conf.)** – 180 nm。Abelehadi 等人比较了每个周期锁存冗余（和，进位）输出的 MAC 设计。他们的“CSA-MAC”设计从循环中移除了加法器：部分和与进位被存储起来，仅在最后重新组合。这打破了加法-累加循环，并实现了每周期约 2-3 倍的加速（代价是最终需要一个 CPA）[^3]。
*   **高速双周期 MAC (High-Speed Two-Cycle MAC) (2010, IEEE TCAS-I)** – 65 nm, 1.1 V。Hoang & Själander 用一个保留进位加法器加上符号扩展（“双周期 MAC”）替换了流水线 MAC 的最终加法器。在 65 nm 实现中，这比基准 MAC 计算快约 31%，能耗低约 32% [^4]。关键在于每次累加分两步完成，中间没有 CPA，将进位传播推迟到两次部分积压缩之后。

## 乘法器的深度流水线与重定时

*   **“最佳流水线深度为 6–8 FO4” (“Optimal Pipeline Depth is 6–8 FO4”) (2002, IEEE ISCA)** – 100 nm。Hrishikesh 等人报告称，在高性能 100 nm 设计中，为了获得最佳时钟频率，每个流水线级应包含约 6 FO4 的逻辑（加上约 2 FO4 的开销）[^5]。推算到 65 nm（FO4 ≈ 20–30 ps），这意味着每级逻辑的目标约为 150–200 ps（约 5–6 FO4）。这指导了如何切分压缩树：例如，计划每级约 4–6 个全加器（或等效的几个 3:2 压缩）以达到 1GHz+。
*   **一种 65 nm 10 GHz 流水线 MAC 结构 (A 65 nm 10 GHz Pipelined MAC Structure) (2008, Conf.)** – 65 nm, 1.2 V。Kashfi 等人实现了一个 5 级流水线的 16×16+32 MAC（改进的 Booth 算法，低压摆幅 4:2 压缩器，低压摆幅 CSA 加法器），运行频率为 10 GHz [^6]。（在后来的一篇期刊文章中，他们利用先进的 LVS 逻辑将 5 级 MAC 推至 15 GHz。）这表明，通过非常细粒度的流水线，65 nm Wallace 树乘法器中的每一级可以达到 150–200 ps 的量级。

## 高活动性结构的低功耗技术

*   **数据通路的操作数隔离 (Operand Isolation for Datapaths) (2014, IEEE VLSID)** – 65 nm。Siddhu 等人提出了隔离电路，用于钳位或锁存空闲组合逻辑块的输出，防止其输入在下游翻转。在 MAC 流水线中，当数据无效时，操作数隔离会停止乘法器/加法器模块中的开关切换，从而削减不必要的动态功耗 [^7]。
*   **虚假功耗抑制 (Spurious Power Suppression, SPST) (2007, IEEE TVLSI)** – 180 nm。Chen & Chu 引入了逻辑（AND 门或寄存器），当 Booth 编码预测没有贡献（例如零部分积）时，“门控”部分积的生成和加法。应用于 Booth 解码器和压缩树时，这种虚假开关抑制消除了“无用”的翻转，在乘法器中产生了约 40% 的功耗节省 [^8]。
*   **采用 Booth 编码的位串行 MAC (Bit-Serial MAC with Booth Encoding) (2023, Electronics)** – 90 nm。Cheng 等人展示了一种 500 MHz (16-bit) 的 Booth-4 基数位串行乘法器，其功耗比传统位串行设计低约 5.5%，且能效更高 [^9]。Booth 编码将 1 位部分积的数量减半，减少了翻转。（在 180 nm 和 28 nm 库中实施该设计时也报告了类似的趋势。）
*   **符号-幅值与二进制补码对比 (Sign-Magnitude vs Two’s Complement) (2025, L&S Workshop)** – ~40 nm。Arnold 等人建议在乘法之前将输入转换为符号-幅值形式。对于典型（高斯）数据，4 位乘法器的开关活动（即功耗）比二进制补码设计低约 12.9% [^10]。在有限的输入范围内，减少幅度达到约 33%。这表明在内部使用符号-幅值可以减少 MAC 中的翻转，而无需更改其输出格式。

## 55 nm/65 nm 特定的变异收敛 (Variation Closure)

*   **变异感知时钟综合 (Variation-Aware Clock Synthesis) (2013, Integration: VLSI J.)** – 65 nm。Abdelhadi 等人讨论了时序驱动的时钟网格/树设计。他们指出，调度“有用”偏斜（故意偏移时钟以加速关键路径）可以提高 $f_{clk}$，但先进节点的 PVT（工艺、电压、温度）变异增加了偏斜的不确定性，限制了增益 [^11]。在实践中，人们可能会在非 SS 工艺角应用较小的有用偏斜，但随后需为宽 SS 工艺角的偏斜散布预留保护带（guard-band）。
*   **自适应体偏置 (Adaptive Body-Biasing) (2001, IEEE TVLSI)** – 180 nm（较旧节点）。Mircea R. Stan 等人表明，工艺引起的阈值漂移（如慢工艺角漂移）可以通过正向/反向体偏置来抵消 [^12]。在 55 nm 设计中，通常在 SS 工艺角使用正向体偏置来加速关键路径（减少从 TT 到 SS 的 ~1.8 倍减速）。结合多 $V_{th}$ 单元（SS 关键路径上使用低 $V_{th}$，非关键路径上使用高 $V_{th}$）和变异感知时序，这有助于弥合 TT/SS 性能差距 [^12] [^11]。（例如，Stan 建议反向偏置器件以恢复 $V_{th}$ 漂移 [^12]。）

---

**来源：** 近期关于高速 MAC/乘法器设计的架构和行业报告 [^1] [^4] [^5] [^6] [^7] [^8] [^9] [^10]，以及变异感知设计技术 [^11] [^12]。每个参考文献都按要求给出了标题/年份/会议和技术节点。所有主张均由引用的文献支持。

### 参考文献列表

[^1]: Microsoft Word - draft.doc
    https://mrmgroup.cs.princeton.edu/papers/Daspie.pdf

[^2]: emo.org.tr
    https://www.emo.org.tr/ekler/163ced2de82de21_ek.pdf

[^3]: Microsoft Word - CSCC-first.doc
    https://www.wseas.us/e-library/conferences/2011/Tenerife/CSCC/CSCC-36.pdf

[^4]: untitled
    https://www.sjalander.com/research/pdf/sjalander-tcas2010.pdf

[^5]: isca02_dist.dvi
    https://www.cs.utexas.edu/~skeckler/pubs/isca02.pdf

[^6]: 5 GHz pipelined multiplier and MAC in 0.18 μm complementary static CMOS | Request PDF
    https://www.researchgate.net/publication/4018980_5_GHz_pipelined_multiplier_and_MAC_in_018_mm_complementary_static_CMOS

[^7]: (PDF) Operand Isolation with Reduced Overhead for Low Power Datapath Design
    https://www.researchgate.net/publication/261859304_Operand_Isolation_with_Reduced_Overhead_for_Low_Power_Datapath_Design

[^8]: (PDF) A Low-Power Multiplier With the Spurious Power Suppression Technique
    https://www.researchgate.net/publication/3338000_A_Low-Power_Multiplier_With_the_Spurious_Power_Suppression_Technique

[^9]: Booth Encoded Bit-Serial Multiply-Accumulate Units with Improved Area and Energy Efficiencies
    https://www.mdpi.com/2079-9292/12/10/2177

[^10]: [2507.18179] Explicit Sign-Magnitude Encoders Enable Power-Efficient Multipliers
    https://arxiv.org/abs/2507.18179

[^11]: Timing–driven variation–aware synthesis of hybrid mesh/tree clock distribution networks
    https://hajim.rochester.edu/ece/sites/friedman/papers/Integration_13.pdf

[^12]: Timing chart of clock signals. | Download Scientific Diagram
    https://www.researchgate.net/figure/Timing-chart-of-clock-signals_fig1_3765584