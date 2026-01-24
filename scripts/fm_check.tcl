# Formality Script
# Source using: fm_shell -f fm_check.tcl

set DESIGN_NAME "mac16"

# 1. Libs
set PDK_ROOT "/work/mac/icsprout55-pdk"
set LIB_PATH "${PDK_ROOT}/IP/STD_cell/ics55_LLSC_H7C_V1p10C100/ics55_LLSC_H7CL/liberty/ics55_LLSC_H7CL_typ_tt_1p2_25_nldm.lib"

read_db $LIB_PATH

# 2. Reference (RTL)
read_sverilog -r [glob ../rtl/*.sv]
set_top r:/WORK/${DESIGN_NAME}

# 3. Implementation (Netlist)
# Read netlist from Syn dir
read_verilog -i ../syn/${DESIGN_NAME}.netlist.v
set_top i:/WORK/${DESIGN_NAME}

# 4. Verify
match
verify

save_session -replace ./session
report_failing_points > ./failing.rpt
report_status > ./status.rpt

exit
