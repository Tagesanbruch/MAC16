# 2026-02-03 tb_mac16_data vs tb_mac16：差异、问题根因与适配方案

## 1. 两个测试 TB 的核心差异

### 1.1 采样时序
- [verif/tb_mac16_data.sv](verif/tb_mac16_data.sv) 在 `out_ready` 拉高后，从**下一个上升沿**开始采样 24 位，等价于**不采样拉高当拍的 MSB**。
- [verif/tb_mac16.sv](verif/tb_mac16.sv) 按 Plan.md 语义，**在 `out_ready` 拉高当拍采样 MSB**，并连续采满 24 位。

### 1.2 校验覆盖
- `tb_mac16_data.sv`：仅校验数值正确性，不校验延迟、`out_ready` 窗口、空闲 `sum_out=0`、`carry` 行为。
- `tb_mac16.sv`：覆盖 Plan.md 全部约束（功能、延迟≤5、窗口、空闲、carry）。

### 1.3 模式切换与间隔
- `tb_mac16_data.sv` 在 mode 切换点和输入间隔上**更宽松**；
- `tb_mac16.sv` 之前引入了“输入间隔/切换空拍”，在无 `input_valid` 接口的 RTL 中会导致**输入位错位**。

---

## 2. 根因与修复要点

### 2.1 输出采样早/晚导致位流错位
- 现象：输出被右移/左移 1~2 位。
- 根因：`sum_out/out_ready` 在上升沿更新，TB 在同一上升沿直接读值会拿到旧值。
- 修复：`tb_mac16.sv` 中对采样点增加极小延时 `#1ps`，确保采到更新后的值。

### 2.2 输入间隔导致串行位流错位
- 现象：第二组起输出错位，乘积“折半/倍增”。
- 根因：接口没有 `input_valid`，DUT 只能按 16 个周期固定计数。TB 插入 gap 会被当作输入比特。
- 修复：将 gap 设为 0（仍满足“≤5”约束），避免空拍破坏输入对齐。

### 2.3 模式切换空拍导致错位
- 现象：切换到 mode=1 后首组输出错位。
- 根因：mode 切换处额外空拍（TB 中 `@(posedge clk)`）被当作输入比特。
- 修复：移除该空拍，并将 carry 清零检查移动到切换后首组输出。

### 2.4 carry 检查过严
- 现象：carry 首次置 1 时被误判为错误。
- 根因：TB 先比较旧的 `carry_latched`，再更新为 1。
- 修复：当期望溢出时直接要求 `carry==1`，允许其首次拉高。

---

## 3. exp_a 与 exp_sd 的 RTL 适配

### 3.1 exp_a 关键修复
- **输入捕获与 valid 分离**：增加 `mult_in_a/b` 与 `mult_valid_pending`，在输入采满后**下一拍**才拉高 `valid_in`。
- **输出窗口**：确保 `out_ready` 连续覆盖 24 个输出位（MSB 当拍即有效）。
- **mode 切换**：在 S_INPUT 中检测 mode 变化，清空 `accum/prev_product/first_op/carry`。

### 3.2 exp_sd 关键修复
- **输入捕获与 valid 分离**：增加 `mult_input_pending`，避免 `valid_in` 与 `mult_in_a/b` 同拍更新。
- **输出窗口**：S_OUTPUT 周期内保持 `out_ready` 为 1，回到 S_INPUT 自动拉低。
- **mode 切换**：清空 `acc_sum/acc_carry/prev_sum/prev_carry/carry/first_op`。

> 以上改动不会引入新的关键组合逻辑，仅增加少量控制寄存器，STA 影响预计较小，但仍应以报告为准。

---

## 4. 适配所有实验的通用清单

### 4.1 必要的接口时序一致性
1. **MSB-first 输入**：保持 16 个周期固定采样，无 `input_valid` 时不要插入 gap。
2. **MSB-first 输出**：`out_ready` 拉高当拍输出 MSB，窗口连续 24 周期。
3. **空闲输出**：`out_ready=0` 时 `sum_out=0`。
4. **mode 切换清零**：在输入阶段检测 mode 变化，清空累加状态与 carry。

### 4.2 多级流水/特殊结构注意点
- **多级流水（exp_k/l/m/o/p/q 等）**：输入与 `valid_in` 必须分离，避免“最后一位同拍触发”。
- **DCS/CSA/LLCBC 系列（exp_n/na/nc/ng/r/sd 等）**：`valid_in` 延后 1 拍最安全。
- **VMA/前缀加法器**：`out_ready` 与 `sum_out` 一致性优先于前缀结构细节。

### 4.3 若必须支持 gap（可选增强）
- 当前接口**无 input_valid**，严格支持 gap 需要额外协议（例如新增输入有效信号或固定“帧开始”标记）。
- 若不改接口，建议 TB 不插入 gap，或固定 gap=0 以满足“≤5”约束但不破坏位流。

---

## 5. 当前验证结果

- exp_a：通过 `tb_mac16.sv` 全部检查。
- exp_sd：通过 `tb_mac16.sv` 全部检查。

如需推进其他实验的适配，我可以按上述清单批量更新 RTL 并逐一跑 `verif`。
