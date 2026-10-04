#!/bin/bash
# Phase-2 gate: build and run the COArchive harness against every
# fixture archive. Requires vendor/build-libs.sh to have run.
set -euo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$ENGINE_DIR/../.." && pwd)"
GEN="$REPO_ROOT/tests/fixtures/generated"
SRC="$REPO_ROOT/tests/fixtures/src"
RAR5_FINAL="$REPO_ROOT/tests/fixtures/sample/header_error_sample.rar"
OUT="$ENGINE_DIR/out"
mkdir -p "$OUT"

[ -f "$REPO_ROOT/vendor/lib/libarchive.13.dylib" ] && [ -f "$REPO_ROOT/vendor/lib/libzip.5.dylib" ] ||
    { echo "run vendor/build-libs.sh first" >&2; exit 1; }
[ -f "$GEN/test.zip" ] ||
    { echo "run tests/fixtures/make_fixtures.sh first" >&2; exit 1; }
[ -f "$RAR5_FINAL" ] ||
    { echo "missing tests/fixtures/sample/header_error_sample.rar" >&2; exit 1; }

# corrupt variants, derived from test.zip
head -c 100000 "$GEN/test.zip" > "$GEN/corrupt_truncated.zip"
python3 - "$GEN/test.zip" "$GEN/corrupt_bitflip.zip" <<'EOF'
import sys
data = bytearray(open(sys.argv[1], "rb").read())
for off in range(2000, 2100):   # inside entry #1's deflate stream
    data[off] ^= 0xFF
open(sys.argv[2], "wb").write(bytes(data))
EOF

# corrupt variants, derived from test.cbr (rar-only, optional like test.cbr)
if [ -f "$GEN/test.cbr" ]; then
    head -c 50000 "$GEN/test.cbr" > "$GEN/corrupt_truncated.cbr"
    python3 - "$GEN/test.cbr" "$GEN/corrupt_bitflip.cbr" <<'EOF'
import sys
data = bytearray(open(sys.argv[1], "rb").read())
for off in range(150000, 150100):   # inside entry #2's compressed stream
    data[off] ^= 0xFF
open(sys.argv[2], "wb").write(bytes(data))
EOF
fi

# hostile-metadata fixtures (long names, "../" nested archive, oversized RAR4,
# unreadable and repeated nested archives, repeated entry names)
python3 "$REPO_ROOT/tests/fixtures/make_hostile_fixtures.py" "$GEN" "$SRC"

# solid RAR4, refused at open (KNOWN_ISSUES #39); the Unicode-named one
# takes the libarchive fallback path rather than the header index
python3 "$REPO_ROOT/tests/fixtures/make_rar4_fixture.py" --solid "$SRC" "$GEN/test_rar4_solid.cbr" >/dev/null
python3 "$REPO_ROOT/tests/fixtures/make_rar4_fixture.py" --solid --unicode-names \
    "$SRC" "$GEN/test_rar4_solid_unicode.cbr" >/dev/null

# non-solid archives whose stored order is not page order, for direct
# positioning (B1): RAR4 by the hand-written generator, RAR5 by rar when
# installed. The Unicode-named RAR4 takes the libarchive fallback index
# pass and so keeps the fast-forward cursor.
python3 "$REPO_ROOT/tests/fixtures/make_rar4_fixture.py" --order 3,1,4,2 \
    "$SRC" "$GEN/test_rar4_unordered.cbr" >/dev/null
python3 "$REPO_ROOT/tests/fixtures/make_rar4_fixture.py" --order 3,1,4,2 --unicode-names \
    "$SRC" "$GEN/test_rar4_unordered_unicode.cbr" >/dev/null
if command -v rar >/dev/null 2>&1; then
    rm -f "$GEN/test_rar5_unordered.cbr"
    (cd "$SRC" && rar a -idq "$GEN/test_rar5_unordered.cbr" 003.png 001.png 004.jpg 002.jpg)
fi

# B2: a non-solid RAR4 stored in page order whose entries are larger than the
# reader's 256 KB decode chunk, so a prefetch can be stopped part-way through
# one. The entries are pseudo-random bytes (not images); the harness compares
# them with the files in rar4_large_src.
LARGE_SRC="$GEN/rar4_large_src"
python3 - "$LARGE_SRC" <<'EOF'
import pathlib, random, sys
out = pathlib.Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
rng = random.Random(20261004)
for name in ("001.png", "002.jpg", "003.png", "004.jpg"):
    (out / name).write_bytes(rng.randbytes(1024 * 1024))
EOF
python3 "$REPO_ROOT/tests/fixtures/make_rar4_fixture.py" \
    "$LARGE_SRC" "$GEN/test_rar4_large.cbr" >/dev/null

# B3: a solid RAR5 whose entries (1 MB each) are larger than the reader's
# 256 KB decode chunk, for decode-ahead
if command -v rar >/dev/null 2>&1; then
    rm -f "$GEN/test_rar5_solid_large.cbr"
    (cd "$LARGE_SRC" && rar a -idq -s "$GEN/test_rar5_solid_large.cbr" 001.png 002.jpg 003.png 004.jpg)
fi

# link entries between pages (code review M6): a Unix symbolic link in the
# hand-written RAR4 (header index, and libarchive fallback with Unicode
# names), and a symbolic plus a hard link in RAR5 by rar when installed
python3 "$REPO_ROOT/tests/fixtures/make_rar4_fixture.py" --symlink \
    "$SRC" "$GEN/test_rar4_links.cbr" >/dev/null
python3 "$REPO_ROOT/tests/fixtures/make_rar4_fixture.py" --symlink --unicode-names \
    "$SRC" "$GEN/test_rar4_links_unicode.cbr" >/dev/null
if command -v rar >/dev/null 2>&1; then
    LINKS_SRC="$GEN/rar5_links_src"
    rm -rf "$LINKS_SRC" && mkdir "$LINKS_SRC"
    cp "$SRC"/00?.* "$LINKS_SRC/"
    ln -s 001.png "$LINKS_SRC/001_link.png"
    ln "$LINKS_SRC/003.png" "$LINKS_SRC/003_hard.png"
    rm -f "$GEN/test_rar5_links.cbr"
    (cd "$LINKS_SRC" && rar a -idq -ol -oh "$GEN/test_rar5_links.cbr" \
        001.png 001_link.png 002.jpg 003.png 003_hard.png 004.jpg)
    rm -rf "$LINKS_SRC"
fi

# books with no readable pages, and one with a single corrupt page
# (KNOWN_ISSUES #30)
NO_PAGES="$GEN/no_pages"
rm -rf "$NO_PAGES" && mkdir -p "$NO_PAGES/empty_dir" "$NO_PAGES/text_only_dir" \
    "$NO_PAGES/garbage_only_dir" "$NO_PAGES/corrupt_page_dir"
python3 - "$NO_PAGES" "$SRC" <<'EOF'
import pathlib, sys, zipfile
out, src = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
garbage = bytes((i * 37 + 11) % 256 for i in range(4096))   # no archive signature
text = b"not a page\n"
(out / "text_only_dir" / "readme.txt").write_bytes(text)
with zipfile.ZipFile(out / "text_only.cbz", "w") as z:
    z.writestr("readme.txt", text)
with zipfile.ZipFile(out / "no_entries.cbz", "w"):
    pass
for name in ("garbage.cbz", "garbage.cbr", "garbage.7z", "garbage.pdf"):
    (out / name).write_bytes(garbage)
(out / "garbage_only_dir" / "garbage.cbz").write_bytes(garbage)
pages = [("001.png", (src / "001.png").read_bytes()),
         ("002.jpg", (src / "002.jpg").read_bytes()),
         ("003.png", (src / "003.png").read_bytes()),
         ("004.jpg", b"\xff\xd8\xff\xe0 truncated, not a JPEG")]
for name, data in pages:
    (out / "corrupt_page_dir" / name).write_bytes(data)
with zipfile.ZipFile(out / "corrupt_page.cbz", "w") as z:
    for name, data in pages:
        z.writestr(name, data)
EOF
if command -v 7zz >/dev/null 2>&1; then
    # data-only and header encryption; neither can be decrypted by libarchive
    (cd "$SRC" && 7zz a -bso0 -bsp0 -pSECRET "$NO_PAGES/encrypted.7z" 001.png 002.jpg)
    (cd "$SRC" && 7zz a -bso0 -bsp0 -pSECRET -mhe=on "$NO_PAGES/encrypted_headers.7z" 001.png 002.jpg)
    # a password-protected ZIP that holds no image, opened by the deferred
    # (window-modal) password path
    (cd "$NO_PAGES/text_only_dir" && 7zz a -bso0 -bsp0 -tzip -pSECRET "$NO_PAGES/encrypted_text_only.cbz" readme.txt)
fi

clang -O2 \
    -I "$REPO_ROOT/vendor/include" \
    -I "$REPO_ROOT/Sources" \
    "$ENGINE_DIR/test_coarchive.m" "$REPO_ROOT/Sources/COArchive.m" "$REPO_ROOT/Sources/COZipArchive.m" \
    "$REPO_ROOT/Sources/CORarArchive.m" "$REPO_ROOT/Sources/CORarHeaderIndex.m" \
    "$REPO_ROOT/Sources/NSString_Compare.m" \
    "$REPO_ROOT/vendor/lib/libarchive.13.dylib" \
    "$REPO_ROOT/vendor/lib/libuchardet.0.dylib" \
    "$REPO_ROOT/vendor/lib/libzip.5.dylib" \
    -framework Foundation -framework CoreFoundation -framework CoreServices \
    -Wl,-rpath,"$REPO_ROOT/vendor/lib" \
    -o "$OUT/test_coarchive"

EXIT_FILE="$OUT/decode_ahead_exit_dir.txt"
rm -f "$EXIT_FILE"
CO_TEST_DECODE_AHEAD_EXIT_FILE="$EXIT_FILE" "$OUT/test_coarchive" "$GEN" "$SRC" "$RAR5_FINAL"

# B3: an archive still alive at exit() has its decode-ahead files removed
if [ -f "$EXIT_FILE" ]; then
    LEFT_DIR="$(cat "$EXIT_FILE")"
    if [ -z "$LEFT_DIR" ] || [ -e "$LEFT_DIR" ]; then
        echo "FAIL: decode-ahead directory left after exit: '$LEFT_DIR'" >&2
        exit 1
    fi
    # the directory it was given, empty once the cache is gone, goes too
    if [ -e "$(dirname "$LEFT_DIR")" ]; then
        echo "FAIL: empty decode-ahead parent left after exit: $(dirname "$LEFT_DIR")" >&2
        exit 1
    fi
    echo "decode-ahead directory and its empty parent removed at exit: ok"
    rm -f "$EXIT_FILE"
fi

# book level: COImageLoader on top of the archive layer (nested archives).
# The app's Info.plist is embedded so +[COImageLoader fileTypes], which reads
# CFBundleDocumentTypes from the main bundle, knows the archive extensions.
clang -O2 -Wno-deprecated-declarations -Wno-unused-value \
    -I "$REPO_ROOT/vendor/include" \
    -I "$REPO_ROOT/Sources" \
    "$ENGINE_DIR/test_imageloader.m" "$REPO_ROOT/Sources/COImageLoader.m" \
    "$REPO_ROOT/Sources/COPDFImage.m" "$REPO_ROOT/Sources/COPDFImageRep.m" \
    "$REPO_ROOT/Sources/COArchive.m" "$REPO_ROOT/Sources/COZipArchive.m" \
    "$REPO_ROOT/Sources/CORarArchive.m" "$REPO_ROOT/Sources/CORarHeaderIndex.m" \
    "$REPO_ROOT/Sources/NSString_Compare.m" \
    "$REPO_ROOT/vendor/lib/libarchive.13.dylib" \
    "$REPO_ROOT/vendor/lib/libuchardet.0.dylib" \
    "$REPO_ROOT/vendor/lib/libzip.5.dylib" \
    -framework Cocoa -framework Quartz -framework CoreServices \
    -Wl,-rpath,"$REPO_ROOT/vendor/lib" \
    -Wl,-sectcreate,__TEXT,__info_plist,"$REPO_ROOT/Resources/Info.plist" \
    -o "$OUT/test_imageloader"

"$OUT/test_imageloader" "$GEN"
