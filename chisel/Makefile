MILL ?= mill

VSRC_DIR = ./vsrc
OBJ_DIR = ./obj_dir
TB_DIR = ../verif
TB_FILE = $(TB_DIR)/tb_mac16.sv

# Default experiment
EXP ?= exp_d

.PHONY: gen_exp_d gen_exp_i gen_all compile clean help verif-vl verif test test-csa test-comp test-booth test-mult

gen_exp_d:
	mkdir -p $(VSRC_DIR)/exp_d
	$(MILL) mac16.runMain mac16.Generate -- --exp exp_d --out $(VSRC_DIR)/exp_d

gen_exp_i:
	mkdir -p $(VSRC_DIR)/exp_i
	$(MILL) mac16.runMain mac16.Generate -- --exp exp_i --out $(VSRC_DIR)/exp_i

gen_all: gen_exp_d gen_exp_i

compile:
	$(MILL) mac16.compile

# ============================================================================
# Unit Tests (Chisel/ScalaTest based)
# ============================================================================

# Run all unit tests
test:
	@echo "=== Running all Chisel unit tests ==="
	$(MILL) mac16.test

# Run specific test classes
test-csa:
	@echo "=== Testing CSA (3:2 Compressor) ==="
	$(MILL) mac16.test.testOnly mac16.CSATest

test-comp:
	@echo "=== Testing 4:2 Compressor ==="
	$(MILL) mac16.test.testOnly mac16.Compressor4to2Test mac16.Compressor4to2ArrayTest

test-booth:
	@echo "=== Testing Booth Encoder & Partial Product Generator ==="
	$(MILL) mac16.test.testOnly mac16.BoothEncoderTest mac16.PartialProductGenTest

test-mult:
	@echo "=== Testing Mult16Booth (Pipelined Multiplier) ==="
	$(MILL) mac16.test.testOnly mac16.Mult16BoothTest

# ============================================================================
# Verilator verification target
# ============================================================================
verif-vl: gen_$(EXP)
	@echo "=== Running Verilator verification for $(EXP) ==="
	mkdir -p $(OBJ_DIR)
	verilator --binary --trace -Wno-fatal \
		-j 8 \
		--Mdir $(OBJ_DIR)/$(EXP) \
		-o tb_mac16_chisel_$(EXP) \
		--top-module tb_mac16 \
		$(VSRC_DIR)/$(EXP)/mac16.sv $(TB_FILE)
	@echo "=== Running simulation ==="
	$(OBJ_DIR)/$(EXP)/tb_mac16_chisel_$(EXP)

# Shortcut for verification
verif: verif-vl

# Full validation: unit tests + integration test
validate: test verif-vl
	@echo "=== All tests passed ==="

help:
	@echo "Usage:"
	@echo "  make compile         - Compile Scala sources"
	@echo ""
	@echo "Unit Tests:"
	@echo "  make test            - Run all Chisel unit tests"
	@echo "  make test-csa        - Test CSA module"
	@echo "  make test-comp       - Test 4:2 Compressor modules"
	@echo "  make test-booth      - Test Booth encoder & PP generator"
	@echo "  make test-mult       - Test pipelined multiplier"
	@echo ""
	@echo "Verilog Generation:"
	@echo "  make gen_exp_d       - Generate exp_d Verilog to vsrc/exp_d/"
	@echo "  make gen_exp_i       - Generate exp_i Verilog to vsrc/exp_i/"
	@echo "  make gen_all         - Generate all experiments"
	@echo ""
	@echo "Integration Test:"
	@echo "  make verif-vl EXP=x  - Run Verilator verification (default: exp_d)"
	@echo "  make validate        - Run unit tests + integration test"
	@echo ""
	@echo "  make clean           - Clean generated files"

clean:
	-rm -rf $(VSRC_DIR)/exp_d $(VSRC_DIR)/exp_i
	-rm -rf $(OBJ_DIR)
	-rm -rf out
	-rm -rf test_run_dir
