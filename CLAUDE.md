# CLAUDE.md
@AGENTS.md

## Project-specific (cooViewer)
- Build: `vendor/build-libs.sh` (one-time, needs cmake), then `xcodebuild -configuration Deployment`
- Vendored libs: libarchive/uchardet/libzip are built as universal dylibs, bundled in Frameworks/
- Do not edit vendored library sources