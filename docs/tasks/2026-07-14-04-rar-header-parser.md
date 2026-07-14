# TASK: Fast solid RAR indexing via revived XADMaster header parser — phase 6

## Background

Phase 5 (archived: `docs/tasks/2026-07-14-03-solid-rar-investigation.md`)
root-caused the 13-second open time for solid RAR archives: libarchive's
`archive_read_data_skip()` on RAR5 internally calls the real LZ decoder
and simply discards the checksum step — it is not a cheap header-only
skip. This was confirmed both by reading
`archive_read_support_format_rar5.c` and by observing linear
`archive_filter_bytes` progress over the full 13 seconds.

v1.3.7 (pre-libarchive-migration) opened the same 1.4 GB solid archive
to first page in under 1 second, because XADMaster's RAR skip strategy
(`XADRAR5Parser.m` `-skipBlock:` and the RAR4 equivalent) does a raw
file-offset seek using the compressed size recorded in each entry's
header — it never touches the decompressor, for solid or non-solid
alike. This is possible because RAR headers record each entry's
compressed byte length even within a solid stream.

This task revives just the header-parsing portion of XADMaster (not the
decompression engine — CORarArchive's existing libarchive-based cursor
pass already handles decode) to replace `CORarArchive`'s current index
pass, which currently goes through libarchive and therefore inherits the
same solid-archive decode cost during indexing.

## Goal

- Building the entry index (name, ordinal, offset, compressed/
  uncompressed size) for a RAR archive is a pure header-seek operation,
  independent of solid/non-solid status — no entry data is decoded
  during indexing.
- Time-to-first-page for the 1.4 GB solid fixture approaches the v1.3.7
  baseline (target: sub-second to low-single-digit seconds; document
  the actual number rather than assuming exact parity).
- The libarchive-based cursor pass (decode of a specific requested
  entry, added in phase 4) is unchanged — this task only replaces how
  the index is built, not how entry data is decoded.
- Both RAR4 and RAR5 header formats are supported (v1.3.7 supported
  both; do not regress either).
- Non-solid path, zip/cbz, 7z, and tar are all unaffected.

## Scope

### In scope

- **Locate the source**: find the commit in git history that removed
  XADMaster/UniversalDetector (the v1.4.0 migration). Identify the RAR
  header-parsing files (e.g. `XADRARParser.m`/`.h` for RAR4,
  `XADRAR5Parser.m`/`.h` for RAR5, and any shared support files they
  depend on — archive/entry base classes, CRC or header-checksum
  helpers, etc.). List what's needed vs. what's decoder-only and can be
  left out.
- **Extract a minimal header-only parser**: restore only the code path
  needed to walk a RAR4 or RAR5 file and produce, per entry: name (raw
  bytes, for the existing shared uchardet-based decode step), ordinal,
  byte offset, compressed size, uncompressed size. Do not restore or
  reintroduce XADMaster's decompression/decoder classes — decode
  continues to go through libarchive as it does today.
- **Integrate into `CORarArchive`**: replace the current index-pass
  implementation (libarchive walk with `archive_read_data_skip`) with
  the revived header parser. Keep the existing public interface/
  behavior (entry list, encoding detection hookup) unchanged so the
  cursor pass and caller code need no changes.
- **Licensing**: XADMaster is LGPLv2.1-or-later. Add proper attribution
  (license text + per-file copyright headers preserved) alongside the
  existing libarchive/uchardet/libzip notices. Since this is vendored
  source (not a dylib), confirm whether static inclusion under LGPL
  requires anything beyond attribution for this project's distribution
  model (ad-hoc/Developer ID, not App Store) — note any open question
  in the Implementation Result rather than guessing.
- **Multi-volume / recovery record handling**: if the restored parser
  encounters these, preserve v1.3.7's behavior (or explicitly document
  if this is deferred — see out of scope).
- **Fallback**: if the header parser fails to parse a given archive
  (corrupt, unsupported variant), fall back to the existing
  libarchive-based index pass rather than failing to open, consistent
  with the fallback philosophy used elsewhere in this project.

### Out of scope

- Any change to decompression/decoding — the libarchive cursor pass
  stays as-is.
- Any change to zip/cbz, 7z, tar handling.
- Encrypted/password-protected RAR support (still dropped, per v1.3.7
  policy carried into v1.4.0+).
- QuickLook extension work (still a later phase).
- Restoring XADMaster's non-RAR format support (LhA, etc.) — RAR
  header parsing only.

## Verification

- Build: universal build succeeds; app launches and quits cleanly.
- Correctness: existing RAR4/RAR5 fixtures (non-solid, solid, CP932
  where available) open with correct entry names, order, and page
  content — spot-check against phase 4's fixtures.
- Performance (manual, record numbers in Implementation Result):
  time-to-first-page for the 1.4 GB solid RAR5 fixture, compared
  against both the phase 4 baseline (13.0s) and the v1.3.7 baseline
  (~0.5–1s) from phase 5.
- Regression: non-solid RAR open time stays in the phase 4 range
  (~0.19s); zip/cbz, 7z, tar unaffected.
- Fallback path: verify a deliberately corrupted/truncated RAR still
  opens via the libarchive fallback rather than crashing.

## Implementation Result

**Status:** Completed

### Changes

- **New files** `Sources/CORarHeaderIndex.h` / `Sources/CORarHeaderIndex.m`:
  a from-scratch, header-only RAR4/RAR5 block parser. Not a restoration
  of XADMaster's own class hierarchy (`XADArchiveParser`/`CSHandle`/
  `XADPath`, ~3500 lines of infrastructure this project has no other
  use for) — instead, the block-layout/flag-bit *knowledge* was read
  out of `XADRARParser.m` and `XADRAR5Parser.m` and reimplemented as
  small C/Foundation functions matching `COArchive.m`/`COZipArchive.m`'s
  existing style. Per entry, walks the file via `fseeko`/`fread` only
  (no decompression anywhere in this file): signature check, then a
  block-by-block loop reading `crc/type/flags/headersize` (+ RAR5's
  vint-encoded `extrasize`/`datasize`), extracting name bytes + sizes
  for File blocks, and always advancing to the next block via
  `headerEnd + datasize` — the same byte-offset arithmetic
  `XADRAR5Parser.m`'s `-skipBlock:`/`-endOfBlockHeader:` use, which is
  what makes this cheap for solid archives too (RAR headers record
  each entry's compressed byte length even inside a solid stream).
  Bails (`return nil`) rather than guessing on: wrong/missing
  signature, archive-level header encryption, multi-volume archives
  (Volume flag / split-before/-after), and RAR4 `LHD_UNICODE`-flagged
  names (see Remaining Issues). Filtering (directories, zero-byte,
  AppleDouble sidecars, per-entry encryption) exactly mirrors
  `CORarArchive`'s existing policy so stream ordinals line up with
  what the libarchive-based cursor pass independently derives.
- **`Sources/CORarArchive.m`**: `-readArchiveWithProgress:` now tries
  `-indexArchiveViaHeaderParser` first; on success (`YES`), that's the
  whole index pass — no libarchive call happens during open at all.
  On failure, `crypted`/`lastError`/`contentArray` are reset and the
  method falls through to the *unchanged*, renamed
  `-indexArchiveViaLibarchiveWithProgress:` (this is exactly phase 4's
  method body, just no longer called unconditionally) — the fallback
  requested in scope. `-indexArchiveViaHeaderParser` reuses the same
  `decodeName:fallback:charset:` + single-`uchardet`-pass policy as
  before; RAR5 names are UTF-8 by spec and validated directly (no
  `uchardet` needed unless validation fails), RAR4 non-Unicode names
  go through the shared raw-bytes+charset-detection path unchanged.
- **`Sources/CORarArchive.h`**: design comment updated to describe the
  phase 6 fast path and its relationship to the still-present phase 4
  fallback; clarified that the header-only path never invokes
  progress and cannot be cancelled (matches `COZipArchive`'s
  precedent — expected to finish in well under a second regardless of
  archive size, confirmed by measurement below).
- **Licensing**: `Licence_xadmaster.txt` added (XADMaster's own
  LGPL-2.1-or-later `LICENSE`, with a note at the top scoping which
  files it covers and why). `CORarHeaderIndex.h` carries a formal
  LGPL-2.1-or-later notice (matching `XADRARParser.m`/`XADRAR5Parser.m`'s
  own header style) since it is a derivative work informed by that
  source; `CORarHeaderIndex.m` points to the `.h` for the full notice.
  `README.md`'s license list updated.
  **Open question, not resolved here (flagged per scope rather than
  guessed):** LGPL-2.1's Section 6 static-linking provisions are
  usually satisfied either by dynamic linking or by making the
  LGPL-covered object code/relink material available. cooViewer
  statically compiles `CORarHeaderIndex.*` directly into the app
  binary (no separate dylib), which is the *stricter* case LGPL
  contemplates. My non-lawyer assessment: since cooViewer is already
  fully open source and buildable from this repository (stronger than
  "relink material available" — the complete corresponding source,
  including these files under their own LGPL notice, is already
  public), ordinary LGPL compliance appears satisfied without
  anything beyond attribution. This has **not** been reviewed by
  counsel; if cooViewer's distribution model ever changes (e.g.
  closed-source or object-only releases), this should be revisited
  before shipping.
- **Multi-volume / recovery record**: explicitly deferred, not
  reimplemented. Detected via the RAR5 `Volume` archive flag / RAR4
  `MHD_VOLUME`, or any file with split-before/split-after flags set —
  in every case `CORarParseHeadersAtPath` returns nil and
  `CORarArchive` falls back to the libarchive-based scan (which itself
  doesn't reassemble multi-volume sets either — this project has never
  supported multi-volume RAR, in phase 4 or before; phase 6 does not
  change that, it just declines to *guess* at a format extension it
  wasn't asked to implement).
- **Fallback**: implemented exactly as scoped — verified with
  `corrupt_truncated.cbr` (header parser hits EOF mid-scan → falls
  back → same 1-entry-plus-`lastError` result as phase 4),
  `corrupt_bitflip.cbr` (headers intact, only entry data corrupted →
  fast path succeeds, corrupt entry surfaces as `nil` data at read
  time exactly as before), and a new `mislabeled.cbr` test (a `.zip`
  renamed to `.cbr` → header parser correctly rejects both RAR
  signatures → libarchive-based `CORarArchive` scan also fails → outer
  `COArchive` dispatch falls back further to the base full-extraction
  path, which opens it correctly as zip).
- **Tests**: `tests/fixtures/make_rar4_fixture.py` (new) hand-writes a
  minimal valid RAR4 (STORE method) archive from the standard
  `001.png`–`004.jpg` fixture set — no RAR4-capable archiver is
  available in this environment (`rar`/`unrar` 7.23 only create RAR5;
  `-ma4`-style format-version switches were removed). Needs no
  external tool, so it's generated unconditionally in
  `make_fixtures.sh`. Cross-checked against libarchive's own RAR4
  reader directly (a standalone probe correctly listed and decoded
  both entries) before wiring into the suite. `tests/engine/test_coarchive.m`:
  added `test_rar4.cbr` to the positive matrix plus a dedicated
  fast-path/progress-count check, a `mislabeled.cbr` fallback test,
  and updated the RAR progress/cancel test to reflect the new
  behavior (progress no longer fires for a plain RAR5 fixture, since
  the fast path — not the old libarchive scan — now handles it).

### Verification

- Build: `xcodebuild -configuration Deployment clean build` succeeds,
  no new warnings from any new or modified file; `clang --analyze` on
  `CORarHeaderIndex.m` and `CORarArchive.m` reports nothing.
- Correctness: `tests/fixtures/make_fixtures.sh` +
  `tests/engine/run_tests.sh` — **ALL PASS**, including SHA-256
  payload verification for `test.cbr`, `test_solid.cbr`,
  `test_utf8.cbr`, and the new `test_rar4.cbr`, plus backward
  navigation and the corruption/fallback tests above.
- Performance (manual, `~/Downloads/1.cbr` / `1-solid.cbr`, both
  1.4 GB RAR5 / 665 entries — same fixtures phases 4–5 used;
  measured with the same throwaway timing harness):

  | | phase 4 (libarchive index pass) | phase 6 (header-only fast path) | v1.3.7 (phase 5 baseline) |
  |---|---|---|---|
  | non-solid open | 0.189–0.211 s | **0.102–0.106 s** | n/a |
  | solid open | 13.0 s | **0.106 s** | n/a |
  | solid first-entry decode (after open) | 0.025 s | 0.023 s (unchanged — cursor pass untouched) | n/a |
  | **solid time-to-first-page (open + first entry)** | **~13.0 s** | **~0.13 s** | ~0.5–1 s (screenshot-measured) |
  | solid full sequential read-through (665 entries) | 13.097 s | 13.217 s (unchanged — same cursor/decode cost, now spread across reading instead of blocking open) | n/a |

  Phase 6 doesn't just match the v1.3.7 baseline for time-to-first-page,
  it beats the screenshot-measured figure — consistent with the root
  cause being fully addressed (enumeration no longer touches a
  decompressor at all, matching XADMaster's own strategy exactly).
  In-app (manual, screenshots taken): the 1.4 GB solid file now shows
  its first page within the same launch-plus-render window as the
  non-solid file (no more black screen + indeterminate spinner);
  forward/backward page turns near the open position are smooth.
  Total CPU work for a full sequential read-through of a solid archive
  is **unchanged** (still ~13 s, since the cursor/decode pass is
  exactly phase 4's code) — phase 6 only removes the requirement to
  pay that cost *before* showing anything, matching v1.3.7's own
  background-lookahead-thread behavior (see phase 5's CPU trace).
- Regression: non-solid RAR open time improved rather than regressed
  (0.1s range, down from phase 4's 0.19–0.21s, since header-only
  parsing is cheaper than a libarchive skip-loop even when skip is
  already cheap). zip/cbz (`COZipArchive`) and 7z (base `COArchive`)
  verified unaffected via the engine suite and manual app checks.
- Manual app verification (screenshots): `sample.cbr` (small
  non-solid), `sample-solid.cbr` (small solid), `1.cbr` / `1-solid.cbr`
  (large, both), and `test.7z` (regression) all open correctly with
  forward/backward paging confirmed on the ones exercised interactively.

### Remaining Issues

- **RAR4 `LHD_UNICODE` names are not fast-pathed.** XADMaster decodes
  these with a bespoke run-length name encoding (`XADRARParser.m`
  `-parseNameData:flags:`); porting it untested felt riskier than
  useful — a subtly wrong port could produce silently incorrect
  (not obviously erroring) filenames, which is worse than the
  fallback. Entries with this flag make the whole-archive header
  parse bail, falling back to libarchive (which decodes RAR4 Unicode
  names correctly today, unaffected by this task). Net effect: such
  archives keep working exactly as in phase 4, just without the phase
  6 speed benefit.
- **No RAR4 fixture-generation tool exists** in this environment;
  `tests/fixtures/make_rar4_fixture.py` hand-writes one from the RAR4
  spec (verified against libarchive's own reader), which covers the
  basic single-volume/non-Unicode/non-encrypted/STORE-method case
  well, but doesn't exercise every RAR4 corner (LARGE files needing
  the 64-bit size extension, per-entry `LHD_SALT`, legacy pre-2.0
  solid-flag inference). These paths were written directly from
  `XADRARParser.m` with the same bail-on-anything-unexpected
  discipline as the rest of the parser, but are unverified beyond
  code review.
- **CP932/legacy-charset RAR remains untested for RAR4 specifically**
  (same gap phase 4/5 already noted for RAR5, where it's moot since
  RAR5 mandates UTF-8 names). Non-Unicode RAR4 names go through the
  exact same shared `decodeName:fallback:charset:` + `uchardet` path
  already verified for zip's CP932 fixture, so risk is judged low, but
  it is not a RAR4-specific test.

### Follow-up Suggestions

- If a genuine RAR4-with-Unicode-names sample ever surfaces, port and
  verify `XADRARParser.m`'s name-decoding algorithm against it, then
  remove the `LHD_UNICODE` bail condition in `CORarHeaderIndex.m`.
- Get an outside opinion on the LGPL static-linking question above
  before any packaging/distribution change (e.g. object-only or
  closed releases) that would weaken the "fully buildable from public
  source" argument this task's assessment leans on.
- QuickLook extension work remains a later phase, untouched here.
