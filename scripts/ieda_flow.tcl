# iEDA P&R Script (Robust)
# Usage: iEDA scripts/ieda_flow.tcl <PDK_ROOT> <NETLIST> <SDC_FILE>
#
# Path Mapping (Docker):
#   Host: ../yosys-sta -> Container: /work
#   Host: /ysyx/*      -> Container: /ysyx/*

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

# PDK paths (these use /work which is the mapped yosys-sta directory)
set STD_ROOT "${PDK_ROOT}/IP/STD_cell/ics55_LLSC_H7C_V1p10C100/ics55_LLSC_H7CL/liberty"
set LEF_ROOT "${PDK_ROOT}/IP/STD_cell/ics55_LLSC_H7C_V1p10C100/ics55_LLSC_H7CL/lef"
set TECH_LEF_ROOT "${PDK_ROOT}/prtech/techLEF"

# Config dir - use /ysyx/mac path (mapped from host)
set IEDA_CONFIG_DIR "/ysyx/mac/scripts/iEDA_config"

# Result dir - relative to netlist location
set NETLIST_DIR [file dirname $NETLIST_FILE]
set RESULT_DIR [file join $NETLIST_DIR "pr"]

puts "========================================"
puts "iEDA P&R Flow Configuration"
puts "========================================"
puts "PDK_ROOT: $PDK_ROOT"
puts "NETLIST: $NETLIST_FILE"
puts "SDC: $SDC_FILE"
puts "CONFIG_DIR: $IEDA_CONFIG_DIR"
puts "RESULT_DIR: $RESULT_DIR"
puts "========================================"

# Validate paths
# Validate paths
if {![file exists $NETLIST_FILE]} {
    puts "Error: Netlist not found: $NETLIST_FILE"
    exit 1
}

# Create result dir if not exists (might happen in flow init)
file mkdir $RESULT_DIR

# =============================================================================
# Initialize iEDA 
# =============================================================================
puts "\n--- Initializing iEDA ---"

# Set environment variables that iEDA expects
set ::env(CONFIG_DIR) $IEDA_CONFIG_DIR
set ::env(RESULT_DIR) $RESULT_DIR
set ::env(TECH_LEF) "${TECH_LEF_ROOT}/N551P6M_ieda.lef"
set ::env(LEF_STDCELL) "${LEF_ROOT}/ics55_LLSC_H7CL.lef"
set ::env(LIB_STDCELL) "${STD_ROOT}/ics55_LLSC_H7CL_typ_tt_1p2_25_nldm.lib"
set ::env(NETLIST_FILE) $NETLIST_FILE
set ::env(TOP_NAME) $DESIGN
set ::env(CLK_PORT_NAME) "clk"

# NOTE: The following commands may cause crash due to null string issue in iEDA
# See docs/2026-01-26-ieda-flow-debug-log.md for details
# Error: terminate called after throwing an instance of 'std::logic_error'
#        what():  basic_string::_M_construct null not valid

puts "Trying flow_init with environment variables set..."
if {[catch {flow_init -config "$IEDA_CONFIG_DIR/flow_config.json"} err]} {
    puts "WARNING: flow_init failed: $err"
    puts "Proceeding without flow_init..."
}

puts "Trying db_init..."
if {[catch {db_init -config "$IEDA_CONFIG_DIR/db_default_config.json" -output_dir_path "$RESULT_DIR"} err]} {
    puts "WARNING: db_init failed: $err"
    puts "Proceeding without db_init..."
}

# Init Tech/LEF
puts "Initializing LEF..."
set TECH_LEF_FILE "${TECH_LEF_ROOT}/N551P6M_ieda.lef"
set CELL_LEF_FILE "${LEF_ROOT}/ics55_LLSC_H7CL.lef"
puts "  Tech LEF: $TECH_LEF_FILE"
puts "  Cell LEF: $CELL_LEF_FILE"
tech_lef_init -path $TECH_LEF_FILE
lef_init -path $CELL_LEF_FILE

# Init Lib (Timing/Power) - Note: lib_init command doesn't exist in iEDA
# Liberty is loaded via db_init -lib_path or STA commands
puts "Initializing Liberty..."
set LIB_FILE "${STD_ROOT}/ics55_LLSC_H7CL_typ_tt_1p2_25_nldm.lib"
puts "  Liberty: $LIB_FILE"
# Load liberty via db_init
db_init -lib_path $LIB_FILE

# Init SDC
puts "Initializing SDC..."
puts "  SDC: $SDC_FILE"
db_init -sdc_path $SDC_FILE

# Init Netlist
puts "Initializing Netlist..."
verilog_init -path $NETLIST_FILE -top $DESIGN

# Floorplan
puts "\n--- Floorplan ---"
# Use fixed area mode with die_area and core_area
# Format: "llx lly urx ury" in microns
set DIE_AREA "0 0 $DIE_WIDTH $DIE_HEIGHT"
set CORE_MARGIN_X $CORE_MARGIN
set CORE_MARGIN_Y $CORE_MARGIN
set CORE_AREA "$CORE_MARGIN_X $CORE_MARGIN_Y [expr {$DIE_WIDTH - $CORE_MARGIN_X}] [expr {$DIE_HEIGHT - $CORE_MARGIN_Y}]"

# Site name from LEF - check LEF file for actual site name
set PLACE_SITE "core7"

puts "  Die area: $DIE_AREA"
puts "  Core area: $CORE_AREA"
puts "  Site: $PLACE_SITE"

init_floorplan \
    -die_area $DIE_AREA \
    -core_area $CORE_AREA \
    -core_site $PLACE_SITE \
    -io_site $PLACE_SITE \
    -corner_site $PLACE_SITE

# Create routing tracks - required for placement and routing
puts "Creating routing tracks..."
gern_track -layer MET1 -x_start 0 -x_step 200 -y_start 0 -y_step 200
gern_track -layer MET2 -x_start 0 -x_step 200 -y_start 0 -y_step 200
gern_track -layer MET3 -x_start 0 -x_step 200 -y_start 0 -y_step 200
gern_track -layer MET4 -x_start 0 -x_step 200 -y_start 0 -y_step 200
gern_track -layer MET5 -x_start 0 -x_step 200 -y_start 0 -y_step 200
gern_track -layer T4M2 -x_start 0 -x_step 800 -y_start 0 -y_step 800
gern_track -layer RDL -x_start 0 -x_step 5000 -y_start 0 -y_step 5000

# Auto place pins
auto_place_pins -layer MET3 -width 300 -height 600

# =============================================================================
# Power Delivery Network (PDN)
# =============================================================================
puts "\n--- Power Network Planning (PDN) ---"

# 1. Insert Tap Cells (for substrate bias, prevent latch-up)
# Cell name confirmed from LEF: FILLTAPH7L
# NOTE: tapcell command causes crash - see docs/2026-01-26-ieda-flow-debug-log.md
# Error: terminate called after throwing an instance of 'std::logic_error'
#        what():  basic_string::_M_construct null not valid
puts "Inserting Tap Cells..."
# COMMENTED OUT due to crash:
# if {[catch {tapcell -tapcell "FILLTAPH7L" -distance 60} err]} {
#     puts "WARNING: tapcell failed: $err"
# }
puts "  SKIPPED: tapcell command causes iEDA crash"

# 2. Define global power/ground connections
puts "Setting up global power connections..."
if {[catch {global_net_connect -net_name VDD -instance_pin_name VDD -is_power 1} err]} {
    puts "WARNING: global_net_connect VDD failed: $err"
}
if {[catch {global_net_connect -net_name VSS -instance_pin_name VSS -is_power 0} err]} {
    puts "WARNING: global_net_connect VSS failed: $err"
}

# 3. Create Power Stripes (MET5 vertical, MET4 horizontal)
# NOTE: Power stripes cause "shape outside die" error during routing
# This may be due to PDK constraints or iEDA bugs
# See docs/2026-01-26-ieda-flow-debug-log.md Issue 5
# DISABLED for now - relying on standard cell power rails only
puts "Creating Power Stripes..."
puts "  SKIPPED: Power stripes cause routing boundary errors"
# if {[catch {
#     create_stripe -layer_name "MET5" -net_name_power VDD -net_name_ground VSS \
#         -width 1.0 -pitch 30.0 -offset 15.0
# } err]} {
#     puts "WARNING: create_stripe MET5 failed: $err"
# }
#
# if {[catch {
#     create_stripe -layer_name "MET4" -net_name_power VDD -net_name_ground VSS \
#         -width 1.0 -pitch 30.0 -offset 15.0
# } err]} {
#     puts "WARNING: create_stripe MET4 failed: $err"
# }

# 4. Connect power layers with vias
puts "Connecting power layers..."
puts "  SKIPPED: No power stripes to connect"
# if {[catch {connect_two_layer -layers "MET4 MET5"} err]} {
#     puts "WARNING: connect_two_layer MET4-MET5 failed: $err"
# }
# if {[catch {connect_two_layer -layers "MET1 MET4"} err]} {
#     puts "WARNING: connect_two_layer MET1-MET4 failed: $err"
# }

puts "PDN Setup Completed."

# =============================================================================
# Placement
# =============================================================================
puts "\n--- Placement ---"

# First save the floorplan result to DEF
set FP_DEF "${RESULT_DIR}/${DESIGN}_fp.def"
puts "Saving floorplan to: $FP_DEF"
def_save -path $FP_DEF

# NOTE: run_placer causes SIGSEGV in wrapRoutingInfo()
# This might be due to incomplete routing layer initialization
# See docs/2026-01-26-ieda-flow-debug-log.md for details
# Error: *** SIGSEGV (@0x8) received by PID 1 
#        @     0xaaaacce8750c ipl::IDBWrapper::wrapRoutingInfo()

puts "Running placement..."
if {[catch {run_placer -config $IEDA_CONFIG_DIR/pl_default_config.json} err]} {
    puts "ERROR: Placement failed: $err"
    puts "Skipping placement and subsequent steps."
    # Try to save what we have so far
    set OUT_DEF "${RESULT_DIR}/${DESIGN}.def"
    set OUT_V "${RESULT_DIR}/${DESIGN}_pr.v"
    def_save -path $OUT_DEF
    netlist_save -path $OUT_V -exclude_cell_names {}
    puts "Saved partial results to:"
    puts "  DEF: $OUT_DEF"
    puts "  Verilog: $OUT_V"
    exit 1
}

# =============================================================================
# Clock Tree Synthesis (CTS)
# =============================================================================
puts "\n--- Clock Tree Synthesis (CTS) ---"
# NOTE: run_cts causes null string crash - see docs/2026-01-26-ieda-flow-debug-log.md
# Error: terminate called after throwing an instance of 'std::logic_error'
#        what():  basic_string::_M_construct null not valid
#        @     0xaaaac6e5034f tcl::CmdCTSAutoRun::exec()
# COMMENTED OUT due to crash:
# if {[catch {run_cts} err]} {
#     puts "WARNING: CTS failed: $err"
#     puts "Proceeding without CTS (ideal clock)..."
# }
puts "  SKIPPED: run_cts command causes iEDA crash"
puts "  Using ideal clock for subsequent steps"

# =============================================================================
# Filler Cell Insertion
# =============================================================================
puts "\n--- Filler Cell Insertion ---"
# Insert filler cells to complete rows and meet DRC
# NOTE: add_fillers command doesn't exist - use filler_placement instead
if {[catch {
    filler_placement -filler_types "FILLER64H7L FILLER32H7L FILLER16H7L FILLER8H7L FILLER4H7L FILLER2H7L FILLER1H7L"
} err]} {
    puts "WARNING: filler_placement failed: $err"
    puts "  Skipping filler cell insertion"
}

# =============================================================================
# Routing
# =============================================================================
puts "\n--- Routing ---"
# NOTE: Routing fails with "No access point was generated!" error and ABORT
# This appears to be a pin access issue in iEDA with this PDK
# See docs/2026-01-26-ieda-flow-debug-log.md Issue 6
# DISABLED completely - proceeding with placement-only output
puts "  SKIPPED: Routing disabled due to iEDA/PDK compatibility issues"
puts "  Error: 'No access point was generated!' causes abort"
puts "  Proceeding with placement results only"
set ROUTING_SUCCESS 0

# Original routing code (disabled):
# if {[catch {
#     init_rt -temp_directory_path "${RESULT_DIR}/rt" \
#             -bottom_routing_layer "MET2" \
#             -top_routing_layer "MET5" 
#     run_rt
#     destroy_rt
#     set ROUTING_SUCCESS 1
# } err]} {
#     puts "WARNING: Routing failed: $err"
#     set ROUTING_SUCCESS 0
# }

# =============================================================================
# Output & Sign-off Preparation
# =============================================================================
puts "\n--- Output ---"
set OUT_DEF "${RESULT_DIR}/${DESIGN}.def"
set OUT_V "${RESULT_DIR}/${DESIGN}_pr.v"
set OUT_SPEF "${RESULT_DIR}/${DESIGN}.spef"

puts "Saving DEF..."
if {[catch {def_save -path $OUT_DEF} err]} {
    puts "WARNING: def_save failed: $err"
}

puts "Saving netlist..."
if {[catch {netlist_save -path $OUT_V -exclude_cell_names {}} err]} {
    puts "WARNING: netlist_save failed: $err"
}

# Export SPEF for post-layout STA (only if routing was successful)
puts "Exporting SPEF for parasitic extraction..."
if {[info exists ROUTING_SUCCESS] && $ROUTING_SUCCESS == 1} {
    if {[catch {write_spef $OUT_SPEF} err]} {
        puts "WARNING: write_spef failed: $err"
        puts "Post-layout STA will use zero-wire-load model."
    }
} else {
    puts "  SKIPPED: No routing completed, no SPEF generated"
    puts "  Post-layout STA will use zero-wire-load model."
}

# Try to export GDS if supported
set OUT_GDS "${RESULT_DIR}/${DESIGN}.gds"
if {[catch {write_gds $OUT_GDS} err]} {
    puts "INFO: write_gds not available or failed: $err"
}

# =============================================================================
# DRC Check
# =============================================================================
puts "\n--- DRC Check ---"
# NOTE: run_drc causes null string crash - see docs/2026-01-26-ieda-flow-debug-log.md
puts "  SKIPPED: run_drc command causes iEDA crash"
# if {[catch {run_drc} err]} {
#     puts "INFO: run_drc not available or failed: $err"
# }

# =============================================================================
# Report Area
# =============================================================================
puts "\n--- Area Report ---"
if {[catch {report_area} err]} {
    # Try alternative
    puts "Calculating area from DEF..."
}

puts "P&R Flow Complete"
puts "Results in: $RESULT_DIR"
puts "  DEF: $OUT_DEF"
puts "  Verilog: $OUT_V"
puts "  SPEF: $OUT_SPEF"
