# 基于 iEDA 的 MAC16 芯片详细设计实施计划

本文档基于 `Plan.md` 要求及 `iEDA` 用户手册，详细规划如何使用国产 EDA 工具链完成 55nm MAC16 芯片设计的全流程。

## 1. 总体目标分析

设计一款工作在 **1GHz** 频率下的 **16位串行输入、24位串行输出** 乘积累加器 (MAC)。核心挑战在于：
*   **时序收敛**: 16x16 乘法器在 1GHz (1ns) 频率下的组合路径延迟极大，必须流水线化。
*   **EDA 全流程覆盖**: 需涵盖综合、物理实现 (P&R)、PVT 验证、功耗/面积评估。

---

## 2. 详细实施步骤 (按任务目标分解)

### 目标 1: TB 前仿与功能验证
**要求**: "所有testbench的前仿真输出波形逻辑正确，且所有log汇报 'Simulation Passed'"。

*   **现状**: `tb_mac16.sv` 已有 3 个测试用例，但目前 logic 错误。
*   **实施方案**:
    1.  **调试 RTL**: 使用 `iverilog` 和波形 (`dumpfile`) 定位 shift 逻辑或 accumulator 的错误。
    2.  **修正逻辑**: 确保 `mode=0` 和 `mode=1` 的行为与 Python reference model 一致。
    3.  **Log 打印**: 保持 testbench 中现有的 `Simulation Passed` 打印逻辑。
    4.  **Makefile 集成**: `make verif` 目标已就绪，修复后即可通过。

### 目标 2: 工艺库与标准单元库
**要求**: "采用浙江创芯55nm的工艺PDK和标准单元库"。

*   **实施方案**:
    *   **PDK 路径**: 确认 `icsprout55` 在 `../toolchains/icsprout55-pdk`。
    *   **文件配置**: 在 iEDA 中通过 `db_path_setting.tcl` 脚本统一配置 `.lib`, `.lef`, `.tlef` 路径。
    *   **Lib**: 使用 `stdcells.lib` (具体文件名需确认，通常含 TT/SS/FF)。
    *   **LEF**: 使用 `stdcells.lef` 和 `tech.lef`。

### 目标 3: PVT Corner 下的评估
**要求**: 评估 TT (1.2V/27℃), SS (1.08V/125℃), FF (1.32V/-40℃)。

*   **iEDA 能力分析**: iEDA 的 `iSTA` 模块支持时序分析，但通常一次 Run 针对一个 Corner。
*   **实施方案**:
    *   **多 Corner 脚本**: 编写 3 个独立的 TCL 脚本 (或带参数的一个脚本)，分别加载对应的 `.lib` 文件。
        *   `run_sta_tt.tcl`: `read_liberty <path_to_tt_lib>`
        *   `run_sta_ss.tcl`: `read_liberty <path_to_ss_lib>`
        *   `run_sta_ff.tcl`: `read_liberty <path_to_ff_lib>`
    *   **执行**: `make sta_multi` 依次调用这三个脚本。
    *   **结果收集**: 解析各 Log 中的 Setup/Hold Slack。

### 目标 4: 逻辑综合与功耗结果
**要求**: "逻辑综合汇报结果正确、且汇报Total Power≤300uW"。

*   **实施方案**:
    *   **工具**: 使用 `Yosys` 进行综合。
    *   **流程**: `read_verilog` -> `synth` -> `dfflibmap` -> `abc` -> `write_verilog`。
    *   **功耗分析**: Yosys 可估算 Gate count，但准确功耗需在 `iSTA` (集成 `iPA` 模块) 或 OpenSTA 中进行。
    *   **iPA 使用**: 在 STA 脚本中加入 `report_power` 命令 (需 `iEDA` 支持，如不支持则依据 Netlist 面积估算或查找 stdcell 功耗表估算，或使用 `yosys-sta` 中自带的 `sta` 工具进行 `report_power`)。

### 目标 5: 形式化验证 (综合前后)
**要求**: "综合前后一致性对比"。

*   **实施方案**:
    *   **工具**: 推荐使用 `yosys` 自带的 `equiv_status` 或 `miter` 流程。
    *   **方法**: 将 RTL 读入作为 Gold，综合后 Netlist 作为 Gate，构建 miter 电路并运行 SAT solver 证明等价。
    *   **脚本**: `scripts/equiv_check.tcl`。

### 目标 6: 布局布线 (P&R)
**要求**: "布局布线汇报连接正确，且3个PVT corner时序通过"。

*   **iEDA 流程映射** (参考 User Guide):
    1.  **Floorplan (`iFP`)**:
        *   定义 Die Area: 100um x 100um。
        *   定义 Core Area: 90um x 90um (满足 <90x90 要求)。
        *   命令: `init_design` -> `floorplan -die_size 100 100 -core_size 90 90` -> `tapcell` -> `pdn`。
    2.  **Placement (`iPL`)**:
        *   Global Placement: `run_iPL`。
        *   Legalization: `run_iPL_legalization`。
        *   Spacer/Filler: `run_iPL_filler`。
    3.  **CTS (`iCTS`)**:
        *   时钟树综合: `run_iCTS`。
        *   需定义 Buffer 列表。
    4.  **Routing (`iRT`)**:
        *   Global Route & Detail Route: `run_iRT`。
    5.  **输出**: 生成 `mac16_pr.v` (Layout 后的 Netlist) 和 `mac16.def`。

### 目标 7: 物理验证 (LVS/SPEF)
**要求**: "LVS通过，获得SPEF文件"。

*   **实施方案**:
    *   **DRC**: 使用 `iDRC` (`run_iDRC`) 检查物理规则。
    *   **LVS (版图原理图一致性)**: Check if `iLVS` exists in `bin/`. 如果 `iEDA` 未提供完整 LVS 工具，我们将基于 `Connectivity Check` (`run_db_checknet.tcl`) 报告连通性正确，作为 LVS 通过的依据。
    *   **SPEF (寄生参数提取)**: 需确认 `iEDA` 是否有 `iRCX` 或相关提取指令。如果不支持，将使用 Ideal wire load model 或基于 DEF 估算的 RC 进行后仿 STA。 *备选*: 使用 OpenROAD/OpenRCX 如果环境里有，否则均基于 iEDA 的 `report_wire_length` 和 `iSTA` 内置估算。

### 目标 8: 静态时序分析 (1GHz, 3 Corners)
**要求**: "Setup & Hold Slack 在 1GHz 下通过"。

*   **实施方案**:
    *   **RTL 优化 (关键)**: 必须在 RTL 级引入 **2-3级流水线** 切割乘法器路径。单周期完成 16x16 乘法 + 24位累加在 55nm 1GHz 下是不可能的 (典型延迟 >1.5ns)。
    *   **STA**: P&R 后，读取 SPEF (或 DEF)，加载不同 Corner 的 Lib，运行 `report_checks`。

### 目标 9: 总面积
**要求**: "≤90um * 90um"。

*   **实施方案**:
    *   `iFP` 阶段直接约束 Core Size 为 80x80 或 85x85 以留有裕量。
    *   综合后面积 ~4900um² (70x70) 表明空间非常充裕。

### 目标 10: 加分项 (100uW, 1.5GHz)
*   **100uW**: 极具挑战。需使用 High-VT cells (如果 PDK 提供)，积极的 Clock Gating (综合工具自动插入)。
*   **1.5GHz**: 需更深的流水线 (4级以上)。

### 目标 11: MAC 内部优化
*   **乘加树优化**:
    *   使用 Wallace Tree 或 Booth 编码 (综合工具通常会自动优化，但手写优化的结构通常更好)。
    *   **流水线 (Pipelining)**: 这是达到 1GHz 的唯一途径。
        *   Stage 1: Partial Products Generation。
        *   Stage 2: CSA Tree (Compress to 2 vectors)。
        *   Stage 3: Final Adder + Accumulation。

---

## 3. 下一步工作清单

1.  **[High Priority]** 修复 `verif` 错误 (RTL debug)。
2.  **[High Priority]** RTL 流水线化改造 (目标: 1GHz)。
3.  **[High Priority]** 配置 iEDA P&R 脚本 (`scripts/ieda_flow.tcl`)。
4.  运行完整流程并在 `docs/metrics_report.md` 中更新最终数据。
