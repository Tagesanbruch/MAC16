# iEDA.mk - Modified for Multi-Experiment Support
# Usage: make -f iEDA.mk EXP=exp_baseline yosys
#        make -f iEDA.mk EXP=exp_a sta
#        make -f iEDA.mk EXP=exp_b yosys sta

YOSYS_STA_DIR = $(abspath ../yosys-sta)
DESIGN = mac16
PDK = icsprout55
BUILD_DIR = ./build
TIMESTAMP = $(shell date "+%Y-%m-%d_%H-%M-%S")
SYN_DIR_ROOT = ./syn
CLK_FREQ_MHZ = 1000
CLK_PORT_NAME = clk

# =============================================================================
# Experiment Selection
# =============================================================================
# Default to current rtl/ directory (original code)
EXP ?= current

ifeq ($(EXP),current)
    RTL_DIR = $(abspath ./rtl)
    EXP_SUFFIX =
else
    RTL_DIR = $(abspath ./rtl/experiments/$(EXP))
    EXP_SUFFIX = -$(EXP)
endif

# Check if experiment directory exists
EXP_DIR_EXISTS = $(shell test -d $(RTL_DIR) && echo "yes" || echo "no")

RTL_FILES = $(shell find $(RTL_DIR) -maxdepth 1 -name '*.sv' ! -name 'tb_*.sv' 2>/dev/null)

$(shell mkdir -p $(BUILD_DIR))

# =============================================================================
# Available Experiments Info
# =============================================================================
.PHONY: list_exp
list_exp:
	@echo "=============================================="
	@echo " Available Experiments"
	@echo "=============================================="
	@echo "  EXP=current      - Use ./rtl/ (original code)"
	@if [ -d "./rtl/experiments" ]; then \
		for d in ./rtl/experiments/*/; do \
			exp_name=$$(basename $$d); \
			echo "  EXP=$$exp_name"; \
		done; \
	fi
	@echo ""
	@echo " Usage: make -f iEDA.mk EXP=<name> <target>"
	@echo " Example: make -f iEDA.mk EXP=exp_b yosys sta"
	@echo "=============================================="

all: yosys

yosys:
	@if [ "$(EXP_DIR_EXISTS)" = "no" ]; then \
		echo "[ERROR] Experiment directory not found: $(RTL_DIR)"; \
		echo "Use 'make -f iEDA.mk list_exp' to see available experiments"; \
		exit 1; \
	fi
	@echo "=============================================="
	@echo " Synthesizing Experiment: $(EXP)"
	@echo " RTL Directory: $(RTL_DIR)"
	@echo " RTL Files: $(RTL_FILES)"
	@echo "=============================================="
	@mkdir -p $(SYN_DIR_ROOT)
	$(MAKE) -C $(YOSYS_STA_DIR) syn \
		DESIGN=$(DESIGN) \
		RTL_FILES="$(RTL_FILES)" \
		PDK=$(PDK) \
		CLK_FREQ_MHZ=$(CLK_FREQ_MHZ) \
		CLK_PORT_NAME=$(CLK_PORT_NAME) \
		O=$(abspath $(SYN_DIR_ROOT)/yosys-syn$(EXP_SUFFIX)-$(TIMESTAMP))

# Find latest synthesis directory for this experiment
LATEST_SYN_DIR = $(shell ls -td $(SYN_DIR_ROOT)/yosys-syn$(EXP_SUFFIX)-* 2>/dev/null | head -1)

sta:
	@if [ -z "$(LATEST_SYN_DIR)" ]; then \
		echo "[ERROR] No synthesis results found for EXP=$(EXP)."; \
		echo "Run 'make -f iEDA.mk EXP=$(EXP) yosys' first."; \
		exit 1; \
	fi
	@echo "=============================================="
	@echo " Running STA for Experiment: $(EXP)"
	@echo " Synthesis Directory: $(LATEST_SYN_DIR)"
	@echo "=============================================="
	$(MAKE) -C $(YOSYS_STA_DIR) sta \
		DESIGN=$(DESIGN) \
		RTL_FILES="$(RTL_FILES)" \
		PDK=$(PDK) \
		CLK_FREQ_MHZ=$(CLK_FREQ_MHZ) \
		CLK_PORT_NAME=$(CLK_PORT_NAME) \
		O=$(abspath $(LATEST_SYN_DIR))

sta_all:
	@if [ -z "$(LATEST_SYN_DIR)" ]; then \
		echo "[ERROR] No synthesis results found for EXP=$(EXP)."; \
		exit 1; \
	fi
	@echo "Running Multi-Corner STA for $(EXP)..."
	@rm -f $(LATEST_SYN_DIR)/sta_all.log
	@echo "--- Corner TT ---" | tee -a $(LATEST_SYN_DIR)/sta_all.log
	NETLIST="$(abspath $(LATEST_SYN_DIR))/$(DESIGN)-$(CLK_FREQ_MHZ)MHz/$(DESIGN).netlist.v" \
	../yosys-sta/bin/iEDA $(abspath scripts/sta_multicorner.tcl) \
		$(abspath ../yosys-sta/pdk/icsprout55) \
		"$(abspath $(LATEST_SYN_DIR))/$(DESIGN)-$(CLK_FREQ_MHZ)MHz/$(DESIGN).netlist.v" \
		$(abspath scripts/sdc/mac16.sdc) "TT" 2>&1 | tee -a $(LATEST_SYN_DIR)/sta_all.log
	@echo "--- Corner SS ---" | tee -a $(LATEST_SYN_DIR)/sta_all.log
	NETLIST="$(abspath $(LATEST_SYN_DIR))/$(DESIGN)-$(CLK_FREQ_MHZ)MHz/$(DESIGN).netlist.v" \
	../yosys-sta/bin/iEDA $(abspath scripts/sta_multicorner.tcl) \
		$(abspath ../yosys-sta/pdk/icsprout55) \
		"$(abspath $(LATEST_SYN_DIR))/$(DESIGN)-$(CLK_FREQ_MHZ)MHz/$(DESIGN).netlist.v" \
		$(abspath scripts/sdc/mac16.sdc) "SS" 2>&1 | tee -a $(LATEST_SYN_DIR)/sta_all.log

equiv:
	@if [ -z "$(LATEST_SYN_DIR)" ]; then \
		echo "[ERROR] No synthesis results found for EXP=$(EXP)."; \
		exit 1; \
	fi
	@echo "Running Equivalence Check for $(EXP)..."
	NETLIST="$(abspath $(LATEST_SYN_DIR))/$(DESIGN)-$(CLK_FREQ_MHZ)MHz/$(DESIGN).netlist.v" \
	yosys -c scripts/equiv_check.tcl 2>&1 | tee $(LATEST_SYN_DIR)/equiv.log

pr:
	@if [ -z "$(LATEST_SYN_DIR)" ]; then \
		echo "[ERROR] No synthesis results found for EXP=$(EXP)."; \
		exit 1; \
	fi
	@echo "Running Place & Route (iEDA) for $(EXP)..."
	@mkdir -p $(LATEST_SYN_DIR)/pr
	NETLIST="$(abspath $(LATEST_SYN_DIR))/$(DESIGN)-$(CLK_FREQ_MHZ)MHz/$(DESIGN).netlist.v" \
	../yosys-sta/bin/iEDA $(abspath scripts/ieda_flow.tcl) \
		$(abspath ../yosys-sta/pdk/icsprout55) \
		"$(abspath $(LATEST_SYN_DIR))/$(DESIGN)-$(CLK_FREQ_MHZ)MHz/$(DESIGN).netlist.v" \
		$(abspath scripts/sdc/mac16.sdc) 2>&1 | tee $(LATEST_SYN_DIR)/pr/ieda_pr.log

verif:
	@if [ "$(EXP_DIR_EXISTS)" = "no" ]; then \
		echo "[ERROR] Experiment directory not found: $(RTL_DIR)"; \
		exit 1; \
	fi
	@echo "Running functional simulation for $(EXP)..."
	mkdir -p $(BUILD_DIR)
	iverilog -g2012 -o $(BUILD_DIR)/tb_mac16$(EXP_SUFFIX).vvp \
		-I $(RTL_DIR) -I verif \
		$(RTL_FILES) verif/tb_mac16.sv
	vvp $(BUILD_DIR)/tb_mac16$(EXP_SUFFIX).vvp | tee $(BUILD_DIR)/sim$(EXP_SUFFIX).log
	@if grep -q "Simulation Passed" $(BUILD_DIR)/sim$(EXP_SUFFIX).log; then \
		echo "\033[0;32m[VERIF] $(EXP): All tests passed!\033[0m"; \
	else \
		echo "\033[0;31m[VERIF] $(EXP): Tests failed!\033[0m"; \
		exit 1; \
	fi

power:
	@if [ -z "$(LATEST_SYN_DIR)" ]; then \
		echo "[ERROR] No synthesis results found for EXP=$(EXP)."; \
		exit 1; \
	fi
	@echo "Running Power Analysis for $(EXP)..."
	NETLIST="$(abspath $(LATEST_SYN_DIR))/$(DESIGN)-$(CLK_FREQ_MHZ)MHz/$(DESIGN).netlist.v" \
	../yosys-sta/bin/iEDA $(abspath scripts/power_analysis.tcl) \
		$(abspath ../yosys-sta/pdk/icsprout55) \
		"$(abspath $(LATEST_SYN_DIR))/$(DESIGN)-$(CLK_FREQ_MHZ)MHz/$(DESIGN).netlist.v" \
		$(abspath scripts/sdc/mac16.sdc) "TT" 2>&1 | tee $(LATEST_SYN_DIR)/power.log

# Quick experiment flow: verif -> yosys -> sta
.PHONY: exp_flow
exp_flow: verif yosys sta
	@echo "=============================================="
	@echo " Experiment Flow Complete: $(EXP)"
	@echo " Results in: $(LATEST_SYN_DIR)"
	@echo "=============================================="

# Compare all experiments timing results
.PHONY: compare
compare:
	@echo "=============================================="
	@echo " Timing Comparison Across Experiments"
	@echo "=============================================="
	@for syn_dir in $(SYN_DIR_ROOT)/yosys-syn*/; do \
		if [ -d "$$syn_dir" ]; then \
			exp_name=$$(basename $$syn_dir); \
			sta_dirs=$$(ls -td $$syn_dir*_sta_* 2>/dev/null | head -1); \
			if [ -n "$$sta_dirs" ]; then \
				for sta_dir in $$sta_dirs; do \
					if [ -f "$$sta_dir/sta.rpt" ]; then \
						wns=$$(grep -i "WNS" $$sta_dir/sta.rpt 2>/dev/null | head -1 || echo "WNS: N/A"); \
						echo "$$exp_name: $$wns"; \
					fi; \
				done; \
			fi; \
		fi; \
	done

report:
	@echo "Generating gap analysis report for $(EXP)..."
	mkdir -p docs
	python3 scripts/analyze_results.py \
		--sim_log $(BUILD_DIR)/sim$(EXP_SUFFIX).log \
		--syn_dir "$(LATEST_SYN_DIR)" \
		--design $(DESIGN) \
		--freq $(CLK_FREQ_MHZ) \
		--output docs/gap_analysis_report$(EXP_SUFFIX).md

clean:
	-rm -rf $(BUILD_DIR) $(SYN_DIR_ROOT)

clean_exp:
	-rm -rf $(SYN_DIR_ROOT)/yosys-syn$(EXP_SUFFIX)-*

.PHONY: yosys sta sta_all equiv pr power verif report clean clean_exp all exp_flow compare list_exp
