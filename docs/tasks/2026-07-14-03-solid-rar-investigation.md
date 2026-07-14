# TASK: Solid RAR open-time investigation — phase 5 (vs v1.3.7 baseline)

## Background

Phase 4 (archived: `docs/tasks/2026-07-14-02-rar-partial-lazy.md`) added
`CORarArchive` with an index pass (header-only scan via
`archive_read_data_skip`) and a cursor pass (on-demand entry decode).
For the 1.4 GB / 665-entry solid RAR5 fixture, phase 4 measured:

- non-solid: open 2.060s → 0.189s, footprint 2676MB → 2.6MB (expected win)
- solid: open 13.835s → 13.000s, footprint 2714.5MB → 34.5MB (memory won,
  open time essentially unchanged — expected per phase 4's own scope
  notes, since solid decoding of later entries requires the shared
  dictionary from preceding entries)

However, v1.3.7 (XADMaster-based, pre-libarchive-migration) opens the
same 1.4 GB solid archive to a visible first page in **under 1 second**.
This is suspicious: decoding entry 1 of a solid archive has no
preceding-entry dependency (nothing precedes it), so XADMaster's
sub-second time is plausible for "decode entry 1 only" — but it's
unclear whether phase 4's "solid open: 13.0s" figure represents the same
thing (time to first page) or something heavier (e.g. the index pass
scanning all 665 entries turns out to be expensive for solid archives
specifically, or the cursor pass is decoding more than entry 1).

This task is a diagnostic investigation first, fix second. Do not assume
the fix before measuring where the 13 seconds actually goes.

## Goal

- Understand precisely what "open" measured in phase 4 for solid
  archives, and where the 13 seconds is actually spent (index pass vs
  cursor pass vs something else).
- Compare directly against the v1.3.7 baseline under identical
  conditions (same file, same machine, cold cache) to confirm what
  "sub-second open" meant there (first page visible? full window ready?).
- If CORarArchive can reach first-page-visible in similar time to
  v1.3.7 for solid archives (which theory suggests should be possible,
  since entry 1 has no solid-chain dependency), implement that fix.
- If there's a fundamental reason it cannot match v1.3.7 (e.g. a
  necessary full-archive header scan that XADMaster avoided), document
  why clearly enough that Master can decide whether it's an acceptable
  tradeoff.

## Scope

### In scope

- **Baseline comparison setup**: `git worktree add` a checkout of the
  `v1.3.7` tag (confirm the tag exists first) alongside the current
  working tree. Build both. Do not modify the v1.3.7 worktree.
- **Instrumented measurement on current (post-phase-4) code**:
  - Add temporary timing logs (or use Instruments/signposts if
    convenient) around: index pass start/end, first
    `archive_read_data()` call for entry 1, and time-to-first-page
    displayed in the UI.
  - Run against the same 1.4 GB solid RAR5 fixture used in phase 4.
  - Identify which phase dominates the 13 seconds.
- **Baseline measurement on v1.3.7**:
  - Same fixture, same machine, cold cache (e.g. drop caches or use a
    fresh copy of the file if disk cache is a concern).
  - Measure wall-clock time to first page visible.
  - If useful, skim XADMaster's RAR entry-access code (read-only, in
    the v1.3.7 worktree) to understand its actual strategy for solid
    archives — does it also decode all preceding entries for entry 1
    (trivially fast, since there are none), or does it do something
    else entirely (e.g. defer the index scan too)?
- **Root-cause conclusion**: write up, in the Implementation Result,
  what's actually happening in the current 13s (e.g. "index pass alone
  takes 12.8s because `archive_read_data_skip` on solid RAR5 still
  performs dictionary-building work internally" vs "index pass is fast
  but entry 1 decode is slow for an unrelated reason").
- **Fix, if the root cause is addressable**:
  - Likely candidate based on current understanding: defer the full
    index pass for solid archives (or make it lazy/incremental) so
    that entry 1 can be decoded and displayed before all 665 headers
    are scanned. Only implement this if measurement confirms the index
    pass is the bottleneck — do not implement speculatively.
  - Keep the existing non-solid fast path and the phase 4 fallback
    behavior unchanged.
  - If the fix is more involved than expected, stop and report back
    rather than expanding scope — this can be split into a phase 6 if
    needed.

### Out of scope

- Any change to zip/cbz, 7z, tar handling.
- Any change to the non-solid RAR path (already fast).
- QuickLook extension work (still phase 6+, after this).
- Adding unrar/UnrarKit or any new third-party library.

## Verification

- Build: both worktrees build independently without cross-contamination
  (confirm you're building/running the intended binary each time).
- Measurement table in Implementation Result: v1.3.7 vs pre-fix vs
  post-fix (if a fix is implemented), each showing time-to-first-page
  for the 1.4 GB solid fixture.
- If a fix is implemented: re-run the phase 4 solid-archive regression
  checks (correctness of page order, backward navigation) to confirm no
  regression was introduced.
- Non-solid path: confirm untouched (spot check open time still ~0.19s
  range).

## Implementation Result

**Status:** Completed (diagnosis only — no fix implemented; see below)

### Root cause

**The 13 seconds is spent entirely in the index pass, and it is
genuine, unavoidable-via-libarchive decompression work — not waste
in cooViewer's own code.**

`archive_read_support_format_rar5.c` (vendored libarchive,
`rar5_read_data_skip()`, ~line 4258):

```c
if(rar->main.solid && (rar->cstate.data_encrypted == 0)) {
    /* In solid archives, instead of skipping the data, we need to
     * extract it, and dispose the result. ... */
    while(rar->file.bytes_remaining > 0) {
        rar->skip_mode++;
        ret = rar5_read_data(a, NULL, NULL, NULL);   /* <- real decode */
        rar->skip_mode--;
        ...
    }
} else {
    /* non-solid: cheap byte-offset consume */
    consume(a, rar->file.bytes_remaining);
}
```

For solid RAR5, libarchive's own "skip" is implemented by calling the
**actual decompressor** (`rar5_read_data`) and throwing the output
away; `skip_mode` only disables checksum verification, not the LZ
decode itself. So `CORarArchive`'s index pass — one
`archive_read_data_skip()` per entry — pays the **full decompression
cost of the entire solid stream once**, and non-cached reads later
pay it again. This was confirmed empirically: instrumenting the
existing `COArchiveProgress` callback during the index pass on the
1.4 GB solid fixture shows `archive_filter_bytes` advancing
**linearly** over the full 13.057s (≈0.66s per 5% of the file) — the
signature of sustained decompression throughput, not a quick scan
that stalls once.

By contrast, v1.3.7's XADMaster (`XADRAR5Parser.m`, `-skipBlock:`,
~line 701) enumerates entries — solid or not — via:

```objc
-(void)skipBlock:(RAR5Block)block
{
    [[self handle] seekToFileOffset:[self endOfBlockHeader:block]+block.datasize];
}
```

A **raw file-offset seek** based on the block header's declared
`datasize` (packed size) field. RAR headers store each entry's
compressed byte length even inside a solid stream (the compressed
bytes are contiguous and their length is known), so enumerating names
never touches the decompressor — only actually *reading* an entry's
data requires decoding through the shared dictionary from the start
of its solid block. This is why entry 1 (no preceding entries) shows
almost instantly regardless of how many entries follow it.

**libarchive's public API does not expose this cheap, seek-based
enumeration path for solid RAR entries.** It is a design choice baked
into the vendored library's RAR5 reader, not a bug or a missed flag —
there is no alternate libarchive call that gets the XADMaster
behavior.

### Measurements

Same 1.4 GB / 665-entry solid RAR5 fixture (`~/Downloads/1-solid.cbr`),
same machine. Disk cache was **not** forcibly dropped (`purge`
requires sudo, unavailable) — the file had been read repeatedly in
phase 4's session, so this favors *faster* results across the board;
since the comparison is between builds on the *same* warm-cache
conditions, the relative gap is still meaningful.

| | v1.3.7 (XADMaster) | current (phase 4, CORarArchive) |
|---|---|---|
| time to first page visible (real app, screenshot-confirmed) | **~0.5–1 s** | **~13 s** (black screen + indeterminate spinner, no % shown) |
| CPU trace after launch | burst ~0.7–3 s (background lookahead-thread prefetch of *later* pages, does not block display) | burst for the full ~13 s (blocking `-initWithPath:` — no page can display until it returns) |
| index-pass byte progress (current build only) | n/a | linear: 0.2%→97% tracked steadily across the full 13.057s |
| non-solid open (regression spot check) | n/a | **0.211 s** — unaffected, consistent with phase 4's 0.189 s |

v1.3.7's own CPU burst (0.7–3 s) is *not* comparable to the current
build's 13 s block: it happens **after** page 1 is already on
screen, running on `Controller.m`'s existing background lookahead
thread to prefetch upcoming pages — a mechanism present in both
versions and orthogonal to this investigation.

### Fix assessment — not implemented

The task's speculative "likely candidate" fix (defer/incrementalize
the index pass so entry 1 can show before all 665 headers are
scanned) does not actually help once the root cause above is
accounted for: **there is no cheap way to even reach "entry 1's
header" without the same libarchive skip machinery paying the same
per-entry decompression cost for anything read before it in the
stream** — and entry 1 specifically has nothing before it, so it's
already fast today (confirmed in phase 4: 0.025 s once the archive
object exists). The blocker isn't "we scan too far" — it's that
`COImageLoader`'s existing design (shared by every archive format)
requires the **full, name-sorted entry list** before it can decide
what "page 1" even is, and building that list is what pays the 13 s
for solid RAR.

A fix that actually matches XADMaster's speed would mean writing a
**from-scratch RAR5 (and RAR4, for older archives) header-only block
parser** — walking the archive via raw file-offset seeks based on
declared block sizes, exactly mirroring `XADRAR5Parser.m`'s
`-skipBlock:` — used only for enumeration, while still handing actual
page decoding to libarchive. This is a new, parallel format parser
(handling RAR4/RAR5 header variants, merge blocks, multi-volume
archives, encryption-flag edge cases XADMaster already had to solve),
not a small change to `CORarArchive`. That is squarely "more involved
than expected" per this task's own scope boundary, so per the task's
instruction, **no fix was implemented** — reported back for the
project owner to scope as a dedicated phase 6, if wanted.

### Verification

- Build: both worktrees built and ran independently
  (`../cooViewer-v1.3.7-baseline`, detached at tag `v1.3.7` with
  XADMaster/UniversalDetector submodules initialized; current tree
  unmodified by the investigation itself).
- Non-solid path: confirmed untouched — 0.211 s open on the 1.4 GB
  non-solid fixture (phase 4 measured 0.189 s; same order, no code
  changed on this path).
- No fix was implemented, so no regression re-run was needed; the
  full phase 4 engine test suite was re-run anyway as a sanity check
  (`tests/engine/run_tests.sh`) — ALL PASS, no code changes.
- `../cooViewer-v1.3.7-baseline` worktree removed after use
  (`git worktree remove`) to leave the workspace clean; it was
  read-only scratch scaffolding for this investigation, not part of
  the tracked repo.

### Remaining Issues

- Solid RAR archives take roughly as long to open in the current code
  as v1.3.7 took, in total CPU work, but with **no visible progress
  feedback** during that time (indeterminate spinner only, despite
  `COArchiveProgress` already reporting exact byte-level percentage —
  see Follow-up Suggestions) and **zero page visible** until the
  whole thing finishes, versus v1.3.7 showing page 1 immediately and
  doing equivalent background work later, out of the user's way. This
  is a real regression in perceived responsiveness for solid RAR
  archives specifically (non-solid and zip/cbz are unaffected and
  much improved by phases 2 and 4).

### Follow-up Suggestions

- **Phase 6 (large scope, needs its own task definition):** a
  from-scratch RAR5/RAR4 header-only block parser for the index pass
  (raw seeks based on declared block sizes, mirroring
  `XADRAR5Parser.m`), used purely for enumeration; keep libarchive for
  actual page decompression. This is the only way found to close the
  gap with v1.3.7 for solid archives. Estimate: substantial — a new,
  independently-correct format parser, not a small patch.
- **Cheap interim mitigation (small scope, no architecture change):**
  wire the existing `COArchiveProgress` percentage into a determinate
  progress bar / "Loading… NN%" label instead of (or alongside) the
  current indeterminate spinner for the RAR open path. Doesn't reduce
  the 13 s, but replaces "frozen-looking black window" with visible,
  honest progress — plausibly worth doing regardless of whether phase
  6 happens.
- Do **not** attempt the "assume stream order matches sorted-name
  order and show page 1 immediately, sort in the background" idea
  that was considered and rejected during this investigation: even
  though it was verified true for the one realistic homogeneous-page
  fixture tested, it's a fragile assumption to bake into
  `COImageLoader`'s synchronous list-then-sort design, would only
  improve *first-page* latency (page count, thumbnails, and general
  browsability would still block on the full 13 s), and risks a
  visibly wrong page 1 flashing before correcting itself if the
  assumption doesn't hold for some archive.
