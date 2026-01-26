# Equivalence Checking Script using Yosys
# Usage: yosys -c scripts/equiv_check.tcl

yosys -import

set DESIGN "mac16"

# ========================================================
# 0. 环境与路径配置
# ========================================================

# 设置 PDK Liberty 文件路径 (根据您的要求修改)
set PDK_LIB "../yosys-sta/pdk/icsprout55/IP/STD_cell/ics55_LLSC_H7C_V1p10C100/ics55_LLSC_H7CL/liberty/ics55_LLSC_H7CL_typ_tt_1p2_25_nldm.lib"

if {[info exists ::env(NETLIST)]} {
    set GATE_FILE $::env(NETLIST)
} else {
    puts "Error: NETLIST environment variable not set."
    exit 1
}

if {[info exists ::env(RTL_DIR)]} {
    set RTL_DIR $::env(RTL_DIR)
} else {
    set RTL_DIR "rtl"
}

puts "INFO: RTL_DIR = $RTL_DIR"
puts "INFO: GATE_FILE = $GATE_FILE"
puts "INFO: PDK_LIB = $PDK_LIB"

# ========================================================
# 1. 预定义缺失的复杂单元 (Stub / Blackbox Model)
# ========================================================
# 解决 ICGX0P5H7L 在 .lib 中可能无逻辑定义或 Verilog 中包含 UDP 的问题。
# 我们用 SystemVerilog 行为级描述来替代它。
# 依据您提供的 Verilog: input CK, E; output ECK;
# 这是一个 Latch-based Clock Gating。

read_verilog -sv - <<EOF
module ICGX0P5H7L (
    input  CK,
    input  E,
    output ECK
);
    reg enable_latch;
    
    // ICG 的行为：在时钟低电平时，如果 E 为高，锁存器变高。
    // 在时钟高电平时，锁存器保持。
    // 这防止了 E 在时钟高电平时变化导致 ECK 产生毛刺。
    // 对于形式化验证，我们需要一个干净的逻辑模型。
    
    always_latch begin
        if (!CK) begin
            enable_latch <= E;
        end
    end

    assign ECK = CK & enable_latch;

endmodule
EOF

# ========================================================
# 2. Read Gold (RTL)
# ========================================================
set rtl_files [glob -nocomplain -directory $RTL_DIR *.sv]
foreach rtl_file $rtl_files {
    if {[string match "*/tb_*.sv" $rtl_file]} { continue }
    read_verilog -sv $rtl_file
}

prep -top $DESIGN -flatten
async2sync
memory_map
opt -full
design -stash gold

# ========================================================
# 3. Read Gate (Netlist)
# ========================================================

# [关键步骤]
# 1. 读取 Liberty 文件，不加 -lib 选项，让 Yosys 解析逻辑功能。
# 2. -ignore_miss_func: 忽略那些没有 function 定义的单元(如 IO, Analog)，防止报错退出。
# 3. -overwrite: 如果刚才定义的 ICG 也在 lib 里，优先使用我们刚才定义的 Verilog 模型(因为它已经加载了)。
read_liberty -ignore_miss_func -ignore_miss_dir -overwrite $PDK_LIB

# 读取网表
read_verilog $GATE_FILE

# 准备 Gate 电路
prep -top $DESIGN -flatten
async2sync
design -stash gate

# ========================================================
# 4. Equivalence Check
# ========================================================
design -copy-from gold -as gold $DESIGN
design -copy-from gate -as gate $DESIGN

# 构建 miter 电路
equiv_make gold gate miter

# 优化层级
hierarchy -top miter
flatten

# 求解
equiv_simple
equiv_induct

# 断言验证
equiv_status -assert miter

puts "Equivalence Check Passed!"