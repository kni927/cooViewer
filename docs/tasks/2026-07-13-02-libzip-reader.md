# TASK: Lazy zip extraction — phase 2 (libzip reader path + dispatch)

## Background

Phase 1 (archived: `docs/tasks/2026-07-13-01-vendor-libzip.md`) vendored
libzip 1.11.4 as a universal dylib and wired it into the Xcode project.
No reader code exists yet; all formats still go through the libarchive
full-extraction path, so the large-archive open-time regression remains.

This task implements the actual lazy reader path for zip/cbz and switches
format dispatch to it. This completes the work originally scoped in the
phase 1 task document.

## Goal

- Opening a zip/cbz archive reads only the central directory; no entry
  data is decoded at open time.
- Entry data is decoded on demand, per entry, when requested by the
  viewer; peak memory no longer scales with total archive size.
- No behavior change for rar / 7z / tar (libarchive path untouched).

## Scope

### In scope

- **Zip reader class** (new, alongside the existing libarchive wrapper):
  - Open with `zip_open` (read-only), keep the `zip_t*` handle for the
    document lifetime, close on document close.
  - Enumerate entries via the central directory only.
- **Filename encoding** (same policy as v1.4.0):
  - Fetch names with `ZIP_FL_ENC_RAW` so libzip performs no conversion.
  - Concatenate all raw name bytes, run uchardet once on the buffer
    (per-filename detection is known to produce unacceptable CP932
    error rates — do not change this policy).
  - Convert raw names to NSString with the detected encoding.
  - Verify the `setlocale(LC_ALL, "en_US.UTF-8")` workaround is NOT
    needed on this path (it must remain in place for the libarchive
    path). Record the finding in the Implementation Result.
- **On-demand entry data**:
  - Decode a single entry via `zip_fopen_index` + `zip_fread` into
    NSData on first request; preserve the existing NSData interface
    consumed by COImageLoader.
  - Cache decoded NSData in an NSCache (or simple LRU) keyed by entry
    index, with a byte-count limit so memory stays bounded.
  - Optional, only if trivial: prefetch the next entry in reading order
    on a background queue.
- **Thread safety**: a `zip_t*` handle is not safe for concurrent reads.
  Serialize entry reads on a dedicated serial dispatch queue (preferred
  for simplicity), or open a per-read handle if serialization proves
  insufficient. Choose the simplest correct option and document it.
- **Format dispatch**: route `.zip` / `.cbz` to the new reader; all
  other extensions keep the current libarchive path unchanged.
- **Failure handling**:
  - Encrypted entries: unsupported (crypto backends were disabled in
    the phase 1 libzip build). Fail gracefully via the existing error
    path.
  - Corrupt/partial central directory (`zip_open` failure): fall back
    to the libarchive full-extraction path if straightforward;
    otherwise surface the existing error UI.

### Out of scope

- rar lazy extraction (separate future task).
- Any change to 7z / tar handling or the libarchive wrapper itself.
- Password prompt UI / encrypted zip support.
- Controller.m refactoring or source-tree reorganization.

## Verification

- Build: universal build succeeds; app launches and quits cleanly.
- Encoding: CP932-named fixture CBZ opens with correct Japanese
  filenames on the new path; ensure the CI test fixture exercises the
  libzip path after dispatch switch.
- Performance (manual, record numbers in Implementation Result):
  - ~2 GB CBZ: open-to-first-page time before (v1.4.0 libarchive path)
    vs after; should be subjectively immediate after.
  - Peak RSS during sequential read-through stays bounded.
  - Page turning (including backwards) has no perceptible regression.
- Regression (manual): representative rar / 7z / tar archives open and
  display exactly as in v1.4.0.
- Carry over the unverified items listed in the phase 1 archive
  (2 GB measurement, CP932 fixture, non-zip regression) — they are
  verified here.

## Implementation Result

**Status:** Completed

### Changes

- `COZipArchive.h` / `COZipArchive.m` (new): libzip lazy reader.
  - `COZipArchive` subclasses `COArchive` and overrides the archive
    read: `zip_open(ZIP_RDONLY)`, central directory enumeration only,
    handle kept for the document lifetime, `zip_discard` on dealloc.
  - `COZipEntry` subclasses `COArchiveEntry` and overrides `-data`:
    decoded on first request via `zip_fopen_index`/`zip_fread`, with
    an explicit EOF read so libzip verifies the entry CRC. Decoded
    NSData is cached in an NSCache keyed by entry index with a 256 MB
    `totalCostLimit`. After a demand read, the next entry in archive
    order is prefetched on the read queue.
  - Thread safety: all libzip calls after init are serialized on a
    private serial dispatch queue (`dispatch_sync` for demand reads,
    `dispatch_async` for prefetch); chosen over per-read handles for
    simplicity. `-data` is safe from any thread.
  - Filename encoding: names fetched with `ZIP_FL_ENC_RAW`, uchardet
    run once over all concatenated raw names, decoding shared with
    COArchive's `decodeName:fallback:charset:` (unchanged policy).
  - Entry skipping matches COArchive: directories, zero-byte entries,
    AppleDouble sidecars; encrypted entries set `-crypted` and are
    skipped (fails via the existing error path when nothing remains).
- `COArchive.m`: format dispatch in `initWithPath:progress:` — for
  `.zip`/`.cbz` it returns a `COZipArchive` when `zip_open` succeeds;
  on failure (corrupt/partial central directory) it logs and falls
  through to the unchanged libarchive full-extraction path. Non-zip
  formats and the libarchive code itself are untouched; COImageLoader
  needed no changes (the NSData entry interface is preserved).
- `main.m`: comment updated — the setlocale workaround stays (needed
  by the libarchive fallback and non-zip formats) but the libzip path
  is locale-independent.
- Tests (`tests/engine/`): harness now builds COZipArchive + libzip;
  added dispatch-class assertions (zip/cbz → COZipArchive, others →
  COArchive), a CP932 test under a forced C locale, and a
  zip-cancel-is-noop check. The bit-flip corruption expectation
  changed: the lazy reader lists all 4 entries and returns nil data
  for the corrupt one at read time (the libarchive path dropped it at
  open time) — intentional behavior change, documented in
  COZipArchive.h. Missing optional 7z/rar fixtures are now skipped.
- CI: new "Run archive engine tests" step (make_fixtures.sh +
  run_tests.sh), so the CP932/zip fixtures exercise the libzip path
  on every build; actionlint passes.

### Verification

- Build: Deployment build succeeds (only pre-existing deprecation
  warnings); app launches and quits cleanly.
- Tests: `tests/engine/run_tests.sh` ALL PASS, including the full
  regeneration flow (`make_fixtures.sh` + tests) and a run with a
  fixture removed to confirm skip handling.
- Encoding: CP932 fixture decodes correctly on the libzip path, and
  still decodes correctly with `LC_ALL=C` forced — empirically
  confirms the setlocale workaround is NOT needed on this path (it
  remains required for the libarchive path).
- Performance (~1.9 GB, 200-entry deflate CBZ, local M-series
  machine, timing harness on the engine):
  - open: 6.1 s (v1.4.0 libarchive) → **0.004 s** (libzip lazy)
  - phys_footprint after open: 3772 MB → **2.2 MB**
  - first entry on demand: 0.051 s (15.5 MB page)
  - sequential read of all 200 entries (1880 MB decoded): 6.0 s
    total with peak footprint **400 MB** (peak RSS 469 MB) — bounded
    by the 256 MB cache, vs 3772 MB before
  - In-app (manual): the 2 GB CBZ opens with the first page visible
    immediately; forward and backward page turns render instantly;
    app RSS ~90 MB after open, ~35 MB steady during reading.
- Regression (manual + suite): tar/7z/rar fixtures pass byte-identical
  in the suite; test.cbr opened and displayed correctly in the app.
- Not performed: rar lazy extraction (out of scope).

### Remaining Issues

- None.

### Follow-up Suggestions

- rar lazy extraction (already planned as a separate task).
- The zip open path ignores the progress callback and cannot be
  cancelled (open is near instant, so the progress UI never appears);
  if a pathological zip with a huge central directory ever matters,
  progress could be added around the enumeration loop.
- Corrupt zip entries now surface as the broken-image placeholder at
  view time instead of being dropped from the page list at open time;
  if that proves confusing, a background integrity sweep could prune
  them after open.
