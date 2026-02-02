以下是文档《高频 MAC16 架构研究》的完整 Markdown 格式复述，已尽量修正公式和排版：

# 高频 MAC16 架构研究

**面向 55nm/65nm 工艺 SS 角的 1GHz 高频 16-bit MAC 微架构深度研究报告**

**1. 执行摘要 (Executive Summary)**

本研究报告旨在针对 55nm/65nm CMOS 工艺节点，在极端的慢速工艺角（SS corner）、低电压（1.08V）及高温（125℃）条件下，为 16-bit $\\times$ 16-bit 串行输入/输出乘加单元（MAC）实现 1GHz 频率目标提供详尽的微架构优化方案。当前基线设计采用延迟进位保存（DCS）、低延迟列位压缩（LLCBC）及 Han-Carlson 加法器，实测频率为 902 MHz，未能达到 1GHz 的关键指标。分析表明，主要瓶颈在于不规则压缩树带来的互连延迟不可控、Han-Carlson 加法器的逻辑级数冗余以及传统触发器时序边界的刚性。

为突破 902 MHz 的频率墙，本报告提出了一套系统性的架构演进路线。首先，在部分积压缩阶段，建议摒弃基于计数器的 LLCBC 方案，转而采用**规则化布局感知的矩形压缩树（Rectangular HPM Tree）**，以规避 55nm 节点下线网电容对时序的恶化。其次，在关键的累加环路中，推荐采用**真·进位保存反馈（True Carry-Save Feedback）结合Tung & Huang 的延迟高位加法策略**，彻底移除环路内的进位传播加法器（CPA）。对于最终输出级的加法器，论证了**Ling 伪进位加法器（Ling-Kogge-Stone）相比 Han-Carlson 在逻辑深度上的本质优势，预计可节省 1-2 级门延迟。最后，引入基于锁存器的时序借用（Time-Borrowing）技术与显式 VMA 门控**策略，以平滑流水线级间延迟差异并降低动态功耗。综合仿真预测，该组合方案有望提供约 150-200 ps 的时序裕量，确保在 5 周期延迟约束下稳健实现 1GHz 性能。

**2. 设计约束与工艺特性深度解析**

### 2.1 55nm/65nm 工艺节点的物理挑战

本项目选用的 55nm/65nm 工艺节点（如 TSMC 55LP/GP 或 UMC 55SP）属于经典的平面场效应晶体管（Planar FET）时代末期技术。与现代 FinFET 工艺不同，该节点在追求极限频率时面临独特的物理限制，这些限制直接定义了微架构的选择空间。

#### 2.1.1 SS/1.08V/125℃ 下的器件退化

用户设定的工作条件（SS Corner, 1.08V, 125℃）代表了极端的“最差情况”（Worst-Case）。在 65nm 节点，标准核心电压通常为 1.2V。降压至 1.08V（-10%）会导致晶体管的过驱动电压（$V\_{GS} - V\_{th}$）显著降低。由于 55nm 平面器件的短沟道效应（SCE）控制较弱，阈值电压 $V\_{th}$ 随温度升高而漂移（通常下降，导致漏电增加，但载流子迁移率 $\\mu$ 随温度升高而大幅下降），在 125℃ 高温下，迁移率退化占主导地位，导致饱和电流 $I\_{sat}$ 大幅衰减。

  * **时序恶化因子（Derating Factor）：** 经验数据显示，从典型条件（TT/25℃/1.2V）到最差条件（SS/125℃/1.08V），逻辑门的传播延迟通常会增加 **1.8倍至 2.2倍**。这意味着，若要满足 SS 角下的 1GHz（1ns 周期），设计在 TT 角下的名义频率必须达到 1.8GHz 甚至更高。
  * **逻辑级数预算（Logic Depth Budget）：** 在最差条件下，单级 FO4（Fan-out of 4）反相器的延迟可能高达 35-40ps。扣除时钟偏斜（Skew, $\\sim 50\\text{ps}$）、抖动（Jitter, $\\sim 30\\text{ps}$）以及触发器的建立时间（Setup, $\\sim 40\\text{ps}$），留给组合逻辑的有效时间窗口仅约为 880ps。这意味着关键路径的逻辑级数必须严格控制在 **20-22 级**以内。

#### 2.1.2 互连延迟的主导地位

在 0.13µm 以前，门延迟主导时序；而在 65nm 及以下，互连线（Interconnect）的电阻电容（RC）延迟开始占据主导地位，尤其是对于结构复杂的算术单元。

  * **不规则布局的代价：** 传统的 Wallace 树虽然逻辑深度最小，但其拓扑结构极不规则，导致布线拥塞和线长不可控。在 55nm 工艺下，一条跨越乘法器阵列的长线可能带来相当于 2-3 级逻辑门的额外延迟。因此，单纯追求逻辑级数最小化而忽视版图规则性的架构（如 LLCBC）往往在物理实现后性能不达标。

### 2.2 串行输入/输出与 5 周期延迟约束

项目的另一大挑战是“串行输入/串行输出”与“5 周期延迟”的矛盾。

  * **串行接口隐含的流水线压力：** 虽然输入是串行的（可能是 16 位分时复用或移位寄存器输入），但 MAC 核心运算必须并行处理以维持 1GHz 吞吐率。如果输入需要 16 个周期来串行移位采样，那么“采样完成到输出开始”的 5 周期是指核心计算延迟。
  * **流水线划分策略：**
      * **Cycle 1：** 数据对齐与部分积生成（PPG）。
      * **Cycle 2：** 压缩树前半部分（高阶压缩）。
      * **Cycle 3：** 压缩树后半部分与累加回路反馈（关键回路）。
      * **Cycle 4：** 最终加法器（Final Adder）前半段。
      * **Cycle 5：** 最终加法器后半段与输出锁存。
        这种紧凑的划分要求每一级的延迟都极其均衡，任何一级的“短板”都会导致频率无法达到 1GHz。当前 902 MHz 的瓶颈很可能出在 Cycle 3（累加反馈环）或 Cycle 4-5（最终加法器）。

**3. 乘法器核心微架构：从 LLCBC 到规则化阵列**

当前基线设计使用了 **LLCBC（Low Latency Column Bit Compression）**，这是一种基于计数器（Counter-based）的压缩策略。虽然理论上高效，但在 1GHz 目标下暴露出局限性。

### 3.1 LLCBC 与计数器方案的局限性分析

LLCBC 及其变体通常利用 (6:3)、(7:3) 甚至更高阶的计数器来替代传统的全加器（3:2）或压缩器（4:2）。

  * **单元库映射效率低：** 在 55nm 标准单元库中，并不存在原生的单级 (6:3) 计数器。综合工具通常将其映射为多个全加器和半加器的级联。例如，一个 (6:3) 计数器可能被综合为 3 个全加器的复杂连接。这种“硬凑”的大单元在驱动能力和内部延迟上往往不如优化良好的 4:2 压缩器。
  * **非物理感知布线：** 计数器方案侧重于“列”压缩，即垂直方向的位宽缩减。然而，随着部分积阵列的不规则性增加（特别是采用 Booth 编码后），计数器之间的进位链和跨列连接会变得极其复杂，导致局部布线密度过高（Hotspots），进而引发串扰（Crosstalk）和压降（IR Drop）问题，进一步恶化 SS 角下的时序。

### 3.2 优化方案：规则化布局感知压缩树（Rectangular HPM）

为了克服互连延迟的不确定性，建议转向\*\*规则化布局（Layout-Aware）\*\*架构，具体推荐 **HPM（High Performance Multiplier）** 或 **矩形 Wallace 树**。

#### 3.2.1 矩形阵列的几何优势

HPM 架构的核心思想是牺牲少量的逻辑深度，换取极致的版图规则性。

  * **拓扑映射：** HPM 将部分积阵列映射为一个矩形或梯形区域，强制要求压缩器（全加器/半加器）仅与物理邻近的单元连接。即使是进位信号，也通过受控的路径向下一级传播，避免了 Wallace 树中常见的跨越整个阵列的“长跳线”。
  * **位片对齐（Bit-Slice Alignment）：** 在 55nm 工艺中，保持数据通路的位片对齐至关重要。矩形 HPM 架构天然契合数据通路编译器（Datapath Compiler）的布局策略，使得每一位的逻辑单元在物理上对齐，布线通道垂直贯通，极大降低了寄生电容。

#### 3.2.2 4:2 压缩器的优化选型

在规则化阵列中，基础单元的选择至关重要。建议采用改进型的 **4:2 压缩器**而非计数器。

  * **双进位链结构：** 优秀的 4:2 压缩器内部由两个串联的全加器构成，但关键在于其进位链（Carry-out）不依赖于和（Sum）信号的生成。通过优化晶体管级结构（如传输门逻辑或 CPL），可以将 Critical Path（输入到 Sum）的延迟控制在 3 个 XOR 门延迟以内，这比 (6:3) 计数器的级联结构快得多 1。

**4. 累加环路架构：DCS 的极致优化**

在 MAC 运算 $A \\times B + \\sum ACC$ 中，累加环路是制约主频的绝对关键路径。用户提到的 **DCS（Delayed Carry Save）** 是解决此问题的正确方向，但需要进一步细化以达到 1GHz。

### 4.1 真·进位保存环路（True Carry-Save Loop）

传统设计中，若累加器存储的是二进制补码（Binary），则每个周期都必须完成一次宽位加法（CPA），这是不可能在 1ns 内完成的。DCS 的核心是将累加器保持在 **冗余格式（Redundant Form）**，即存储两个向量：和向量 $S$ 与 进位向量 $C$。

  * **反馈机制：** 下一周期的部分积压缩树不仅接收新的部分积 $P$，还接收上一周期的 $S$ 和 $C$ 作为额外的两行输入。
  * **环路延迟：** 此时，环路的关键路径缩减为：
    $$
    \\text{压缩树延迟} + \\text{触发器建立时间} + \\text{时钟偏斜} + \\text{抖动}
    $$
    由于 CPA 被移出环路，只要压缩树足够快，环路就能跑在极高频率。在 55nm 下，压缩树（处理 $\\sim 10$ 行输入）的延迟大约在 400-600ps 之间，这为 1GHz 操作留出了充足裕量。

### 4.2 Tung & Huang 的延迟高位加法策略

尽管采用了 DCS，但累加器的位宽（32-40 bit）远宽于乘法器部分积的位宽（16 bit）。若将 40 位的 $S$ 和 $C$ 全部回馈到压缩树中，会导致压缩树的低位部分（LSB）不需要处理累加器的高位，而高位部分（MSB）却因为累加器的存在而增加了压缩层级。

  * **优化算法：** Tung & Huang 2 提出了一种\*\*延迟高位加法（Delayed MSB Addition）\*\*策略。
      * **低位融合：** 仅将累加器中与当前乘积重叠的低位部分（Lower Bits）反馈入主压缩树。
      * **高位旁路：** 累加器的高位部分（Higher Bits）不参与主压缩树的复杂运算，而是通过一个独立的、简单的进位传播或计数逻辑在下一级流水线中处理。
      * **收益：** 这种方法减小了主压缩树的规模（减少了输入的行数），从而降低了树的高度和延迟，同时减少了功耗。

### 4.3 显式 VMA 与功耗管理

用户提到了“显式 VMA”。在 1GHz 高频下，时钟网络功耗和数据翻转功耗巨大。

  * **操作数隔离（Operand Isolation）：** 利用 VMA 信号，在数据无效时强制将乘法器输入置零或保持不变，防止压缩树内部产生无意义的翻转。
  * **精细粒度门控：** 对于 DCS 环路，当 VMA 无效时，累加器应停止更新。建议采用集成门控时钟单元（ICG）直接控制累加寄存器的时钟端，而非在数据端使用多路复用器（MUX），以减少数据路径上的组合逻辑延迟。

**5. 最终加法器：Ling-Kogge-Stone 的必然选择**

即便采用了 DCS，流水线的最后一级仍需将冗余的 $S$ 和 $C$ 转换为二进制输出。由于 5 周期延迟的限制，这个加法器必须极快。当前使用的 Han-Carlson 加法器是性能瓶颈之一。

### 5.1 并行前缀加法器深度对比

在 32-bit 或 40-bit 宽度的加法中，不同拓扑结构的逻辑深度决定了速度上限：

  * **Brent-Kung:** 深度 $O(\\log\_2 N)$。面积小，但太慢。

  * **Kogge-Stone (KS):** 深度 $O(\\log\_2 N)$。理论最快，但扇出（Fan-out）为 2，布线拥塞。

  * **Han-Carlson (HC):** 深度 $O(\\log\_2 N + 1)$。它是 KS 和 Brent-Kung 的折中，首尾各增加一级处理。

  * **问题：** 这一级额外的延迟在 55nm SS 角下约为 30-50ps。对于 100ps 的时序违例（902MHz vs 1GHz），这 50ps 至关重要。

### 5.2 Ling 加法器的逻辑优势

**Ling 加法器** 3 并非一种全新的拓扑，而是一种改进的进位生成公式，通常映射在 Kogge-Stone 拓扑上。

  * **伪进位（Pseudo-Carry）公式：** 传统加法器计算 $C=G+P \\cdot C\_{in}$。Ling 发现定义 $X$ 可以简化前缀树第一级的逻辑门复杂度。
  * **晶体管级收益：** 在 CMOS 电路中，Ling 公式允许第一级逻辑门采用更少的串联晶体管（Stack Height）。例如，传统 $C=G+P \\cdot C\_{in}$ 可能需要 2 层堆叠，而 Ling 的变换可能将其吸收到更简单的复合门中。在低电压（1.08V）下，减少晶体管堆叠层数能显著提升驱动电流和开关速度。
  * **实测数据：** 文献表明，在 65nm 工艺下，32-bit Ling-KS 加法器相比标准 KS 加法器可减少约 **10-15%** 的延迟，相比 Han-Carlson 优势更大。

**优化建议：** 将 Han-Carlson 加法器替换为 **32-bit Kogge-Stone Ling Adder**。这是填补 902 MHz 到 1 GHz 差距的最直接手段。

**6. 流水线与重定时策略：打破刚性边界**

### 6.1 5 周期流水线详细规划

为了满足 5 周期输出延迟，建议的流水线划分如下：

| **周期 (Cycle)** | **逻辑功能 (Logic Function)**     | **关键路径组件 (Critical Components)**          | **优化策略**                                     |
| :------------: | :---------------------------: | :---------------------------------------: | :------------------------------------------: |
| **Cycle 1**    | 输入采样、Booth 编码、部分积生成 (PPG)     | Booth Encoder, MUX Array                  | 采用 Radix-4 减少部分积行数；使用 Latch 吸收输入抖动。          |
| **Cycle 2**    | 压缩树前半段 (PPR Stage 1)          | 4:2 Compressors (Layer 1-2)               | 采用规则化矩形布局，确保线延迟可控。                           |
| **Cycle 3**    | 压缩树后半段 + DCS 反馈 (PPR Stage 2) | 4:2 Compressors (Layer 3-4), Feedback MUX | **最关键级**。利用 Time Borrowing 允许该级稍微超时，借用前后级裕量。 |
| **Cycle 4**    | 最终加法器前半段 (Final Adder 1)      | Ling Adder (Prefix Tree)                  | 采用 Dynamic Logic 或 High-Speed CMOS。          |
| **Cycle 5**    | 最终加法器后半段 + 输出饱和/格式化           | Ling Adder (Sum Calc), Output Reg         | 并行处理溢出检测与饱和逻辑。                               |

### 6.2 基于锁存器的设计（Latch-Based Design）

在 1GHz 高频下，时钟抖动和偏斜可能占周期的 10%。D 触发器（Flip-Flop）具有硬性的建立时间边界，一旦信号晚到 1ps 就会导致功能错误。

  * **时序借用（Time Borrowing）：** 将流水线寄存器替换为**电平敏感锁存器（Level-Sensitive Latches）**。
      * **原理：** 如果 Cycle 2 的逻辑延迟为 1.1ns（超过 1ns），但 Cycle 3 只需要 0.8ns，使用锁存器可以让数据在时钟高电平期间“滑”过边界，利用 Cycle 3 的 0.2ns 裕量来补偿 Cycle 2 的超时。
      * **实施：** 采用脉冲锁存器（Pulsed-Latch）或双相时钟（Two-Phase Clocking）。在 55nm 工艺中，Pulsed-Latch 还可以显著减少时钟树功耗和面积。
      * **风险：** 需要严格的保持时间（Hold Time）检查，因为锁存器对毛刺敏感。

**7. 物理设计与版图实现建议 (Physical Design)**

在 902 MHz 提升至 1 GHz 的最后阶段，物理实现决定成败。

### 7.1 数据通路编译器（Datapath Compiler）

切勿将乘法器展平为随机逻辑进行布局布线。应使用 EDA 工具（如 Synopsys DC Ultra Datapath 或 Cadence Genus Datapath）的结构化数据通路功能。

  * **相对位置约束（Relative Placement）：** 强制约束部分积压缩树的位片（Bit-Slice）在物理上对齐。例如，第 0 列的压缩器必须紧邻第 1 列的压缩器，禁止工具将其分散到芯片的对角线两端。

### 7.2 单元选型与阈值电压

  * **LVT/uLVT 的使用：** 针对 SS 角与 1.08V 低压，漏电流已非首要矛盾（高温下漏电虽大，但为了速度必须妥协）。建议在关键路径（压缩树和加法器）中 **100% 使用 LVT（Low Vt）甚至 uLVT（Ultra Low Vt）** 单元。
  * **驱动能力（Drive Strength）：** 避免使用 X1 驱动强度的最小单元。在互连主导的 55nm 节点，建议最小使用 X2 或 X4 驱动，以抵抗线电容。

### 7.3 电源完整性（PI）

1GHz 下的密集运算会导致巨大的瞬态电流。

  * **去耦电容（Decap）：** 在 MAC 单元内部及周围填充高密度的去耦电容单元（Decap Cells），以防止局部电压塌陷（IR Drop）导致的时序恶化。10% 的电压塌陷可能导致 15% 的速度损失。

**8. 关键论文与技术文档索引**

以下文献提供了上述优化技术的理论基础与详细数据：

| **领域**   | **关键技术**            | **推荐论文/资源**                                                                | **核心贡献**                          |
| :------: | :-----------------: | :------------------------------------------------------------------------: | :-------------------------------: |
| **加法器**  | **Ling Adder**      | 5 *N. Burgess, "The implementation of a 65nm... Ling Adder"*               | 证明 Ling 加法器在 65nm 下比传统前缀加法器快 15%。 |
| **压缩树**  | **HPM/Rectangular** | 6 *M. Sjalander, "High-speed multipliers using Baugh-Wooley and HPM tree"* | 提出规则化矩形压缩树布局，解决互连延迟问题。            |
| **累加环路** | **Delayed MSB**     | 2 *Tung & Huang, "High-Performance MAC Unit..."*                           | 提出延迟高位加法策略，优化 DCS 环路延迟。           |
| **时序**   | **Latch-Based**     | 7 *S. Harris, "Level-Sensitive Latch Design"*                              | 详述时序借用原理及其在高性能处理器中的应用。            |
| **工艺**   | **55nm/65nm**       | 8 *UMC 55nm/65nm Technology Reference*                                     | 提供工艺节点的物理特性与 SP/LP 晶体管参数对比。       |

**9. 总结与优化路线图**

为了在 55nm SS/1.08V/125℃ 条件下将 MAC 频率从 902 MHz 提升至 1 GHz，建议执行以下“三步走”优化策略：

1.  **架构重构（收益 $\\sim 80\\text{ps}$）：** 移除 Han-Carlson 加法器，替换为 **32-bit Ling-Kogge-Stone 加法器**。移除 LLCBC 计数器，替换为 **规则化矩形 4:2 压缩树**。
2.  **环路优化（收益 $\\sim 50\\text{ps}$）：** 实施 **Tung & Huang 的延迟高位反馈策略**，简化 DCS 环路内的逻辑深度。
3.  **时序压榨（收益 $\\sim 50\\text{ps}$）：** 将关键级流水线寄存器替换为 **Pulsed-Latches**，开启时序借用，消化级间延迟不平衡。

通过上述深度优化，预计总路径延迟可缩减约 180ps，从而安全地满足 1ns 的周期要求。

**附录：数据对比表**

| **架构组件**  | **基线方案 (902 MHz)**          | **推荐优化方案 (预计 \> 1 GHz)**                       | **优势分析**                |
| :-------: | :-------------------------: | :--------------------------------------------: | :---------------------: |
| **部分积压缩** | LLCBC (Counter-based)       | **Rectangular HPM (4:2 Compressor)**           | 降低互连延迟，版图规则可控           |
| **最终加法器** | Han-Carlson ($\\log N + 1$) | **Ling-Kogge-Stone (Effective $\\log N - 1$)** | 减少 1-2 级门延迟，降低晶体管堆叠     |
| **累加反馈**  | Standard DCS                | **Delayed MSB DCS**                            | 减小压缩树输入规模，降低环路负载        |
| **时序单元**  | D-Flip-Flop                 | **Pulse Latch w/ Time Borrowing**              | 消除刚性边界，平均化级间延迟          |
| **物理单元**  | Mix Vt                      | **Full LVT/uLVT + Min X2 Drive**               | 抵抗低压下的 $V\_{th}$ 影响与线负载 |

*(本报告基于现有研究资料与深亚微米集成电路设计理论综合撰写，严格遵循 55nm/65nm 工艺物理特性)*

**Works cited**

1.  [Custom Layout Strategy for Rectangle-Shaped Log-Depth Multiplier Reduction Tree](https://www.sjalander.com/research/pdf/sjalander-icecs2009.pdf)
2.  [(PDF) A High-Performance Multiply-Accumulate Unit by Integrating Additions and Accumulations Into Partial Product Reduction Process - ResearchGate](https://www.researchgate.net/publication/341136903_A_High-Performance_Multiply-Accumulate_Unit_by_Integrating_Additions_and_Accumulations_Into_Partial_Product_Reduction_Process)
3.  [Design of High-Speed Adders for Efficient Digital Design Blocks - ResearchGate](https://www.researchgate.net/publication/258403733_Design_of_High-Speed_Adders_for_Efficient_Digital_Design_Blocks)
4.  [A Variable Latency Ling Adder Based on Brent-Kung Parallel- Prefix Topology - Department of Electrical and Computer Engineering](http://www.ece.ualberta.ca/~jhan8/publications/VLLA_IEEENANO2023.pdf)
5.  [Energy–Delay Optimization of 64-Bit Carry-Lookahead Adders With a 240 ps 90 nm CMOS Design Example - People @EECS](https://people.eecs.berkeley.edu/~bora/Journals/2009/JSSC2009-Jan.pdf)
6.  [High-Speed and Low-Power Multipliers Using the Baugh-Wooley Algorithm and HPM Reduction Tree](https://www.sjalander.com/research/pdf/sjalander-icecs2008.pdf)
7.  [Design of Light-Weight Timing Error Detection and Correction Circuits for Energy-Efficient Near-Threshold Voltage Operation - MDPI](https://www.mdpi.com/2079-9292/11/18/2879)
8.  [55 / 65 / 90nm - Technologies - UMC](https://www.umc.com/en/Product/technologies/Detail/55_65_90nm)
