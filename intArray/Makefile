# Makefile for intArray (16x16 Systolic Array)
# Reference: Parent directory Makefile style

# Configuration
BUILD_DIR = ./build
RTL_DIR = ./rtl/sa16x16
VERIF_DIR = ./verif/unit
VECTORS_DIR = ./verif/vectors
SCRIPTS_DIR = ./scripts

# Tool settings
IVERILOG = iverilog
VVP = vvp
PYTHON = python3
IVERILOG_FLAGS = -g2012 -Wall

# RTL source files
RTL_COMMON = $(RTL_DIR)/sa16x16_defs.svh \
             $(RTL_DIR)/booth_encoder.sv \
             $(RTL_DIR)/partial_product_gen.sv \
             $(RTL_DIR)/csa.sv \
             $(RTL_DIR)/compressor_4to2.sv \
             $(RTL_DIR)/mult16_booth_5stage.sv

RTL_PE = $(RTL_COMMON) $(RTL_DIR)/sa16x16_pe.sv
RTL_BUF = $(RTL_DIR)/sa16x16_buf.sv
RTL_CTRL = $(RTL_DIR)/sa16x16_ctrl.sv
RTL_TOP = $(RTL_COMMON) $(RTL_PE) $(RTL_BUF) $(RTL_CTRL) \
          $(RTL_DIR)/sa16x16_axi_stream.sv $(RTL_DIR)/sa16x16_top.sv

# Create build directory
$(shell mkdir -p $(BUILD_DIR))

# Default target
.PHONY: all
all: unit_all

#============================================================================
# Unit Tests
#============================================================================

.PHONY: unit_pe
unit_pe: $(BUILD_DIR)/tb_sa16x16_pe.vvp
	@echo "=== Running PE Unit Test ==="
	$(VVP) $< | tee $(BUILD_DIR)/unit_pe.log
	@if grep -q "Simulation Passed" $(BUILD_DIR)/unit_pe.log; then \
		echo "\033[0;32m[PASS] PE Unit Test\033[0m"; \
	else \
		echo "\033[0;31m[FAIL] PE Unit Test\033[0m"; \
		exit 1; \
	fi

$(BUILD_DIR)/tb_sa16x16_pe.vvp: $(VERIF_DIR)/tb_sa16x16_pe.sv $(RTL_PE)
	$(IVERILOG) $(IVERILOG_FLAGS) -I $(RTL_DIR) -o $@ $^

.PHONY: unit_ctrl
unit_ctrl: $(BUILD_DIR)/tb_sa16x16_ctrl.vvp
	@echo "=== Running Controller Unit Test ==="
	$(VVP) $< | tee $(BUILD_DIR)/unit_ctrl.log
	@if grep -q "Simulation Passed" $(BUILD_DIR)/unit_ctrl.log; then \
		echo "\033[0;32m[PASS] Controller Unit Test\033[0m"; \
	else \
		echo "\033[0;31m[FAIL] Controller Unit Test\033[0m"; \
		exit 1; \
	fi

$(BUILD_DIR)/tb_sa16x16_ctrl.vvp: $(VERIF_DIR)/tb_sa16x16_ctrl.sv $(RTL_CTRL)
	$(IVERILOG) $(IVERILOG_FLAGS) -I $(RTL_DIR) -o $@ $^

.PHONY: unit_buf
unit_buf: $(BUILD_DIR)/tb_sa16x16_buf.vvp
	@echo "=== Running FIFO/Buffer Unit Test ==="
	$(VVP) $< | tee $(BUILD_DIR)/unit_buf.log
	@if grep -q "Simulation Passed" $(BUILD_DIR)/unit_buf.log; then \
		echo "\033[0;32m[PASS] FIFO/Buffer Unit Test\033[0m"; \
	else \
		echo "\033[0;31m[FAIL] FIFO/Buffer Unit Test\033[0m"; \
		exit 1; \
	fi

$(BUILD_DIR)/tb_sa16x16_buf.vvp: $(VERIF_DIR)/tb_sa16x16_buf.sv $(RTL_BUF)
	$(IVERILOG) $(IVERILOG_FLAGS) -I $(RTL_DIR) -o $@ $^

.PHONY: unit_top
unit_top: $(BUILD_DIR)/tb_sa16x16_top.vvp
	@echo "=== Running Top-Level System Test ==="
	$(VVP) $< | tee $(BUILD_DIR)/unit_top.log
	@if grep -q "Simulation Passed" $(BUILD_DIR)/unit_top.log; then \
		echo "\033[0;32m[PASS] System Test\033[0m"; \
	else \
		echo "\033[0;31m[FAIL] System Test\033[0m"; \
		exit 1; \
	fi

$(BUILD_DIR)/tb_sa16x16_top.vvp: $(VERIF_DIR)/tb_sa16x16_top.sv $(RTL_TOP)
	$(IVERILOG) $(IVERILOG_FLAGS) -I $(RTL_DIR) -o $@ \
		$(RTL_DIR)/sa16x16_defs.svh \
		$(RTL_DIR)/booth_encoder.sv \
		$(RTL_DIR)/partial_product_gen.sv \
		$(RTL_DIR)/csa.sv \
		$(RTL_DIR)/compressor_4to2.sv \
		$(RTL_DIR)/mult16_booth_5stage.sv \
		$(RTL_DIR)/sa16x16_pe.sv \
		$(RTL_DIR)/sa16x16_buf.sv \
		$(RTL_DIR)/sa16x16_ctrl.sv \
		$(RTL_DIR)/sa16x16_axi_stream.sv \
		$(RTL_DIR)/sa16x16_top.sv \
		$(VERIF_DIR)/tb_sa16x16_top.sv

.PHONY: unit_all
unit_all: unit_buf unit_ctrl unit_pe
	@echo ""
	@echo "=== All Unit Tests Complete ==="

#============================================================================
# Debug and Full System Tests
#============================================================================

.PHONY: debug
debug: $(BUILD_DIR)/tb_sa_debug.vvp
	@echo "=== Running 4x4 Debug Test ==="
	$(VVP) $< | tee $(BUILD_DIR)/debug.log

$(BUILD_DIR)/tb_sa_debug.vvp: $(VERIF_DIR)/tb_sa_debug.sv
	$(IVERILOG) $(IVERILOG_FLAGS) -I $(RTL_DIR) -DN=4 -DSIM -o $@ \
		$(RTL_DIR)/booth_encoder.sv \
		$(RTL_DIR)/partial_product_gen.sv \
		$(RTL_DIR)/csa.sv \
		$(RTL_DIR)/compressor_4to2.sv \
		$(RTL_DIR)/mult16_booth_5stage.sv \
		$(RTL_DIR)/sa16x16_pe.sv \
		$(RTL_DIR)/sa16x16_buf.sv \
		$(RTL_DIR)/sa16x16_ctrl.sv \
		$(RTL_DIR)/sa16x16_top.sv \
		$<

.PHONY: full
full: $(BUILD_DIR)/tb_sa_full.vvp
	@echo "=== Running 16x16 Full Test Suite ==="
	$(VVP) $< | tee $(BUILD_DIR)/full.log
	@if grep -q "ALL TESTS PASSED" $(BUILD_DIR)/full.log; then \
		echo "\033[0;32m[PASS] Full Test Suite\033[0m"; \
	else \
		echo "\033[0;31m[FAIL] Full Test Suite\033[0m"; \
		exit 1; \
	fi

$(BUILD_DIR)/tb_sa_full.vvp: $(VERIF_DIR)/tb_sa_full.sv
	$(IVERILOG) $(IVERILOG_FLAGS) -I $(RTL_DIR) -DN=16 -DSIM -o $@ \
		$(RTL_DIR)/booth_encoder.sv \
		$(RTL_DIR)/partial_product_gen.sv \
		$(RTL_DIR)/csa.sv \
		$(RTL_DIR)/compressor_4to2.sv \
		$(RTL_DIR)/mult16_booth_5stage.sv \
		$(RTL_DIR)/sa16x16_pe.sv \
		$(RTL_DIR)/sa16x16_buf.sv \
		$(RTL_DIR)/sa16x16_ctrl.sv \
		$(RTL_DIR)/sa16x16_top.sv \
		$<

#============================================================================
# Test Vector Generation
#============================================================================

.PHONY: gen_vectors
gen_vectors:
	@echo "=== Generating Test Vectors ==="
	@mkdir -p $(VECTORS_DIR)
	$(PYTHON) $(SCRIPTS_DIR)/sa16x16_gen.py -o $(VECTORS_DIR) -n 5
	@echo "Vectors generated in $(VECTORS_DIR)/"

#============================================================================
# Waveform viewing
#============================================================================

.PHONY: wave_pe
wave_pe: unit_pe
	gtkwave $(BUILD_DIR)/tb_sa16x16_pe.vcd &

.PHONY: wave_top
wave_top: unit_top
	gtkwave $(BUILD_DIR)/tb_sa16x16_top.vcd &

#============================================================================
# Integration with iEDA.mk
#============================================================================

# Copy RTL to experiments directory for synthesis
.PHONY: prep_synth
prep_synth:
	@echo "Preparing RTL for synthesis..."
	@mkdir -p ../rtl/experiments/exp_sa16x16
	cp $(RTL_DIR)/*.sv ../rtl/experiments/exp_sa16x16/
	cp $(RTL_DIR)/*.svh ../rtl/experiments/exp_sa16x16/
	@echo "RTL copied to ../rtl/experiments/exp_sa16x16/"
	@echo "Run: make -f iEDA.mk EXP=exp_sa16x16 yosys sta"

#============================================================================
# Utility
#============================================================================

.PHONY: lint
lint:
	@echo "=== Linting RTL ==="
	verilator --lint-only -Wall -I$(RTL_DIR) $(RTL_DIR)/*.sv

.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)
	rm -rf $(VECTORS_DIR)/*.hex $(VECTORS_DIR)/*.csv $(VECTORS_DIR)/*.txt

.PHONY: clean_all
clean_all: clean
	rm -rf ../rtl/experiments/exp_sa16x16

.PHONY: help
help:
	@echo "=========================================="
	@echo " intArray 16x16 Systolic Array Makefile"
	@echo "=========================================="
	@echo ""
	@echo "Unit Tests:"
	@echo "  make unit_pe      - Test PE module"
	@echo "  make unit_ctrl    - Test controller"
	@echo "  make unit_buf     - Test FIFO/buffer"
	@echo "  make unit_top     - Test full system"
	@echo "  make unit_all     - Run all unit tests"
	@echo ""
	@echo "Test Vectors:"
	@echo "  make gen_vectors  - Generate test vectors"
	@echo ""
	@echo "Waveforms:"
	@echo "  make wave_pe      - View PE waveform"
	@echo "  make wave_top     - View system waveform"
	@echo ""
	@echo "Synthesis:"
	@echo "  make prep_synth   - Prepare RTL for iEDA synthesis"
	@echo ""
	@echo "4x4 Systolic Array:"
	@echo "  make sim4x4       - Run 4x4 array simulation"
	@echo ""
	@echo "Utility:"
	@echo "  make lint         - Lint check RTL"
	@echo "  make clean        - Clean build artifacts"
	@echo "=========================================="

#============================================================================
# 4x4 Systolic Array (for faster synthesis exploration)
# Shares common multiplier modules with sa16x16
#============================================================================

# Common multiplier components from sa16x16
RTL_MULT_COMMON = ./rtl/sa16x16/booth_encoder.sv \
                  ./rtl/sa16x16/partial_product_gen.sv \
                  ./rtl/sa16x16/csa.sv \
                  ./rtl/sa16x16/compressor_4to2.sv \
                  ./rtl/sa16x16/mult16_booth_5stage.sv

RTL_4X4 = ./rtl/sa4x4/sa4x4_top.sv \
          ./rtl/sa4x4/sa4x4_ctrl.sv \
          ./rtl/sa4x4/sa4x4_pe.sv

TB_4X4 = ./verif/tb_sa4x4.sv

.PHONY: sim4x4
sim4x4: $(BUILD_DIR)/tb_sa4x4.vvp
	@echo "=== Running 4x4 Systolic Array Test ==="
	$(VVP) $(BUILD_DIR)/tb_sa4x4.vvp | tee $(BUILD_DIR)/sim4x4.log
	@if grep -q "Simulation Passed" $(BUILD_DIR)/sim4x4.log; then \
		echo "\033[0;32m[PASS] 4x4 Systolic Array Test\033[0m"; \
	else \
		echo "\033[0;31m[FAIL] 4x4 Systolic Array Test\033[0m"; \
		exit 1; \
	fi

$(BUILD_DIR)/tb_sa4x4.vvp: $(RTL_MULT_COMMON) $(RTL_4X4) $(TB_4X4)
	$(IVERILOG) $(IVERILOG_FLAGS) -o $@ $(RTL_MULT_COMMON) $(RTL_4X4) $(TB_4X4)

