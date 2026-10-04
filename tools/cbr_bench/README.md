# cbr_bench — RAR reading benchmark

Measures how fast cooViewer's archive layer reads RAR (`.cbr`) books, the
method of `docs/cbr-performance-20261003.md`, made repeatable, plus a solid
7z for the full-extraction path. It times the object `COImageLoader` uses —
`-contents`, a sort with `-finderCompareS:`, then `-[entry data]` per page —
not the app, so there is no window, no ImageIO decode per page and no
app-level look-ahead.

Everything it builds and generates goes to `$OUT` (default
`$TMPDIR/cbr_bench`), outside the repository. Nothing here is part of the
app build.

## Builds compared

| build | what |
|---|---|
| `current` | the working tree's `Sources/COArchive.m`, `COZipArchive.m`, `CORarArchive.m`, `CORarHeaderIndex.m`, `NSString_Compare.m` (and any `EXTRA_SOURCES`) against `vendor/lib`; uncommitted and untracked changes included. With `AFTER_REF`, the same files from that ref instead |
| `before` | the same files from `BEFORE_REF` (default `HEAD`), exported with `git archive` |
| `v137` | optional: v1.3.7's `XADWrapper.m` / `XADItem.m` against `XADMaster.framework` |

`$OUT/builds.txt` records what each build was made from (ref and commit, or
the working tree and how many `Sources/` files differ from `HEAD`).

Both libarchive builds hand the page order to the archive
(`-setPrefetchPageOrder:`, where it exists), as `COImageLoader` does. Every
archive-layer source is compiled with `archive_read_open_filename` and
`archive_read_open2` renamed to counters in `bench.m`, which gives "stream
opens": every decode stream opened after the open, from the start of the
file or positioned.

If the change under test adds a source file the archive layer needs, name it
in `EXTRA_SOURCES` (e.g. `EXTRA_SOURCES=CODecodeAheadCache.m`); a build
whose tree lacks it simply leaves it out.

### Decode-ahead

When the archive responds to `-setDecodeAheadDirectory:` (a solid RAR5 in a
build with B3), `bench.m` gives it a fresh directory under `$TMPDIR` inside
the timed open, as `COImageLoader` does right after the open, and removes it
at the end; `BENCH_DECODE_AHEAD=0` leaves it off. The pass opens a stream
of its own, so stream opens count one more where it ran.

### Counters

After the timed reads, `bench.m` reports under `counters` every integer or
`BOOL` method with no arguments that the archive responds to, from its list
(`prefetchCount`, `rewindCount`, `positionedOpenCount`, and names later work
may add: `cursorContinueCount`, `prefetchSkippedCount`,
`prefetchCancelledCount`, `prefetchAbortedCount`, and the decode-ahead ones from B3:
`decodeAheadEntryCount` / `decodeAheadByteCount` (stored by the pass),
`decodeAheadWriteThroughCount` (stored by the foreground cursor),
`decodeAheadDiskHitCount`, `decodeAheadAwaitCount` (reads that waited for
the pass or a write instead of decoding), `decodeAheadDiskByteCount` (disk
used),
`decodeAheadByteBound`, `decodeAheadPassMilliseconds` /
`decodeAheadPassCPUMilliseconds` / `decodeAheadPassYieldMilliseconds` (set
when the pass has ended) and `decodeAheadPassEnded`) or named in
`BENCH_COUNTERS` (comma or space separated). Methods are found with `respondsToSelector:`, so the harness
builds and runs against a ref that lacks them; the summary shows — there.
Counters are read immediately after the last timed read, so a prefetch
still running on the archive's read queue may not be counted yet.

## Corpus

`make_corpus.py` generates it with `gen_pages` (synthetic greyscale JPEG
pages: noise inside white margins, so RAR compresses them with `-m3` at
98–99 % rather than storing them), `rar` and `7zz`:

| file | format | solid | pages | stored order | size |
|---|---|---|---|---|---|
| `r4n` | RAR4, STORE | no | 120 × ~1.4 MB | shuffled | 170 MB |
| `r4n_small` | RAR4, STORE | no | 2000 × ~70 KB | shuffled | 148 MB |
| `r5n` | RAR5, `-m3` | no | 120 × ~1.4 MB | shuffled | 168 MB |
| `r5n_small` | RAR5, `-m3` | no | 2000 × ~70 KB | shuffled | 146 MB |
| `r5s` | RAR5, `-m3` | yes | 120 × ~1.4 MB | name order | 167 MB |
| `r5n_ordered` | RAR5, `-m3` | no | 120 × ~1.4 MB | name order | 168 MB |
| `s7s` (`.cb7`) | 7z, LZMA2 `-mx=5` | yes, one block | 120 × ~1.4 MB | name order | 166 MB |
| `r5n_large` | RAR5, `-m3` | no | 400 × ~1.4 MB | shuffled | 559 MB |
| `r5s_large` | RAR5, `-m3` | yes | 400 × ~1.4 MB | name order | 557 MB |
| `s7s_large` (`.cb7`) | 7z, LZMA2 `-mx=5` | yes, one block | 400 × ~1.4 MB | name order | 552 MB |

- The first five are unchanged from the first version of this tool, so their
  numbers stay comparable with `docs/cbr-performance-20261003.md`'s
  follow-up.
- `r5n_ordered` is stored in page order: a read-through can continue on one
  cursor, so stream opens should stay at about 1.
- The `_large` books decode to about 560 MB, more than the archive layer's
  256 MB decoded-bytes `NSCache`, so paging back past the cache and the
  cache's size limit show. They are made only when named (in `FILES`, or
  with `LARGE=1`).
- `s7s` / `s7s_large` go through `COArchive`'s libarchive full-extraction
  path (every entry decoded into memory at open), so their open time is the
  whole decode.
- "Shuffled" is a fixed-seed permutation, standing in for the directory order
  `rar` uses for non-solid archives (not name order on APFS). RAR4 is written
  by `tests/fixtures/make_rar4_fixture.py`'s block writers, STORE only:
  `rar` 7.x cannot write RAR4, and a compressed RAR4 corpus needs `rar` 6.x
  (`-ma4`), which is not assumed here.
- Existing files are kept; delete one to regenerate it.

Generation time and disk, measured once (Apple Silicon, `rar` 7.23, `7zz`
26.03): the default seven files take about 40 s and 1.4 GB including their
page directories (`corpus/pages/large`, `small`, ~310 MB); the three large
files about 5 minutes and 2.2 GB more (`corpus/pages/large400`, 540 MB,
included). The whole `$OUT` with everything is about 3.5 GB.

## Scenarios

One fresh process per scenario and run:

- `open` — open, list and sort, then page 1's data and a full ImageIO decode.
- `seq` — every page in page order, back to back (read-through).
- `paced` — the first 30 pages, one every 300 ms (reading pace).
- `jump` — page 1, the middle page, the last page, page 1, the page ¼ in.
- `back` — every page in page order (untimed), then −3, −10, −100, −200
  and −300 pages from the last, in turn (the survey's Q4 back-step; steps
  beyond the book's start are left out).
- `idlejump` (opt-in) — open, wait `BENCH_IDLE_MS` (default 10000) without
  reading, then the `jump` steps. For background work started at open
  (decode-ahead of a solid archive): `jump` shows whether it yields to
  foreground reads, `idlejump` what it gains once it has had time.

Peak memory is reported for every scenario as "ru_maxrss / peak physical
footprint" (`task_info` `TASK_VM_INFO` `ledger_phys_footprint_peak`, what
Activity Monitor calls Memory). The footprint is the one to compare:
`ru_maxrss` misses compressed and swapped-out pages and can read far lower
(the `s7s` open, which holds all 166 MB of pages in memory, showed about
100 MB of `ru_maxrss` against a 395 MB footprint). The first version of
this tool reported `ru_maxrss` only, as did the survey. Each
run is warm-cache: the archive is read once (`cat > /dev/null`) right before
it (`purge` needs sudo). The order of the builds rotates between runs.
Tables show the median of the runs.

## Running

Requirements: `vendor/build-libs.sh` has run; `rar` (RAR5 files) and `7zz`
(7z files) are on `PATH`.

```bash
tools/cbr_bench/run_bench.sh
```

Environment: `OUT`, `BEFORE_REF`, `AFTER_REF`, `EXTRA_SOURCES`, `RUNS`
(default 3), `FILES`, `LARGE`, `SCENARIOS` (default `open seq paced jump
back`), `BENCH_IDLE_MS`, `BENCH_COUNTERS`, `V137_DIR`. The raw results are
`$OUT/results.jsonl` (overwritten by every run: copy it away first to keep
it); `summarize.py` prints the tables again from it.

Duration, estimated from single-process times rather than a timed full
run: the defaults (seven files, five scenarios, two builds, three runs) take
about 15 minutes, most of it `paced` (9 s per process) and `s7s` (its open
decodes the whole archive, about 8 s, in every scenario). `LARGE=1` with the
default scenarios adds roughly half an hour, mostly `s7s_large` (its open
alone took 30 s); restrict
`SCENARIOS` or `FILES` for the large books. Do not run it while a build or
another heavy process is running: the timings are wall-clock.

### Before and after a change

Build `before` from the commit before the change and `current` from the
working tree (or from the change's commit with `AFTER_REF`):

```bash
# reading speed: cursor continuation, prefetch cancellation, cache size
BEFORE_REF=<commit before the change> LARGE=1 SCENARIOS="open seq paced jump back" \
    tools/cbr_bench/run_bench.sh

# solid decode-ahead: open cost, yielding (jump), gain (idlejump, back)
BEFORE_REF=<commit before the change> FILES="r5s s7s r5s_large s7s_large" \
    SCENARIOS="open jump back idlejump" BENCH_IDLE_MS=30000 \
    tools/cbr_bench/run_bench.sh
```

`BENCH_IDLE_MS` should cover one full decode of the largest solid file
(`r5s_large` about 7 s with libarchive's RAR5 decoder; `s7s_large` about
30 s at the 7z open's measured rate).

### The v1.3.7 build (optional)

Prepare a directory and pass it as `V137_DIR`:

```bash
V137=/path/outside/the/repo/v137
mkdir -p "$V137"
git clone https://github.com/tak758/XADMaster.git "$V137/XADMaster"
git -C "$V137/XADMaster" checkout 56f3becfc8001cbcf900fda690ef77653b92d842
git clone https://github.com/tak758/universal-detector.git "$V137/UniversalDetector"
git -C "$V137/UniversalDetector" checkout d5b9d951d4d1e93deecbdfbdd027647094c620a8
git archive -o "$V137/wrapper.tar" v1.3.7 XADWrapper.h XADWrapper.m XADItem.h XADItem.m NSString_Compare.h NSString_Compare.m
tar -xf "$V137/wrapper.tar" -C "$V137"
xcodebuild -project "$V137/XADMaster/XADMaster.xcodeproj" -target XADMaster \
  -configuration Release MACOSX_DEPLOYMENT_TARGET=12.0 ARCHS=arm64 \
  SYMROOT="$V137/build" OBJROOT="$V137/obj" CODE_SIGNING_ALLOWED=NO build
```

The commits are the ones the `v1.3.7` tag's submodules point to
(`git ls-tree v1.3.7 XADMaster UniversalDetector`). Xcode 27 needs
`MACOSX_DEPLOYMENT_TARGET=12.0`; the v1.3.7 sources are compiled unchanged
(with `-Wno-error=int-conversion` for one `nil` passed as an encoding).
