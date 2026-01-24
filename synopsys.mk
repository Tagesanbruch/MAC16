# Synopsys Toolchain Makefile
# Usage: make -f synopsys.mk <target>

DESIGN = mac16
RTL_DIR = ./rtl
VERIF_DIR = ./verif
BUILD_DIR = ./build_synopsys
SCRIPT_DIR = ./scripts

# Source Files
RTL_FILES = $(RTL_DIR)/adder.sv
TB_FILES = $(VERIF_DIR)/tb_adder.sv

# Tools
VCS = vcs
DC = dc_shell
FM = fm_shell
ICC = icc_shell # or icc2_shell
VERDI = verdi

# Tool Options
VCS_FLAGS = -full64 -sverilog -l $(abspath $(BUILD_DIR)/vcs.log)
DC_FLAGS = -64bit -no_gui
FM_FLAGS = -64bit
ICC_FLAGS = -64bit

# Directories
$(shell mkdir -p $(BUILD_DIR))

# Targets

all: vcs

# 1. Simulation (VCS)
vcs:
	@echo "Running VCS Compilation and Simulation..."
	mkdir -p $(BUILD_DIR)/sim
	cd $(BUILD_DIR)/sim && $(VCS) $(VCS_FLAGS) \
		+incdir+$(abspath $(RTL_DIR)) \
		+incdir+$(abspath $(VERIF_DIR)) \
		$(foreach f,$(RTL_FILES),$(abspath $f)) \
		$(foreach f,$(TB_FILES),$(abspath $f)) \
		-o simv
	cd $(BUILD_DIR)/sim && ./simv | tee sim.log

# 2. Waveform Verification (Verdi)
verdi:
	@echo "Opening Verdi..."
	cd $(BUILD_DIR)/sim && $(VERDI) -ssf tb_mac16.fsdb &

# 3. Synthesis (Design Compiler)
dc:
	@echo "Running Design Compiler..."
	mkdir -p $(BUILD_DIR)/syn
	cd $(BUILD_DIR)/syn && $(DC) $(DC_FLAGS) -f $(abspath $(SCRIPT_DIR)/dc_syn.tcl) | tee dc.log

# 4. Formal Verification (Formality)
fm:
	@echo "Running Formality..."
	mkdir -p $(BUILD_DIR)/fm
	cd $(BUILD_DIR)/fm && $(FM) $(FM_FLAGS) -f $(abspath $(SCRIPT_DIR)/fm_check.tcl) | tee fm.log

# 5. Place & Route (IC Compiler)
icc:
	@echo "Running IC Compiler..."
	mkdir -p $(BUILD_DIR)/icc
	cd $(BUILD_DIR)/icc && $(ICC) $(ICC_FLAGS) -f $(abspath $(SCRIPT_DIR)/icc_pr.tcl) | tee icc.log

clean:
	rm -rf $(BUILD_DIR)csrc $(BUILD_DIR)/simv* $(BUILD_DIR)/ucli.key

.PHONY: vcs verdi dc fm icc clean all
