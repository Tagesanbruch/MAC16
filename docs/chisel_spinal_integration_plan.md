# Chisel/SpinalHDL 集成与 PPA 对比计划（分析草案）

**目的**：在保持现有 `verif`/`yosys`/`sta` 流程的前提下，引入 Chisel 与 SpinalHDL 版本的 MAC16（`exp_d`、`exp_i`），并把生成的 Verilog RTL 纳入统一验证与 PPA 分析。

> 本文是“先分析再实施”的计划文档，不包含代码修改。

---

## 1. 当前工程状态速览

- **现有验证入口**：`verif/tb_mac16.sv`，由 `iverilog` 编译 `RTL_DIR` 下的 `*.sv`。
- **综合/STA入口**：`iEDA.mk` 通过 `RTL_FILES`（`find $(RTL_DIR)`）驱动 `yosys-sta`。
- **实验结构**：`rtl/experiments/exp_d` 与 `exp_i` 都包含完整 `mac16.sv` + Booth/CSA/压缩树子模块。
- **Chisel/Spinal 目录**：`chisel/` 与 `spinalhdl/` 仅有构建脚本，`src/` 与 `vsrc/` 为空。

结论：**需要为 Chisel/Mill 与 Spinal/SBT 增加“生成 Verilog 到 `vsrc/`”的构建入口，并把 `vsrc/` 引入顶层 Makefile 与 `iEDA.mk` 的 RTL 选择路径。**

---

## 2. 构建系统改造方案（输出 Verilog 到 `vsrc/`）

### 2.1 Chisel（Mill）
当前 `chisel/build.sc` 基于 RocketChip 模板，未提供 Verilog 生成任务。建议精简为一个独立 `mac16` 模块，并提供一个生成任务，将 Verilog 输出到 `chisel/vsrc/<exp>/`。

**建议方向**
- 新增 `object mac16 extends ScalaModule with HasThisChisel`。
- 在模块中定义 `def emitVerilog` 任务，调用 `chisel3.stage.ChiselStage.emitVerilog` 或 `chisel3.emitVerilog`。
- 将输出路径固定为 `chisel/vsrc/<exp>/`，并要求顶层模块名为 `mac16`。

**引用 API**
- Chisel 官方 API：`chisel3.emitVerilog` / `chisel3.stage.ChiselStage.emitVerilog`。
  - https://www.chisel-lang.org/api/latest/chisel3/emitVerilog$.html

**建议输出布局**
```
chisel/
  src/
    main/scala/
      mac16/
        exp_d/
        exp_i/
  vsrc/
    exp_d/
    exp_i/
```

**建议生成命令（示意）**
```
./mill chisel.mac16.emitExpD
./mill chisel.mac16.emitExpI
```

### 2.2 SpinalHDL（SBT）
当前 `spinalhdl/build.sbt` 仅包含依赖，未提供生成任务。建议新增 `Main` 对象，调用 `SpinalConfig().generateVerilog(new Mac16ExpD)` 等。

**引用 API**
- SpinalHDL 文档入口：
  - https://spinalhdl.github.io/SpinalDoc-RTD/master/index.html
- 典型生成接口（在示例中常见）：`SpinalConfig().generateVerilog(...)`。

**建议输出布局**
```
spinalhdl/
  src/
    main/scala/
      mac16/
        exp_d/
        exp_i/
  vsrc/
    exp_d/
    exp_i/
```

**建议生成命令（示意）**
```
sbt "runMain mac16.GenExpD"
sbt "runMain mac16.GenExpI"
```

### 2.3 子目录 Makefile（可选）
在 `chisel/` 与 `spinalhdl/` 下分别提供 `Makefile`，统一输出路径并简化顶层调用：

```
make -C chisel gen_exp_d
make -C chisel gen_exp_i
make -C spinalhdl gen_exp_d
make -C spinalhdl gen_exp_i
```

---

## 3. exp_d 与 exp_i 的 Chisel/SpinalHDL 结构映射

### 3.1 exp_d：结构化 Booth + Wallace/CSA 树
**现有 RTL 关键模块**
- `booth_encoder.sv`
- `partial_product_gen.sv`
- `csa.sv`
- `compressor_4to2.sv`
- `mult16_booth.sv`（3 级流水）
- `mac16.sv`（状态机 + accum + output shift）

**Chisel/Spinal 结构建议**
- 将 Booth 编码、PP 生成、CSA/4:2 压缩树拆为 `object`/`class`，提供通用 `def`/`component`，在 `mult16` 中组合。
- 用 `Vec[UInt]` 描述部分积与中间行，提升结构表达清晰度。
- 将 `WIDTH` 作为参数，保持复用能力（例如 `CSA(width: Int)`）。

**优化点（结构级）**
- 确保流水线边界与组合压缩树一致，避免在生成 Verilog 时被综合工具误合并。
- 给关键寄存器命名，方便后续 STA 路径定位。

### 3.2 exp_i：有效信号门控 + operand isolation
**现有 RTL 关键逻辑**
- `mult16_booth_gated.sv`：所有流水线寄存器在 `valid_in/valid_s*` 为 1 时更新。
- `mac16.sv`：输入采样完成后才 latch 到 `mult_in_a/b`；在 `S_MULT_STAGE3` 等待 `valid_out`。

**Chisel/Spinal 结构建议**
- 使用 `valid` 流水：`valid_s1 -> valid_s2 -> valid_s3`。
- 用 `when(valid)` 包裹寄存器更新，保持与现有行为一致。
- 不要引入“隐式 clock enable”优化，避免与门控语义冲突。
- 复用 exp_d 中的 Booth/CSA 模块，仅在寄存器使能策略上差异化。

**优化点（功耗相关）**
- 对于 `mult_in_a/b` 采用寄存器写使能，确保只在输入完整时更新。
- 对于 `out_shift_reg` 输出移位保持与现有 `S_OUTPUT` 状态机一致，避免无效周期切换。

---

## 4. 数据结构与代码生成层面的优化思路

### 4.1 Chisel 优化思路
- 用 `Vec` + `UInt` 组织压缩树输入，便于生成结构化的 CSA/4:2 逻辑。
- 使用 `WireDefault`/`RegEnable` 明确寄存器更新条件（`valid` gating）。
- 关键路径模块加 `dontTouch`（仅必要时），减少 FIRRTL 对结构的重写。
- 明确 `SInt`/`UInt` 的符号扩展，避免隐式宽度扩张。

### 4.2 SpinalHDL 优化思路
- 使用 `Vec`、`Bits` 明确位宽；中间节点尽量固定宽度。
- 使用 `when(valid)` 或 `RegNextWhen` 的等价方式实现寄存器门控。
- `Area` 组织：按 pipeline stage 切分，减少组合块跨级。

---

## 5. 顶层流程纳入（verif / yosys / sta）

### 5.1 顶层 Makefile 增加“RTL 来源选择”
建议新增变量：
- `RTL_SRC = rtl | chisel | spinal`
- `EXP = exp_d | exp_i | current`

**推荐路径映射**
- `rtl`：`RTL_DIR=./rtl/experiments/$(EXP)`
- `chisel`：`RTL_DIR=./chisel/vsrc/$(EXP)`
- `spinal`：`RTL_DIR=./spinalhdl/vsrc/$(EXP)`

### 5.2 生成 → 验证 → 综合 → STA 的统一入口
建议在顶层 `Makefile` 中提供：
- `gen_chisel_exp_d / gen_chisel_exp_i`
- `gen_spinal_exp_d / gen_spinal_exp_i`
- `verif_chisel`, `verif_spinal`（先生成再 `iverilog`）
- `yosys_chisel`, `yosys_spinal`（先生成再调用 `iEDA.mk`）

### 5.3 `iEDA.mk` 的最小改动策略
保持 `iEDA.mk` 结构不动，只增加一个可选输入：
- `RTL_DIR` 外部传入时优先使用。
- `RTL_FILES` 改为基于 `RTL_DIR` 统一计算。

这样可实现：
```
make -f iEDA.mk EXP=exp_i RTL_DIR=./chisel/vsrc/exp_i yosys
make -f iEDA.mk EXP=exp_i RTL_DIR=./spinalhdl/vsrc/exp_i yosys
```

---

## 6. 验证一致性与回归策略

### 6.1 端口与命名对齐
- 生成的 Verilog **必须保持顶层模块名 `mac16`**。
- 端口名必须与 `verif/tb_mac16.sv` 一致：`clk/rst_n/mode/inA/inB/sum_out/carry/out_ready`。

### 6.2 回归流程建议
- `iverilog`：对 `exp_d` 与 `exp_i` 各跑一轮。
- `yosys/sta`：对 Chisel 与 Spinal 的生成 RTL 分别做 STA 比较。
- 将结果汇总到 `docs/` 的对比报告（频率、面积、功耗）。

---

## 7. 风险与注意事项

- **保持行为一致**：状态机与输出移位逻辑要与现有 RTL 对齐，否则测试会失败。
- **门控语义一致**：`valid` gating 必须精准复刻 exp_i。
- **工具差异**：Chisel/Spinal 生成的结构可能在综合层面产生不同优化，需要在 STA 结果中解释。

---

## 8. 下一步落地建议（无需立即执行）

1. 先在 `chisel/` 与 `spinalhdl/` 中增加最小可用的 Verilog 生成入口（单一 `mac16`）。
2. 完成 `exp_d` 结构化迁移，再逐步加入 `exp_i` 的门控策略。
3. 在顶层 `Makefile` 与 `iEDA.mk` 增加 `RTL_SRC` 与 `RTL_DIR` 逻辑。
4. 做一次 `verif + yosys + sta` 的三路对比（SV/Chisel/Spinal）。

---

## 参考链接

- Chisel API（含 `emitVerilog`）：https://www.chisel-lang.org/api/latest/chisel3/emitVerilog$.html
- Chisel Stage 文档：https://www.chisel-lang.org/api/latest/chisel3/stage/index.html
- SpinalHDL 文档入口：https://spinalhdl.github.io/SpinalDoc-RTD/master/index.html

