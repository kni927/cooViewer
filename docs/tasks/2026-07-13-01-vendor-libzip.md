# TASK: Lazy per-entry extraction for zip archives (libzip)

## Background

v1.4.0 replaced XADMaster/UniversalDetector with libarchive 3.8.4 + uchardet.
libarchive is a pure streaming API, so the current design extracts **all**
entries into memory when an archive is opened. For large archives (~2 GB CBZ),
open time and memory pressure regressed noticeably compared to XADMaster,
which supported per-entry lazy extraction.

Zip's central directory allows true random access per entry. This task
introduces libzip for zip/cbz files only, restoring on-demand extraction.
Other formats (rar, 7z, tar) remain on the existing libarchive
full-extraction path and are out of scope.

## Goal

- Opening a zip/cbz archive is near-instant regardless of archive size
  (only the central directory is read; no entry data is decoded).
- Entry data is decoded on demand, per entry, when a page is requested.
- Peak memory no longer scales with total archive size for zip archives.
- No behavior change for non-zip formats.

## Scope

### In scope

- Vendor libzip as a universal (arm64 + x86_64) dylib, bundled in
  `Frameworks/`, following the same build/bundling pattern as libarchive
  and uchardet. Pin a specific release version.
- New zip reader path:
  - Open archive, read central directory only.
  - Enumerate entry names with `ZIP_FL_ENC_RAW` (raw bytes, no libzip
    name conversion).
  - Concatenate **all** entry name bytes and run uchardet once on the
    concatenated buffer (same policy as v1.4.0; per-filename detection
    produced unacceptable CP932 error rates).
  - Convert raw names to NSString using the detected encoding.
  - Note: the `setlocale(LC_ALL, "en_US.UTF-8")` workaround required by
    libarchive's zip reader (CP932 0x5C corruption) should NOT be needed
    on this path since libzip never sees converted names; verify this.
- Replace the "fully extracted entries dictionary" with an on-demand
  cache for zip archives:
  - Keep the existing NSData-based interface that COImageLoader consumes.
  - Decode a single entry via `zip_fopen_index` + `zip_fread` when first
    requested; store the NSData in an NSCache (or simple LRU) keyed by
    entry index.
  - Optional (only if trivial): prefetch the next entry in reading order
    on a background queue.
- Format dispatch: route `.zip` / `.cbz` to the libzip path; all other
  extensions keep the current libarchive path unchanged.
- Licensing: libzip is BSD-3-Clause. Add the license text to the existing
  third-party notices alongside libarchive/uchardet attributions.
- CI: extend the vendored-library build caching to cover libzip.

### Out of scope

- rar/unrar lazy extraction (planned as a separate follow-up task).
- Any change to 7z/tar handling.
- Multi-window support or Controller.m refactoring.
- Changing COImageLoader's NSData consumption model.

## Implementation notes

- Thread safety: a `zip_t*` handle is not safe for concurrent reads.
  Either serialize entry reads on a dedicated dispatch queue, or open a
  separate handle per concurrent read. Prefer the simplest correct option.
- Keep the archive file handle open for the lifetime of the document;
  close it on document close.
- Encrypted zip entries: unsupported (consistent with v1.3.7 dropping
  password-protected archive support). Fail gracefully with the existing
  error path.
- Corrupt/partial central directory: fall back to the libarchive
  full-extraction path rather than failing to open, if straightforward;
  otherwise surface the existing error UI.

## Verification

- Build: universal build succeeds; `otool -L` shows libzip loaded from
  `@rpath`/Frameworks, not a system path.
- Encoding: existing CP932-named test fixture CBZ opens with correct
  Japanese filenames; add it to CI if not already exercised on this path.
- Performance (manual): with a ~2 GB CBZ,
  - open-to-first-page time is subjectively immediate (compare against
    v1.4.0 baseline),
  - memory footprint during sequential reading stays bounded,
  - page turning has no perceptible regression.
- Regression (manual): rar / 7z / tar archives open and display exactly
  as in v1.4.0.
- Record numbers (open time before/after, peak RSS) in the
  Implementation Result section.

## Implementation Result

**Status:** Partially completed

Phase 1 (vendoring) only. The libzip reader path, on-demand entry
cache, and format dispatch were intentionally deferred to a follow-up
task per the project owner's instruction.

### Changes

- `vendor/build-libs.sh`: added libzip pinned to v1.11.4
  (`6f8a0cdd24a0dc6cce9dac4a7679da784ab124ea`), built as a universal
  (arm64 + x86_64) dylib with install name `@rpath/libzip.5.dylib`.
  Crypto backends disabled (encrypted zip entries are unsupported by
  the app); lzma/zstd disabled so only SDK zlib/bzip2 are linked and
  arm64-only Homebrew dylibs cannot leak into the universal link.
  `zip.h`/`zipconf.h` copied into `vendor/include/`; lipo and
  install_name sanity checks extended to the third library.
- `cooViewer.xcodeproj`: link `libzip.5.dylib` and copy it into
  `Contents/Frameworks` with CodeSignOnCopy, same pattern as
  libarchive/uchardet.
- `Licence_libzip.txt` (BSD-3-Clause) added; README build and license
  sections updated.
- CI: no workflow change needed — the vendored-libs cache key is
  `hashFiles('vendor/build-libs.sh')`, so the libzip addition
  invalidates the cache automatically.
- Commits: `550ba9b` (phase 1), plus `18f8739` (workflow docs +
  dev-log/known-issues filename fixes, requested alongside this task).

### Verification

- Build: `vendor/build-libs.sh` builds all three libs; Deployment
  build succeeds; app binary loads `@rpath/libzip.5.dylib` in both
  arch slices; bundled dylib is universal, ad-hoc signed, and depends
  only on `/usr/lib` system libs (verified with otool/lipo/codesign).
- Tests: no code path uses libzip yet, so the engine test suite is
  unaffected.
- Manual verification: app launches and quits cleanly with the new
  dylib bundled.
- Not performed: everything requiring the reader path — open-time /
  memory measurements against the ~2 GB CBZ baseline, CP932 fixture
  check on the libzip path, non-zip regression pass. Deferred with
  the reader implementation.

### Remaining Issues

- None in the vendored phase itself. The v1.4.0 regression this task
  targets (open time / peak memory scaling with archive size for
  zip/cbz) remains until the reader path lands.

### Follow-up Suggestions

- Implement the libzip reader path, on-demand NSCache/LRU entry
  cache, and `.zip`/`.cbz` dispatch (phases 2+, to be defined in a
  new TASK.md).
- While wiring the reader, verify the `setlocale(LC_ALL,
  "en_US.UTF-8")` workaround in `main.m` is indeed unnecessary on the
  libzip path (`ZIP_FL_ENC_RAW` should bypass it) before considering
  its removal — libarchive still needs it for non-zip formats.
- rar lazy extraction as a separate follow-up (already noted as out
  of scope).
