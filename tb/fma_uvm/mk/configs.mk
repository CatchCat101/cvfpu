FORMAT ?= FP32
CFG ?= n0_before
TEST ?= fma_smoke_test
SEED ?= 1
NB_TXNS ?= 1000
PROFILE ?= fast
RUN_PLUSARGS ?=

SUPPORTED_FORMATS := FP16 FP32 FP64

CFG_n0_before := 0 0
CFG_n2_before := 2 0
CFG_n2_inside := 2 2
CFG_n2_after  := 2 1
CFG_n1_dist   := 1 3
CFG_n2_dist   := 2 3
CFG_n3_dist   := 3 3
CFG_n4_dist   := 4 3

ALL_CFGS := n0_before n2_before n2_inside n2_after \
	       n1_dist n2_dist n3_dist n4_dist
CFG_VALUES := $(CFG_$(CFG))
NUM_PIPE_REGS := $(word 1,$(CFG_VALUES))
PIPE_CONFIG := $(word 2,$(CFG_VALUES))

FORMAT_DEFINE_FP16 := +define+FMA_FORMAT_FP16
FORMAT_DEFINE_FP32 := +define+FMA_FORMAT_FP32
FORMAT_DEFINE_FP64 := +define+FMA_FORMAT_FP64
FORMAT_DEFINE := $(FORMAT_DEFINE_$(FORMAT))

.PHONY: doctor_config
doctor_config:
	@test -n "$(filter $(FORMAT),$(SUPPORTED_FORMATS))" || { \
		echo "Unsupported FORMAT=$(FORMAT); choose FP16, FP32 or FP64"; exit 2; }
	@test -n "$(CFG_VALUES)" || { echo "Unknown CFG=$(CFG)"; exit 2; }
	@test "$(PROFILE)" = fast -o "$(PROFILE)" = debug -o "$(PROFILE)" = cov || { \
		echo "Unknown PROFILE=$(PROFILE)"; exit 2; }
