# 16×16 脉动阵列（Systolic Array）扩展方案（MAC16 项目）

## 目标与范围
- 目标：在现有串行 MAC 阵列基础上，新增一个 16×16 脉动阵列实现，用于矩阵乘/卷积型计算。
- 范围：新增 RTL 子目录、接口（优先 AXI-Stream）、片上存储体系、验证与综合/STA 流程。
- 约束：保持现有工程结构与 iEDA.mk 多实验流程兼容。

## 与现有工程的对齐（已阅读当前目录结构）
- 现有 RTL 顶层为串行 MAC，采用 16-bit 串行输入、24-bit 串行输出，带多级乘法流水与状态机。
- 现有验证 TB 使用任务驱动串行输入与串行采样输出，并输出 Simulation Passed/Failed。
- 现有 Makefile 管理 build/log 目录，并在综合前进行验证与归档。
- docs 目录已有验证流程计划与实验结果总结文档；papers 目录仅包含论文 PDF。

本计划将严格复用这些结构与风格，确保接口语义一致、验证逻辑一致、目录与日志风格一致。

## 目录约定（必须遵守）
```
intArray/
  rtl/
    sa16x16/
      sa16x16_top.sv
      sa16x16_pe_serialmac.sv   # PE：复用当前目录串行 MAC（核心要求）
      sa16x16_ctrl.sv
      sa16x16_buf.sv            # FIFO/line buffer/BRAM wrapper
      sa16x16_axi_stream.sv     # AXI-Stream 适配与节拍管理
      sa16x16_defs.svh          # 统一参数/类型/常量
  verif/
    unit/
      tb_sa16x16_pe.sv
      tb_sa16x16_ctrl.sv
      tb_sa16x16_buf.sv
      tb_sa16x16_axi_stream.sv
      tb_sa16x16_top.sv
    vectors/
      *.hex *.csv
  scripts/
    sa16x16_gen.py
    sa16x16_ref.py
  plan/
    systolic_array_16x16_plan.md
  docs/
    arch/                 # 架构/接口/时序文档
    verif/                # 验证计划/覆盖率/失败归因
    synth/                # 综合/STA/时序报告摘要
    pr/                   # 布局布线/时序/功耗
  papers/
    参考论文与笔记/       # 仅存放引用资料与阅读笔记
  Makefile
```

## 串行 MAC 复用原则（关键约束）
- PE 必须实现与现有串行 MAC 相同的**串行输入/输出时序**：
  - inA/inB 串行输入 16 拍（MSB 先入）
  - sum_out 串行输出 24 拍（MSB 先出）
  - out_ready 指示输出窗口
  - mode 切换清空行为与复位行为一致
- PE 的乘法/累加内部实现可借用现有乘法流水模块，但**外部串行接口与时序必须保持一致**。

## 架构概述
### 1) 计算模型
- 目标计算：$C = A \times B$，其中 $A,B,C$ 为 16×16、元素位宽可配置（例如 16-bit signed）。
- PE（Processing Element）标准结构：
  - 输入：$a_{in}$、$b_{in}$、$acc_{in}$（可选）
  - 输出：$a_{out}$、$b_{out}$、$acc_{out}$
  - 每拍执行：$acc_{out} = acc_{in} + a_{in} \times b_{in}$，并将 $a_{in}$、$b_{in}$ 向右/向下转发。

### 2) 脉动阵列拓扑
- 16×16 规则网格，A 从左向右流动，B 从上向下流动。
- 时间展开：阵列填充延迟约为 $2N-2$，总输出延迟约为 $3N-2$（取决于是否在 PE 内累加与输出方式）。

### 3) 控制与时序
- 控制模块负责：
  - 启动/复位/清零累加
  - 行列数据装载节拍
  - 输出有效时序对齐
- 推荐：内部使用“相位计数器 + 有效窗口”产生 valids。

## 接口建议（AXI-Stream 优先）
### 1) 建议接口划分
- 输入 A 流：AXI-Stream Slave（s_axis_a）
- 输入 B 流：AXI-Stream Slave（s_axis_b）
- 输出 C 流：AXI-Stream Master（m_axis_c）

### 2) AXI-Stream 信号
- 必选：TVALID, TREADY, TDATA, TLAST
- 可选：TKEEP/TSTRB/USER（若需标记行列或帧信息）

### 3) 数据格式
- A/B 输入：一拍一个元素，按行/列顺序输入。
  - A：按行输入（row-major），配合行缓冲展开到阵列左边界。
  - B：按列输入（column-major）或也按行输入后转置缓冲。
- C 输出：按行输出，TLAST 标记一行或一帧结束。

### 4) 接口节拍与反压
- 需要在输入侧增加 FIFO，吸收 TREADY 波动。
- 输出侧允许下游反压，阵列输出需写入输出 FIFO。

## 存储体系建议
### 1) 输入缓冲
- A 缓冲：16 行 × 16 列（或流式行缓冲），建议使用行缓冲+FIFO。
- B 缓冲：16 列 × 16 行（或转置缓冲），建议用双口 RAM 或行/列 FIFO。

### 2) 输出缓冲
- C 结果缓冲：16×16，输出时序对齐后推送到 AXI-Stream。

### 3) 片上存储实现方式
- 使用 SystemVerilog 模块包装：
  - 小规模：寄存器阵列 + 读写指针
  - 可扩展：抽象成简单 SRAM/BRAM wrapper，后端综合映射

### 4) 控制与地址
- 控制模块维护行/列索引与时间相位。
- 使用二维索引转线性地址：$addr = row \times 16 + col$。

## RTL 设计建议
### 1) 模块划分（含约束）
- sa16x16_top.sv：顶层接口，含 AXI-Stream 三通道与控制/状态寄存器（若需要配置）
- sa16x16_pe_serialmac.sv：**PE 单元必须复用现有串行 MAC 架构**（与当前目录 mac16 串行形式一致）
- sa16x16_ctrl.sv：时序控制/valid 生成/相位计数器
- sa16x16_buf.sv：输入/输出缓冲（FIFO/line-buffer/BRAM wrapper）
- sa16x16_axi_stream.sv：AXI-Stream 驱动/反压/帧界定
- sa16x16_defs.svh：统一参数、位宽、frame/row/col 编码

### 2) 与现有 RTL 的映射建议
- 将现有串行 MAC 的输入采样/输出移位逻辑迁移为 PE 本地状态机。
- PE 仅做局部累加与转发，阵列级别通过 ctrl 统一调度相位与有效窗口。

### 2) 参数化
- 参数：N=16、DATA_W=16、ACC_W=32/40
- 允许后续扩展到不同规模与位宽

### 3) 时序关键点
- PE 内部乘法器使用综合映射
- 关键路径可能在乘加与累加器，必要时加流水

## 验证（verif）搭建
### 1) 单元测试（必须覆盖所有模块）
- 每个模块必须有独立 TB（unit/ 下 1:1 对应）：
  - `tb_sa16x16_pe.sv`：PE 单元功能/时序/复位/模式切换
  - `tb_sa16x16_ctrl.sv`：相位与 valid 产生、窗口对齐
  - `tb_sa16x16_buf.sv`：FIFO/line buffer 读写、空满、反压
  - `tb_sa16x16_axi_stream.sv`：AXI-Stream 协议握手与 TLAST
  - `tb_sa16x16_top.sv`：系统级端到端矩阵乘

### 2) PE 单元测试约束（关键）
- PE 必须**参考当前目录串行 MAC（mac16 形式）**：
  - 串行输入/串行输出时序保持一致
  - mode/复位行为一致
  - PE 仅负责“乘法 + 局部累加 + 转发”，不得破坏串行节拍

### 3) 单元测试编写风格（对齐现有 TB）
- TB 使用任务化串行输入与输出采样方式，保持与现有 TB 相同的时序驱动风格。
- 每个单元测试必须输出 Simulation Passed/Failed，失败时返回非零退出码。
- 单元测试至少覆盖：复位后首拍、mode 切换清空、输出位序与 out_ready 对齐。

### 3) 系统级 Testbench 结构
- tb_sa16x16_top.sv：
  - 生成随机矩阵 A/B
  - 通过 AXI-Stream 驱动输入（含反压场景）
  - 收集输出 C（含 TLAST 帧界）
  - 与 Python 参考模型比对（sa16x16_ref.py）

### 4) 参考模型
- Python 脚本：
  - scripts/sa16x16_gen.py：向量生成
  - scripts/sa16x16_ref.py：golden 计算
- 输出格式：CSV/HEX，便于 SV TB 读取

### 5) 覆盖用例
- 全 0/全 1/随机/边界值
- 有符号与溢出行为（明确截断/饱和策略）
- 反压场景：随机拉低 TREADY

## Makefile 体系（参考当前路径风格）
### 1) 顶层 Makefile 目标
- build 目录由 Makefile 统一管理
- 目标建议：
  - `make unit_pe` / `make unit_ctrl` / `make unit_buf` / `make unit_axi` / `make unit_top`
  - `make unit_all`
  - `make sim_top`（系统级）
  - `make gen_vectors`
  - `make clean`

### 2) 与当前 Makefile 的一致性规则
- build/log 目录组织方式与现有 Makefile 一致
- 单元测试日志统一落在 build/ 下
- 提供 pre_sim_check（可选）以复用“先验证再综合”的工作流

### 2) 与 iEDA.mk 集成建议
- 通过 rtl/experiments/exp_sa16x16 入口，复用 iEDA.mk 的 yosys/sta 目标
- Makefile 内部不要直接替换 iEDA.mk，仅提供快捷命令转发

## docs 与 papers 约定
### 1) docs 约定
- docs/arch：接口/时序/协议（AXI-Stream 帧定义、TLAST 含义）
- docs/verif：测试计划、覆盖率矩阵、失败归因记录
- docs/synth：综合/STA 汇总与关键路径说明
- docs/pr：P&R 与后仿时序/功耗摘要

### 2) papers 约定
- papers/ 仅存储引用论文与阅读笔记，不存放工程结果
- 记录引用来源与使用结论（便于报告写作）

## docs 结构与命名风格（对齐现有 docs 约定）
- 延续“日期-主题”命名风格，便于和现有文档并行管理。
- 建议新增：
  - 2026-02-xx-sa16x16-verif-plan.md
  - 2026-02-xx-sa16x16-ppa-summary.md
  - 2026-02-xx-sa16x16-issues-log.md

## 综合与 STA（沿用 iEDA.mk 流程）
### 1) 目录与实验集成
- 在 rtl/experiments 下新增 exp_sa16x16：
  - rtl/experiments/exp_sa16x16/*.sv
- 运行示例：
  - make -f iEDA.mk EXP=exp_sa16x16 yosys sta

### 2) 频率目标
- 初期建议：500–800 MHz 作为参考点
- 根据综合结果决定是否插入流水

### 3) 约束与 SDC
- 新增 sdc/sa16x16.sdc 或复用 mac16.sdc
- 若复用，确保顶层端口名一致

### 4) STA 指标
- 关注 WNS/TNS 与关键路径（乘加链）
- 若 WNS 负：增加 PE 内部 pipeline 或拆分累加路径

## 里程碑与交付
1. 规格定义与接口协议冻结
2. RTL 框架完成（top/ctrl/pe/buf）
3. TB + 参考模型完成，基本功能通过
4. 接入 iEDA.mk 实验流程，完成综合/STA
5. 性能评估与优化（流水/位宽）

## 风险与对策
- 关键路径过长：引入流水、分阶段累加
- AXI-Stream 反压影响吞吐：加大输入/输出 FIFO
- 验证复杂度：用 Python 参考模型自动化生成

## 下一步行动清单
- 创建 intArray/rtl/sa16x16 目录与模块骨架（含 serial MAC PE）
- 搭建 verif/unit 单元测试框架（覆盖所有模块）
- 完成 Python 参考模型与向量生成
- 建立 intArray/Makefile 统一管理验证与向量生成
- 接入 iEDA.mk 的 yosys/sta 流程并出首版报告
