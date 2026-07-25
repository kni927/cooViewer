#!/bin/bash
# COZipArchive password gate: build and run test_zip_password against
# encrypted and plain ZIP fixtures. Requires vendor/build-libs.sh to have
# run with CommonCrypto enabled. Exercises the reader layer only (no app,
# no UI); the password is supplied directly by the test.
set -euo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$ENGINE_DIR/../.." && pwd)"
OUT="$ENGINE_DIR/out"
PW="cooViewer-secret-42"
mkdir -p "$OUT"

[ -f "$REPO_ROOT/vendor/lib/libzip.5.dylib" ] ||
    { echo "run vendor/build-libs.sh first" >&2; exit 1; }

# 1. encrypted fixtures (enc_aes.zip, enc_trad.zip) via the libzip-level
#    generator, which also self-checks the crypto build.
clang -O2 -I "$REPO_ROOT/vendor/include" \
    "$ENGINE_DIR/test_zip_encryption.c" \
    "$REPO_ROOT/vendor/lib/libzip.5.dylib" \
    -Wl,-rpath,"$REPO_ROOT/vendor/lib" \
    -o "$OUT/test_zip_encryption"
"$OUT/test_zip_encryption" "$OUT" >/dev/null

# 2. plain (non-encrypted) fixture with the same entry/payload.
python3 - "$OUT/secret.txt" <<'PY'
import sys
open(sys.argv[1], "wb").write(bytes((i*37+11) & 0xff for i in range(512)))
PY
( cd "$OUT" && rm -f plain.zip && zip -q -j plain.zip secret.txt )

# 3. COZipArchive-level test.
clang -O2 \
    -I "$REPO_ROOT/vendor/include" \
    -I "$REPO_ROOT/Sources" \
    "$ENGINE_DIR/test_zip_password.m" \
    "$REPO_ROOT/Sources/COArchive.m" "$REPO_ROOT/Sources/COZipArchive.m" \
    "$REPO_ROOT/Sources/CORarArchive.m" "$REPO_ROOT/Sources/CORarHeaderIndex.m" \
    "$REPO_ROOT/vendor/lib/libarchive.13.dylib" \
    "$REPO_ROOT/vendor/lib/libuchardet.0.dylib" \
    "$REPO_ROOT/vendor/lib/libzip.5.dylib" \
    -framework Foundation -framework CoreFoundation \
    -Wl,-rpath,"$REPO_ROOT/vendor/lib" \
    -o "$OUT/test_zip_password"

"$OUT/test_zip_password" "$OUT"
