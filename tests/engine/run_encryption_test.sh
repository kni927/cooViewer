#!/bin/bash
# Encrypted-ZIP gate: build and run test_zip_encryption against the vendored
# libzip, verifying WinZip AES-256 and traditional PKWARE ZipCrypto can be
# decrypted with the correct password (and that a wrong password fails
# cleanly). Requires vendor/build-libs.sh to have run with CommonCrypto
# enabled. No application code is exercised.
set -euo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$ENGINE_DIR/../.." && pwd)"
OUT="$ENGINE_DIR/out"
GEN="$REPO_ROOT/tests/fixtures/generated"
PW="cooViewer-secret-42"
mkdir -p "$OUT" "$GEN"

[ -f "$REPO_ROOT/vendor/lib/libzip.5.dylib" ] ||
    { echo "run vendor/build-libs.sh first" >&2; exit 1; }

# Independent traditional-ZipCrypto fixture created by the system `zip` tool
# (Info-ZIP only produces traditional PKWARE). The payload must match
# g_payload in test_zip_encryption.c: bytes((i*37+11)&0xff) for i in 0..511.
EXT_ARGS=()
if command -v zip >/dev/null 2>&1; then
    python3 - "$OUT/secret.txt" <<'PY'
import sys
open(sys.argv[1], "wb").write(bytes((i*37+11) & 0xff for i in range(512)))
PY
    ( cd "$OUT" && rm -f enc_trad_cli.zip && zip -q -j -P "$PW" enc_trad_cli.zip secret.txt )
    cp "$OUT/enc_trad_cli.zip" "$GEN/enc_trad_cli.zip"
    EXT_ARGS=("$OUT/enc_trad_cli.zip" "$PW")
    echo "prepared external traditional fixture: $GEN/enc_trad_cli.zip"
else
    echo "note: system 'zip' absent; skipping external traditional fixture"
fi

clang -O2 \
    -I "$REPO_ROOT/vendor/include" \
    "$ENGINE_DIR/test_zip_encryption.c" \
    "$REPO_ROOT/vendor/lib/libzip.5.dylib" \
    -Wl,-rpath,"$REPO_ROOT/vendor/lib" \
    -o "$OUT/test_zip_encryption"

"$OUT/test_zip_encryption" "$OUT" "${EXT_ARGS[@]}"
