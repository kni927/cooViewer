#!/bin/bash
# Update the Homebrew cask kni927/tap/cooviewer to a published release.
#
# Run from the repository root, exactly as
#   tools/update_tap.sh <version> [tap checkout]
# on its own (no pipes, redirects, `&&` or command substitution). It is
# listed in .claude/settings.json under sandbox.excludedCommands because it
# writes to the tap checkout, outside this repository.
#
# It downloads cooViewer-v<version>.zip from the GitHub Release, computes its
# sha256, rewrites `version` and `sha256` in Casks/cooviewer.rb, shows the
# diff and commits it locally. It never pushes: pushing the tap is a
# separate step (CLAUDE.md, Releasing). The tap checkout defaults to the one
# Homebrew uses (`brew --repository kni927/tap`).
set -euo pipefail

die() { echo "update_tap: $*" >&2; exit 1; }

VERSION="${1:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "usage: tools/update_tap.sh <version like 1.6.7> [tap checkout]"
TAP="${2:-}"
if [ -z "$TAP" ]; then
    command -v brew >/dev/null || die "brew not found; give the tap checkout path"
    TAP="$(brew --repository kni927/tap)"
fi
CASK="$TAP/Casks/cooviewer.rb"
[ -f "$CASK" ] || die "no $CASK"
git -C "$TAP" remote get-url origin | grep -q 'kni927/homebrew-tap' ||
    die "$TAP is not a kni927/homebrew-tap checkout"
[ -z "$(git -C "$TAP" status --porcelain)" ] || die "$TAP has uncommitted changes; leave them to the owner"

URL="https://github.com/kni927/cooViewer/releases/download/v$VERSION/cooViewer-v$VERSION.zip"
WORK="$(getconf DARWIN_USER_TEMP_DIR)cooViewer-tap"
mkdir -p "$WORK"
ZIP="$WORK/cooViewer-v$VERSION.zip"
curl -fsSL -o "$ZIP" "$URL" || die "download failed: $URL (is the release published?)"
SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo "cooViewer-v$VERSION.zip sha256 $SHA"

sed -i '' -E \
    -e "s/^(  version \")[^\"]*(\")/\1$VERSION\2/" \
    -e "s/^(  sha256 \")[^\"]*(\")/\1$SHA\2/" "$CASK"
grep -q "version \"$VERSION\"" "$CASK" && grep -q "sha256 \"$SHA\"" "$CASK" ||
    die "could not rewrite $CASK; check its format"
git -C "$TAP" --no-pager diff
git -C "$TAP" commit -q -am "cooviewer $VERSION"
echo "committed in $TAP: $(git -C "$TAP" log --oneline -1)"
echo "not pushed; push only with the owner's approval of the release"
