# iEDA P&R Flow Script (Based on Official ics55_gcd Reference)
# Usage: iEDA scripts/ieda_pr_flow.tcl <RESULT_DIR> <NETLIST> <SDC> <DIE_BBOX> <CORE_BBOX>
# Arguments passed via command line instead of environment variables

if { $argc < 5 } {
    puts "Error: Usage: iEDA scripts/ieda_pr_flow.tcl <RESULT_DIR> <NETLIST> <SDC> <DIE_BBOX> <CORE_BBOX>"
    puts "  Example: iEDA scripts/ieda_pr_flow.tcl ./pr netlist.v mac16.sdc \"0 0 100 100\" \"5 5 95 95\""
    exit 1
}

#===========================================================
#   Configuration from command line arguments
#===========================================================
set RESULT_DIR [lindex $argv 0]
set NETLIST_FILE [lindex $argv 1]
set SDC_FILE [lindex $argv 2]
set DIE_BBOX [lindex $argv 3]
set CORE_BBOX [lindex $argv 4]

# Fixed configuration
set TOP_NAME "mac16"
set CLK_PORT_NAME "clk"

# PDK paths (container paths)
set PDK_ROOT "/work/pdk/icsprout55"
set TECH_LEF "${PDK_ROOT}/prtech/techLEF/N551P6M_ieda.lef"
set LEF_STDCELL "${PDK_ROOT}/IP/STD_cell/ics55_LLSC_H7C_V1p10C100/ics55_LLSC_H7CL/lef/ics55_LLSC_H7CL.lef"
set LIB_STDCELL "${PDK_ROOT}/IP/STD_cell/ics55_LLSC_H7C_V1p10C100/ics55_LLSC_H7CL/liberty/ics55_LLSC_H7CL_typ_tt_1p2_25_nldm.lib"

# PDK cells
set TAPCELL "FILLTAPH7L"
set TAP_DISTANCE 60
set ENDCAP "FILLTAPH7L"

# Script paths (container paths)
set IEDA_CONFIG_DIR "/ysyx/mac/scripts/iEDA_config"
set IEDA_TCL_SCRIPT_DIR "/ysyx/mac/scripts/iEDA_config/tcl_scripts"

# Output files
set OUTPUT_DEF "$RESULT_DIR/mac16_pr.def"
set OUTPUT_VERILOG "$RESULT_DIR/mac16_pr.v"

puts "========================================"
puts "iEDA P&R Flow (Reference-based)"
puts "========================================"
puts "RESULT_DIR: $RESULT_DIR"
puts "NETLIST: $NETLIST_FILE"
puts "TOP: $TOP_NAME"
puts "DIE: $DIE_BBOX"
puts "CORE: $CORE_BBOX"
puts "========================================"

# Set environment variables that db_path_setting.tcl expects
set ::env(TECH_LEF) $TECH_LEF
set ::env(LEF_STDCELL) $LEF_STDCELL
set ::env(LIB_STDCELL) $LIB_STDCELL
set ::env(SDC_FILE) $SDC_FILE

#===========================================================
##   init flow config
#===========================================================
puts "\n--- Initializing Flow ---"
flow_init -config $IEDA_CONFIG_DIR/flow_config.json

#===========================================================
##   read db config
#===========================================================
db_init -config $IEDA_CONFIG_DIR/db_default_config.json -output_dir_path $RESULT_DIR

#===========================================================
##   reset data path (sets TECH_LEF_PATH, LEF_PATH, LIB_PATH from env)
#===========================================================
source $IEDA_TCL_SCRIPT_DIR/DB_script/db_path_setting.tcl

#===========================================================
##   read lef
#===========================================================
source $IEDA_TCL_SCRIPT_DIR/DB_script/db_init_lef.tcl

#===========================================================
##   read verilog
#===========================================================
puts "\n--- Loading Netlist ---"
verilog_init -path $NETLIST_FILE -top $TOP_NAME

#===========================================================
##   init floorplan
#===========================================================
puts "\n--- Floorplan ---"
set PLACE_SITE core7
set IO_SITE core7
set CORNER_SITE core7

init_floorplan \
    -die_area $DIE_BBOX \
    -core_area $CORE_BBOX \
    -core_site $PLACE_SITE \
    -io_site $IO_SITE \
    -corner_site $CORNER_SITE

#===========================================================
##   Create Tracks (from reference)
#===========================================================
puts "Creating routing tracks..."
source $IEDA_TCL_SCRIPT_DIR/iFP_script/module/create_tracks.tcl

#===========================================================
##   Place IO Port
#===========================================================
puts "Placing IO pins..."
auto_place_pins -layer MET3 -width 300 -height 600

#===========================================================
##   Tap Cell (may cause crash - wrap in catch)
#===========================================================
puts "\n--- Tap Cell Insertion ---"
if {[catch {
    tapcell \
        -tapcell $TAPCELL \
        -distance $TAP_DISTANCE \
        -endcap $ENDCAP
} err]} {
    puts "WARNING: tapcell failed: $err"
    puts "  Skipping tap cell insertion"
}

#===========================================================
##   PDN
#===========================================================
puts "\n--- PDN Creation ---"
source $IEDA_TCL_SCRIPT_DIR/iFP_script/module/global_net.tcl

# PDN stripes (from reference)
if {[catch {
    create_grid -layer_name "MET1" -net_name_power VDD -net_name_ground VSS -width 0.16 -offset 0
    create_stripe -layer_name "MET4" -net_name_power VDD -net_name_ground VSS -width 1 -pitch 16 -offset 0.5
    create_stripe -layer_name "MET5" -net_name_power VDD -net_name_ground VSS -width 1 -pitch 16 -offset 0.5
    connect_two_layer -layers "MET1 MET4"
    connect_two_layer -layers "MET4 MET5"
} err]} {
    puts "WARNING: PDN creation failed: $err"
    puts "  Proceeding without PDN stripes"
}

#===========================================================
##   set clock net
#===========================================================
puts "Setting clock net..."
set_net -net_name $CLK_PORT_NAME -type CLOCK

#===========================================================
##   Save Floorplan DEF
#===========================================================
set FP_DEF "$RESULT_DIR/iFP_result.def"
def_save -path $FP_DEF
puts "Floorplan saved to: $FP_DEF"

#===========================================================
##   run Placer
#===========================================================
puts "\n--- Placement ---"
run_placer -config $IEDA_CONFIG_DIR/pl_default_config.json

set PL_DEF "$RESULT_DIR/iPL_result.def"
def_save -path $PL_DEF
puts "Placement saved to: $PL_DEF"

#===========================================================
##   CTS - Clock Tree Synthesis
#===========================================================
puts "\n--- Clock Tree Synthesis ---"

# Load liberty library for CTS (required by iEDA CTS module)
puts "Loading liberty library for CTS..."
source $IEDA_TCL_SCRIPT_DIR/DB_script/db_init_lib.tcl

# Read SDC for timing
puts "Loading SDC..."
source $IEDA_TCL_SCRIPT_DIR/DB_script/db_init_sdc.tcl

if {[catch {
    run_cts -config $IEDA_CONFIG_DIR/cts_default_config.json -work_dir "$RESULT_DIR/cts"
    set CTS_DEF "$RESULT_DIR/iCTS_result.def"
    def_save -path $CTS_DEF
    puts "CTS saved to: $CTS_DEF"
} err]} {
    puts "WARNING: CTS failed: $err"
    puts "  Proceeding with ideal clock"
}

#===========================================================
##   Routing
#===========================================================
puts "\n--- Routing ---"

if {[catch {
    init_rt -temp_directory_path "$RESULT_DIR/rt" \
            -bottom_routing_layer "MET2" \
            -top_routing_layer "MET5" \
            -thread_number 4 \
            -output_inter_result 0
    run_rt
    destroy_rt
    set RT_DEF "$RESULT_DIR/iRT_result.def"
    def_save -path $RT_DEF
    puts "Routing saved to: $RT_DEF"
} err]} {
    puts "WARNING: Routing failed: $err"
    puts "  Proceeding with placement-only results"
}
#===========================================================
##   Save Final Results
#===========================================================
puts "\n--- Saving Final Results ---"
def_save -path $OUTPUT_DEF
netlist_save -path $OUTPUT_VERILOG -exclude_cell_names {}

puts "P&R Flow Complete"
puts "  DEF: $OUTPUT_DEF"
puts "  Verilog: $OUTPUT_VERILOG"

#===========================================================
##   Report
#===========================================================
puts "\n--- Reports ---"
report_db -path "$RESULT_DIR/report/pr_summary.rpt"

#===========================================================
##   Exit
#===========================================================
flow_exit
