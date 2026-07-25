# TASK: Investigate cvbdl support scope (investigation only)

## Scope

Investigation only. Do not implement, modify code, or commit source
changes. Determine what is needed to (a) treat `.cvbdl` as a first-class
archive type in the main app, and (b) support it in the QuickLook Preview
and Thumbnail extensions.

## Part A: Current handling, precisely

1. Re-confirm and document the exact current path: `LSTypeIsPackage`
   makes Finder present the folder as one document; `COImageLoader` falls
   through to the generic directory branch because `cvbdl` is excluded
   from `archiveTypes`. Cite the exact files/lines.
2. Determine what the generic directory path currently does differently
   from the archive path (e.g. sorting behaviour, saved per-book settings
   keyed by path, bookmarks, last-opened-page memory). Anything that
   depends on archive-specific code today would need an equivalent for
   `cvbdl` once it stops falling through generically — or would need to
   keep falling through, if the generic path already covers it adequately.
3. Report whether the generic directory path already satisfies the
   documented feature set (page direction, single/spread settings,
   bookmarks, last page) for a `cvbdl` bundle, or whether something is
   missing today that users opening a `cvbdl` would not get compared to
   opening it as a plain folder.

## Part B: What "first-class" would require in the main app

1. If `cvbdl` were removed from the `archiveTypes` exclusion, report what
   actually changes in behaviour — is the generic directory path
   effectively equivalent already, or does the archive path do something
   the directory path doesn't (indexing, caching, page-count precomputation)?
2. Report whether making this change is additive (a one-line removal) or
   whether it touches code that assumes archive entries come from a
   COArchive subclass rather than a filesystem directory.
3. Recommend whether promoting `cvbdl` to a real archive type is worth
   doing at all, or whether the generic directory path is sufficient and
   only the QuickLook/Thumbnail side needs work.

## Part C: QuickLook / Thumbnail extensions

1. Report exactly how `COCoverExtractor.m` currently excludes `cvbdl`, and
   what it would need to do instead: open the bundle as a directory, find
   the first image by the same ordering rule the main app uses for plain
   folders, and return it.
2. Report whether the extensions currently have filesystem/directory read
   access for this case, or whether they only know how to read through
   `COArchive` subclasses — i.e. whether directory traversal is new code
   for the extension target or something it can already do.
3. Report what UTI/document-type declarations are needed for the
   extensions to be invoked for `.cvbdl` at all — confirm whether the
   main target's `LSTypeIsPackage` declaration is sufficient or whether
   the extension targets need their own `NSExtension` /
   `CFBundleDocumentTypes` entries (compare with how `.cbz`/`.cbr` are
   declared for the extensions today).
4. Report any risk of `.cvbdl` colliding with ordinary folder handling in
   Finder/QuickLook for folders that are not comic bundles, given
   `LSTypeIsPackage` reassigns how Finder treats any folder with that
   extension.

## Part D: Test fixture

1. Report whether a `.cvbdl` fixture can be constructed simply (rename a
   folder of test images) for use in later verification, consistent with
   the existing `tests/fixtures/` conventions.

## Deliverable

A chat report covering:

- whether the generic directory path already provides full functionality
  for `cvbdl`, or what's missing
- recommended scope: QuickLook/Thumbnail only, or also promote `cvbdl` to
  a first-class archive type in the main app
- exact files/entries to change for the QuickLook/Thumbnail case
- any risk to ordinary folders from the `LSTypeIsPackage` declaration
- a proposed task split for implementation

## Notes

- Investigation only. Archive this `TASK.md` on completion per
  `docs/task-workflow.md`.
- This targets v1.5.2, alongside the deferred notarization/release work.
  Do not begin release steps in this task.
## Implementation Result

**Status:** Completed

### Changes

Investigation only; no code, Info.plist, or build changes. Full findings
delivered in chat; summarized below so they survive outside the chat.

**Part A — current handling:**
- `.cvbdl` document type (`Resources/Info.plist:129-147`) has
  `LSTypeIsPackage = true` and, unlike `.cbz`/`.cbr`, **no**
  `LSItemContentTypes`/UTI declaration at all.
- `+[COImageLoader archiveTypes]` (`Sources/COImageLoader.m:37-46`)
  explicitly excludes `cvbdl`; the dispatch in `-content`
  (`Sources/COImageLoader.m:339-350` for the archive branch,
  `:408-436` for the directory fallback) sends it to the generic
  directory branch (`mode=0`) since `LSTypeIsPackage` only affects Finder
  presentation, not what `NSFileManager -fileExistsAtPath:isDirectory:`
  reports.
- The directory path already provides full documented functionality:
  bookmarks/last-page/read-mode are stored in `NSUserDefaults` keyed by
  path/alias strings (`BookSettings`/`LastPages`/`RecentItems`,
  `Sources/Controller.m:795-957`), entirely independent of loader `mode`.
  It additionally supports `-canSortByDate` (`COImageLoader.m:158`), which
  archive mode (`mode==2`) does not, and handles nested archives more
  simply (direct path reuse vs. `-uncompressToTempDir:` for archive mode).
  **Nothing is missing** compared to opening `.cvbdl` as a plain folder.

**Part B — decisive finding, do not promote to archive type:**
- Removing `cvbdl` from the `archiveTypes` exclusion would **break** it,
  not improve it. `COArchive -initWithPath:progress:`
  (`Sources/COArchive.m:94-138`) only special-cases zip/cbz and rar/cbr
  extensions; any other extension falls to the base libarchive path, which
  calls `archive_read_open_filename` directly on the path
  (`COArchive.m:237`) with **no `isDirectory` guard** — libarchive cannot
  open a directory as an archive stream, so this would fail closed
  (`lastError` set, `itemCount==0`, `mode=-1`), regressing a currently
  working document type.
- This is not a one-line additive change; making the archive path work for
  `cvbdl` would require an entirely new `COArchive` subclass wrapping
  `NSFileManager` — reimplementing what the directory path already does,
  for no functional gain.
- **Recommendation: do not promote `cvbdl`.** The generic directory path
  is required, not merely adequate. Scope is QuickLook/Thumbnail only.

**Part C — QuickLook/Thumbnail:**
- `COCoverExtractor.m` (full file reviewed) excludes `cvbdl` as a
  documented side effect of routing through `COArchive`, which cannot open
  a directory (same mechanism as Part B). Needed instead: skip `COArchive`
  entirely for this case, list the directory via `NSFileManager`, filter
  with `[NSImage imageFileTypes]` (same filter `COImageLoader` uses,
  `COImageLoader.m:65-66`), sort with `-finderCompareS:` (same category
  already reused by `COCoverExtractor`), read the first entry's bytes
  directly — simpler than the existing archive path, no `COZipArchive`/
  `CORarArchive`/`CORarHeaderIndex` involvement, roughly 20 lines.
- Both extensions' entitlements (`com.apple.security.app-sandbox` +
  `files.user-selected.read-only`) are identical; neither currently calls
  any `NSFileManager` directory-listing API (confirmed via grep — zero
  hits). Directory traversal is genuinely new code for the extensions.
  Expected to work under the existing entitlements (standard sandbox
  behaviour for package-type documents), but this is **not provable
  statically** and must be verified on-device once implemented.
- `.cvbdl` has no UTI today. `QLSupportedContentTypes` in both extensions'
  `Info.plist` is UTI-based and currently lists only the cbz/cbr UTIs.
  `LSTypeIsPackage` alone does **not** make QuickLook invoke the
  extension. Three declarations are needed: a new
  `UTExportedTypeDeclarations` entry (conforming to `com.apple.package`,
  tagged `cvbdl`), an `LSItemContentTypes` array added to the `cvbdl`
  document-type dict (matching the cbz/cbr pattern at
  `Resources/Info.plist:257-262`), and that UTI added to
  `QLSupportedContentTypes` in `PreviewExtension/Info.plist` and
  `ThumbnailExtension/Info.plist`.
- `LSTypeIsPackage` risk to ordinary folders is **pre-existing** (since
  the original fork import, commit `77b2275`) and not introduced by any
  QuickLook work. The incremental risk from adding QuickLook support is
  narrow: a non-comic folder using the rare `.cvbdl` extension could show
  a misleading cover thumbnail (cosmetic only — no crash/hang/data risk).

**Part D — fixture:** Trivial. `mkdir generated/test.cvbdl` + copy the
existing `src/001.png,002.jpg,003.png,004.jpg` fixtures in, consistent with
`tests/fixtures/make_fixtures.sh`'s existing per-format sections.

### Verification

- Build: Not performed (investigation only).
- Automated verification: Not performed (investigation only) — read-only
  inspection of `Resources/Info.plist`, `PreviewExtension/Info.plist`,
  `ThumbnailExtension/Info.plist`, `Sources/COImageLoader.{h,m}`,
  `Sources/COArchive.m`, `Sources/COCoverExtractor.m`,
  `Sources/Controller.m`, both extensions' entitlements and provider
  `.m` files, and `tests/fixtures/make_fixtures.sh`.
- Manual verification: traced the exact dispatch path with line-precise
  citations (above); confirmed via grep that no directory-listing code
  exists in the extension targets today; confirmed the `cvbdl` UTI gap by
  diffing its document-type dict against `cbz`'s in `Info.plist`.

### Remaining Issues

None. Deliverable is the report above.

### Follow-up Suggestions

Proposed task split for v1.5.2 (not started here):
1. UTI/`QLSupportedContentTypes` plumbing across the three `Info.plist`
   files.
2. `COCoverExtractor.m`: add a directory-listing branch for `cvbdl`,
   bypassing `COArchive`.
3. Extend `make_fixtures.sh` with a `test.cvbdl` fixture; verify on-device
   (thumbnail/preview render, and that no new entitlement is actually
   needed) per `CLAUDE.md`'s On-Device Verification Procedure.
4. Explicitly excluded from any future task: removing `cvbdl` from
   `COImageLoader.archiveTypes` — confirmed to break the main app.
