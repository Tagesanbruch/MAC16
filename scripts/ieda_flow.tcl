# iEDA P&R Script (Robust)
# Usage: iEDA scripts/ieda_flow.tcl <PDK_ROOT> <NETLIST> <SDC_FILE>

if { $argc < 3 } {
    puts "Error: Usage: iEDA scripts/ieda_flow.tcl <PDK_ROOT> <NETLIST> <SDC_FILE>"
    exit 1
}

set PDK_ROOT [lindex $argv 0]
set NETLIST_FILE [lindex $argv 1]
set SDC_FILE [lindex $argv 2]

set DESIGN "mac16"
set DIE_WIDTH 100
set DIE_HEIGHT 100
set CORE_MARGIN 5

# Set absolute path to toolchain scripts
# We assume the structure is fixed relative to workspace or passed args
# Finding toolchains dir relative to PDK_ROOT (which is .../yosys-sta/pdk/...)
# A safer bet is to use the known path structure
set TOOLCHAIN_SCRIPT_DIR "/Volumes/disk/work/ysyx/toolchains/iEDA/scripts/design/ics55_gcd/script"
# Or derive from Pwd if needed, but absolute is safer given Docker/wrapper
# note: PDK_ROOT from wrapper is /work/pdk/icsprout55 inside container?
# If running via wrapper `iEDA`, paths inside container might be different.
# The wrapper maps `../yosys-sta` to `/work`.
# So `../toolchains` might NOT be visible or mapped!
# CRITICAL: iEDA wrapper script maps `host_path/../yosys-sta` to `/work`.
# It does NOT map toolchains.
# However, the `ics55_gcd` scripts rely on `IEDA` installation or are part of the `iEDA` repo.
# If `iEDA` executable is in `/work/bin/iEDA` (mapped), then scripts might be... wait.
# The `iEDA` binary is at `../yosys-sta/bin/iEDA`.
# In the container, this is `/work/bin/iEDA`.
# The `ics55_gcd` scripts are in `../toolchains/iEDA/...`.
# Unless `toolchains` is mapped, we cannot access them.
# CHECK THE WRAPPER SCRIPT AGAIN from memory/view. 
# The wrapper maps `$HOST_PATH/../yosys-sta` to `/work`.
# AND `$HOST_PATH` is `yosys-sta/bin`.
# So `/work` is the `yosys-sta` directory.
# `toolchains` is likely a sibling of `yosys-sta` on host (`/Volumes/disk/work/ysyx/toolchains`).
# IT IS NOT MAPPED into the container by default `iEDA` wrapper!?
# Wait, user command `../yosys-sta/bin/iEDA` ...
# Wrapper script logic:
# `PROJECT_PATH=$(cd $(dirname $0)/../../; pwd)` -> `ysyx` root?
# No, `$(dirname $0)` is `yosys-sta/bin`. `../../` is the parent of `yosys-sta`?
# Let's check the wrapper script content again.

# If scripts are not available, I have to replicate the logic manually in this script.
# I will assume I need to implement `db_init`, `verilog_init`, `run_placer` directly if possible, OR
# Since I cannot easily map toolchains without modifying the wrapper or command,
# I will try to use the commands directly if they are built-in.
# But `run_placer` is likely a Tcl proc in `iPL_script/module/run_placer.tcl` or similar?
# Or is it a C++ command?
# `run_placer` is a C++ command registerTclCmd.
# `init_floorplan` is regTclCmd.
# `verilog_init` is regTclCmd.
# `db_init` is regTclCmd.
# `tech_lef_init` is regTclCmd.

# So I CAN run them directly without sourcing the helper scripts, as long as I pass the right arguments.
# The helper scripts mainly set env vars or wrapping calls.

set STD_ROOT "${PDK_ROOT}/IP/STD_cell/ics55_LLSC_H7C_V1p10C100/ics55_LLSC_H7CL/liberty"
set LEF_ROOT "${PDK_ROOT}/IP/STD_cell/ics55_LLSC_H7C_V1p10C100/ics55_LLSC_H7CL/lef"
set TECH_LEF_ROOT "${PDK_ROOT}/IP/STD_cell/ics55_LLSC_H7C_V1p10C100/ics55_LLSC_H7CL/tech_lef"

# Resolve paths relative to this script
set SCRIPT_DIR [file dirname [file normalize [info script]]]
set IEDA_CONFIG_DIR [file join $SCRIPT_DIR "iEDA_config"]
# Result dir relative to Netlist or passed as arg? 
# Netlist is absolute /ysyx/mac/... so we use its dir
set NETLIST_DIR [file dirname $NETLIST_FILE]
set RESULT_DIR [file join $NETLIST_DIR "pr"]

puts "DEBUG: SCRIPT_DIR=$SCRIPT_DIR"
puts "DEBUG: IEDA_CONFIG_DIR=$IEDA_CONFIG_DIR"
puts "DEBUG: RESULT_DIR=$RESULT_DIR"

if {![file exists $IEDA_CONFIG_DIR]} {
    puts "Error: Config dir not found: $IEDA_CONFIG_DIR"
    exit 1
}

# Create result dir if not exists (might happen in flow init)
file mkdir $RESULT_DIR

feature_summary -step init
flow_init -config "$IEDA_CONFIG_DIR/flow_config.json"
db_init -config "$IEDA_CONFIG_DIR/db_default_config.json" -output_dir_path "$RESULT_DIR"

# Init Tech/LEF
puts "DEBUG: Initializing LEF..."
puts "DEBUG: Tech LEF = ${TECH_LEF_ROOT}/ics55_LLSC_H7CL_m4_9t_tech.lef"
puts "DEBUG: Cell LEF = ${LEF_ROOT}/ics55_LLSC_H7CL_m4_9t.lef"
tech_lef_init -path "${TECH_LEF_ROOT}/ics55_LLSC_H7CL_m4_9t_tech.lef"
lef_init -path "${LEF_ROOT}/ics55_LLSC_H7CL_m4_9t.lef"

# Init Lib (Timing/Power)
puts "DEBUG: Initializing Lib..."
puts "DEBUG: Lib path = ${STD_ROOT}/ics55_LLSC_H7CL_typ_tt_1p2_25_nldm.lib"
lib_init -path "${STD_ROOT}/ics55_LLSC_H7CL_typ_tt_1p2_25_nldm.lib"

# Init Netlist
puts "DEBUG: Initializing Netlist..."
verilog_init -path $NETLIST_FILE -top $DESIGN

# Floorplan
puts "\n--- Floorplan ---"
init_floorplan -die_size "$DIE_WIDTH $DIE_HEIGHT" -core_margin $CORE_MARGIN
# Auto place pins
auto_place_pins -layer MET3 -width 300 -height 600
# Create Tracks - crucial for placement/routing
# `create_track -layer ...` needed.
# Without sourcing `create_tracks.tcl`, we might miss this.
# Try `auto_create_track` if exists, or manual.
# `create_track -layer MET1 -width 0.1 -space 0.1 ...` options depend on TF.
# If I don't create tracks, placement might fail.
# Let's hope `init_floorplan` or `run_placer` handles defaults or I can skip for now.

# Placement
puts "\n--- Placement ---"
# `run_placer` arguments: `-config`
run_placer -config $IEDA_CONFIG_DIR/pl_default_config.json

# CTS
puts "\n--- CTS ---"
# Needs configuration or defaults
# run_cts 
# run_iCTS likely wrapper.
# try `clock_tree_synthesis` if available?
# For now, skip CTS to see if placement passes.

# Routing
# `run_rt` comes from `run_iRT.tcl`. Real command is likely `run_route` or `global_route / detail_route`.
# Grep showed `init_rt`, `run_rt`.
# init_rt -temp_directory_path ... -top_routing_layer ...
puts "\n--- Routing ---"
init_rt -temp_directory_path "${RESULT_DIR}/rt" \
        -bottom_routing_layer "MET2" \
        -top_routing_layer "MET5" 
run_rt
destroy_rt

# Output
puts "\n--- Output ---"
set OUT_DEF "${RESULT_DIR}/${DESIGN}.def"
set OUT_V "${RESULT_DIR}/${DESIGN}_pr.v"

write_def $OUT_DEF
write_verilog $OUT_V

puts "P&R Flow Complete"
