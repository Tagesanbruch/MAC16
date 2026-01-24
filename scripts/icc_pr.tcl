# IC Compiler P&R Script
# Source using: icc_shell -f icc_pr.tcl

set DESIGN_NAME "mac16"
set LIB_NAME "mac16_lib"

# 1. Setup Libraries (Using logic from DC script)
# Need TLU+ files for RC extraction in ICC, assuming in PDK
# Assuming same PDK root structure
set PDK_ROOT "/work/mac/icsprout55-pdk"
set SEARCH_PATH "${PDK_ROOT}/IP/STD_cell/ics55_LLSC_H7C_V1p10C100/ics55_LLSC_H7CL/liberty"
set LINK_LIB "ics55_LLSC_H7CL_typ_tt_1p2_25_nldm.lib"
set LEF_FILE "${PDK_ROOT}/IP/STD_cell/ics55_LLSC_H7C_V1p10C100/ics55_LLSC_H7CL/lef/ics55_LLSC_H7CL_m4_9t.lef"
# Tech LEF?
set TECH_LEF_FILE "${PDK_ROOT}/IP/STD_cell/ics55_LLSC_H7C_V1p10C100/ics55_LLSC_H7CL/tech_lef/ics55_LLSC_H7CL_m4_9t_tech.lef"

set_app_var search_path ". $search_path $SEARCH_PATH"
set_app_var target_library $LINK_LIB
set_app_var link_library "* $LINK_LIB"

# 2. Optimization/Routing Layer config
# TLUPlus?
# set_tlu_plus_files ...

# 3. Design Init
# If MW Lib doesn't exist, create it
if {![file exists $LIB_NAME]} {
    create_mw_lib $LIB_NAME -technology $TECH_LEF_FILE -mw_reference_library {} -bus_naming_style {[%d]}
}
open_mw_lib $LIB_NAME

# Read Netlist (from synthesis dir)
read_verilog ../syn/${DESIGN_NAME}.netlist.v
link
read_sdc ../syn/${DESIGN_NAME}.sdc

# 4. Floorplan
# Core utilization 0.7
initialize_floorplan -control_type width_and_height -core_width 90 -core_height 90 -core_utilization 0.7

# 5. Place
place_opt

# 6. CTS
clock_opt

# 7. Route
route_opt

# 8. Output
write_verilog ./${DESIGN_NAME}_pr.v
write_stream -format gds -lib_name $LIB_NAME -output ./${DESIGN_NAME}.gds

exit
