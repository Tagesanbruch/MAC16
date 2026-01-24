# Power Analysis Script
# Usage: iEDA scripts/power_analysis.tcl <PDK_ROOT> <NETLIST> <SDC_FILE> <CORNER>

if { $argc < 4 } {
    puts "Error: Usage: iEDA scripts/power_analysis.tcl <PDK_ROOT> <NETLIST> <SDC_FILE> <CORNER>"
    exit 1
}

set PDK_ROOT [lindex $argv 0]
set NETLIST [lindex $argv 1]
set SDC_FILE [lindex $argv 2]
set CORNER_SELECT [lindex $argv 3]

# Library Definitions
set LIB_TT "${PDK_ROOT}/IP/STD_cell/ics55_LLSC_H7C_V1p10C100/ics55_LLSC_H7CL/liberty/ics55_LLSC_H7CL_typ_tt_1p2_25_nldm.lib"
set LIB_SS "${PDK_ROOT}/IP/STD_cell/ics55_LLSC_H7C_V1p10C100/ics55_LLSC_H7CL/liberty/ics55_LLSC_H7CL_ss_rcworst_1p08_125_nldm.lib"

proc run_power {lib_path corner_name netlist sdc} {
    puts "\n======================================================="
    puts "Running Power Analysis for Corner: $corner_name"
    puts "Library: $lib_path"
    puts "=======================================================\n"

    read_liberty $lib_path
    read_netlist $netlist
    link_design "mac16"
    read_sdc $sdc
    
    set power_out_dir "syn/power_report_${corner_name}"
    file mkdir $power_out_dir
    set_design_workspace $power_out_dir 

    puts "Reporting Power..."
    if {[catch {report_power} errMsg]} {
        puts "Error running report_power: $errMsg"
    } else {
        puts "Power Report Generated."
    }
}

if {$CORNER_SELECT == "TT"} {
    run_power $LIB_TT "TT" $NETLIST $SDC_FILE
} elseif {$CORNER_SELECT == "SS"} {
    run_power $LIB_SS "SS" $NETLIST $SDC_FILE
} else {
    puts "Unknown corner: $CORNER_SELECT"
}
