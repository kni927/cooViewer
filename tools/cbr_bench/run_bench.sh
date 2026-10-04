#!/bin/bash
# tools/cbr_bench/run_bench.sh — build the harnesses, generate the corpus,
# run every scenario, write results.jsonl. See README.md.
#
# Environment:
#   OUT         work directory (default: $TMPDIR/cbr_bench); nothing is
#               written inside the repository
#   BEFORE_REF  git ref whose Sources/ form the "before" build (default HEAD)
#   V137_DIR    optional: a directory prepared as in README.md (v1.3.7's
#               XADWrapper/XADItem/NSString_Compare sources and
#               build/Release/XADMaster.framework); adds the "v137" build
#   RUNS        runs per scenario (default 3)
#   FILES       archive names in the corpus (default: all five)
#   SCENARIOS   default: "open seq paced jump"
set -euo pipefail

TOOL_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$TOOL_DIR/../.." && pwd)"
OUT="${OUT:-${TMPDIR:-/tmp}/cbr_bench}"
BEFORE_REF="${BEFORE_REF:-HEAD}"
RUNS="${RUNS:-3}"
FILES="${FILES:-r4n r4n_small r5n r5n_small r5s}"
SCENARIOS="${SCENARIOS:-open seq paced jump}"
mkdir -p "$OUT/bin"

[ -f "$REPO_ROOT/vendor/lib/libarchive.13.dylib" ] ||
    { echo "run vendor/build-libs.sh first" >&2; exit 1; }
command -v rar >/dev/null || { echo "rar is required for the RAR5 corpus" >&2; exit 1; }

# --- corpus
clang -O2 "$TOOL_DIR/gen_pages.m" -framework Foundation -framework CoreGraphics \
    -framework ImageIO -o "$OUT/bin/gen_pages"
python3 "$TOOL_DIR/make_corpus.py" "$OUT/bin/gen_pages" "$OUT/corpus"

# --- harness builds. CORarArchive.m is compiled on its own so that its
# stream opens go through bench.m's counters.
build_libarchive_harness() {	# <name> <sources-dir>
    local name="$1" src="$2" obj="$OUT/obj/$1"
    mkdir -p "$obj"
    local common=(-O2 -I "$REPO_ROOT/vendor/include" -I "$src")
    clang "${common[@]}" -c "$src/CORarArchive.m" -o "$obj/CORarArchive.o" \
        -Darchive_read_open_filename=cobench_open_filename \
        -Darchive_read_open2=cobench_open2
    clang "${common[@]}" "$TOOL_DIR/bench.m" "$obj/CORarArchive.o" \
        "$src/COArchive.m" "$src/COZipArchive.m" "$src/CORarHeaderIndex.m" \
        "$src/NSString_Compare.m" \
        "$REPO_ROOT/vendor/lib/libarchive.13.dylib" \
        "$REPO_ROOT/vendor/lib/libuchardet.0.dylib" \
        "$REPO_ROOT/vendor/lib/libzip.5.dylib" \
        -framework Foundation -framework CoreFoundation -framework CoreServices \
        -framework ImageIO -framework CoreGraphics \
        -Wl,-rpath,"$REPO_ROOT/vendor/lib" -o "$OUT/bin/bench-$name"
}

build_libarchive_harness current "$REPO_ROOT/Sources"

rm -rf "$OUT/before-src"
mkdir -p "$OUT/before-src"
git -C "$REPO_ROOT" archive -o "$OUT/before-src.tar" "$BEFORE_REF" Sources
tar -xf "$OUT/before-src.tar" -C "$OUT/before-src"
build_libarchive_harness before "$OUT/before-src/Sources"
IMPLS="before current"

if [ -n "${V137_DIR:-}" ]; then
    # v1.3.7 passes nil as an NSStringEncoding; current clang makes that an error
    clang -O2 -Wno-error=int-conversion -DBENCH_XAD -I "$V137_DIR" -F "$V137_DIR/build/Release" \
        "$TOOL_DIR/bench.m" "$V137_DIR/XADWrapper.m" "$V137_DIR/XADItem.m" \
        "$V137_DIR/NSString_Compare.m" \
        -framework XADMaster -framework Cocoa -framework ImageIO \
        -Wl,-rpath,"$V137_DIR/build/Release" -o "$OUT/bin/bench-v137"
    IMPLS="v137 before current"
fi

# --- runs. Warm cache: the archive is read once right before every run
# (purge needs sudo). The order of the builds rotates between runs.
RESULTS="$OUT/results.jsonl"
: > "$RESULTS"
read -r -a impls <<< "$IMPLS"
for run in $(seq 1 "$RUNS"); do
    for file in $FILES; do
        archive="$OUT/corpus/$file.cbr"
        for scenario in $SCENARIOS; do
            n=${#impls[@]}
            for k in $(seq 0 $((n - 1))); do
                impl="${impls[$(( (k + run) % n ))]}"
                cat "$archive" > /dev/null
                json="$("$OUT/bin/bench-$impl" "$scenario" "$archive" 2>> "$OUT/stderr.log")"
                echo "{\"impl\":\"$impl\",\"run\":$run,\"file\":\"$file\",${json#\{}" \
                    >> "$RESULTS"
                echo "run $run $file $scenario $impl done" >&2
            done
        done
    done
done
python3 "$TOOL_DIR/summarize.py" "$RESULTS"
