# Equivalence Checking Script using Yosys
# Usage: yosys -c scripts/equiv_check.tcl

yosys -import

set DESIGN "mac16"
set RTL_FILE "rtl/mac16.sv"
# Note: Using the netlist from the latest synthesis run
# We need to pass the netlist path as an env var or argument, but for simplicity/robustness in Makefile, we'll use an env var
if {[info exists ::env(NETLIST)]} {
    set GATE_FILE $::env(NETLIST)
} else {
    puts "Error: NETLIST environment variable not set."
    exit 1
}

# 1. Read Gold (RTL)
read_verilog -sv $RTL_FILE
read_verilog -sv rtl/mult16.sv
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
