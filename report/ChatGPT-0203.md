# 高频乘法器架构研究

[cite_start]为了实现 **55nm** 左右工艺下 **16b×16b** 串行输入/串行输出 MAC 达到 **1GHz** 运行频率，需要在乘法器的各个阶段进行深度优化 [cite: 2][cite_start]。文献中高频乘法器常用的技术包括高效的 Booth 编码、部分积生成（PPG）、压缩加法树（CSA/4:2/5:2 等）、前缀加法器与最终加法优化，以及布线/扇出改进等 [cite: 2]。

---

## Booth 编码与部分积生成 (PPG)

* [cite_start]**Booth 编码**：改进的 Booth 编码（如 Radix-4 或 one-hot Booth）可将部分积数减半，从而缩短压缩树深度 [cite: 4][cite_start]。例如，Zeydel 等人在 90nm 工艺下的 16×16 乘法器中采用了 “one-hot” Booth 编码，并结合优化的 3:2 压缩树，使得电路在 1.2V 下达到 **1GHz** 时钟 [cite: 4][cite_start]。该设计在 1GHz 时功耗 22mW，可见高效 Booth 编码有助于提高频率 [cite: 4]。
* [cite_start]**部分积生成优化**：部分积的生成逻辑也要并行设计、流水化，以避免成为瓶颈 [cite: 5][cite_start]。论文[1]提到，该 16 位乘法器在生成 8 行 Booth 部分积后，仍需将结果扩展到 40 位以避免溢出，但设计通过流水化和冗余表示保持了高速运行 [cite: 5][cite_start]。一般而言，可考虑在 PPG 级插入对齐寄存器或使用压缩编码输出，以平衡不同部分积路径的到达时间 [cite: 5]。

---

## 部分积压缩树 (CSA) 与管道

### 1. CSA 树结构与高级压缩器
* [cite_start]**CSA 树结构**：常见的部分积压缩结构有 Wallace 树、Dadda 树等，它们均由一系列 3:2 全加器和较高阶压缩器（如 4:2 或 5:2 压缩器）构成，用来尽快将多行部分积压缩为两行 [cite: 7][cite_start]。实际中常用平衡的结构（如结合 Wallace 与 Dadda 的混合方法）来最小化关键路径 [cite: 7]。
* [cite_start]**高级压缩器设计**：最新研究设计出的高性能 5:2 压缩器已将进位限制在单级内传递，实测结果优于以往所有同类设计 [cite: 8]。

### 2. 冗余累加 (DCS) 与流水化
* [cite_start]**冗余累加 (DCS)**：双重进位保存（Double Carry-Save, DCS）架构是一种冗余表示方法，可完全消除进位级联 [cite: 9][cite_start]。文献[3]指出，在 FPGA 中实现的 DCS MAC 单元相比传统带进位累加的 CSA MAC，性能提升约 **8–10%**，逻辑资源（LUT）减少约 **18%** [cite: 9][cite_start]。DCS 架构通过延迟将累加器输出用 3 位冗余表示，可在单周期内完成乘加运算 [cite: 9]。
* [cite_start]**流水级划分**：为了达到 GHz 级频率，部分积压缩树内通常需要深度流水化，每隔 1–2 层加法器插入触发器可平衡时序 [cite: 10]。

### 3. Counter-Based 压缩 (LLCBC) 示例
* [cite_start]**LLCBC**：低延迟列比特压缩 (LLCBC) 技术采用多输入计数器和 Wallace 树加法器结合的方式来减少延迟 [cite: 11]。
* [cite_start]**7:3 计数器**：Saha 等人提出了一种自定义的 7:3 计数器结构，应用于 90nm 工艺的乘法器中 [cite: 12][cite_start]。采用该 7:3 计数器设计的 16×16 乘法器在 500MHz 下对比已有设计 **功耗延迟积 (PDP) 降低约 55%** [cite: 12]。

---

## 前缀加法器与最终加法器

[cite_start]乘法结果的最终加法常用并行前缀加法器，其性能与面积各有不同 [cite: 14]：

| 加法器类型 | 逻辑深度 | 扇出 | 面积 (16b, 90nm) | 延迟 (16b, 90nm) |
| :--- | :--- | :--- | :--- | :--- |
| **Kogge-Stone (KS)** | 最短 | 大 | [cite_start]最大 (502μm²) [cite: 23] | [cite_start]~429ps (约 2.33GHz) [cite: 20] |
| **Han-Carlson (HC)** | 中等 | 中等 | [cite_start]中等 (366μm²) [cite: 23] | [cite_start]~444ps [cite: 20] |
| **Brent-Kung (BK)** | 最深 | 小 | [cite_start]最小 (329μm²) [cite: 23] | [cite_start]~522ps (约 1.91GHz) [cite: 20] |

* [cite_start]**性能比较**：在 90nm 工艺下，64 位加法器中 Han-Carlson 延迟约 594ps，Kogge-Stone 约 561ps [cite: 21][cite_start]。由此可见，在与 1GHz 目标频率相比，这些并行加法器在 55nm 上应有足够裕量 [cite: 22]。
* [cite_start]**选择建议**：在 16b MAC 中，若极限频率是关键，可选择 KS 或其变体；若版图资源有限，可用 HC 或改进版 BK 结构 [cite: 24][cite_start]。Han-Carlson 常被认为是在性能和扇出（布局友好度）间较好的折衷 [cite: 24]。

---

## 布线/扇出优化

* [cite_start]**扇出与布线延迟**：在深亚微米工艺中，高扇出的前缀节点会产生长线或多条扇出分支，严重增加延迟 [cite: 26]。
* [cite_start]**Prefix Node Cloning**：Roy 等人使用结构感知克隆技术，在保持逻辑功能不变的情况下将高扇出节点复制 [cite: 27][cite_start]。仿真表明，对于 128 位前缀加法器，将最大扇出降为 2 时，可获得约 **12.8% 的面积减小** 和 **15.4% 的功耗降低** [cite: 27]。
* [cite_start]**FO4 度量**：以 90nm 下 16 位 KS 延迟 428ps 为例，大约相当于 20–25 个 FO4 [cite: 29][cite_start]。在 55nm 上 FO4 约 15ps，则可推测相似结构深度约 30 FO4 左右 [cite: 29]。

---

## 结论：适用方法与 DCS/LLCBC 建议

[cite_start]综合文献结果和实际需求，以下方法对当前 MAC16 项目较为适合 [cite: 40]：

1.  [cite_start]**Booth+CSA 合理组合**：采用高效率的 Booth 编码（如 one-hot 或 Radix-4）配合深度流水化的 CSA 树（3:2/4:2/5:2）是基础 [cite: 41][cite_start]。可进一步探索较新设计的高阶压缩器和多输入计数器（如 7:3）[cite: 41]。
2.  [cite_start]**冗余累加 (DCS) 架构**：建议将 DCS（双重进位保存）与计数器化的压缩树（如 LLCBC 结构或自定义高阶计数器）相结合 [cite: 45][cite_start]。DCS 架构通过延迟将累加器输出用 3 位冗余表示，可在单周期内完成乘加运算，非常适用于高频场景 [cite: 42]。
3.  [cite_start]**前缀加法器选型**：建议使用 Han-Carlson 这类中等扇出的前缀加法器，以平衡速度和面积 [cite: 43]。
4.  [cite_start]**布线优化**：无论哪种前缀结构，都应应用 **节点克隆/扇出控制** 技术来减小布线负担 [cite: 43, 44]。

[cite_start]综上，MAC16 项目有望在 55nm 附近工艺下实现甚至超过 **1GHz** 的性能，并有可能向 **1.5GHz** 靠拢 [cite: 45]。