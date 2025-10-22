# Detect OS
UNAME_S := $(shell uname -s)

# Compiler settings
CC = gcc
CFLAGS = -Wall -Wextra -O2 -fPIC -std=c11
LDFLAGS = -shared

# Output
ifeq ($(UNAME_S),Linux)
    TARGET = libdiff_core.so
else ifeq ($(UNAME_S),Darwin)
    TARGET = libdiff_core.dylib
else
    TARGET = diff_core.dll
endif

# Source files
SRC = c-diff-core/diff_core.c
OBJ = $(SRC:.c=.o)

# Build targets
all: $(TARGET)

$(TARGET): $(OBJ)
	$(CC) $(LDFLAGS) -o $@ $^

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

test: c-diff-core/test_diff_core.c c-diff-core/diff_core.c
	$(CC) $(CFLAGS) -o test_diff_core $^
	./test_diff_core

clean:
	rm -f $(OBJ) $(TARGET) test_diff_core

.PHONY: all test clean
