# TASK: QuickLook extension for cbz/cbr — phase 7

## Background

Phases 1–2 (libzip) and 4/6 (libarchive cursor pass + revived XADMaster
header index) made opening a single entry from a zip/cbz or rar/cbr
archive fast and low-memory, independent of total archive size. This
was explicitly designed with QuickLook's tight time budget in mind
(QuickLook extensions must render a preview/thumbnail within a few
seconds or the system gives up).

Master currently uses a separate third-party app (Simple Comic) solely
for Finder QuickLook previews of comic archives. This task replaces that
dependency with a native QuickLook App Extension bundled in cooViewer.

This is the last task before a 1.5.0 release.

## Goal

- Selecting a .cbz/.cbr/.zip/.rar comic archive in Finder and pressing
  Space shows a preview of its first page (cover), without opening
  cooViewer itself.
- Finder icon thumbnails for these files show the cover image.
- Preview/thumbnail generation is fast (well under QuickLook's timeout)
  regardless of archive size or solid/non-solid status, by reusing the
  existing lazy readers.
- No regression to the main app.

## Scope

### In scope

- **New target**: add a QuickLook App Extension target (Preview
  Extension using `QLPreviewProvider`, and a Thumbnail Extension using
  `QLThumbnailProvider` — confirm whether one combined extension or two
  separate ones is more appropriate for the current Xcode/SDK version
  in use, and note the choice).
- **UTI declarations**: declare supported types for cbz/cbr in the
  extension's Info.plist (`QLSupportedContentTypes` / equivalent).
  cbz/cbr are not standard system UTIs — define exported/imported UTI
  declarations as needed (e.g. conforming to `public.zip-archive` /
  `public.data` as appropriate). Confirm plain `.zip`/`.rar` handling
  doesn't unintentionally hijack the system's default zip/rar previews
  (scope the UTI to the cbz/cbr extensions specifically, or gate on
  content if extension-based UTI declaration alone isn't precise
  enough).
- **Cover extraction logic**: reuse `COZipArchive` and
  `CORarArchive`/`CORarHeaderIndex` (as libraries/shared code, not
  reimplemented) to open the archive, determine the first page in
  display order (reuse existing sort/ordering logic from the main app —
  do not reimplement page ordering), and decode only that one entry.
- **Rendering**: for the thumbnail provider, return an appropriately
  scaled image per the requested size. For the preview provider, return
  a reasonably sized image (no need to build a full viewer UI).
- **Extension packaging of dependencies**: the extension runs as a
  separate sandboxed process and cannot rely on the host app's loaded
  frameworks. Bundle the needed vendored dylibs (libarchive, uchardet,
  libzip) into the extension's own Frameworks, following the same
  build/bundling pattern as the main app target.
- **Sandbox verification**: determine whether the extension needs
  `com.apple.security.app-sandbox` and, if so, what entitlements are
  required for it to read the archive file QuickLook hands it (file
  access is typically provided via a security-scoped URL from the
  system, not general filesystem access — confirm the exact mechanism).
  Test on-device with the project's current ad-hoc/Developer ID signing
  setup; document what worked, since this was flagged in earlier
  discussion as needing real verification rather than assumption.
- **Encrypted / corrupt archives**: fail gracefully (return no preview
  rather than crashing the extension process, which would affect Finder
  system-wide).
- Update README/CLAUDE.md to note Simple Comic is no longer needed once
  this ships.
- **Fix missing `CFBundleShortVersionString`**: the main app target
  currently sets `CFBundleVersion` (build number) but not
  `CFBundleShortVersionString` (user-facing version), which is why
  Finder's Get Info panel shows a blank version while QuickLook's
  preview falls back to `CFBundleVersion` and shows one anyway (root
  cause confirmed: `defaults read Info.plist
  CFBundleShortVersionString` returns "does not exist";
  `CFBundleVersion` returns "1.4.0"). Set `MARKETING_VERSION` in the
  Xcode build settings (wired to `CFBundleShortVersionString` via
  Info.plist, typically `$(MARKETING_VERSION)`) to `1.5.0` for this
  release, and keep `CURRENT_PROJECT_VERSION`/`CFBundleVersion` as the
  separate internal build number going forward. Apply the same fix to
  the new QuickLook extension target's Info.plist so its version stays
  in sync with the main app. After building, verify with `mdimport -f`
  + `mdls -name kMDItemVersion` that Finder's Get Info panel shows
  1.5.0 (not blank).

### Out of scope

- Any change to zip/rar reading logic itself (reuse as-is).
- Full-featured preview (page navigation within QuickLook) — cover/
  first-page only.
- 7z/tar QuickLook support (can be a fast-follow if trivial once the
  cbz/cbr plumbing exists, but don't expand scope proactively — note as
  a follow-up if it turns out easy).
- The 1.5.0 release process itself (versioning, changelog, tagging,
  release build) — that's the next step after this task, not part of it.

## Verification

- Build: main app + extension both build; extension embeds correctly
  in the app bundle.
- Finder: quicklook preview (Space) and icon thumbnails work for
  sample .cbz and .cbr files, including the large (1.4 GB, solid RAR)
  fixture — confirm it doesn't time out.
- Regression: main app's own in-app viewing is unaffected.
- Sandbox: document actual on-device behavior (works / doesn't / what
  entitlements were needed) rather than assuming from documentation
  alone.
- Corrupt/encrypted archive: Finder shows a generic icon or "no
  preview" rather than the extension crashing or hanging.

## Implementation Result

**Status:** Completed

### Changes

- Added two new Xcode targets by hand-editing `project.pbxproj`
  (no target-creation API existed in the available `pbxproj` Python
  library, and Xcode's GUI target wizard couldn't be driven because
  computer-use access to Xcode was granted at "click" tier only, which
  blocks typing): `cooViewerPreview` (`QLPreviewProvider`, extension
  point `com.apple.quicklook.preview`) and `cooViewerThumbnail`
  (`QLThumbnailProvider`, `com.apple.quicklook.thumbnail`) — confirmed
  via Apple's own current Xcode templates that these are always
  separate targets, never combined.
- New `Sources/COCoverExtractor.h/.m` — shared cover-extraction
  helper used by both extensions, reusing `COArchive`/
  `COZipArchive`/`CORarArchive`/`CORarHeaderIndex` and the existing
  `finderCompareS:` page-ordering category unchanged.
- New `ThumbnailExtension/` (`ThumbnailProvider.h/.m`, `Info.plist`,
  `.entitlements`) and `PreviewExtension/` (`PreviewProvider.h/.m`,
  `Info.plist`, `.entitlements`) directories.
- Each extension target bundles its own copies of the vendored
  dylibs (libarchive, uchardet, libzip) via a CopyFiles build phase,
  mirroring the main app's pattern.
- Declared `jp.coo.cooViewer.cbz-archive`/`cbr-archive` UTIs
  (`UTExportedTypeDeclarations` + `LSItemContentTypes`) in the main
  app's `Info.plist`. On-device testing then found this dev Mac's
  `.cbz`/`.cbr` files actually resolve to `public.cbz-archive`/
  `public.cbr-archive` — pre-existing public UTIs already exported by
  other installed comic-reader apps (Yomu, EdgeView 2) — not to
  cooViewer's own declaration. Fixed by also listing
  `public.cbz-archive`/`public.cbr-archive` in both extensions'
  `QLSupportedContentTypes` and in the main app's `LSItemContentTypes`,
  without touching `public.zip-archive`/`public.data` (the system's
  default zip/rar handlers). See `docs/DECISIONS.md`.
- Both extensions run with `com.apple.security.app-sandbox` +
  `com.apple.security.files.user-selected.read-only`, ad-hoc signed
  (`CODE_SIGN_IDENTITY = "-"` — an empty identity silently drops
  entitlements at build time despite a "successful" build).
- Fixed the pre-existing missing `CFBundleShortVersionString` bug in
  the main app's `Info.plist` (added `$(MARKETING_VERSION)`), and
  bumped `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` to `1.5.0`
  across all 5 build configs × 3 targets.
- `README.md`: added a "Finder QuickLook Support" note that Simple
  Comic is no longer needed.
- No deviation from the requested scope. The addition of
  `public.cbz-archive`/`public.cbr-archive` support (beyond the
  originally-envisioned custom UTI alone) was a small integration fix
  discovered necessary through on-device testing, not a scope
  expansion — the extensions still target the same cbz/cbr file types.

### Verification

- **Build:** `xcodebuild -configuration Deployment` — BUILD SUCCEEDED
  for all 3 targets. Extensions embed into
  `cooViewer.app/Contents/PlugIns/` via an "Embed App Extensions"
  CopyFiles phase, confirmed present in the built app bundle.
- **Tests:** No automated test suite exists in this project (see
  `docs/KNOWN_ISSUES.md` #10); verification below is manual.
- **Manual verification:** Installed the built app to `~/Applications`
  (the `/Applications` copy was left untouched after the destructive
  `rm -rf` was repeatedly denied by the permission gate despite an
  earlier in-chat confirmation — pivoted to the non-destructive
  `~/Applications` path instead) and registered it via
  `lsregister -f` + `pluginkit -a`.
  - `codesign -d --entitlements -` confirmed both extensions have the
    sandbox entitlements actually applied.
  - Real Finder GUI testing (via computer-use): Space-preview and
    icon thumbnails confirmed working for a small `.cbz`, a small
    `.cbr`, a small solid `.cbr`, the ~1.4 GB solid-RAR `.cbr`
    fixture, and a ~1.9 GB `.cbz` fixture — all rendered in ~1 second,
    far under QuickLook's timeout.
  - A truncated/corrupt `.cbr` fixture correctly fell back to the
    generic file icon / no preview, with no crash and no hang; no
    crash reports were generated (`~/Library/Logs/DiagnosticReports`
    checked).
  - Main app regression: opening the same corrupt fixture directly in
    cooViewer produced the expected pre-existing "broken or not image
    file" message, confirming the extensions don't interfere with the
    main app.
  - The `CFBundleShortVersionString` fix was verified via Finder's
    Get Info panel showing "Version: 1.5.0" — `mdls`/Spotlight proved
    unreliable for freshly-built products in this dev environment
    (documented in `docs/KNOWN_ISSUES.md` #13), so Get Info was used
    as the authoritative check instead.
- **Not performed:** testing against a password-protected/encrypted
  archive fixture specifically (only corrupt/truncated was available
  and tested — `COCoverExtractor` returns `nil` on any archive-open
  failure by design, which should cover this case, but it wasn't
  exercised live through the extension path with an actual encrypted
  fixture). Also not tested: behavior on a machine without
  Yomu/EdgeView 2 installed, to directly confirm the
  `jp.coo.cooViewer.*` UTI fallback resolves and works standalone when
  no competing public UTI exists (reasoned correct from the
  Info.plist/pbxproj declarations, not observed live).

### Remaining Issues

None blocking. The two "not performed" verification gaps above are
noted for awareness, not known failures.

### Follow-up Suggestions

- 7z/tar QuickLook support (explicitly out of scope this phase).
- Verify the `jp.coo.cooViewer.*` UTI fallback on a machine/VM without
  other comic-reader apps installed.
- Add a small encrypted-archive fixture to `tests/fixtures/` for
  extension-path graceful-failure coverage.
- The 1.5.0 release process itself (versioning, changelog, tagging,
  release build, notarization) — explicitly out of scope, is the
  natural next task now that this is the last pre-release item.
