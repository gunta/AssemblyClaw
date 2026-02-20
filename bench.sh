#!/bin/bash
# AssemblyClaw Benchmark Suite
# Measures binary size, RAM usage, startup time, and throughput

set -euo pipefail

BINARY="./build/assemblyclaw"
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

header() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  AssemblyClaw Benchmark Suite${NC}"
    echo -e "${BOLD}  $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${BOLD}  $(uname -m) / $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'unknown')${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
}

section() {
    echo ""
    echo -e "${CYAN}── $1 ──${NC}"
}

metric() {
    printf "  %-30s ${GREEN}%s${NC}\n" "$1" "$2"
}

warn() {
    printf "  %-30s ${YELLOW}%s${NC}\n" "$1" "$2"
}

# Check binary exists
if [ ! -f "$BINARY" ]; then
    echo "Binary not found. Building..."
    make
fi

header

# ── Binary Size ──
section "Binary Size"
SIZE_BYTES=$(stat -f%z "$BINARY" 2>/dev/null || stat -c%s "$BINARY" 2>/dev/null)
SIZE_KB=$(echo "scale=2; $SIZE_BYTES / 1024" | bc)
metric "Binary size" "${SIZE_KB} KB ($SIZE_BYTES bytes)"

# Compare to others
metric "vs NullClaw (Zig)" "678 KB"
metric "vs CClaw (C)" "~100 KB"
RATIO=$(echo "scale=1; 678 * 1024 / $SIZE_BYTES" | bc 2>/dev/null || echo "N/A")
metric "Size ratio (NullClaw/Asm)" "${RATIO}x smaller"

# ── Sections breakdown ──
section "Binary Sections"
if command -v size &>/dev/null; then
    size "$BINARY" 2>/dev/null | tail -1 | while read text data bss total rest; do
        metric "__TEXT (code)" "$text bytes"
        metric "__DATA (data)" "$data bytes"
        metric "__BSS (zeroed)" "$bss bytes"
    done
fi

# ── Startup Time ──
section "Startup Time (--help)"
# Warm up
"$BINARY" --help >/dev/null 2>&1 || true

# Measure with /usr/bin/time
TIMES=()
for i in $(seq 1 10); do
    # Use gtime if available, otherwise /usr/bin/time
    if command -v gtime &>/dev/null; then
        T=$( { gtime -f "%e" "$BINARY" --help >/dev/null; } 2>&1 )
    else
        T=$( { /usr/bin/time -p "$BINARY" --help >/dev/null; } 2>&1 | grep real | awk '{print $2}' )
    fi
    TIMES+=("$T")
done

# Calculate average (using bc)
SUM=0
for t in "${TIMES[@]}"; do
    SUM=$(echo "$SUM + $t" | bc 2>/dev/null || echo "0")
done
AVG=$(echo "scale=6; $SUM / ${#TIMES[@]}" | bc 2>/dev/null || echo "N/A")
AVG_MS=$(echo "scale=3; $AVG * 1000" | bc 2>/dev/null || echo "N/A")
metric "Average (10 runs)" "${AVG_MS} ms"
metric "vs NullClaw" "< 2 ms"

# ── Memory Usage ──
section "Memory Usage"
# Use /usr/bin/time -l for peak RSS on macOS
MEM_OUT=$( { /usr/bin/time -l "$BINARY" --help >/dev/null; } 2>&1 )
RSS=$(echo "$MEM_OUT" | grep "maximum resident" | awk '{print $1}')
if [ -n "$RSS" ]; then
    RSS_KB=$(echo "scale=2; $RSS / 1024" | bc 2>/dev/null || echo "N/A")
    metric "Peak RSS" "${RSS_KB} KB ($RSS bytes)"
    metric "vs NullClaw" "~1 MB (1024 KB)"
else
    warn "Peak RSS" "Could not measure"
fi

# ── Page Faults ──
PAGEFAULTS=$(echo "$MEM_OUT" | grep "page faults" | head -1 | awk '{print $1}')
if [ -n "$PAGEFAULTS" ]; then
    metric "Page faults" "$PAGEFAULTS"
fi

# ── Mach-O Info ──
section "Mach-O Details"
if command -v otool &>/dev/null; then
    LIBS=$(otool -L "$BINARY" 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
    metric "Linked libraries" "$LIBS"
    otool -L "$BINARY" 2>/dev/null | tail -n +2 | while read -r line; do
        LIB=$(echo "$line" | awk '{print $1}')
        metric "  →" "$LIB"
    done
fi

# ── Summary ──
section "Summary"
echo ""
echo -e "  ${BOLD}AssemblyClaw${NC}"
echo -e "  Binary: ${GREEN}${SIZE_KB} KB${NC}"
echo -e "  RAM:    ${GREEN}${RSS_KB:-?} KB${NC}"
echo -e "  Start:  ${GREEN}${AVG_MS:-?} ms${NC}"
echo ""
echo -e "  ${BOLD}Target${NC}"
echo -e "  Binary: < 32 KB"
echo -e "  RAM:    < 128 KB"
echo -e "  Start:  < 0.1 ms"
echo ""
