# Synopsys Flow Local Wrappers
# This makefile handles the synchronization and remote execution of Synopsys tools.
# It is meant to be included by the main Makefile when FLOW=synopsys.

# --- Remote Configuration ---
REMOTE_HOST = unix20@100.118.95.3
REMOTE_PROJECT_ROOT = /home/unix20/mac
REMOTE_DOCKER_CONTAINER = mac16_env
REMOTE_DOCKER_WORK_DIR = /work/mac

# --- Sync Targets ---

# A. Sync Local to Remote Host (Volume source)
sync_host:
	@echo "Syncing code to remote host ($(REMOTE_HOST))..."
	rsync -avz --exclude '.git' --exclude 'build*' --exclude 'syn' --exclude 'logs' \
		./ $(REMOTE_HOST):$(REMOTE_PROJECT_ROOT)/

# B. Sync Up (Alias to sync_host)
sync_up: sync_host
	@echo "Code synced to host (Auto-mounted in Docker)."

# One-time setup: Verify PDK on host
setup_remote: sync_host
	@echo "Verifying PDK on remote host..."
	ssh $(REMOTE_HOST) "if [ -d $(REMOTE_PROJECT_ROOT)/icsprout55-pdk ]; then echo 'PDK found.'; else echo 'PDK not found on host!'; exit 1; fi"

# --- Remote Execution Helper ---
# Runs 'make -f synopsys_remote.mk <target>' inside the container
run_remote_%: sync_up
	@echo "Executing '$*' on remote container..."
	ssh $(REMOTE_HOST) "docker exec -w $(REMOTE_DOCKER_WORK_DIR) $(REMOTE_DOCKER_CONTAINER) make -f synopsys_remote.mk $*"

# --- Sync DOWN: Remote -> Local ---
sync_down:
	@echo "Syncing results back from remote..."
	rsync -avz $(REMOTE_HOST):$(REMOTE_PROJECT_ROOT)/build_synopsys/ ./build_synopsys/
	rsync -avz $(REMOTE_HOST):$(REMOTE_PROJECT_ROOT)/logs/ ./logs/ || true

# --- User Facing Targets ---
# These map local targets to the remote execution flow

vcs: run_remote_vcs sync_down
dc: run_remote_dc sync_down
fm: run_remote_fm sync_down
icc: run_remote_icc sync_down

clean_remote:
	ssh $(REMOTE_HOST) "docker exec -w $(REMOTE_DOCKER_WORK_DIR) $(REMOTE_DOCKER_CONTAINER) make -f synopsys_remote.mk clean"

# Help for this flow
help_synopsys:
	@echo "Synopsys Flow Targets:"
	@echo "  make vcs            (Remote: VCS Simulation)"
	@echo "  make dc             (Remote: Design Compiler Synthesis)"
	@echo "  make fm             (Remote: Formality Verification)"
	@echo "  make icc            (Remote: IC Compiler P&R)"
	@echo "  make setup_remote   (Check remote PDK)"
	@echo "  make clean_remote   (Clean remote build dir)"
