#!/bin/bash
# tools/cbr_bench/run_bench.sh — build the harnesses, generate the corpus,
# run every scenario, write results.jsonl. See README.md.
#
# Environment:
#   OUT            work directory (default: $TMPDIR/cbr_bench); nothing is
#                  written inside the repository
#   BEFORE_REF     git ref whose Sources/ form the "before" build (default HEAD)
#   AFTER_REF      optional git ref for the "current" build; unset (default)
#                  builds "current" from the working tree, uncommitted and
#                  untracked changes included
#   EXTRA_SOURCES  optional: more Sources/*.m file names the archive layer
#                  needs (e.g. a new file added by the change under test);
#                  each is compiled into a build only if that build's tree
#                  has it
#   V137_DIR       optional: a directory prepared as in README.md (v1.3.7's
#                  XADWrapper/XADItem/NSString_Compare sources and
#                  build/Release/XADMaster.framework); adds the "v137" build
#   RUNS           runs per scenario (default 3)
#   FILES          corpus file names (default: the seven in make_corpus.py's
#                  DEFAULT); LARGE=1 adds r5n_large r5s_large s7s_large
#   SCENARIOS      default: "open seq paced jump back"; "idlejump" is opt-in
#   BENCH_IDLE_MS  idlejump's wait after open (default 10000)
#   BENCH_COUNTERS more archive counter method names to report (bench.m)
set -euo pipefail

TOOL_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$TOOL_DIR/../.." && pwd)"
OUT="${OUT:-${TMPDIR:-/tmp}/cbr_bench}"
BEFORE_REF="${BEFORE_REF:-HEAD}"
AFTER_REF="${AFTER_REF:-}"
RUNS="${RUNS:-3}"
FILES="${FILES:-r4n r4n_small r5n r5n_small r5s r5n_ordered s7s}"
[ "${LARGE:-0}" = 1 ] && FILES="$FILES r5n_large r5s_large s7s_large"
SCENARIOS="${SCENARIOS:-open seq paced jump back}"
EXTRA_SOURCES="${EXTRA_SOURCES:-}"
mkdir -p "$OUT/bin"

[ -f "$REPO_ROOT/vendor/lib/libarchive.13.dylib" ] ||
    { echo "run vendor/build-libs.sh first" >&2; exit 1; }

# --- corpus (make_corpus.py checks for rar / 7zz as each file needs them)
clang -O2 "$TOOL_DIR/gen_pages.m" -framework Foundation -framework CoreGraphics \
    -framework ImageIO -o "$OUT/bin/gen_pages"
# shellcheck disable=SC2086
python3 "$TOOL_DIR/make_corpus.py" "$OUT/bin/gen_pages" "$OUT/corpus" $FILES

corpus_path() {	# <name> -> the corpus file, whatever its suffix
    local f
    for f in "$OUT/corpus/$1.cbr" "$OUT/corpus/$1.cb7"; do
        [ -f "$f" ] && { echo "$f"; return; }
    done
    echo "no corpus file for $1" >&2
    exit 1
}

# --- harness builds. Every archive-layer source is compiled with
# archive_read_open_filename / archive_read_open2 renamed to bench.m's
# counters, so stream opens after the open are counted wherever they happen.
build_libarchive_harness() {	# <name> <sources-dir>
    local name="$1" src="$2" obj="$OUT/obj/$1"
    rm -rf "$obj"
    mkdir -p "$obj"
    local common=(-O2 -I "$REPO_ROOT/vendor/include" -I "$src"
        -Darchive_read_open_filename=cobench_open_filename
        -Darchive_read_open2=cobench_open2)
    local objs=() f
    for f in COArchive.m COZipArchive.m CORarArchive.m CORarHeaderIndex.m NSString_Compare.m \
             $EXTRA_SOURCES; do
        [ -f "$src/$f" ] || continue
        clang "${common[@]}" -c "$src/$f" -o "$obj/${f%.m}.o"
        objs+=("$obj/${f%.m}.o")
    done
    clang -O2 -I "$REPO_ROOT/vendor/include" -I "$src" "$TOOL_DIR/bench.m" "${objs[@]}" \
        "$REPO_ROOT/vendor/lib/libarchive.13.dylib" \
        "$REPO_ROOT/vendor/lib/libuchardet.0.dylib" \
        "$REPO_ROOT/vendor/lib/libzip.5.dylib" \
        -framework Foundation -framework CoreFoundation -framework CoreServices \
        -framework ImageIO -framework CoreGraphics \
        -Wl,-rpath,"$REPO_ROOT/vendor/lib" -o "$OUT/bin/bench-$name"
}

export_ref() {	# <ref> <dir>: the ref's Sources/ into <dir>/Sources
    rm -rf "$2"
    mkdir -p "$2"
    git -C "$REPO_ROOT" archive -o "$2.tar" "$1" Sources
    tar -xf "$2.tar" -C "$2"
}

BUILDS="$OUT/builds.txt"
if [ -n "$AFTER_REF" ]; then
    export_ref "$AFTER_REF" "$OUT/after-src"
    build_libarchive_harness current "$OUT/after-src/Sources"
    echo "current: $AFTER_REF ($(git -C "$REPO_ROOT" rev-parse --short "$AFTER_REF"))" > "$BUILDS"
else
    build_libarchive_harness current "$REPO_ROOT/Sources"
    echo "current: working tree on $(git -C "$REPO_ROOT" rev-parse --short HEAD);" \
        "Sources changes: $(git -C "$REPO_ROOT" status --porcelain -- Sources | wc -l | tr -d ' ') files" \
        > "$BUILDS"
fi
export_ref "$BEFORE_REF" "$OUT/before-src"
build_libarchive_harness before "$OUT/before-src/Sources"
echo "before: $BEFORE_REF ($(git -C "$REPO_ROOT" rev-parse --short "$BEFORE_REF"))" >> "$BUILDS"
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
cat "$BUILDS" >&2

# --- runs. Warm cache: the archive is read once right before every run
# (purge needs sudo). The order of the builds rotates between runs.
RESULTS="$OUT/results.jsonl"
: > "$RESULTS"
read -r -a impls <<< "$IMPLS"
for run in $(seq 1 "$RUNS"); do
    for file in $FILES; do
        archive="$(corpus_path "$file")"
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
