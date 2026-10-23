# Build rules
CC ?= gcc
CFLAGS := -O2 -Wall $(EXTRA)
OBJS = main.o util.o
VERSION = 1.2.3

.PHONY: all clean

all: app

app: $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^ -lm

%.o: %.c
	@echo "compiling $<"
	$(CC) $(CFLAGS) -c $< -o $@

ifeq ($(DEBUG),1)
CFLAGS += -g
else
CFLAGS += -DNDEBUG
endif

define HELP
usage: make [target]
endef

clean:
	rm -f $(OBJS) app  # remove outputs
include deps.mk
