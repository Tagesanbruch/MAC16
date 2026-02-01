ifneq ($(words $(CURDIR)),1)
 $(error Unsupported: GNU Make cannot build in directories containing spaces, build elsewhere: '$(CURDIR)')
endif

######################################################################

# This is intended to be a minimal example.  Before copying this to start a
# real project, it is better to start with a more complete example,
# e.g. examples/make_tracing_c.

# If $VERILATOR_ROOT isn't in the environment, we assume it is part of a
# package install, and verilator is in your path. Otherwise find the
# binary relative to $VERILATOR_ROOT (such as when inside the git sources).
ifeq ($(VERILATOR_ROOT),)
VERILATOR = verilator
else
export VERILATOR_ROOT
VERILATOR = $(VERILATOR_ROOT)/bin/verilator
endif
TRACE_FST ?= 0

ifeq ($(TRACE_FST),1)
	VERILATOR_CFLAGS += -MMD --build -cc --trace-fst -j 8 \
					-O3 --x-assign fast --x-initial fast --noassert
	CXXFLAGS += -DTRACE_FST
else
	VERILATOR_CFLAGS += -MMD --build -cc --trace -j 8 \
					-O3 --x-assign fast --x-initial fast --noassert
endif
TOPNAME = NPC
# NXDC_FILES = constr/YPC.nxdc
# INC_PATH ?=
WORK_DIR  = $(shell pwd)
INC_PATH := $(WORK_DIR)/inc $(INC_PATH)
TEST_BIN = $(FILE)

ifeq ($(strip $(ELF)),)
	ELFFLAGS ?=
else
    ELFFLAGS = --elf=$(ELF)
endif


BUILD_DIR = ./build
OBJ_DIR = $(BUILD_DIR)/obj_dir
BIN = $(BUILD_DIR)/$(TOPNAME)
default: $(BIN)
	
$(shell mkdir -p $(BUILD_DIR))
# constraint file
# SRC_AUTO_BIND = $(abspath $(BUILD_DIR)/auto_bind.cpp)
# $(SRC_AUTO_BIND): $(NXDC_FILES)
# 	python3 $(NVBOARD_HOME)/scripts/auto_pin_bind.py $^ $@

# project source
VSRCS = $(shell find $(abspath ./vsrc) -name "*.v" -or -name "*.sv")
CSRCS = $(shell find $(abspath ./csrc) -name "*.c" -or -name "*.cc" -or -name "*.cpp")
CXXSRCS = $(shell find $(abspath ./csrc) -name "*.cc" -or -name "*.cpp")
# CSRCS += $(SRC_AUTO_BIND)

ifeq ($(strip $(LOG)),)
	LOGFLAGS ?=
else
    LOGFLAGS = --log=$(LOG)
endif

# Default DIFFTEST reference (NEMU .so)
NEMU_HOME ?= $(WORK_DIR)/../../../nemu
DIFF_SO_DEFAULT = $(NEMU_HOME)/build/riscv32-nemu-interpreter-so
DIFFFLAGS ?= --diff=$(DIFF_SO_DEFAULT)

# LOG ?= --l $(BUILD_DIR)/npc-log.txt
# rules for NVBoard
# include $(NVBOARD_HOME)/scripts/nvboard.mk

# llvm
CXXFLAGS += $(shell /opt/homebrew/opt/llvm/bin/llvm-config --cxxflags) -fPIE
LIBS += $(shell /opt/homebrew/opt/llvm/bin/llvm-config --libs)
LDFLAGS += $(shell /opt/homebrew/opt/llvm/bin/llvm-config --ldflags)
# rules for verilator
LIBS += -lreadline -ldl -pie
INCFLAGS = $(addprefix -I , $(INC_PATH))
# Map NPC directory to current dir for relative paths in logs
CXXFLAGS += $(INCFLAGS) -DTOP_NAME="\"V$(TOPNAME)\"" -fsanitize=address -ffile-prefix-map=$(WORK_DIR)/=./
LDFLAGS += -fsanitize=address $(LIBS)
$(BIN): $(VSRCS) $(CSRCS)
	rm -rf $(OBJ_DIR)
	$(VERILATOR) $(VERILATOR_CFLAGS) \
		--top-module $(TOPNAME) $^ \
		$(addprefix -CFLAGS , $(CXXFLAGS)) $(addprefix -LDFLAGS , $(LDFLAGS))\
		--Mdir $(OBJ_DIR) --exe -o $(abspath $(BIN))

all: default

preprocess:
	@if [ -f vsrc/CacheMem.sv ] && ! grep -q "verilator tracing_off" vsrc/CacheMem.sv; then \
		awk '/module CacheMem/,/);/{if(/);/){print; print "/* verilator tracing_off */"; next}}1' vsrc/CacheMem.sv > temp && mv temp vsrc/CacheMem.sv; \
	fi
	@if [ -f vsrc/CacheMem_1.sv ] && ! grep -q "verilator tracing_off" vsrc/CacheMem_1.sv; then \
		awk '/module CacheMem_1/,/);/{if(/);/){print; print "/* verilator tracing_off */"; next}}1' vsrc/CacheMem_1.sv > temp && mv temp vsrc/CacheMem_1.sv; \
	fi
run: preprocess $(BIN)
# run: $(BIN)
# 	$(BIN) -b $(LOGFLAGS) $(ELFFLAGS) $(TEST_BIN) 
	$(BIN) -b $(LOGFLAGS) $(ELFFLAGS) $(DIFFFLAGS) $(TEST_BIN) 
# 	$(BIN) $(LOGFLAGS) $(ELFFLAGS) $(DIFFFLAGS) $(TEST_BIN) 

PERF_FLAGS ?=

perf_test: $(BIN)
	perf record -F 999 -e cpu-clock --call-graph dwarf -g $(PERF_FLAGS) ./$^ $(LOGFLAGS) $(ELFFLAGS) $(TEST_BIN)
	mv ./perf.data ./perf
	perf script -i perf/perf.data &> perf/perf.unfold
	FlameGraph/stackcollapse-perf.pl perf/perf.unfold &> perf/perf.folded
	FlameGraph/flamegraph.pl perf/perf.folded > perf/perf.svg
	gimp perf/perf.svg

######################################################################

maintainer-copy::
clean mostlyclean distclean maintainer-clean::
	-rm -rf $(BUILD_DIR) *.log *.dmp *.vcd *.vpd core
.PHONY: default all clean run perf_test