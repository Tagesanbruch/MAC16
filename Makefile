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

# --- Remote Configuration (Synopsys Flow) ---
REMOTE_HOST = unix20@100.118.95.3
REMOTE_PROJECT_ROOT = /home/unix20/mac
REMOTE_DOCKER_CONTAINER = mac16_env
REMOTE_DOCKER_WORK_DIR = /work/mac

# --- Local Directories ---
BUILD_DIR = ./build
SYN_DIR_ROOT = ./syn
LOG_DIR = ./logs
RTL_DIR = ./rtl
VERIF_DIR = ./verif

$(shell mkdir -p $(BUILD_DIR) $(SYN_DIR_ROOT) $(LOG_DIR))

# --- Target Dispatcher ---
# If FLOW is iEDA, include iEDA logic (inline or include)
# If FLOW is Synopsys, define wrapper targets that rsync -> run remote -> rsync back

ifeq ($(FLOW),ieda)
include iEDA.mk
else ifeq ($(FLOW),synopsys)
# Synopsys wrapper targets
# These targets trigger the synopsys flow on the remote machine

# 1. Sync UP: Local -> Remote -> Docker [Volume Mounted]
# A. Sync Local to Remote Host (Volume source)
sync_host:
	@echo "Syncing code to remote host ($(REMOTE_HOST))..."
	rsync -avz --exclude '.git' --exclude 'build*' --exclude 'syn' --exclude 'logs' \
		./ $(REMOTE_HOST):$(REMOTE_PROJECT_ROOT)/

# B. Sync Up (Alias to sync_host, since Docker mounts the host dir)
sync_up: sync_host
	@echo "Code synced to host (Auto-mounted in Docker)."

# One-time setup: Just verify PDK on host
setup_remote: sync_host
	@echo "Verifying PDK on remote host..."
	ssh $(REMOTE_HOST) "if [ -d $(REMOTE_PROJECT_ROOT)/icsprout55-pdk ]; then echo 'PDK found.'; else echo 'PDK not found on host!'; exit 1; fi"

# 2. Remote Execution Helper
run_remote_%: sync_up
	@echo "Executing '$*' on remote container..."
	ssh $(REMOTE_HOST) "docker exec -w $(REMOTE_DOCKER_WORK_DIR) $(REMOTE_DOCKER_CONTAINER) make -f synopsys.mk $*"

# 3. Sync DOWN: Remote -> Local
# Pull back logs and results
sync_down:
	@echo "Syncing results back from remote..."
	rsync -avz $(REMOTE_HOST):$(REMOTE_PROJECT_ROOT)/build_synopsys/ ./build_synopsys/
	rsync -avz $(REMOTE_HOST):$(REMOTE_PROJECT_ROOT)/logs/ ./logs/ || true

# Synopsys Targets Mapping
vcs: run_remote_vcs sync_down
dc: run_remote_dc sync_down
fm: run_remote_fm sync_down
icc: run_remote_icc sync_down
clean_remote:
	ssh $(REMOTE_HOST) "docker exec -w $(REMOTE_DOCKER_WORK_DIR) $(REMOTE_DOCKER_CONTAINER) make -f synopsys.mk clean"

verif: vcs
synth: dc

else
$(error "Invalid FLOW specified. Use FLOW=ieda or FLOW=synopsys")
endif

# Common Utility
help:
	@echo "Available Flows: ieda (default), synopsys"
	@echo "Targets:"
	@echo "  make yosys          (iEDA: Synthesis)"
	@echo "  make pr             (iEDA: P&R)"
	@echo "  make vcs            (Synopsys: Simulation)"
	@echo "  make dc             (Synopsys: Synthesis)"
	@echo "  make icc            (Synopsys: P&R)"
