# cbr_bench — RAR reading benchmark

Measures how fast cooViewer's archive layer reads RAR (`.cbr`) books, the
method of `docs/cbr-performance-20261003.md`, made repeatable. It times the
object `COImageLoader` uses — `-contents`, a sort with `-finderCompareS:`,
then `-[entry data]` per page — not the app, so there is no window, no
ImageIO decode per page and no app-level look-ahead.

Everything it builds and generates goes to `$OUT` (default
`$TMPDIR/cbr_bench`), outside the repository. Nothing here is part of the
app build.

## Builds compared

| build | what |
|---|---|
| `current` | the working tree's `Sources/COArchive.m`, `COZipArchive.m`, `CORarArchive.m`, `CORarHeaderIndex.m`, `NSString_Compare.m` against `vendor/lib` |
| `before` | the same files from `BEFORE_REF` (default `HEAD`), exported with `git archive` |
| `v137` | optional: v1.3.7's `XADWrapper.m` / `XADItem.m` against `XADMaster.framework` |

The `current` build hands the page order to the archive
(`-setPrefetchPageOrder:`), as `COImageLoader` does. `CORarArchive.m` is
compiled with `archive_read_open_filename` and `archive_read_open2` renamed
to counters in `bench.m`, which gives "stream opens": every decode stream
the reader opened while reading, from the start of the file or positioned.

## Corpus

`make_corpus.py` generates it with `gen_pages` (synthetic greyscale JPEG
pages: noise inside white margins, so RAR compresses them with `-m3` at
98–99 % rather than storing them) and `rar`:

| file | format | solid | pages | stored order |
|---|---|---|---|---|
| `r4n` | RAR4, STORE | no | 120 × ~1.4 MB | shuffled |
| `r4n_small` | RAR4, STORE | no | 2000 × ~90 KB | shuffled |
| `r5n` | RAR5, `-m3` | no | 120 × ~1.4 MB | shuffled |
| `r5n_small` | RAR5, `-m3` | no | 2000 × ~90 KB | shuffled |
| `r5s` | RAR5, `-m3` | yes | 120 × ~1.4 MB | name order |

"Shuffled" is a fixed-seed permutation, standing in for the directory order
`rar` uses for non-solid archives (not name order on APFS). RAR4 is written
by `tests/fixtures/make_rar4_fixture.py`'s block writers, STORE only:
`rar` 7.x cannot write RAR4, and a compressed RAR4 corpus needs `rar` 6.x
(`-ma4`), which is not assumed here.

## Scenarios

One fresh process per scenario and run:

- `open` — open, list and sort, then page 1's data and a full ImageIO decode.
- `seq` — every page in page order, back to back (read-through).
- `paced` — the first 30 pages, one every 300 ms (reading pace).
- `jump` — page 1, the middle page, the last page, page 1, the page ¼ in.

Peak memory is the process's `ru_maxrss`. Each run is warm-cache: the
archive is read once (`cat > /dev/null`) right before it (`purge` needs
sudo). The order of the builds rotates between runs. Tables show the median
of the runs.

## Running

Requirements: `vendor/build-libs.sh` has run, `rar` is on `PATH`.

```bash
tools/cbr_bench/run_bench.sh
```

Environment: `OUT`, `BEFORE_REF`, `RUNS` (default 3), `FILES`,
`SCENARIOS`, `V137_DIR`. The raw results are `$OUT/results.jsonl`;
`summarize.py` prints the tables again from it.

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
