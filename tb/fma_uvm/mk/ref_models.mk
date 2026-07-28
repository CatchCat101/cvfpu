SOFTFLOAT_DIR ?= $(ROOT)/tb/berkeley-softfloat-3
SOFTFLOAT_BUILD := $(SOFTFLOAT_DIR)/build/Linux-x86_64-GCC
SOFTFLOAT_LIB := $(SOFTFLOAT_BUILD)/softfloat.a
SOFTFLOAT_EXPECTED_COMMIT ?= a0c6494cdc11865811dec815d5c0049fba9d82a8
ALLOW_UNPINNED_REF ?= 0
CC ?= gcc

DPI_SRC := tb/fma_uvm/dpi/softfloat/fma_softfloat_ref.c
DPI_CFLAGS := -I$(FMA_UVM_DIR)/dpi/include -I$(SOFTFLOAT_DIR)/source/include
DPI_LDFLAGS := -Wl,--whole-archive $(SOFTFLOAT_LIB) -Wl,--no-whole-archive
SELFTEST := $(FMA_UVM_DIR)/build/softfloat-selftest/fma_softfloat_selftest

.PHONY: doctor_ref build_ref selftest
doctor_ref:
	@test -s "$(SOFTFLOAT_DIR)/source/f16_mulAdd.c" \
		-a -s "$(SOFTFLOAT_DIR)/source/f32_mulAdd.c" \
		-a -s "$(SOFTFLOAT_DIR)/source/f64_mulAdd.c" || { \
		echo "Initialize tb/berkeley-softfloat-3 or set SOFTFLOAT_DIR"; exit 2; }
	@if test "$(ALLOW_UNPINNED_REF)" != 1; then \
		actual=$$(git -C "$(SOFTFLOAT_DIR)" rev-parse HEAD 2>/dev/null) || { \
			echo "SOFTFLOAT_DIR is not a Git checkout; use ALLOW_UNPINNED_REF=1 to override"; exit 2; }; \
		test "$$actual" = "$(SOFTFLOAT_EXPECTED_COMMIT)" || { \
			echo "SoftFloat commit $$actual != $(SOFTFLOAT_EXPECTED_COMMIT)"; exit 2; }; \
	fi

build_ref: doctor_ref
	$(MAKE) -C $(SOFTFLOAT_BUILD) -j$(JOBS) SPECIALIZE_TYPE=RISCV

selftest: build_ref
	@mkdir -p $(dir $(SELFTEST))
	$(CC) -std=c11 -Wall -Wextra -Werror $(DPI_CFLAGS) \
		$(FMA_UVM_DIR)/dpi/softfloat/fma_softfloat_ref.c \
		$(FMA_UVM_DIR)/dpi/softfloat/fma_softfloat_selftest.c \
		$(SOFTFLOAT_LIB) -o $(SELFTEST)
	$(SELFTEST)
