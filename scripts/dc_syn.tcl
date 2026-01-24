# Design Compiler Synthesis Script for mac16
# Source using: dc_shell -f dc_syn.tcl

set DESIGN_NAME "mac16"
set CLK_PERIOD 1.0  ;# 1GHz

# 1. Setup Libraries
# NOTE: User needs to confirm PDK path in Docker.
# Assuming typical Synopsys 32/28nm Lab generic libs or user provided PDK.
# Since user said "pdk我可在那里手动git clone", we assume PDK at /work/pdk??
# Or we use generic libs if just testing flow.
# Let's assume a variable for PDK_ROOT, default to something.
if {[info exists ::env(PDK_ROOT)]} {
    set PDK_ROOT $::env(PDK_ROOT)
} else {
    set PDK_ROOT "/work/mac/icsprout55-pdk"
}

# Search Path
set_app_var search_path ". $search_path ${PDK_ROOT}/IP/STD_cell/ics55_LLSC_H7C_V1p10C100/ics55_LLSC_H7CL/liberty"

# Target Library (TT)
set_app_var target_library "ics55_LLSC_H7CL_typ_tt_1p2_25_nldm.lib"
set_app_var link_library "* $target_library"

# 2. Read Design
define_design_lib WORK -path ./work
analyze -format sverilog [glob ../rtl/*.sv]
elaborate $DESIGN_NAME

# 3. Constraints
create_clock -name "clk" -period $CLK_PERIOD [get_ports clk]
set_input_delay -max [expr $CLK_PERIOD * 0.2] -clock clk [remove_from_collection [all_inputs] clk]
set_output_delay -max [expr $CLK_PERIOD * 0.2] -clock clk [all_outputs]
set_clock_uncertainty 0.05 [get_clocks clk]

# 4. Compile
# High effort for timing
compile_ultra

# 5. Reports
check_design > ./check_design.rpt
report_timing > ./timing.rpt
report_area > ./area.rpt
report_power > ./power.rpt

# 6. Output
write -format ddc -hierarchy -output ./${DESIGN_NAME}.ddc
write -format verilog -hierarchy -output ./${DESIGN_NAME}.netlist.v
write_sdc ./${DESIGN_NAME}.sdc

exit
