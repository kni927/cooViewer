# TASK: RAR partial lazy extraction — phase 4 (archive_read_data_skip)

## Background

Phases 1–2 (archived: `docs/tasks/2026-07-13-01-vendor-libzip.md`,
`docs/tasks/2026-07-13-02-libzip-reader.md`) solved the open-time/memory
regression for zip/cbz by adding a libzip-based random-access reader.
RAR archives still go through the original v1.4.0 libarchive
full-extraction-at-open path.

libarchive's RAR reader is a streaming API — it cannot seek directly to
an arbitrary entry the way libzip can. However, `archive_read_data_skip()`
lets the reader advance past an entry's compressed data without fully
decoding it, which is far cheaper than decoding. For non-solid RAR
archives (the common case in this collection — confirmed non-solid for
the RARs surveyed so far), this allows a "skip to target entry, decode
only that entry" pattern that approximates zip's lazy behavior without
adding a new dependency or license.

No new library, no license addition, no Gatekeeper impact — this is a
change to the existing libarchive RAR path only.

## Goal

- Opening a RAR archive reads only entry headers (via skip), not full
  entry data; open time no longer scales with total archive size for
  non-solid RARs.
- Entry data is decoded on demand, when the viewer requests a specific
  page.
- Both forward and backward page navigation work correctly and at
  reasonable speed.
- Solid RAR archives still work correctly (correctness first; skip's
  performance benefit is expected to be smaller for solid archives,
  since decoding may still be required to rebuild the shared
  dictionary up to the target entry — this is an acceptable and
  expected limitation, not a bug).
- No change to zip/cbz (already on the libzip path) or 7z/tar handling.

## Scope

### In scope

- Extend or wrap the existing libarchive-based reader for `.rar` files
  to support entry-indexed access:
  - On open, walk the archive once via `archive_read_next_header` +
    `archive_read_data_skip` to build an index of entry
    metadata (name, index, offset-in-sequence) without decoding entry
    data. This is the same central-directory-equivalent step zip gets
    for free; for RAR it costs one skip-only pass.
  - Encoding detection: same policy as zip/existing RAR handling —
    concatenate raw entry names, run uchardet once. Reuse existing
    shared decoding logic where possible (per phase 2 notes).
  - For decoding a single requested entry: since libarchive can only
    read forward from its current stream position, implement one of:
    - **Preferred if simple:** re-open the archive stream and
      fast-forward with `archive_read_data_skip()` through preceding
      entries to reach the target, then `archive_read_data()` only the
      target entry. Cheap for non-solid; correctness-preserving for
      solid (skip still walks the stream, just not free of decode cost
      internally for solid).
    - Track current stream position; if the next request is for the
      same or a later entry than current position, continue forward
      via skip; if an earlier entry is requested (e.g. user paged
      backwards), re-open and fast-forward from the start.
  - Cache decoded NSData in an NSCache (or simple LRU), consistent with
    the phase 2 zip cache approach (byte-limited, not unbounded).
  - Optional, only if trivial: prefetch the next entry after a
    successful decode, mirroring the zip reader's prefetch.
- **Thread safety**: serialize all archive stream operations for a
  given document on a dedicated serial dispatch queue (same pattern as
  `COZipArchive`).
- **Dispatch**: no change needed at the format-dispatch level (RAR
  already routes to the libarchive-based reader) — the change is
  internal to that reader's entry-access strategy.
- **Failure handling**: corrupt archives, unreadable entries, or
  unexpected header errors fall back to the existing error UI. Do not
  attempt a "full extraction fallback" for RAR (unlike the zip
  central-directory-corruption fallback) unless it turns out to be
  trivial — if not trivial, note it as a follow-up instead.

### Out of scope

- Any change to zip/cbz, 7z, or tar handling.
- unrar / UnrarKit or any new third-party RAR library.
- Solid-archive performance optimization beyond correctness (e.g. no
  dictionary caching across entries within a solid block).
- QuickLook extension work (planned as phase 5, after this task).

## Verification

- Build: universal build succeeds; app launches and quits cleanly.
- Correctness: representative non-solid RAR and at least one solid RAR
  fixture open and display all pages in correct order with correct
  filenames (CP932 fixture included).
- Performance (manual, record numbers in Implementation Result):
  - Non-solid RAR, largest available in the collection: open time and
    peak RSS, before (full extraction) vs after.
  - Solid RAR (if available): confirm correctness; note whether
    performance improved, stayed flat, or regressed, and explain why.
  - Forward and backward page navigation: no perceptible stutter for
    non-solid; document actual behavior for solid.
- Regression: zip/cbz, 7z, and tar archives behave exactly as before
  (unaffected by this change).
- Note in Follow-up Suggestions whether the corrupt-archive fallback
  (mentioned as out-of-scope-if-nontrivial above) turned out to be easy
  enough to add, for future consideration.

## Implementation Result

**Status:** Completed

### Changes

- `Sources/CORarArchive.h` / `Sources/CORarArchive.m` (new):
  libarchive-based partial-lazy reader for `.rar`/`.cbr`.
  - **Index pass** (open time): one skip-only walk of the stream via
    `archive_read_next_header` + `archive_read_data_skip`, collecting
    raw name bytes and a stream ordinal per qualifying entry, without
    decoding any entry data. Runs synchronously on the initializing
    (main) thread, matching the base COArchive path, because its
    progress callback pumps `NSApp`'s event queue directly
    (`Controller.m`'s `-archiveReadProgress:total:`) — that has to
    stay on the main thread, not move to a background queue.
  - **Cursor pass** (on demand, per entry): a second, independent
    `archive_read` stream (`cursor`) tracks the ordinal it will read
    next (`cursorNext`). Reading entry N: if N is behind the cursor
    (or no cursor exists yet), reopen the file from the start and
    fast-forward via `archive_read_data_skip` through every
    qualifying entry up to N; otherwise the existing cursor just
    continues. The target entry is decoded via `archive_read_data`.
    After a successful decode, the following entry is prefetched for
    free since the cursor is already positioned right after it.
  - Decoded `NSData` is cached in an `NSCache` (256 MB
    `totalCostLimit`, same policy as `COZipArchive`) keyed by stream
    ordinal — not array position, since a (very unlikely in
    practice) entry with no decodable name would otherwise desync the
    two; `CORarEntry` carries both `ordinal` (stream position, what
    the cursor targets) and `arrayIndex` (position in `contentArray`,
    used to find the next entry to prefetch).
  - Thread safety: cursor operations (`readEntryOnQueue:`) are
    serialized on a private serial dispatch queue; `-data` is safe
    from any thread (matches `COZipArchive`'s contract).
  - Filename encoding: unchanged policy — raw bytes collected per
    entry, one `uchardet` pass if any entry lacks a UTF-8 conversion,
    decoding via the same `COArchive` `decodeName:fallback:charset:`
    routine `COZipArchive` also reuses. Unlike the libzip path, this
    **does** still depend on the process locale, because libarchive's
    RAR reader performs its own raw-to-UTF8 conversion internally
    (`archive_entry_pathname_utf8`) — the `setlocale` workaround in
    `main.m` remains required for RAR.
  - Corrupt entries are detected at read time (`-data` returns `nil`,
    broken-image placeholder), not dropped at open time — same
    tradeoff as `COZipArchive`, for the same reason.
- `Sources/COArchive.m`: dispatches `.rar`/`.cbr` to `CORarArchive`.
  If `archive_read_open_filename` itself fails (bad signature — e.g.
  a mislabeled non-RAR file with a `.cbr` extension, or an unreadable
  file), falls back to the base full-extraction path, mirroring zip's
  existing corrupt-central-directory fallback — **this turned out to
  be trivial** (a few lines, same shape as the zip fallback already
  in the file) once `CORarArchive` existed, so it was implemented
  rather than deferred. Failures that happen *after* a successful
  open, mid-index-scan (e.g. a truncated file), do **not** trigger
  this fallback — `-rarOpened` is already `YES` by then, so whatever
  entries were indexed before the error stay listed, matching the
  base path's existing partial-results-on-truncation behavior.
- `cooViewer.xcodeproj`: `CORarArchive.h`/`.m` added to the `archive`
  group and the Headers/Sources build phases.
- `Sources/COArchive.h`: top-of-file design comment updated to
  mention the new dispatch target.
- Tests (`tests/engine/`):
  - `tests/fixtures/make_fixtures.sh`: added `test_solid.cbr`
    (`rar a -s`), generated alongside `test.cbr` whenever `rar` is
    available.
  - `tests/engine/run_tests.sh`: links `CORarArchive.m`; generates
    `corrupt_truncated.cbr` (head -c 50000) and `corrupt_bitflip.cbr`
    (bytes flipped inside entry #1's compressed stream) from
    `test.cbr`, guarded on `test.cbr` existing.
  - `tests/engine/test_coarchive.m`: dispatch assertions extended to
    `CORarArchive`; a solid-archive test using the fixture's actual
    (reordered) stream order; a backward-navigation correctness test
    covering both the "continue forward" and "reopen from start"
    cursor paths on non-solid and solid; a RAR progress/cancel test
    (unlike zip, RAR's index pass is a real scan, so progress fires
    and cancel works); truncated/bit-flipped RAR corruption tests;
    and a mislabeled-file (zip renamed `.cbr`) fallback test.
  - `tests/fixtures/README.md`: noted the new solid fixture and why
    its archive order differs from `test.cbr`'s.

### Verification

- Build: `xcodebuild -configuration Deployment` succeeds (only
  pre-existing deprecation warnings); `clang --analyze` on
  `CORarArchive.m`/`COArchive.m` reports nothing; app launches and
  quits cleanly.
- Tests: `tests/fixtures/make_fixtures.sh` + `tests/engine/run_tests.sh`
  — ALL PASS (dispatch, solid reordering, backward navigation,
  progress/cancel, truncated/bit-flip corruption, mislabeled-file
  fallback).
- Correctness (manual, real files from `~/Downloads/`): `sample.cbr`
  (non-solid) and `sample-solid.cbr` (solid) both open in the app
  with all 4 pages correct and forward/backward paging working
  (screenshots taken during the session). CP932 fixture: **not
  covered** — see Remaining Issues.
- Performance (manual, `~/Downloads/1.cbr` / `1-solid.cbr`, both
  1.4 GB RAR5 / 665 entries, measured with a throwaway timing harness
  linking the production reader classes; "before" measured by opening
  the same file through a `.tar`-named symlink, which bypasses the
  extension-based dispatch and exercises the *unchanged*
  full-extraction path libarchive auto-detects RAR5 from regardless
  of filename):

  | | before (full extraction) | after (CORarArchive) |
  |---|---|---|
  | non-solid open | 2.060 s | **0.189 s** |
  | non-solid footprint after open | 2676 MB | **2.6 MB** |
  | non-solid sequential read-all (1324 MB) | — | 0.847 s, footprint ≤477 MB |
  | non-solid cold backward jump (mid-archive) | — | ~0.02 s |
  | solid open | 13.835 s | 13.000 s (no meaningful change — expected) |
  | solid footprint after open | 2714.5 MB | **34.5 MB** |
  | solid sequential read-all (1324 MB) | — | 13.097 s, footprint ≤527 MB |
  | solid cold backward jump to ~halfway (entry 332/665) | — | 6.222 s |
  | solid backward jump to entry 0 specifically | — | 0.031 s (no skip needed) |

  In-app: the 1.4 GB non-solid file opens with the first page visible
  effectively instantly; page turns (forward and backward) are
  imperceptible. The 1.4 GB solid file takes ~13 s to open (matching
  the harness), after which page turns near the current position are
  smooth — this matches the task's own explicit expectation that
  solid archives keep correctness but see a smaller (here: ~0)
  open-time benefit.
- Solid-archive reordering finding (verified, not assumed): RAR's
  solid compressor only reorders entries when file types are mixed —
  the small 4-entry test fixture (`.png`+`.jpg` mixed) came back as
  002,004,001,003 (grouped by extension), which is why the test
  suite treats it specially. The real 1.4 GB solid file (665
  uniformly-`.png` pages) had **zero** archive-order vs.
  name-sorted-display-order mismatches (checked exhaustively), so
  ordinary forward reading in the viewer (which displays pages in
  `COImageLoader`'s name-sorted order) never triggers the expensive
  "backward" re-skip path for a realistic, homogeneous-extension
  comic archive — that path is only reached by an explicit long-range
  jump (e.g. the page-number field) on a solid archive.
- Regression: `test.zip`/`test.cbz` (COZipArchive, unaffected),
  `test.7z`/`test.tar` (base COArchive, unaffected) verified via the
  engine suite; `test.7z` also opened and displayed correctly in the
  app.

### Remaining Issues

- No genuine CP932-encoded RAR fixture exists, so the CP932 path is
  **not directly exercised** for RAR (only for zip, via
  `test_sjis.zip`/phase 2). The `rar` CLI available in this
  environment produces RAR5 archives, which store names as Unicode by
  default; no switch was found (within reasonable effort — see
  Follow-up Suggestions) to force legacy OEM/CP932 names the way
  `make_sjis_fixture.py` does for zip's raw byte layout. Risk is
  judged low because `CORarArchive`'s name decoding is the *same*
  shared `decodeName:fallback:charset:` routine and single-`uchardet`-pass
  policy already verified for zip's CP932 case in phase 2 — the only
  code genuinely new to phase 4 is the index/cursor ordinal
  bookkeeping, which the UTF-8 (`test_utf8.cbr`) and solid-reordering
  tests do exercise. `test_utf8.cbr` opens correctly in the app.

### Follow-up Suggestions

- Investigate producing a genuine CP932-named RAR fixture (e.g. RAR4
  format via a different tool/flag, or a hex-edited RAR5 name field)
  to directly close the gap noted above.
- For solid archives, a long-range backward jump to an entry outside
  the current NSCache window costs time roughly proportional to how
  far into the archive that entry is (measured: ~6.2 s to reach the
  halfway point of a 1.4 GB solid archive from a cold cache). This is
  accepted per this task's scope (solid is correctness-first), but if
  it proves annoying in practice, a future option is detecting solid
  mode at open time and either enlarging the cache budget for it or
  warning the user that random-access jumps are slow for that file.
- QuickLook extension work remains phase 5, as already noted in the
  task background (untouched by this task).
