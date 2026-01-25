# Unified Makefile for MAC16 Project
# Supported FLOWs:
#   - ieda (default): Runs open-source flow locally.
#   - synopsys: Runs commercial flow on remote server.
#
# Usage:
#   make [FLOW=ieda|synopsys] <target>

FLOW ?= ieda

# --- Project Configuration ---
DESIGN = mac16
CLK_FREQ_MHZ = 1000
CLK_PORT_NAME = clk

# --- Local Directories ---
BUILD_DIR = ./build
SYN_DIR_ROOT = ./syn
LOG_DIR = ./logs
RTL_DIR = ./rtl
VERIF_DIR = ./verif

$(shell mkdir -p $(BUILD_DIR) $(SYN_DIR_ROOT) $(LOG_DIR))

# --- Verification & Archiving Helpers ---
# Generates a timestamped archive directory
TIMESTAMP = $(shell date "+%Y-%m-%d_%H-%M-%S")
ARCHIVE_DIR = $(SYN_DIR_ROOT)/yosys-syn-$(TIMESTAMP)

# Pre-Synthesis Verification Check
# This logic runs before synthesis. It runs verification, and if successful,
# creates an archive directory and copies relevant files.
pre_syn_check:
	@echo "Running Pre-Synthesis Verification..."
	@mkdir -p $(BUILD_DIR)
	# Generate Filelist (Temporary for Sim compilation)
	@find $(RTL_DIR) -name "*.sv" -o -name "*.v" > $(BUILD_DIR)/filelist.f
	@find $(VERIF_DIR) -name "*.sv" -o -name "*.v" >> $(BUILD_DIR)/filelist.f
	
	# Compile and Run Simulation
	iverilog -g2012 -o $(BUILD_DIR)/tb_mac16.vvp -I $(RTL_DIR) -I $(VERIF_DIR) \
		$(shell find $(RTL_DIR) -name '*.sv') $(VERIF_DIR)/tb_mac16.sv
	vvp $(BUILD_DIR)/tb_mac16.vvp | tee $(BUILD_DIR)/sim_pre_syn.log
	
	@if grep -q "Simulation Passed" $(BUILD_DIR)/sim_pre_syn.log; then \
		echo "\033[0;32m[VERIF] Pre-Synthesis Simulation Passed!\033[0m"; \
		echo "Archiving to $(ARCHIVE_DIR)..."; \
		mkdir -p $(ARCHIVE_DIR); \
		cp $(BUILD_DIR)/sim_pre_syn.log $(ARCHIVE_DIR)/verif.log; \
		cp -r $(RTL_DIR) $(ARCHIVE_DIR)/rtl; \
		cp -r $(VERIF_DIR) $(ARCHIVE_DIR)/verif; \
		cp $(BUILD_DIR)/filelist.f $(ARCHIVE_DIR)/; \
	else \
		echo "\033[0;31m[VERIF] Pre-Synthesis Simulation Failed! Aborting Synthesis.\033[0m"; \
		exit 1; \
	fi

# --- Target Dispatcher ---

ifeq ($(FLOW),ieda)
include iEDA.mk

# Hook 'yosys' (the synthesis target in iEDA.mk) to depend on pre_syn_check
# Note: We need to override the 'yosys' target or use a prerequisite.
# Since iEDA.mk defines 'yosys', we can add a dependency here.
# However, iEDA.mk generates its own timestamp. We should pass our timestamp/dir to it 
# to ensure consistency, OR just let iEDA.mk do its thing and we assume PRE_SYN_CHECK ran.
# But the user specifically wants the verif report IN the syn dir.
# So we should probably override the logic or pass the directory.

# Make yosys depend on pre_syn_check
# We pass O variable to iEDA's yosys target to reuse our ARCHIVE_DIR
yosys_safe: pre_syn_check
	$(MAKE) -f iEDA.mk yosys O=$(abspath $(ARCHIVE_DIR))

# Redefine 'yosys' to be 'yosys_safe' for convenience if user types 'make yosys'
# (If iEDA.mk is included, it defines 'yosys'. We need to be careful about double definition warnings
# or just declare our own main target that calls it).
# A cleaner way: define 'synth' which calls pre_syn_check then yosys.

synth: yosys_safe

else ifeq ($(FLOW),synopsys)
include synopsys.mk

# For Synopsys, we also want verification before synthesis (dc).
# The 'dc' target in synopsys.mk calls 'run_remote_dc'.
# We can wrap it.

dc_safe: pre_syn_check dc

endif

# --- Common Utility ---
help:
	@echo "Available Flows: ieda (default), synopsys"
	@echo "Usage: make [FLOW=...] <target>"
	@echo ""
	@echo "Common Targets:"
	@echo "  make synth          (Runs Verify -> Archive -> Synthesis)"
	@echo "  make filelist       (Generate filelist.f)"
	@echo "  make clean"
	@if [ "$(FLOW)" = "ieda" ]; then \
		echo "iEDA Targets: yosys, pr, sta, ..."; \
	else \
		make -f synopsys.mk help_synopsys; \
	fi

clean:
	rm -rf $(BUILD_DIR) $(SYN_DIR_ROOT)
	rm -rf build_synopsys
