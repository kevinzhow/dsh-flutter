SHELL := /bin/bash
.DEFAULT_GOAL := help
SRC := $(wildcard src/*.c) $(shell find lib -name '*.c')
OBJ = $(SRC:.c=.o)
override CFLAGS += -I include \
	-DVER=\"1.0\"
export PATH := $(HOME)/bin:$(PATH)
-include $(OBJ:.o=.d)

define RECIPE
	@echo "building $(1)"
endef

.PHONY: help test
help: ## show help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "} {printf "%-10s %s\n", $$1, $$2}'

$(OBJ): %.o: %.c Makefile
	$(call RECIPE,$@)
	$(CC) -MMD -c $< -o $@ # comment

test: $(if $(filter yes,$(CI)),ci,local) | outdir
	for f in tests/*; do \
		echo "$$f"; \
	done
ifdef VERBOSE
  Q :=
else ifneq ($(origin X),undefined)
  Q := @
endif
%.pdf: %.md ; pandoc $< -o $@
.SECONDEXPANSION:
a b: c d
