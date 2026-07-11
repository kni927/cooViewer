#!/bin/bash
# Phase-2 gate: build and run the COArchive harness against every
# fixture archive. Requires vendor/build-libs.sh to have run.
set -euo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$ENGINE_DIR/../.." && pwd)"
GEN="$REPO_ROOT/tests/fixtures/generated"
SRC="$REPO_ROOT/tests/fixtures/src"
OUT="$ENGINE_DIR/out"
mkdir -p "$OUT"

[ -f "$REPO_ROOT/vendor/lib/libarchive.13.dylib" ] ||
    { echo "run vendor/build-libs.sh first" >&2; exit 1; }
[ -f "$GEN/test.zip" ] ||
    { echo "run tests/fixtures/make_fixtures.sh first" >&2; exit 1; }

# corrupt variants, derived from test.zip
head -c 100000 "$GEN/test.zip" > "$GEN/corrupt_truncated.zip"
python3 - "$GEN/test.zip" "$GEN/corrupt_bitflip.zip" <<'EOF'
import sys
data = bytearray(open(sys.argv[1], "rb").read())
for off in range(2000, 2100):   # inside entry #1's deflate stream
    data[off] ^= 0xFF
open(sys.argv[2], "wb").write(bytes(data))
EOF

clang -O2 \
    -I "$REPO_ROOT/vendor/include" \
    -I "$REPO_ROOT" \
    "$ENGINE_DIR/test_coarchive.m" "$REPO_ROOT/COArchive.m" \
    "$REPO_ROOT/vendor/lib/libarchive.13.dylib" \
    "$REPO_ROOT/vendor/lib/libuchardet.0.dylib" \
    -framework Foundation -framework CoreFoundation \
    -Wl,-rpath,"$REPO_ROOT/vendor/lib" \
    -o "$OUT/test_coarchive"

"$OUT/test_coarchive" "$GEN" "$SRC"
