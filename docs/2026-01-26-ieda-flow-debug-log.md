# iEDA P&R Flow 调试日志

## 日期：2026-01-26

## 问题记录

### 问题 1: `feature_summary` / `db_init` 导致 null string 崩溃 [已解决]

**错误信息**:
```
terminate called after throwing an instance of 'std::logic_error'
  what():  basic_string::_M_construct null not valid
```

**解决方案**: 设置必要的环境变量后，`flow_init` 和 `db_init` 可以正常工作

---

### 问题 2: `tapcell` 命令导致 null string 崩溃

**错误信息**:
```
terminate called after throwing an instance of 'std::logic_error'
  what():  basic_string::_M_construct null not valid
```

**发生位置**: 
```tcl
tapcell -tapcell "FILLTAPH7L" -distance 60
```

**可能原因**:
1. 缺少 `-endcap` 参数
2. 环境变量未设置
3. tapcell 内部逻辑问题

**临时解决方案**: 注释掉 tapcell 命令，跳过 tap cell 插入步骤

---

### 问题 3: Placement 时 SIGSEGV 段错误 [已解决]

**错误信息**:
```
E0126 08:51:40.941854     1 Log.cc:58]     @     0xaaaac6367560 ipl::IDBWrapper::wrapRoutingInfo()
*** SIGSEGV (@0x8) received by PID 1
```

**解决方案**: 添加完整的 routing track 定义，包括 T4M2 和 RDL 层
```tcl
gern_track -layer T4M2 -x_start 0 -x_step 800 -y_start 0 -y_step 800
gern_track -layer RDL -x_start 0 -x_step 5000 -y_start 0 -y_step 5000
```

---

### 问题 4: CTS 时 null string 崩溃

**错误信息**:
```
terminate called after throwing an instance of 'std::logic_error'
  what():  basic_string::_M_construct null not valid
  @     0xaaaac6e5034f tcl::CmdCTSAutoRun::exec()
```

**发生位置**: `run_cts` 命令

**可能原因**:
1. CTS 配置文件 (cts_default_config.json) 中有空值
2. 缺少 clock net 定义
3. iEDA CTS 模块内部 bug

**临时解决方案**: 跳过 CTS，使用 ideal clock 进行后续流程

---

### 问题 5: Routing 时 shape outside die 错误 [已解决]

**错误信息**:
```
Error makeObstacleList] This shape is outside the die!
```

**发生位置**: `run_rt` 命令内部

**原因**: PDN stripes 参数导致金属条超出 die 边界

**解决方案**: 禁用 PDN stripes，仅依赖标准单元的电源轨道

---

### 问题 6: Routing 时 "No access point was generated" 错误

**错误信息**:
```
[RT] Warn getBoundingBox] The coord list size is empty!
[RT] Error initAccessPointList] No access point was generated!
```

**发生位置**: `run_rt` → `PinAccessor.cpp:150`

**可能原因**:
1. iEDA 路由器无法识别标准单元 pin 位置
2. PDK LEF 文件中 PIN 定义可能与 iEDA 期望格式不兼容
3. 标准单元 pin 在 MET1 层，但 routing 从 MET2 开始，可能缺少 via 连接逻辑

**当前状态**: 
- Floorplan ✓
- Placement ✓ (2185 cells, 2.5s)
- Legalization ✓
- CTS 跳过
- Routing ✗

**临时解决方案**: 跳过 routing，使用 placement 结果
- 生成 DEF 文件用于面积评估
- 生成 Verilog 文件用于功能验证
- 无 SPEF，STA 使用 zero-wire-load 模型

---

### 问题 7: run_drc 导致 null string 崩溃

**错误信息**:
```
terminate called after throwing an instance of 'std::logic_error'
  what():  basic_string::_M_construct null not valid
  @     0xaaaad6272efb tcl::CmdDRCAutoRun::exec()
```

**发生位置**: `run_drc` 命令

**临时解决方案**: 跳过 DRC 检查

---

## P&R 流程完成状态

| 步骤 | 状态 | 备注 |
|------|------|------|
| Floorplan | ✓ | 100µm × 100µm die |
| PDN | ⚠ | Stripes 跳过，仅使用标准单元电源轨 |
| Tap Cell | ⚠ | 跳过 (crash) |
| Placement | ✓ | 2185 cells, 70.18% utilization |
| CTS | ⚠ | 跳过 (crash), 使用 ideal clock |
| Filler | ⚠ | 命令不存在 |
| Routing | ✗ | Pin access 问题 |
| DRC | ⚠ | 跳过 (crash) |

**输出文件**:
- DEF: `mac16.def` (placement-only)
- Verilog: `mac16_pr.v`
- SPEF: 无 (routing 未完成)

---

## 验证结果总结 (exp_d @ 1GHz)

### 时序分析 (STA)
| 指标 | 值 | 状态 |
|------|-----|------|
| 目标频率 | 1000 MHz | - |
| WNS (Setup) | +0.032 ns | ✓ |
| TNS | 0 ns | ✓ |
| 最高可达频率 | 1033 MHz | ✓ |

### 面积分析
| 指标 | 值 |
|------|-----|
| Cell 面积 | 5659.64 µm² |
| Die 面积 | 10000 µm² (100×100 µm) |
| Core Utilization | 70.18% |
| Cell 数量 | 2185 |
| 触发器数量 | 299 (287 DFFRQX2H7L + 2 DFFSQX2H7L + ICG) |
| 时序单元占比 | 39.77% |

### 功耗分析
| 指标 | 值 |
|------|-----|
| 总功耗 | 5.872 mW |
| 内部功耗 | 5.868 mW (99.93%) |
| 漏电功耗 | 4.304 µW (0.07%) |
| 时序逻辑功耗 | 4.684 mW (79.76%) |
| 组合逻辑功耗 | 1.188 mW (20.24%) |

---

## 配置文件清单

| 文件 | 状态 | 备注 |
|------|------|------|
| flow_config.json | ✓ | 使用绝对路径 /ysyx/mac/... |
| db_default_config.json | ✓ | 基本配置 |
| fp_default_config.json | ✓ | PDN 配置 |
| pl_default_config.json | ✓ | Placement 配置 |
| cts_default_config.json | ✓ | CTS 配置 |
| rt_default_config.json | ✓ | Routing 配置 |
| drc_default_config.json | ✓ | DRC 配置 |
| to_default_config.json | ✓ | Timing Opt 配置（新建） |
| pnp_default_config.json | ✓ | P&P 配置 |

## 参考信息

### Docker 路径映射
- Host `../yosys-sta` → Container `/work`
- Host `/Volumes/disk/work/ysyx/*` → Container `/ysyx/*`

### PDK 单元名称（从 LEF 确认）
- Tap Cell: `FILLTAPH7L`
- Filler Cells: `FILLER1H7L` ~ `FILLER64H7L`
- Tie Cells: `TIEHIH7L`, `TIELOH7L`
