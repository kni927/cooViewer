# CLAUDE.md
@AGENTS.md

## Project-specific (cooViewer)
- Build: `vendor/build-libs.sh` (one-time, needs cmake), then `xcodebuild -configuration Deployment`
- Vendored libs: libarchive/uchardet/libzip are built as universal dylibs, bundled in Frameworks/
- Do not edit vendored library sources
- Do not install local/debug builds directly into `/Applications` for
  manual testing. Use a separate test location (e.g. `~/Applications`)
  and register it with `lsregister -f` / `pluginkit -a` instead.
  Repeatedly building, installing, and re-registering multiple
  cooViewer.app copies (including build output left under
  `build/Deployment/`) during a single dev session has previously left
  LaunchServices/QuickLook in an inconsistent state that only a full
  OS restart resolved — see `docs/KNOWN_ISSUES.md` #15.