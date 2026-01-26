# MAC16 验证流程完善计划

## 日期：2026-01-26

## 目标

基于 Plan.md 要求，完成 4/5/6/7/8 验证流程：

| 编号 | 验证项 | 当前状态 | 目标 |
|------|--------|----------|------|
| 4 | 形式验证（综合前后一致性） | 已有脚本 equiv_check.tcl | 确认可用 |
| 5 | 布局布线 + 3 PVT corner 时序 | P&R 脚本不完整 | 补全 PDN/CTS/SPEF |
| 6 | LVS 通过 + 3 PVT corner SPEF | 未做 | 导出 GDS/SPEF |
| 7 | 3 PVT corner STA 通过 | 仅 TT 单角 | 补全 SS/FF |
| 8 | 面积 ≤ 90um × 90um，金属层 M1~M5 | 未确认 | P&R 后验证 |

## PDK 单元信息（已确认）

从 `ics55_LLSC_H7CL.lef` 确认：
- **Tap Cell**: `FILLTAPH7L`
- **Filler Cells**: `FILLER1H7L`, `FILLER2H7L`, `FILLER4H7L`, `FILLER8H7L`, `FILLER16H7L`, `FILLER32H7L`, `FILLER64H7L`
- **Fill Cap Cells**: `FILLCAP4H7L`, `FILLCAP8H7L`, `FILLCAP16H7L`, `FILLCAP32H7L`
- **Tie Cells**: `TIEHIH7L`, `TIELOH7L`

金属层（从 tech LEF）：
- MET1: 水平, pitch 0.2um
- MET2: 垂直, pitch 0.2um  
- MET3-MET5: 交替方向

## 实施步骤

### 1. 更新 `ieda_flow.tcl` - 添加 PDN/CTS/SPEF

```tcl
# === PDN Section (在 Floorplan 之后，Placement 之前) ===
# 1. 插入 Tap Cells
tapcell -tapcell "FILLTAPH7L" -distance 60

# 2. 全局电源连接
global_net_connect -net_name VDD -instance_pin_name VDD -is_power 1
global_net_connect -net_name VSS -instance_pin_name VSS -is_power 0

# 3. 创建电源网格 (MET4/MET5)
create_stripe -layer_name "MET5" -net_name_power VDD -net_name_ground VSS -width 2.0 -pitch 40.0 -offset 10.0
create_stripe -layer_name "MET4" -net_name_power VDD -net_name_ground VSS -width 2.0 -pitch 40.0 -offset 10.0

# 4. 连接电源层
connect_two_layer -layers "MET4 MET5"
connect_two_layer -layers "MET1 MET4"

# === CTS Section (在 Placement 之后) ===
run_cts

# === Output Section ===
write_spef $SPEF_FILE
write_gds $GDS_FILE  # 如果支持
run_drc  # 如果支持
```

### 2. 更新 `sta_multicorner.tcl` - 读取 SPEF

```tcl
# 在 link_design 之后，read_sdc 之前
set spef_path [string map {".v" ".spef"} $NETLIST]
if {[file exists $spef_path]} {
    puts "Reading SPEF: $spef_path"
    readSpef $spef_path
    buildRCTree $spef_path 0
}
```

### 3. 更新 `iEDA.mk` - 添加验证目标

- `make pr_signoff EXP=exp_d` - 完整 P&R + 签核流程
- `make drc EXP=exp_d` - DRC 检查
- `make sta_post_pr EXP=exp_d` - Post-layout STA

### 4. 验证矩阵

| 实验 | Verif | Synth | Equiv | P&R | STA-TT | STA-SS | STA-FF | DRC |
|------|-------|-------|-------|-----|--------|--------|--------|-----|
| exp_d | ✅ | ✅ | ? | ? | ✅ | ? | ? | ? |
| exp_f | ✅ | ✅ | ? | ? | ⚠️ | ? | ? | ? |

## 执行顺序

1. 更新 `ieda_flow.tcl` 添加 PDN/CTS/SPEF 导出
2. 更新 `sta_multicorner.tcl` 支持 SPEF 读取
3. 更新 `iEDA.mk` 添加新目标
4. 对 exp_d 运行完整流程验证
5. 记录结果并调试

## 预期输出文件

```
syn/yosys-syn-exp_d-xxx/mac16-1000MHz/
├── mac16.netlist.v       # 综合网表
├── mac16.sdc             # 约束
└── pr/
    ├── mac16.def         # 布局布线结果
    ├── mac16_pr.v        # 后端网表
    ├── mac16.spef        # 寄生参数
    ├── mac16.gds         # GDSII (如支持)
    ├── drc.rpt           # DRC 报告
    └── sta_post_pr.rpt   # 后端 STA 报告
```
