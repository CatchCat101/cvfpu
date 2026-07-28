.PHONY: regress cov-report cov-check

SUITE ?= smoke
FORMATS ?= FP16,FP32,FP64
JOBS ?= 1

regress:
	python3 $(FMA_UVM_DIR)/scripts/regress.py \
		--root $(ROOT) --suite $(FMA_UVM_DIR)/cfg/$(SUITE).json \
		--formats $(FORMATS) --profile $(PROFILE) --jobs $(JOBS)

cov-report:
	python3 $(FMA_UVM_DIR)/scripts/coverage_report.py \
		--run-root $(FMA_UVM_DIR)/runs --format $(FORMAT) \
		--report $(FMA_UVM_DIR)/reports/coverage/$(FORMAT)

cov-check: cov-report
	python3 $(FMA_UVM_DIR)/scripts/check_coverage.py \
		$(FMA_UVM_DIR)/reports/coverage/$(FORMAT) \
		--line 95 --branch 95 --condition 95 --toggle 90 --functional 100
