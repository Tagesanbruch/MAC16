# Multi-Corner STA Script
# Usage: iEDA script.tcl <PDK_ROOT> <NETLIST> <SDC_FILE>

if { $argc < 3 } {
    puts "Error: Usage: iEDA sta_multicorner.tcl <PDK_ROOT> <NETLIST> <SDC_FILE>"
    exit 1
}

set PDK_ROOT [lindex $argv 0]
set NETLIST [lindex $argv 1]
set SDC_FILE [lindex $argv 2]

puts "PDK_ROOT: $PDK_ROOT"
puts "NETLIST:  $NETLIST"
puts "SDC_FILE: $SDC_FILE"

set DESIGN "mac16"
set FREQ_MHZ 1000
set CLK_PORT "clk"
set IO_PCT 0.2

# Define Lib Paths based on PDK_ROOT
# Note: PDK_ROOT passed from wrapper should be /work/pdk/icsprout55 (if host was yosys-sta/pdk/icsprout55)
set STD_ROOT "${PDK_ROOT}/IP/STD_cell/ics55_LLSC_H7C_V1p10C100/ics55_LLSC_H7CL/liberty"

set LIB_TT "${STD_ROOT}/ics55_LLSC_H7CL_typ_tt_1p2_25_nldm.lib"
set LIB_SS "${STD_ROOT}/ics55_LLSC_H7CL_ss_rcworst_1p08_125_nldm.lib"
set LIB_FF "${STD_ROOT}/ics55_LLSC_H7CL_ff_rcbest_1p32_m40_nldm.lib"

set TARGET_CORNER "ALL"
if { $argc >= 4 } {
    set TARGET_CORNER [lindex $argv 3]
    puts "Running Single Corner: $TARGET_CORNER"
}

proc run_sta {corner lib_path} {
    global DESIGN NETLIST SDC_FILE CLK_PORT FREQ_MHZ
    
    if {![file exists $lib_path]} {
        puts "\n\[WARN\] Library for $corner not found: $lib_path. Skipping."
        return
    }

    puts "\n======================================================="
    puts "Running STA for Corner: $corner"
    puts "Library: $lib_path"
    puts "=======================================================\n"
    
    # 1. Read Lib
    read_liberty $lib_path
    
    # 2. Read Netlist
    read_netlist $NETLIST
    
    # 3. Link
    link_design $DESIGN
    
    # 4. SDC
    read_sdc $SDC_FILE
    
    # 5. Report
    set out_dir [file dirname $NETLIST]
    set rpt_file "${out_dir}/sta_${corner}.rpt" 

    # Set workspace for iEDA reports
    set_design_workspace $out_dir
    
    puts "\n--- Report Timing (Max/Setup) ---"
    report_timing -delay_type max -max_path 5
    
    puts "\n--- Report Timing (Min/Hold) ---"
    report_timing -delay_type min -max_path 5
    
    puts "Finished STA for $corner"
}

if {$TARGET_CORNER == "ALL" || $TARGET_CORNER == "TT"} {
    run_sta "TT" $LIB_TT
}
if {$TARGET_CORNER == "ALL" || $TARGET_CORNER == "SS"} {
    run_sta "SS" $LIB_SS
}
if {$TARGET_CORNER == "ALL" || $TARGET_CORNER == "FF"} {
    # Try FF
    if {$TARGET_CORNER == "FF"} {
         # If explicitly requested, run it (will warn if missing)
         run_sta "FF" $LIB_FF
    } else {
        # logic for ALL - try to run if exists? Or just run and let it warn
         run_sta "FF" $LIB_FF
    }
}

exit
