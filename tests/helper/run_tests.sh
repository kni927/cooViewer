#!/bin/bash
set -euo pipefail

TEST_TMP="$(mktemp -d /private/tmp/cooViewer-helper-tests.XXXXXX)"
trap 'rm -rf "$TEST_TMP"' EXIT

xcrun clang -fobjc-exceptions -framework Foundation \
  -I Sources Sources/CONewWindowURL.m tests/helper/test_new_window_url.m \
  -o "$TEST_TMP/test_new_window_url"
COOVIEWER_TEST_TMPDIR="$TEST_TMP" "$TEST_TMP/test_new_window_url"

if [[ $# -eq 1 ]]; then
  python3 tests/helper/verify_bundles.py "$1"
fi
