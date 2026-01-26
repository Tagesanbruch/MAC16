# Equivalence Checking Script using Yosys
# Usage: yosys -c scripts/equiv_check.tcl
# Environment variables:
#   NETLIST: Path to synthesis netlist
#   RTL_DIR: Path to RTL source directory (default: rtl)

yosys -import

set DESIGN "mac16"

# Get environment variables
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

# 1. Read Gold (RTL) - read all .sv files from RTL_DIR
set rtl_files [glob -nocomplain -directory $RTL_DIR *.sv]
foreach rtl_file $rtl_files {
    # Skip testbench files
    if {[string match "*/tb_*.sv" $rtl_file]} {
        puts "Skipping testbench: $rtl_file"
        continue
    }
    puts "Reading RTL: $rtl_file"
    read_verilog -sv $rtl_file
}
prep -top $DESIGN -flatten
async2sync
memory_map
opt -full
design -stash gold

# 2. Read Gate (Netlist)
# We need to read the library first to understand cells
read_liberty -lib ../yosys-sta/pdk/icsprout55/IP/STD_cell/ics55_LLSC_H7C_V1p10C100/ics55_LLSC_H7CL/liberty/ics55_LLSC_H7CL_typ_tt_1p2_25_nldm.lib
read_verilog $GATE_FILE
prep -top $DESIGN -flatten
async2sync
design -stash gate

# 3. Equivalence Check
design -copy-from gold -as gold $DESIGN
design -copy-from gate -as gate $DESIGN

# Construct the miter circuit
equiv_make gold gate miter

# Reduce the miter
equiv_simple miter
equiv_induct miter

# Run the solver
equiv_status -assert miter

puts "Equivalence Check Passed!"
