# MAC16 时序优化实施计划

## 目标

优化MAC16芯片时序性能，使其在1GHz工作频率下满足Setup时序要求，同时保证功能验证通过。

## 当前状态

### ✅ 功能验证

- 所有testbench通过（verif/tb_mac16.sv，3种测试模式全部PASS）
- 面积：4380μm² < 8100μm²目标（仅54%利用率，有充足余量）

### ❌ 时序问题

- **Setup Slack**: -0.457ns @ 1GHz（严重违规）
- **TNS**: -24.581ns
- **最大频率**: ~686MHz（仅为目标的68.6%）
- **关键路径**: shift_b[11]:Q → 乘法器组合逻辑(1.187ns) → mult_reg[22]:D
- **根本原因**: 16×16组合乘法器无法在1ns内完成，占总延迟的84%

### 📊 最新STA结果

- 位置：`syn/yosys-syn-2026-01-26_00-42-09/mac16-1000MHz/`
- 报告：`mac16.rpt`, `sta.log`

## 实施策略

采用**渐进式优化**，从低风险到高风险，快速达到1GHz目标。

### 阶段1：综合参数快速验证（1-2小时）⚡

**目的**：验证综合工具是否还有优化空间，为后续RTL修改提供参考数据。

**操作步骤**：

1. 尝试更严格的时序约束（over-constraint）

   - 修改：`../yosys-sta/scripts/yosys.tcl` 或相关ABC参数
   - 设置目标为900MHz（1.11ns周期），逼迫工具更努力优化
2. 调整综合策略

   - 当前已使用 `DELAY 4`（最高级别时序优化）
   - 可尝试调整max_fanout从24降至20
3. 运行并比较结果

   ```bash
   cd /Volumes/disk/work/ysyx/mac
   make yosys
   make sta
   grep "WNS\|TNS\|Freq" syn/yosys-syn-*/mac16-1000MHz/mac16.rpt
   ```

**预期结果**：

- 乐观：改善到-0.3ns左右（~750MHz）
- 悲观：无明显改善，确认必须进行RTL修改

**产出文档**：

- `docs/timing_optimization_log.md`（创建并记录第一轮优化）

---

### 阶段2：RTL乘法器流水线化（核心方案，4-6小时）⭐

**这是唯一能稳定达到1GHz的方案**，将16×16组合乘法器拆分为2级流水线。

#### 2.1 新建流水线乘法器模块

**文件**：`rtl/mult16_pipeline.sv`（新建）

**设计架构**：

```systemverilog
module mult16_pipeline (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [15:0] a,
    input  logic [15:0] b,
    input  logic        valid_in,   // 启动信号
    output logic [31:0] product,
    output logic        valid_out   // 延迟2周期的有效信号
);

    // Stage 1: 部分积生成 + Wallace树第一级压缩
    logic [31:0] partial_sum_s1, partial_carry_s1;
    logic valid_s1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            partial_sum_s1 <= '0;
            partial_carry_s1 <= '0;
            valid_s1 <= 1'b0;
        end else if (valid_in) begin
            // 组合逻辑：部分积生成 + CSA树压缩
            {partial_carry_s1, partial_sum_s1} <= compute_partial_products(a, b);
            valid_s1 <= 1'b1;
        end else begin
            valid_s1 <= 1'b0;
        end
    end

    // Stage 2: 最终进位传播加法器（CPA）
    logic [31:0] product_s2;
    logic valid_s2;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            product_s2 <= '0;
            valid_s2 <= 1'b0;
        end else begin
            product_s2 <= partial_sum_s1 + partial_carry_s1;
            valid_s2 <= valid_s1;
        end
    end

    assign product = product_s2;
    assign valid_out = valid_s2;

    // 辅助函数：组合逻辑，延迟<0.7ns
    function automatic [63:0] compute_partial_products(
        input [15:0] a_in, input [15:0] b_in
    );
        logic [31:0] pp[15:0];
        logic [31:0] sum, carry;

        // 生成16个部分积
        for (int i = 0; i < 16; i++) begin
            pp[i] = b_in[i] ? (a_in << i) : 32'b0;
        end

        // Wallace树第一级压缩（简化实现）
        // 实际应使用4:2压缩器优化
        sum = pp[0];
        carry = 32'b0;
        for (int i = 1; i < 16; i++) begin
            logic [31:0] tmp_sum, tmp_carry;
            tmp_sum = sum ^ pp[i];
            tmp_carry = (sum & pp[i]) << 1;
            sum = tmp_sum;
            carry = carry + tmp_carry;
        end

        return {carry, sum};
    endfunction

endmodule
```

**关键设计考虑**：

- Stage 1延迟：部分积生成 + CSA树 ≈ 0.6-0.7ns
- Stage 2延迟：32位CPA ≈ 0.5-0.6ns
- 每级延迟 < 0.8ns，满足1GHz要求（1.0ns周期 - 0.05ns不确定性 - 0.15ns setup time = 0.8ns可用）

#### 2.2 修改MAC主模块状态机

**文件**：`rtl/mac16.sv`（修改）

**状态机扩展**：

```systemverilog
// 原状态机（2位）
localparam S_INPUT     = 2'd0;
localparam S_COMPUTE_1 = 2'd1;
localparam S_COMPUTE_2 = 2'd2;
localparam S_OUTPUT    = 2'd3;

// 新状态机（3位，适应2周期乘法延迟）
localparam S_INPUT       = 3'd0;
localparam S_MULT_STAGE1 = 3'd1;  // 乘法器第1周期
localparam S_MULT_STAGE2 = 3'd2;  // 乘法器第2周期
localparam S_ADD         = 3'd3;  // 加法阶段
localparam S_OUTPUT      = 3'd4;  // 串行输出

logic [2:0] state;  // 从[1:0]扩展到[2:0]
```

**乘法器实例化**：

```systemverilog
// 删除原mult16实例，替换为流水线版本
mult16_pipeline u_mult (
    .clk(clk),
    .rst_n(rst_n),
    .a(shift_a),
    .b(shift_b),
    .valid_in(mult_valid_in),
    .product(mult_result),
    .valid_out(mult_valid_out)
);

logic mult_valid_in;
logic mult_valid_out;
```

**状态机逻辑修改**：

```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= S_INPUT;
        mult_valid_in <= 1'b0;
        // ... 其他复位逻辑 ...
    end else begin
        case (state)
            S_INPUT: begin
                if (cnt == INPUT_BITS - 1) begin
                    state <= S_MULT_STAGE1;
                    mult_valid_in <= 1'b1;  // 启动乘法器
                    cnt <= '0;
                end else begin
                    cnt <= cnt + 1'b1;
                end
            end

            S_MULT_STAGE1: begin
                mult_valid_in <= 1'b0;
                state <= S_MULT_STAGE2;
            end

            S_MULT_STAGE2: begin
                // 等待乘法器完成（valid_out拉高）
                if (mult_valid_out) begin
                    mult_reg <= mult_result;
                    state <= S_ADD;
                end
                // 如果流水线设计正确，此处应该第一个周期就valid_out=1
            end

            S_ADD: begin
                // 原S_COMPUTE_2的逻辑
                out_shift_reg <= mac_result;

                if (mode_r == 1'b0) begin
                    prev_product <= mac_result;
                end else begin
                    accum <= mac_result;
                end

                if ((!first_op || mode_r == 1'b1) && add_result[OUTPUT_BITS]) begin
                    carry_reg <= 1'b1;
                end

                first_op <= 1'b0;
                out_ready <= 1'b1;
                sum_out <= mac_result[OUTPUT_BITS-1];
                cnt <= '0;
                state <= S_OUTPUT;
            end

            S_OUTPUT: begin
                // 保持不变
                out_ready <= 1'b1;
                sum_out <= out_shift_reg[OUTPUT_BITS-2];
                out_shift_reg <= {out_shift_reg[OUTPUT_BITS-2:0], 1'b0};

                if (cnt == OUTPUT_BITS - 2) begin
                    cnt <= '0;
                    out_ready <= 1'b0;
                    state <= S_INPUT;

                    if (mode != mode_r) begin
                        accum <= '0;
                        prev_product <= '0;
                        carry_reg <= 1'b0;
                        first_op <= 1'b1;
                    end
                end else begin
                    cnt <= cnt + 1'b1;
                end
            end
        endcase
    end
end
```

**关键修改说明**：

- 总周期数仍为：16(输入) + 2(乘法) + 1(加法) + 24(输出) = 43周期（原为42，仅增加1周期）
- 功能逻辑完全相同，只是乘法过程分为2个时钟周期

#### 2.3 验证流程

**步骤1：乘法器单元测试**

```bash
# 创建测试文件：verif/tb_mult16_pipeline.sv
# 测试100个随机乘法，验证延迟2周期后结果正确

cd /Volumes/disk/work/ysyx/mac
iverilog -g2012 -o build/tb_mult16_pipe.vvp \
    rtl/mult16_pipeline.sv verif/tb_mult16_pipeline.sv
vvp build/tb_mult16_pipe.vvp
```

**步骤2：集成验证**

```bash
# 使用原有完整测试
make verif

# 预期：3种模式全部PASS（因为功能逻辑未变）
# Mode 0: 当前乘积+前一乘积 ✓
# Mode 1: 完整累加 ✓
# Mode Switch: 动态切换 ✓
```

**步骤3：时序验证**

```bash
make yosys
make sta

# 检查关键指标
grep "WNS\|TNS" syn/yosys-syn-*/mac16-1000MHz/mac16.rpt

# 预期：WNS > 0（正slack）
# 关键路径延迟从1.413ns降至 <0.8ns
```

**产出文档**：

- `docs/pipeline_design_rationale.md`（流水线设计说明）
- 更新 `docs/timing_optimization_log.md`（记录RTL修改效果）

---

### 阶段3：多角PVT验证（1-2小时）

**操作步骤**：

```bash
make sta_all

# 检查3个corner结果
cat syn/yosys-syn-*/sta_all.log | grep -A 5 "Corner TT\|Corner SS\|Corner FF"
```

**预期结果**：

- TT (1.2V/27°C)：WNS > 0.1ns
- SS (1.08V/125°C)：WNS > 0（最严苛corner）
- FF (1.32V/-40°C)：WNS > 0.2ns

**产出文档**：

- `docs/sta_results/baseline_1ghz_tt.rpt`（复制阶段1的初始结果）
- `docs/sta_results/optimized_1ghz_tt.rpt`（优化后TT corner）
- `docs/sta_results/optimized_1ghz_ss.rpt`（优化后SS corner）
- `docs/sta_results/optimized_1ghz_ff.rpt`（优化后FF corner）
- `docs/sta_results_summary.md`（综合分析报告）

---

## 文档输出计划

### 必需文档（docs/目录）

#### 1. `timing_optimization_log.md`

记录每轮优化的详细过程和效果。

**结构**：

```markdown
# MAC16时序优化记录

## 优化前基线
- 日期：2026-01-26
- STA结果：syn/yosys-syn-2026-01-26_00-42-09/mac16-1000MHz/
- WNS: -0.457ns @ 1GHz
- TNS: -24.581ns
- 最大频率：686MHz
- 关键路径：shift_b[11]:Q → mult逻辑(1.187ns) → mult_reg[22]:D

## 优化轮次1: 综合参数调优
- 时间：[记录实际时间]
- 修改：[具体参数修改]
- 结果：WNS xxx → yyy (改善zzps)
- STA位置：syn/yosys-syn-[timestamp]/mac16-1000MHz/sta.log

## 优化轮次2: RTL 2级流水线
- 时间：[记录实际时间]
- 修改：实施mult16_pipeline.sv + 状态机调整
- 验证：tb_mac16.sv 3种模式全部PASS ✓
- 结果：WNS xxx (>0，达标) ✓
- 关键路径分析：[新的关键路径]
```

#### 2. `pipeline_design_rationale.md`

流水线设计的技术说明。

**内容**：

- 为何选择2级流水线（延迟分解分析）
- 状态机修改的影响（周期数仅增加1）
- 时序收益分析（1.413ns → <0.8ns每级）
- 面积影响评估（增加约32个寄存器）

#### 3. `sta_results_summary.md`

完整的STA结果总结。

**内容**：

- 优化前后对比表格
- 3个PVT corner的详细slack数据
- 关键路径变化分析
- 面积/功耗影响

#### 4. `verification_report.md`

功能验证确认报告。

**内容**：

- 原始验证状态（优化前已通过）
- 流水线修改后的验证结果
- 测试覆盖说明（3种模式）
- 波形文件位置：tb_mac16.vcd

### 目录结构

```
docs/
├── timing_optimization_log.md          # 优化过程记录
├── pipeline_design_rationale.md        # 流水线设计说明
├── sta_results_summary.md              # STA结果总结
├── verification_report.md              # 验证报告
└── sta_results/                        # STA详细报告
    ├── baseline_1ghz_tt.rpt            # 初始TT corner
    ├── optimized_1ghz_tt.rpt           # 优化后TT
    ├── optimized_1ghz_ss.rpt           # 优化后SS
    └── optimized_1ghz_ff.rpt           # 优化后FF
```

---

## 关键文件清单

### 需要修改的文件

1. `rtl/mult16_pipeline.sv` - **新建**，2级流水线乘法器
2. `rtl/mac16.sv` - **修改**，状态机扩展到5状态
3. `verif/tb_mult16_pipeline.sv` - **新建**，流水线乘法器单元测试

### 需要创建的文档

4. `docs/timing_optimization_log.md`
5. `docs/pipeline_design_rationale.md`
6. `docs/sta_results_summary.md`
7. `docs/verification_report.md`
8. `docs/sta_results/` - 目录及内部报告文件

### 关键参考文件

- `rtl/mult16.sv` - 原组合乘法器，作为功能参考
- `verif/tb_mac16.sv` - 主验证基准，修改后必须继续通过
- `iEDA.mk` - 构建流程，执行make命令
- `syn/yosys-syn-2026-01-26_00-42-09/mac16-1000MHz/` - 当前STA结果目录

---

## 成功标准

### 必达指标

- ✅ 功能验证：`make verif` 通过（3种模式全PASS）
- ⬜ 时序TT：WNS(1GHz, TT) > 0
- ⬜ 时序SS：WNS(1GHz, SS) > 0
- ⬜ 时序FF：WNS(1GHz, FF) > 0
- ⬜ 面积：< 8100μm²（当前4380μm²，流水线后预计<6000μm²）
- ⬜ 文档：完整的4个markdown + sta_results目录

### 可选指标（如时间允许）

- ⬜ 功耗分析：`make power`（目标<300μW，当前280.9mW）
- ⬜ 等价性验证：`make equiv`（RTL vs 综合后网表）

---

## 风险与应对

### 风险1：流水线修改后验证失败

**概率**：中（30%）
**应对**：

- 先实现mult16_pipeline单元测试，确保基本功能正确
- 使用宏开关控制新旧版本（`ifdef USE_PIPELINE）
- 保留原mult16.sv作为回退方案

### 风险2：2级流水线仍不满足时序

**概率**：低（10%）
**应对**：

- 升级到3级流水线（每级<0.6ns）
- 调整SDC约束（input/output delay）

### 风险3：状态机修改引入新bug

**概率**：低（15%）
**应对**：

- 详细的状态转移图设计
- 波形验证每个状态转换
- 增加更多corner case测试

---

## 实施时间表

| 阶段           | 时间            | 关键里程碑                                    |
| -------------- | --------------- | --------------------------------------------- |
| 阶段1          | 1-2h            | 综合参数基线测试完成，确认RTL修改必要性       |
| 阶段2          | 4-6h            | RTL流水线实现 + 验证通过 + STA达标            |
| 阶段3          | 1-2h            | 多corner验证完成                              |
| 文档           | 1h              | 所有markdown文档完成                          |
| **总计** | **7-11h** | **1GHz时序达标 + verif通过 + 文档完整** |

---

## 验证命令速查

```bash
# 功能验证
make verif

# 综合
make yosys

# 时序分析
make sta

# 多corner时序
make sta_all

# 快速检查结果
grep "Simulation Passed" build/sim.log
grep "WNS\|TNS" syn/yosys-syn-*/mac16-1000MHz/mac16.rpt
```
