# AssemblyClaw Makefile — ARM64 macOS Assembly
# The world's smallest AI agent infrastructure

BINARY   = assemblyclaw
BUILDDIR = build
SRCDIR   = src

# Toolchain (use clang for assembly + link — handles SDK/platform automatically)
CC       = clang
STRIP    = strip

# SDK
SDK      = $(shell xcrun --show-sdk-path)

# Sources (order matters for link)
SRCS     = $(SRCDIR)/version.s \
           $(SRCDIR)/error.s \
           $(SRCDIR)/string.s \
           $(SRCDIR)/memory.s \
           $(SRCDIR)/io.s \
           $(SRCDIR)/json.s \
           $(SRCDIR)/http.s \
           $(SRCDIR)/config.s \
           $(SRCDIR)/provider.s \
           $(SRCDIR)/agent.s \
           $(SRCDIR)/main.s

OBJS     = $(SRCS:$(SRCDIR)/%.s=$(BUILDDIR)/%.o)

# Flags
ASFLAGS  = -arch arm64 -c
LDFLAGS  = -arch arm64 -lcurl -Wl,-dead_strip
CFLAGS   = -arch arm64

# Debug flags
ASFLAGS_DEBUG = -arch arm64 -c -g
LDFLAGS_DEBUG = -arch arm64 -lcurl

# Default: release build
.PHONY: all clean debug test bench

all: $(BUILDDIR)/$(BINARY)
	@$(STRIP) -x $(BUILDDIR)/$(BINARY)
	@echo ""
	@echo "Built: $(BUILDDIR)/$(BINARY)"
	@stat -f "Size: %z bytes" $(BUILDDIR)/$(BINARY)
	@echo ""

# Link
$(BUILDDIR)/$(BINARY): $(OBJS)
	@echo "LINK $@"
	@$(CC) $(LDFLAGS) -o $@ $^

# Assemble
$(BUILDDIR)/%.o: $(SRCDIR)/%.s | $(BUILDDIR)
	@echo "  AS $<"
	@$(CC) $(ASFLAGS) -o $@ $<

$(BUILDDIR):
	@mkdir -p $(BUILDDIR)

# Debug build
debug: ASFLAGS = $(ASFLAGS_DEBUG)
debug: LDFLAGS = $(LDFLAGS_DEBUG)
debug: $(BUILDDIR)/$(BINARY)
	@echo ""
	@echo "Debug built: $(BUILDDIR)/$(BINARY)"
	@stat -f "Size: %z bytes" $(BUILDDIR)/$(BINARY)

# Clean
clean:
	@rm -rf $(BUILDDIR)
	@echo "Cleaned."

# Test
test: all
	@echo ""
	@echo "═══ AssemblyClaw Tests ═══"
	@echo ""
	@echo "── CLI Tests ──"
	@echo -n "  --help:     "; $(BUILDDIR)/$(BINARY) --help >/dev/null 2>&1 && echo "PASS" || echo "FAIL"
	@echo -n "  -h:         "; $(BUILDDIR)/$(BINARY) -h >/dev/null 2>&1 && echo "PASS" || echo "FAIL"
	@echo -n "  help:       "; $(BUILDDIR)/$(BINARY) help >/dev/null 2>&1 && echo "PASS" || echo "FAIL"
	@echo -n "  --version:  "; $(BUILDDIR)/$(BINARY) --version >/dev/null 2>&1 && echo "PASS" || echo "FAIL"
	@echo -n "  no args:    "; $(BUILDDIR)/$(BINARY) >/dev/null 2>&1 && echo "PASS" || echo "FAIL"
	@echo -n "  bad cmd:    "; $(BUILDDIR)/$(BINARY) badcmd >/dev/null 2>&1; [ $$? -eq 1 ] && echo "PASS" || echo "FAIL"
	@echo -n "  status:     "; $(BUILDDIR)/$(BINARY) status >/dev/null 2>&1 && echo "PASS" || echo "FAIL"
	@echo ""

# Benchmark
bench: all
	@chmod +x bench.sh
	@./bench.sh
