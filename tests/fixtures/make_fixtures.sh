#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"
OUT_DIR="$SCRIPT_DIR/generated"
WORK_DIR="$OUT_DIR/.work"

SOURCE_FILES=(
    "001.png"
    "002.jpg"
    "003.png"
    "004.jpg"
)

command_required() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Error: required command not found: $1" >&2
        exit 1
    fi
}

command_optional() {
    command -v "$1" >/dev/null 2>&1
}

command_required zip
command_required tar
command_required python3

for file in "${SOURCE_FILES[@]}"; do
    if [[ ! -f "$SRC_DIR/$file" ]]; then
        echo "Error: source file not found: $SRC_DIR/$file" >&2
        exit 1
    fi
done

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR" "$WORK_DIR"
touch "$OUT_DIR/.gitkeep"

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

echo "Generating cooViewer test fixtures..."

#
# ASCII filenames
#

(
    cd "$SRC_DIR"

    # -X excludes extra file attributes for reproducibility.
    zip -X -q "$OUT_DIR/test.cbz" "${SOURCE_FILES[@]}"
    zip -X -q "$OUT_DIR/test.zip" "${SOURCE_FILES[@]}"

    tar -cf "$OUT_DIR/test.tar" "${SOURCE_FILES[@]}"
)

if command_optional 7zz; then
    (
        cd "$SRC_DIR"
        7zz a -bd -y "$OUT_DIR/test.7z" "${SOURCE_FILES[@]}" >/dev/null
    )
else
    echo "Skip: test.7z (7zz not installed)"
fi

if command_optional rar; then
    (
        cd "$SRC_DIR"
        rar a -idq "$OUT_DIR/test.cbr" "${SOURCE_FILES[@]}"
        # -s: solid archive, for the RAR partial-lazy reader's solid path
        rar a -idq -s "$OUT_DIR/test_solid.cbr" "${SOURCE_FILES[@]}"
    )
else
    echo "Skip: test.cbr / test_solid.cbr (rar not installed)"
fi

#
# UTF-8 Japanese filenames
#

UTF8_DIR="$WORK_DIR/utf8"
mkdir -p "$UTF8_DIR"

cp "$SRC_DIR/001.png" "$UTF8_DIR/001_表紙.png"
cp "$SRC_DIR/002.jpg" "$UTF8_DIR/002_縦長表示.jpg"
cp "$SRC_DIR/003.png" "$UTF8_DIR/003_網点とカケアミ.png"
cp "$SRC_DIR/004.jpg" "$UTF8_DIR/004_拡大縮小.jpg"

(
    cd "$UTF8_DIR"
    zip -X -q "$OUT_DIR/test_utf8.zip" ./*
)

if command_optional 7zz; then
    (
        cd "$UTF8_DIR"
        7zz a -bd -y "$OUT_DIR/test_utf8.7z" ./* >/dev/null
    )
fi

if command_optional rar; then
    (
        cd "$UTF8_DIR"
        rar a -idq "$OUT_DIR/test_utf8.cbr" ./*
    )
fi

#
# CP932 / legacy Japanese Windows ZIP filenames
#

python3 \
    "$SCRIPT_DIR/make_sjis_fixture.py" \
    "$SRC_DIR" \
    "$OUT_DIR/test_sjis.zip"

#
# RAR4 (legacy, STORE method) — no fixture-generation tool for this
# format is available (modern rar/unrar only create RAR5), so this is
# hand-written directly; needs no external tool, always generated.
#

python3 \
    "$SCRIPT_DIR/make_rar4_fixture.py" \
    "$SRC_DIR" \
    "$OUT_DIR/test_rar4.cbr"

#
# Checksums
#

(
    cd "$OUT_DIR"

    find . -maxdepth 1 -type f \
        ! -name "SHA256SUMS.txt" \
        ! -name ".gitkeep" \
        -print0 |
        sort -z |
        xargs -0 shasum -a 256 > SHA256SUMS.txt
)

echo
echo "Generated:"
find "$OUT_DIR" -maxdepth 1 -type f \
    ! -name ".gitkeep" \
    -print |
    sort |
    sed 's/^/  /'