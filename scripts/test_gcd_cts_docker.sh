#!/bin/bash
# Test official GCD CTS in Docker
set -e

export PDK_DIR="/work/pdk/icsprout55"
export WORKSPACE="/work/iEDA/scripts/design/ics55_gcd"

cd $WORKSPACE

export TECH_LEF="${PDK_DIR}/prtech/techLEF/N551P6M_ieda.lef"
export LEF_STDCELL="${PDK_DIR}/IP/STD_cell/ics55_LLSC_H7C_V1p10C100/ics55_LLSC_H7CR/lef/ics55_LLSC_H7CR_ieda.lef ${PDK_DIR}/IP/STD_cell/ics55_LLSC_H7C_V1p10C100/ics55_LLSC_H7CL/lef/ics55_LLSC_H7CL_ieda.lef"
export LIB_STDCELL="${PDK_DIR}/IP/STD_cell/ics55_LLSC_H7C_V1p10C100/ics55_LLSC_H7CL/liberty/ics55_LLSC_H7CL_ss_rcworst_1p08_125_nldm.lib ${PDK_DIR}/IP/STD_cell/ics55_LLSC_H7C_V1p10C100/ics55_LLSC_H7CR/liberty/ics55_LLSC_H7CR_ss_rcworst_1p08_125_nldm.lib"
export TAPCELL="FILLTAPH7R"
export TAP_DISTANCE=58
export ENDCAP="FILLTAPH7R"
export TOP_NAME="gcd"
export CLK_PORT_NAME="clk"
export USE_FIXED_BBOX="False"
export CORE_UTIL=0.2

export RESULT_DIR="$WORKSPACE/result"
export IEDA_CONFIG_DIR="$WORKSPACE/iEDA_config"
export IEDA_TCL_SCRIPT_DIR="$WORKSPACE/script"
export TCL_SCRIPT_DIR="$WORKSPACE/script"
export DEF_DIR="$WORKSPACE/result"
export SDC_FILE="$WORKSPACE/default.sdc"
export NETLIST_FILE="$WORKSPACE/result/verilog/${TOP_NAME}_nl.v"

echo ">>> Running FP..."
iEDA -script $WORKSPACE/script/iFP_script/run_iFP.tcl

echo ">>> Running PL..."
iEDA -script $WORKSPACE/script/iPL_script/run_iPL.tcl

echo ">>> Running CTS..."
iEDA -script $WORKSPACE/script/iCTS_script/run_iCTS.tcl

echo "=== Done ==="
