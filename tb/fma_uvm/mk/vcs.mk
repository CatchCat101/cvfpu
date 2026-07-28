VCS ?= vcs

BUILD_DIR := $(FMA_UVM_DIR)/build/$(FORMAT)/$(CFG)/$(PROFILE)
SIMV := $(BUILD_DIR)/simv
RUN_DIR := $(FMA_UVM_DIR)/runs/$(FORMAT)/$(CFG)/$(TEST)/seed_$(SEED)
LOG := $(RUN_DIR)/run.log
CM_NAME := $(FORMAT)__$(CFG)__$(TEST)__$(SEED)

VCS_COMMON := -full64 -sverilog -timescale=1ns/1ps -ntb_opts uvm-1.2 \
	-top fma_tb_top -Mdir=$(BUILD_DIR)/csrc \
	+incdir+$(ROOT)/src/common_cells/include \
	$(FORMAT_DEFINE) \
	+define+FMA_NUM_PIPE_REGS=$(NUM_PIPE_REGS) \
	+define+FMA_PIPE_CONFIG=$(PIPE_CONFIG)

ifeq ($(PROFILE),debug)
  PROFILE_COMPILE_FLAGS := -debug_access+r -kdb
  PROFILE_RUN_FLAGS :=
else ifeq ($(PROFILE),cov)
  PROFILE_COMPILE_FLAGS := -cm line+cond+branch+tgl+fsm+assert \
	-cm_hier $(FMA_UVM_DIR)/cfg/cm_hier.cfg
  PROFILE_RUN_FLAGS := -cm line+cond+branch+tgl+fsm+assert \
	-cm_name $(CM_NAME) -cm_dir $(RUN_DIR)/simv.vdb
else
  PROFILE_COMPILE_FLAGS :=
  PROFILE_RUN_FLAGS :=
endif
