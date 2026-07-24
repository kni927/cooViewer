#!/bin/bash
# Builds the vendored archive/encoding libraries for cooViewer as
# universal (arm64 + x86_64) dylibs into vendor/lib/, with headers in
# vendor/include/. Run once before building the app:
#
#   vendor/build-libs.sh
#
# Requirements: Xcode command line tools, cmake, git.
# SRC_DIR (default vendor/src) holds the upstream checkouts and build
# trees; safe to delete after a successful run.
#
# This script is the single source of truth for the exact upstream
# revisions (validated in docs/spike-libarchive-20260711.md):

LIBARCHIVE_REPO="https://github.com/libarchive/libarchive.git"
LIBARCHIVE_COMMIT="d114ceee6de08a7a60ff1209492ba38bf9436f79"   # v3.8.4
LIBARCHIVE_DYLIB="libarchive.13.dylib"
LIBARCHIVE_BUILT="libarchive.13.8.4.dylib"

UCHARDET_REPO="https://gitlab.freedesktop.org/uchardet/uchardet.git"
UCHARDET_COMMIT="06029ec3340cdf6bf9a6a537dafb3f39eda0560e"     # master, post v0.0.8
UCHARDET_DYLIB="libuchardet.0.dylib"
UCHARDET_BUILT="libuchardet.0.0.8.dylib"

LIBZIP_REPO="https://github.com/nih-at/libzip.git"
LIBZIP_COMMIT="6f8a0cdd24a0dc6cce9dac4a7679da784ab124ea"       # v1.11.4
LIBZIP_DYLIB="libzip.5.dylib"

set -euo pipefail

VENDOR_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="${SRC_DIR:-$VENDOR_DIR/src}"
LIB_DIR="$VENDOR_DIR/lib"
INC_DIR="$VENDOR_DIR/include"
mkdir -p "$SRC_DIR" "$LIB_DIR" "$INC_DIR"

# Universal build, matching the app's deployment target. install_name
# is @rpath/<name>; the app sets LD_RUNPATH_SEARCH_PATHS to
# @executable_path/../Frameworks and copies the dylibs there.
CMAKE_FLAGS=(
    -DCMAKE_BUILD_TYPE=Release
    -DBUILD_SHARED_LIBS=ON
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64"
    -DCMAKE_OSX_DEPLOYMENT_TARGET=10.13
    -DCMAKE_MACOSX_RPATH=ON
)

checkout() {
    local repo="$1" commit="$2" dir="$3"
    if [ ! -d "$dir/.git" ]; then
        git clone "$repo" "$dir"
    fi
    git -C "$dir" fetch --quiet origin "$commit" 2>/dev/null || true
    git -C "$dir" checkout --quiet "$commit"
}

#
# libarchive — SDK-only deps (zlib/bzip2/lzma/iconv from /usr/lib).
# Homebrew codecs are explicitly disabled so the universal link cannot
# pick up arm64-only Homebrew dylibs, and the binary has no
# non-system runtime dependencies. XAR needs libxml2, so it is off.
#
checkout "$LIBARCHIVE_REPO" "$LIBARCHIVE_COMMIT" "$SRC_DIR/libarchive"
cmake -S "$SRC_DIR/libarchive" -B "$SRC_DIR/libarchive-build" "${CMAKE_FLAGS[@]}" \
    -DENABLE_TEST=OFF -DENABLE_TAR=OFF -DENABLE_CPIO=OFF -DENABLE_CAT=OFF \
    -DENABLE_UNZIP=OFF -DENABLE_LZ4=OFF -DENABLE_ZSTD=OFF -DENABLE_LIBB2=OFF \
    -DENABLE_OPENSSL=OFF -DENABLE_LIBXML2=OFF -DENABLE_EXPAT=OFF -DENABLE_XAR=OFF
cmake --build "$SRC_DIR/libarchive-build" --target archive
cp "$SRC_DIR/libarchive-build/libarchive/$LIBARCHIVE_BUILT" "$LIB_DIR/$LIBARCHIVE_DYLIB"
cp "$SRC_DIR/libarchive/libarchive/archive.h" \
   "$SRC_DIR/libarchive/libarchive/archive_entry.h" "$INC_DIR/"

#
# uchardet
#
checkout "$UCHARDET_REPO" "$UCHARDET_COMMIT" "$SRC_DIR/uchardet"
cmake -S "$SRC_DIR/uchardet" -B "$SRC_DIR/uchardet-build" "${CMAKE_FLAGS[@]}"
cmake --build "$SRC_DIR/uchardet-build" --target libuchardet
cp "$SRC_DIR/uchardet-build/src/$UCHARDET_BUILT" "$LIB_DIR/$UCHARDET_DYLIB"
cp "$SRC_DIR/uchardet/src/uchardet.h" "$INC_DIR/"

#
# libzip — zlib/bzip2 from the SDK only. CommonCrypto (native to macOS,
# no extra runtime dependency) is enabled so encrypted zip entries can be
# decrypted (WinZip AES); traditional PKWARE ZipCrypto also stays on via
# libzip's default (ENABLE_ZIPCRYPTO, not disabled here). The other crypto
# backends (GNUTLS/MBEDTLS/OPENSSL/WINDOWS_CRYPTO) stay off, and lzma/zstd
# compression methods are disabled so the universal link cannot pick up
# arm64-only Homebrew dylibs. The soname symlink is dereferenced with
# cp -L so the copy is robust against upstream VERSION bumps.
#
checkout "$LIBZIP_REPO" "$LIBZIP_COMMIT" "$SRC_DIR/libzip"
cmake -S "$SRC_DIR/libzip" -B "$SRC_DIR/libzip-build" "${CMAKE_FLAGS[@]}" \
    -DBUILD_TOOLS=OFF -DBUILD_REGRESS=OFF -DBUILD_EXAMPLES=OFF \
    -DBUILD_DOC=OFF -DBUILD_OSSFUZZ=OFF \
    -DENABLE_COMMONCRYPTO=ON -DENABLE_GNUTLS=OFF -DENABLE_MBEDTLS=OFF \
    -DENABLE_OPENSSL=OFF -DENABLE_WINDOWS_CRYPTO=OFF \
    -DENABLE_BZIP2=ON -DENABLE_LZMA=OFF -DENABLE_ZSTD=OFF
cmake --build "$SRC_DIR/libzip-build" --target zip
cp -L "$SRC_DIR/libzip-build/lib/$LIBZIP_DYLIB" "$LIB_DIR/$LIBZIP_DYLIB"
cp "$SRC_DIR/libzip/lib/zip.h" "$SRC_DIR/libzip-build/zipconf.h" "$INC_DIR/"

#
# sanity checks: universal + expected install names
#
for lib in "$LIB_DIR/$LIBARCHIVE_DYLIB" "$LIB_DIR/$UCHARDET_DYLIB" "$LIB_DIR/$LIBZIP_DYLIB"; do
    lipo "$lib" -verify_arch arm64 x86_64 ||
        { echo "ERROR: $lib is not universal" >&2; exit 1; }
done
for name in "$LIBARCHIVE_DYLIB" "$UCHARDET_DYLIB" "$LIBZIP_DYLIB"; do
    actual=$(otool -D "$LIB_DIR/$name" | tail -1)
    [ "$actual" = "@rpath/$name" ] ||
        { echo "ERROR: $name install_name is '$actual', expected '@rpath/$name'" >&2; exit 1; }
done

echo
echo "vendored libs ready:"
ls -l "$LIB_DIR"
