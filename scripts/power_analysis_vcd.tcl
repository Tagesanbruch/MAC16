# Power Analysis Script with VCD Support
# Usage: iEDA scripts/power_analysis_vcd.tcl <PDK_ROOT> <NETLIST> <SDC_FILE> <VCD_FILE> <TOP_INSTANCE>

if { $argc < 5 } {
    puts "Error: Usage: iEDA scripts/power_analysis_vcd.tcl <PDK_ROOT> <NETLIST> <SDC_FILE> <VCD_FILE> <TOP_INSTANCE>"
    puts "  Example: iEDA power_analysis_vcd.tcl /work/pdk netlist.v mac16.sdc tb_mac16.vcd tb_mac16/dut"
    exit 1
}

set PDK_ROOT [lindex $argv 0]
set NETLIST [lindex $argv 1]
set SDC_FILE [lindex $argv 2]
set VCD_FILE [lindex $argv 3]
set TOP_INSTANCE [lindex $argv 4]

# Library Definition (TT corner for power analysis)
set LIB_TT "${PDK_ROOT}/IP/STD_cell/ics55_LLSC_H7C_V1p10C100/ics55_LLSC_H7CL/liberty/ics55_LLSC_H7CL_typ_tt_1p2_25_nldm.lib"

puts "\n======================================================="
puts "Power Analysis with VCD"
puts "======================================================="
puts "Netlist:      $NETLIST"
puts "SDC:          $SDC_FILE"
puts "VCD:          $VCD_FILE"
puts "Top Instance: $TOP_INSTANCE"
puts "Library:      $LIB_TT"
puts "=======================================================\n"

# Read design
read_liberty $LIB_TT
read_netlist $NETLIST
link_design "mac16"
read_sdc $SDC_FILE

# Read VCD for switching activity
puts "Reading VCD file for switching activity..."
if {[catch {read_vcd $VCD_FILE $TOP_INSTANCE} errMsg]} {
    puts "Warning: read_vcd failed: $errMsg"
    puts "Falling back to static toggle rate..."
    # Fallback to default toggle
    report_power -toggle 0.1
} else {
    puts "VCD loaded successfully."
    # Report power with actual switching activity
    report_power
}

puts "\n=== Power Analysis Complete ===\n"
