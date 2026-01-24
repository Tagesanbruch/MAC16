YOSYS_STA_DIR = $(abspath ../yosys-sta)
DESIGN = mac16
PDK = icsprout55
BUILD_DIR = ./build
TIMESTAMP = $(shell date "+%Y-%m-%d_%H-%M-%S")
SYN_DIR_ROOT = ./syn
CLK_FREQ_MHZ = 1000
CLK_PORT_NAME = clk

RTL_FILES = $(shell find $(abspath ./rtl) -name '*.sv' ! -name 'tb_*.sv')

$(shell mkdir -p $(BUILD_DIR))

all: yosys

yosys:
	@mkdir -p $(SYN_DIR_ROOT)
	$(MAKE) -C $(YOSYS_STA_DIR) syn \
		DESIGN=$(DESIGN) \
		RTL_FILES="$(RTL_FILES)" \
		PDK=$(PDK) \
		CLK_FREQ_MHZ=$(CLK_FREQ_MHZ) \
		CLK_PORT_NAME=$(CLK_PORT_NAME) \
		O=$(abspath $(SYN_DIR_ROOT)/yosys-syn-$(TIMESTAMP))

LATEST_SYN_DIR = $(shell ls -td $(SYN_DIR_ROOT)/yosys-syn-* 2>/dev/null | head -1)

sta:
	@if [ -z "$(LATEST_SYN_DIR)" ]; then \
		echo "No synthesis results found. Run 'make yosys' first."; \
		exit 1; \
	fi
	$(MAKE) -C $(YOSYS_STA_DIR) sta \
		DESIGN=$(DESIGN) \
		RTL_FILES="$(RTL_FILES)" \
		PDK=$(PDK) \
		CLK_FREQ_MHZ=$(CLK_FREQ_MHZ) \
		CLK_PORT_NAME=$(CLK_PORT_NAME) \
	CLK_PORT_NAME=$(CLK_PORT_NAME) \
		O=$(abspath $(LATEST_SYN_DIR))

sta_all:
	@if [ -z "$(LATEST_SYN_DIR)" ]; then \
		echo "No synthesis results found. Run 'make yosys' first."; \
		exit 1; \
	fi
	@echo "Running Multi-Corner STA..."
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


# Formal Verification (Equivalence Check)
equiv:
	@if [ -z "$(LATEST_SYN_DIR)" ]; then \
		echo "No synthesis results found. Run 'make yosys' first."; \
		exit 1; \
	fi
	@echo "Running Equivalence Check..."
	NETLIST="$(abspath $(LATEST_SYN_DIR))/$(DESIGN)-$(CLK_FREQ_MHZ)MHz/$(DESIGN).netlist.v" \
	yosys -c scripts/equiv_check.tcl 2>&1 | tee $(LATEST_SYN_DIR)/equiv.log

# Place & Route
pr:
	@if [ -z "$(LATEST_SYN_DIR)" ]; then \
		echo "No synthesis results found. Run 'make yosys' first."; \
		exit 1; \
	fi
	@echo "Running Place & Route (iEDA)..."
	@mkdir -p $(LATEST_SYN_DIR)/pr
	NETLIST="$(abspath $(LATEST_SYN_DIR))/$(DESIGN)-$(CLK_FREQ_MHZ)MHz/$(DESIGN).netlist.v" \
	../yosys-sta/bin/iEDA $(abspath scripts/ieda_flow.tcl) \
		$(abspath ../yosys-sta/pdk/icsprout55) \
		"$(abspath $(LATEST_SYN_DIR))/$(DESIGN)-$(CLK_FREQ_MHZ)MHz/$(DESIGN).netlist.v" \
		$(abspath scripts/sdc/mac16.sdc) 2>&1 | tee $(LATEST_SYN_DIR)/pr/ieda_pr.log
	@if grep -q "Simulation Passed" $(BUILD_DIR)/sim.log; then \
		echo "\033[0;32m[VERIF] All tests passed!\033[0m"; \
	else \
		echo "\033[0;31m[VERIF] Tests failed!\033[0m"; \
		exit 1; \

# Verification Target
verif:
	@echo "Running functional simulation..."
	mkdir -p $(BUILD_DIR)
	iverilog -g2012 -o $(BUILD_DIR)/tb_mac16.vvp -I rtl -I verif $(RTL_FILES) verif/tb_mac16.sv
	vvp $(BUILD_DIR)/tb_mac16.vvp | tee $(BUILD_DIR)/sim.log
	@if grep -q "Simulation Passed" $(BUILD_DIR)/sim.log; then \
		echo "\033[0;32m[VERIF] All tests passed!\033[0m"; \
	else \
		echo "\033[0;31m[VERIF] Tests failed!\033[0m"; \
		exit 1; \
	fi

# Report Target
report:
	@echo "Generating gap analysis report..."
	mkdir -p docs
	python3 scripts/analyze_results.py \
		--sim_log $(BUILD_DIR)/sim.log \
		--syn_dir "$(LATEST_SYN_DIR)" \
		--design $(DESIGN) \
		--freq $(CLK_FREQ_MHZ) \
		--output docs/gap_analysis_report.md

clean:
	-rm -rf $(BUILD_DIR) $(SYN_DIR_ROOT)


# Power Analysis
power:
	@if [ -z "$(LATEST_SYN_DIR)" ]; then \
		echo "No synthesis results found. Run 'make yosys' first."; \
		exit 1; \
	fi
	@echo "Running Power Analysis..."
	NETLIST="$(abspath $(LATEST_SYN_DIR))/$(DESIGN)-$(CLK_FREQ_MHZ)MHz/$(DESIGN).netlist.v" \
	../yosys-sta/bin/iEDA $(abspath scripts/power_analysis.tcl) \
		$(abspath ../yosys-sta/pdk/icsprout55) \
		"$(abspath $(LATEST_SYN_DIR))/$(DESIGN)-$(CLK_FREQ_MHZ)MHz/$(DESIGN).netlist.v" \
		$(abspath scripts/sdc/mac16.sdc) "TT" 2>&1 | tee $(LATEST_SYN_DIR)/power.log

.PHONY: yosys sta sta_all equiv pr power verif report clean all
