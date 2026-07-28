SHELL := /bin/bash

FMA_UVM_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
ROOT := $(abspath $(FMA_UVM_DIR)/../..)

include $(FMA_UVM_DIR)/mk/configs.mk
include $(FMA_UVM_DIR)/mk/ref_models.mk
include $(FMA_UVM_DIR)/mk/vcs.mk
include $(FMA_UVM_DIR)/mk/regress.mk

.PHONY: doctor build compile run run-only smoke directed flow flush reset \
	random-data random-control clean

doctor: doctor_config doctor_ref
	@command -v $(VCS) >/dev/null || { echo "VCS not found"; exit 2; }
	@test -s "$(ROOT)/src/common_cells/src/lzc.sv" || { \
		echo "Initialize src/common_cells"; exit 2; }
	@echo "FORMAT=$(FORMAT) CFG=$(CFG) NumPipeRegs=$(NUM_PIPE_REGS) PipeConfig=$(PIPE_CONFIG) PROFILE=$(PROFILE)"

build compile: doctor build_ref
	@mkdir -p $(BUILD_DIR)
	cd $(ROOT) && $(VCS) $(VCS_COMMON) $(PROFILE_COMPILE_FLAGS) \
		-CFLAGS "$(DPI_CFLAGS)" -LDFLAGS "$(DPI_LDFLAGS)" \
		$(DPI_SRC) -f tb/fma_uvm/filelist.f -o $(SIMV) \
		-l $(BUILD_DIR)/compile.log

run: compile
	$(MAKE) run-only FORMAT=$(FORMAT) CFG=$(CFG) PROFILE=$(PROFILE) \
		TEST=$(TEST) SEED=$(SEED) NB_TXNS=$(NB_TXNS)

run-only:
	@test -x $(SIMV) || { echo "Missing $(SIMV); run make compile first"; exit 2; }
	@mkdir -p $(RUN_DIR)
	cd $(RUN_DIR) && $(SIMV) +UVM_TESTNAME=$(TEST) \
		+ntb_random_seed=$(SEED) +NB_TXNS=$(NB_TXNS) $(RUN_PLUSARGS) \
		$(PROFILE_RUN_FLAGS) -l $(LOG)

smoke:
	$(MAKE) run TEST=fma_smoke_test NB_TXNS=0

directed:
	$(MAKE) run TEST=fma_directed_test NB_TXNS=0

flow:
	$(MAKE) run TEST=fma_flow_control_test NB_TXNS=0

flush:
	$(MAKE) run TEST=fma_flush_test NB_TXNS=0

reset:
	$(MAKE) run TEST=fma_reset_test NB_TXNS=0

random-data:
	$(MAKE) run TEST=fma_random_data_test

random-control:
	$(MAKE) run TEST=fma_random_control_test

clean:
	rm -rf $(FMA_UVM_DIR)/build $(FMA_UVM_DIR)/runs $(FMA_UVM_DIR)/reports
