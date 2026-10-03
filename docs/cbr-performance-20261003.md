# CBR Performance: v1.6.5 vs v1.3.7 — 2026-10-03

Measurement-only investigation; no product code was changed. Task record:
`docs/tasks/2026-10-03-04-cbr-perf-and-code-review.md`.

## Answer

The current version (v1.6.5, libarchive) is **not generally slower** than
v1.3.7 (XADMaster). Open, time to first page, solid RAR5 reading, solid
jumps, and especially paging *back* in a solid archive are as fast or faster.
It is worse in three specific cases, ranked by impact:

1. **Solid RAR4 archives do not work at all.** Only page 1 is readable;
   every later page shows "broken or not image file" (confirmed in the app).
   If the names use RAR4's Unicode flag, as WinRAR writes Japanese names, the
   book opens as a single page. v1.3.7 reads these archives fully. The vendored
   libarchive 3.8.4, and upstream master as of today, reject solid RAR4
   ("RAR solid archive support unavailable"). This is the most likely thing
   an owner of older RAR4 `.cbr` files would notice, and it is a correctness
   regression, not a speed one.
2. **Non-solid archives whose stored order differs from page order** are
   slower to read through without pause: 1.3× on the owner-provided book,
   1.1× on a 400-page book, and 3.3–3.9× on 2000 small pages. Single page
   turns occasionally take 60–170 ms. `CORarArchive` has a forward-only
   decoder cursor, so every page that lies *behind* the cursor in stored
   order reopens the archive and walks the headers from the start (194
   reopens for the 511-page owner book). XADMaster seeks straight to each
   entry. `rar` on macOS stores non-solid archives in directory order, which
   is not name order, and the owner book is stored this way. At a normal
   reading pace (a page every 300 ms) the prefetch hides it, and the current
   version is faster than v1.3.7 there.
3. **Memory.** Peak memory while reading is 85–237 MB against 17–52 MB,
   because of the 256 MB decoded-entry `NSCache`. This is not a speed problem;
   it is the price of finding 2 under Q4.

Solid archives still need seconds to jump far ahead or to page back past
the cache (Q1, Q4). That holds in both versions, and v1.3.7 is slower at it.
An owner who notices "slow" when jumping into a large solid book is seeing a
property of the format that both decoders share, not a regression.

## Method

- **Machine:** one Apple Silicon Mac, macOS 26.6.2, on AC power. Both
  versions were measured in the same session, interleaved.
- **Harness:** a command-line program built twice from one source, outside
  the repository (session scratchpad).
  - **Current:** compiles `Sources/COArchive.m`, `COZipArchive.m`,
    `CORarArchive.m`, `CORarHeaderIndex.m` and `NSString_Compare.m` against
    the vendored `vendor/lib` dylibs.
  - **Baseline:** compiles v1.3.7's `XADWrapper.m` / `XADItem.m` from a
    `git worktree` of tag `v1.3.7` (outside the repository), against
    `XADMaster.framework` built from that worktree's submodule. Xcode 27
    needed `MACOSX_DEPLOYMENT_TARGET=12.0` on the command line; the worktree
    was not edited.
  - **What it times:** both sides go through the object the app's
    `COImageLoader` uses (`-contents`, then a sort with `-finderCompareS:`,
    then `-[item data]`). Time to first page also forces a full ImageIO decode
    of page 1.
- **Scenarios**, one fresh process each:
  - `open`: open, list and sort, then page 1 data and decode.
  - `seq`: every page in page order, back to back.
  - `paced`: the first 30 pages, one every 300 ms.
  - `jump`: page 1, the middle page, the last page, page 1, then the page a
    quarter of the way in.
  - `back`: Q4.
- **Runs:** 3 runs each; the tables show the median. "1st page" is the
  minimum of 3, see the note below.
- **Cache:** `purge` needs sudo and was not used, so the file cache was never
  dropped. **All numbers are warm-cache**: each run reads the whole archive
  once (`cat > /dev/null`) immediately before it, and the order of the two
  versions alternates between runs.
  - A first pass without this was discarded. It systematically penalised
    whichever version ran first on a file: non-solid header reads were cold,
    and open took 250–430 ms instead of 4–6 ms for 2000-entry archives.
- **Decode spike:** even with pre-warming, the first process after the
  `cat` decodes page 1 in 120–250 ms instead of about 27 ms. This happens to
  either version, whichever runs first. It is an artefact of the method, so
  "1st page" is reported as the minimum of 3, and "1st data" (the archive
  layer alone) as the median.
- **In the app:** `build/cooViewer.app` (main app only, launched with `open`)
  confirmed the solid-RAR4 page-2 failure and showed page 1 of the 557 MB
  solid RAR5 fixture within the one to two seconds between `open` and the
  first screenshot, launch included. Screenshots cannot time anything finer.
- **Build:** the current version was built with the `CLAUDE.md` command and
  its `getconf DARWIN_USER_TEMP_DIR` note. This was the first use of that
  note, and it worked as written: `getconf` in its own call, then the literal
  path to `xcodebuild`, `cp` and `rm`. `cp` from the per-user temp directory
  into `build/` worked inside the sandbox.

### Corpus

The fixtures are generated: synthetic greyscale JPEG pages of 1400×2000 px
at about 1.45 MB each, or 300×430 px at about 100 KB each. Like real scans,
they are nearly incompressible, so RAR stores them at roughly their original
size. RAR5 archives were made with `rar` 7.23. RAR4 archives were made with
`rar` 6.24 `-ma4`, since 7.x can no longer write RAR4; it was downloaded from
rarlab.com with the owner's approval and used only for these fixtures. All
generated archives use method 3 (normal). One owner-provided book is included
and described generically.

| file | format | solid | entries | size | method | names | stored order |
|---|---|---|---|---|---|---|---|
| r4n | RAR4 | no | 120 | 170 MB | 3 | ASCII | directory order |
| r4s | RAR4 | yes | 120 | 169 MB | 3 | ASCII | name order |
| r4u | RAR4 | no | 120 | 170 MB | 3 | Japanese (`LHD_UNICODE`) | directory order |
| r4us | RAR4 | yes | 120 | 169 MB | 3 | Japanese (`LHD_UNICODE`) | name order |
| r4n_small | RAR4 | no | 2000 | 195 MB | 3 | ASCII | directory order |
| r4s_large | RAR4 | yes | 400 | 563 MB | 3 | ASCII | name order |
| r5n | RAR5 | no | 120 | 170 MB | 3 | ASCII | directory order |
| r5s | RAR5 | yes | 120 | 167 MB | 3 | ASCII | name order |
| r5n_large | RAR5 | no | 400 | 567 MB | 3 | ASCII | directory order |
| r5s_large | RAR5 | yes | 400 | 557 MB | 3 | ASCII | name order |
| r5n_small | RAR5 | no | 2000 | 195 MB | 3 | ASCII | directory order |
| r5s_small | RAR5 | yes | 2000 | 192 MB | 3 | ASCII | name order |
| control | ZIP (`.cbz`) | — | 120 | 179 MB | deflate | ASCII | name order |
| owner | RAR5 | no | 511 | 335 MB | 1 (fastest), 2 stored | ASCII, in a subfolder | directory order |

"Directory order" means the order `rar` met the files in, which on APFS is
not name order. For solid archives `rar` sorts the files itself.

## Q1 — Where does time go, by archive kind?

All values are medians of 3 runs, in ms unless marked s. Each cell is
v1.3.7 / current. FAIL means the page data could not be read.

### Open and first page

| file | open | 1st data | 1st page (min of 3) |
|---|---|---|---|
| r4n | 7 / 2 | 18 / 16 | 51 / 70 |
| r4s | 3 / 2 | 18 / 16 | 48 / 39 |
| r4u | 7 / 5 | 18 / 16 | 50 / 48 |
| r4us | 6 / 3 | 18 / 13 | 52 / 39 (book has 1 page) |
| r4n_small | 22 / 6 | 2 / 4 | 25 / 14 |
| r4s_large | 12 / 5 | 20 / 16 | 56 / 48 |
| r5n | 5 / 1 | 20 / 17 | 50 / 46 |
| r5s | 3 / 0 | 24 / 16 | 54 / 42 |
| r5n_large | 7 / 1 | 19 / 19 | 53 / 48 |
| r5s_large | 9 / 1 | 24 / 19 | 59 / 44 |
| r5n_small | 24 / 4 | 1 / 4 | 29 / 13 |
| r5s_small | 25 / 5 | 7 / 2 | 34 / 10 |
| control | 7 / 3 | 5 / 4 | 36 / 34 |
| owner | 9 / 2 | 14 / 14 | 44 / 43 |

- Open is faster in the current version everywhere: the header-only index
  versus XADMaster's parser.
- Time to first page is the same: data plus a ~27 ms ImageIO decode.
- **Cold header reads are not covered by these numbers.** In the discarded
  cold-ish pass, the open of 2000-entry non-solid archives took 0.15–0.43 s
  for whichever version ran first, because the headers are spread across
  the file.

### Sequential reading

| file | next page med / p90 / max | all pages (s) | paced, 1 page per 300 ms (med) |
|---|---|---|---|
| r4n | 18/20/53 · 12/28/76 | 2.21 / 1.68 | 42 / 25 |
| r4s | 18/21/56 · **FAIL** | 2.34 / **119 of 120 pages fail** | 36 / FAIL |
| r4u | 17/19/41 · 13/31/50 | 2.23 / 1.72 | 42 / 18 |
| r4us | 18/24/60 · — | 2.40 / **book has 1 page** | 40 / — |
| r4n_small | 1/1/10 · 1/17/100 | 2.68 / **10.42** | 4 / 8 |
| r4s_large | 18/23/58 · **FAIL** | 7.91 / **399 of 400 pages fail** | 42 / FAIL |
| r5n | 18/22/56 · 15/32/73 | 2.30 / 1.93 | 43 / 31 |
| r5s | 20/21/48 · 16/17/34 | 2.44 / 1.92 | 46 / 0 |
| r5n_large | 18/20/55 · 28/44/167 | 7.59 / **8.44** | 38 / 34 |
| r5s_large | 20/23/52 · 17/21/46 | 8.41 / 7.19 | 44 / 0 |
| r5n_small | 1/1/26 · 1/14/93 | 2.71 / **9.07** | 5 / 8 |
| r5s_small | 1/1/6 · 1/1/7 | 2.79 / 2.24 | 4 / 0 |
| control | 4/4/5 · 4/6/8 | 0.51 / 0.52 | 11 / 0 |
| owner | 8/10/38 · 8/25/63 | 3.96 / **5.27** | 25 / 16 |

### Jumps and memory

| file | → middle | → end | → page 1 | → ¼ (backward) | peak MB |
|---|---|---|---|---|---|
| r4n | 18 / 26 | 18 / 26 | 17 / 0 | 17 / 25 | 22 / 95 |
| r4s | 1206 / FAIL | 1046 / FAIL | 19 / 0 | 562 / FAIL | 22 / 18 |
| r4u | 18 / 28 | 18 / 26 | 17 / 0 | 17 / 24 | 22 / 90 |
| r4us | 1061 / — | 1030 / — | 18 / — | 556 / — | 22 / 17 |
| r4n_small | 1 / 10 | 1 / 5 | 1 / 0 | 1 / 8 | 22 / 45 |
| r4s_large | 3692 / FAIL | 3670 / FAIL | 19 / 0 | 1818 / FAIL | 22 / 19 |
| r5n | 18 / 31 | 19 / 32 | 18 / 0 | 17 / 32 | 23 / 89 |
| r5s | 1196 / 905 | 1193 / 923 | 18 / 0 | 582 / 471 | 52 / 125 |
| r5n_large | 18 / 30 | 18 / 30 | 18 / 0 | 19 / 30 | 22 / 237 |
| r5s_large | 4481 / 3460 | 4638 / 3645 | 22 / 0 | 2330 / 1654 | 52 / 174 |
| r5n_small | 1 / 8 | 1 / 4 | 1 / 0 | 1 / 7 | 21 / 44 |
| r5s_small | 1302 / 1023 | 1394 / 1054 | 2 / 0 | 685 / 513 | 52 / 122 |
| control | 4 / 8 | 4 / 8 | 4 / 0 | 4 / 4 | 17 / 147 |
| owner | 9 / 21 | 1 / 12 | 13 / 0 | 5 / 12 | 22 / 85 |

Peak memory is the maximum resident size of the `seq` process.

- **Solid jumps** cost time in proportion to the distance from the start in
  both versions. The current version is 20–25% faster, which matches its
  decoder throughput (Q3).
- **Non-solid jumps** cost 4–32 ms in the current version against 1–19 ms
  in v1.3.7: reopen plus a header walk, versus a direct seek. Not noticeable.
- **"→ page 1" is free in the current version** because page 1 is still in
  `NSCache`.

## Q2 — Which path was taken?

| file | header-index fast path | why it declined | trailing-error recovery (#37) fired |
|---|---|---|---|
| r4n, r4s, r4n_small, r4s_large | yes | — | no |
| r4u, r4us | **no** → libarchive scan | RAR4 `LHD_UNICODE` names | no |
| r5n, r5s, r5n_large, r5s_large, r5s_small | yes | — | no |
| r5n_small | yes | — | **yes**, once per read-through (entry #1328: "Block checksum error"; `unrar t` reports the archive as valid) |
| owner | yes | — | **yes**, once per read-through (entry #466: "Unsupported block header size") |
| control | n/a (`COZipArchive`) | — | n/a |

- **The fallback is cheap for RAR4.** libarchive's RAR4 `skip` only consumes
  bytes, so r4u opens in 5 ms.
- **But the fallback cannot read past entry 1 of a solid RAR4.** The scan
  stops with an error, which is why r4us becomes a one-page book. With the
  fast path (r4s), all 120 entries are listed, but only page 1 decodes.
- **The libarchive RAR5 decoder raises spurious errors on valid archives.**
  Two archives out of seven RAR5 files hit it: a generated archive that
  `unrar t` accepts, and the owner book. The size-and-CRC recovery from
  `5335880` returned the complete page both times. Its cost is that the
  cursor is invalidated, so the next page reopens the archive. In a non-solid
  archive that is cheap. In a solid archive it would mean re-decoding from
  the start, though this was not observed in the solid fixtures. These are
  new triggers of the defect recorded in `docs/KNOWN_ISSUES.md` #37, with
  different error strings from the original.
- **Cursor reopens during one read-through in page order** (counted with a
  scratch build that logs each reopen): owner book 194 of 511 pages; r5n 44
  of 120; r5n_small 679 of 2000; r5s 1. This is the mechanism behind cause 2.
  Disabling `CORarArchive`'s prefetch in a scratch build did not help (the
  2000-page read-through went from 8.7 s to 11.4 s), so the cost is the
  reopen and header walk, not the prefetch.

## Q3 — Decoder throughput

Each archive is decoded in stored order with no caching, as raw throughput
of decoded output. "libarchive" is the vendored 3.8.4 (`archive_read_data`
in 256 KB reads). "XADMaster" is the v1.3.7 submodule (`-contentsOfEntry:`).
`unrar` 7.23 `t` is shown for reference only; it is multithreaded for RAR5
and is not a candidate decoder. Medians of 3, warm cache.

| file | output | libarchive | XADMaster | unrar 7.23 `t` |
|---|---|---|---|---|
| r5s | 173 MB | 2.06 s · 84 MB/s | 2.79 s · 62 MB/s | 1.15 s |
| r5s_large | 578 MB | 7.02 s · 82 MB/s | 9.34 s · 62 MB/s | 3.78 s |
| r5s_small | 197 MB | 2.51 s · 79 MB/s | 3.37 s · 58 MB/s | 1.17 s |
| r4s | 173 MB | **stops after entry 1** | 2.36 s · 74 MB/s | 1.87 s |
| r4s_large | 578 MB | **stops after entry 1** | 7.94 s · 73 MB/s | 6.48 s |
| r5n | 173 MB | 1.83 s · 95 MB/s | 2.33 s · 74 MB/s | 0.70 s |
| r4n | 173 MB | 1.48 s · 117 MB/s | 2.28 s · 76 MB/s | 1.75 s |
| r4n_small | 197 MB | 1.65 s · 119 MB/s | 2.98 s · 66 MB/s | 2.17 s |
| r5n_small | 197 MB | 2.14 s · 92 MB/s | 2.61 s · 75 MB/s | 0.95 s |

The vendored libarchive decodes 25–60% faster than XADMaster on every format
it supports. Decoder throughput is not a cause of slowness.

## Q4 — Look-ahead and caching

**What exists.**
- *Both versions*: the app-level look-ahead. `-lookahead` runs on detached
  threads, keeps the next two decoded `NSImage`s, and reuses the current
  spread's images for the two pages before it. The app's `cacheArray` image
  cache is off by default (`ImageCache` is not registered and was 0 here).
- *Current version only*: `CORarArchive` (and `COZipArchive`) prefetch the
  next entry *in stored order* after every read, on the archive's serial
  queue, into a 256 MB `NSCache` of decoded entry bytes. That is why `paced`
  is 0 ms for solid archives and the control. When stored order differs from
  page order, the prefetched entry is usually not the next page; see cause 2.

**Paging back after reading to the end** (`back` scenario, ms, medians of 3;
"−N" is N pages before the last).

| file | version | −3 | −10 | −100 | −200 | −300 |
|---|---|---|---|---|---|---|
| r5s | v1.3.7 | 2430 | 2384 | 415 | — | — |
| r5s | current | 0 | 0 | 0 | — | — |
| r5s_large | v1.3.7 | 8779 | 9015 | 6578 | 4527 | 2156 |
| r5s_large | current | 0 | 0 | 0 | 3277 | 1753 |
| r5s_small | v1.3.7 | 2863 | 2659 | 2632 | 2631 | 2945 |
| r5s_small | current | 0 | 0 | 0 | 0 | 0 |
| r4s_large | v1.3.7 | 7537 | 7251 | 5624 | 3583 | 2089 |
| r4s_large | current | FAIL | FAIL | FAIL | FAIL | FAIL |
| r5n_large | v1.3.7 | 18 | 18 | 18 | 18 | 18 |
| r5n_large | current | 0 | 0 | 0 | 40 | 32 |

- **Within the cache budget, paging back costs nothing.** The budget is
  about 170 pages of 1.5 MB, or the whole 2000-page small book.
- **Beyond it, the current version re-decodes from the start**, like v1.3.7
  does for *any* backward step. In v1.3.7 the app only keeps the current
  spread, so turning back one spread in a large solid book cost seconds.
- `NSCache` evicts under its cost limit and under memory pressure, so the
  boundary is approximate; here pages 200 back were already evicted from a
  578 MB book.

## Q5 — Options

None of these touch the image-quality rule. They all work on the decode
side, before the `NSImage` exists, and add no resampling step.

### Cause 1: solid RAR4 unreadable

**A1 (S, interim).** Detect solid RAR4 at open: the `MHD_SOLID` flag
(0x0008) is in the main-header flags that `CORarHeaderIndex` already reads
(`archiveflags`), but nothing checks it yet. Fail the open with a clear
message instead of a book of broken pages, and list it in the README/known
limitations.
- Low risk.
- Recommended first, whatever is chosen next.

**A2 (L). Solid support in libarchive's RAR4 reader**, contributed upstream
first.
- The vendored copy must not be edited locally (`CLAUDE.md`).
- The RAR4 reader resets its LZSS window and tables per entry, and `skip`
  only consumes bytes. Solid support means keeping decoder state across
  entries, and decoding during `skip` like the RAR5 reader.
- Upstream acceptance and timing are unknown.

**A3 (L). A second decoder for RAR4 only.**
- *XADMaster's RAR 2.9 handle*: LGPL-2.1+, but it needs the
  `CSHandle`/`XADArchiveParser` machinery. That is the "fuller machinery"
  line in DECISIONS (2026-07-14).
- *unrar*: also rejected in DECISIONS (2026-07-25) for licence reasons.
- Either way, an owner decision.

**A4 (S–M). Port RAR4 `LHD_UNICODE` name decoding** into
`CORarHeaderIndex`.
- RAR4 Unicode names then take the fast path. The fallback costs only a few
  ms for RAR4, so the gain is listing, not speed.
- Worth doing only together with A2 or A3, and it needs a RAR4 Unicode
  fixture. `rar` 6.24 `-ma4` can now produce one, as here.

### Cause 2: non-solid archives in non-page order

**B1 (M). Direct positioning for non-solid archives.**
- Record each entry's header offset in `CORarHeaderIndex`, which already
  walks to it.
- For a non-solid archive, open a fresh libarchive stream with a custom read
  callback that presents the signature and main header, then continues at
  that entry's header. The cursor then never walks from the start.
- Low decode-side risk; needs tests on RAR4 and RAR5 and on the
  recovery path.

**B2 (S). Prefetch the next *page*, not the next stored entry.**
- Pass a hint from `COImageLoader`, which knows the sorted order.
- On its own this barely helps: with the prefetch disabled the read-through
  was not faster. It only becomes useful together with B1.

**B3 (S, alternative to B1).** Keep a second cursor, or reopen only when the
target is far behind. This cuts the reopens, not their cost. B1 is cleaner.

### Solid jumps and paging back past the cache (both versions)

**C1 (M). Background sequential decode-ahead for solid archives.**
- After open, an idle-priority pass decodes the whole solid stream once.
  Entries are kept in a size-bounded disk cache in the per-book temp
  directory, so later jumps and back-steps read decoded bytes.
- Costs one full decode of CPU (7 s for 578 MB) and disk equal to the
  decoded size.
- Must yield to foreground reads on the serial queue.

**C2 (not feasible as stated).** Checkpointing decoder positions needs
decoder-state snapshots, which libarchive's API does not expose. C1 gives the
same effect.

**C3 (S).** Make the `NSCache` limit a preference or scale it with RAM. This
widens the free paging-back window at the cost of memory (cause 3).

### libarchive update

**D1 (S–M).** Update when a release contains the RAR5 final-block fix
(issue #3352 / PR #3361).
- This would remove the spurious-error cursor resets (Q2).
- It does not help solid RAR4; upstream master still rejects it.

### Not recommended

Widening the header-index fast path for speed. Open is already 0–6 ms on
every fast-path file and 3–5 ms on the RAR4 fallback.

## Recommended next tasks

1. **Solid RAR4: A1 now** (S), then an owner decision between A2
   (upstream patch) and A3 (second decoder) for real support (L). Add A4
   with whichever is chosen.
2. **Non-solid positioning: B1 + B2** (M). This removes the only measured
   speed regression and the reopen tail latencies.
3. **Solid decode-ahead C1** (M), optional. It removes the multi-second
   jumps that both versions have. Decide together with C3 and the memory
   budget.
4. **D1** when upstream ships the RAR5 fix (S–M).
5. **Optional: commit this benchmark** as `tools/cbr_bench/`, with the
   fixture generator and both harness builds, so later tasks can re-measure.
   It needs the v1.3.7 worktree recipe (Xcode 27:
   `MACOSX_DEPLOYMENT_TARGET=12.0`) and `rar` 6.x for RAR4 fixtures. Not
   committed in this task.
