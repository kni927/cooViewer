# TASK: Investigate CBR performance and review the code (report only)

## Background

Two investigations the owner wants after v1.6.5, run together. Neither
changes product code.

- **D — CBR performance.** The owner feels CBR files open or page more
  slowly than in the old XADMaster-based versions, and wants the current
  version to be at least as fast. History (`docs/DEV_LOG.md`, phases 4–6,
  2026-07-14): the archive layer moved from XADMaster to libarchive/libzip.
  `CORarArchive` indexes entries at open and decodes on demand through a
  forward-only cursor stream, reopening from the start on a backward jump.
  Phase 6 added `CORarHeaderIndex` (header-only RAR4/RAR5 parser): open and
  time to first page on a 1.4 GB solid RAR5 fixture dropped to ~0.1 s,
  better than v1.3.7 (~0.5–1 s), but a full sequential read of a solid
  archive still costs ~13 s, paid while reading pages. Phase 4 measured cold
  backward jumps in solid archives roughly proportional to distance (~6 s to
  jump halfway into the 1.4 GB fixture). v1.3.7 is the XADMaster baseline and
  had a background look-ahead thread. `CORarHeaderIndex` declines (falls back
  to the slow libarchive skip scan) on header encryption, multi-volume, and
  RAR4 `LHD_UNICODE` names. So "slow" may be specific to solid archives during
  reading, backward jumps, the fallback scan, missing look-ahead, decoder
  throughput, or the RAR trailing-error recovery path (`5335880`). Find out
  which, by measurement.
- **E — Code review and dead code.** A review of the current sources for
  defects and for dead code, reported for the owner to decide on. Deletion
  is a separate, later task (`CLAUDE.md` ▸ Dead Code).

## Goal

Two committed reports that let the owner choose the next implementation
tasks: what makes CBR slower than v1.3.7 (if it is), with options and
sizes; and a ranked list of code defects and verified dead-code candidates.

## Scope

### In scope

- Measurement harnesses and scratch instrumentation, kept outside the
  repository or reverted, unless the report proposes committing a tool
  under `tools/`.
- A `git worktree` at tag `v1.3.7` outside the repository, to build the
  baseline (as phase 5 did).
- Reports under `docs/` and entries in `docs/KNOWN_ISSUES.md`.

### Out of scope

- Any change to product code, Xcode project settings, or vendored sources.
- Deleting dead code. Fixing defects found by the review.
- Installing anything into `/Applications`.

### Parts

1. **D — CBR performance report.** Commit `docs/cbr-performance-20261003.md`
   (plus a tool under `tools/` only if proposed). One commit.
2. **E — Code review and dead-code report.** Commit
   `docs/code-review-20261003.md` and any new `docs/KNOWN_ISSUES.md` entries.
   One commit. Then archive this task.

## Implementation notes

### Part 1 — D

Questions to answer:

- **Q1 — Where does time go, by archive kind?** For each corpus file, on the
  current `main` (v1.6.5) and on v1.3.7: open time (loader init until the
  page list is known); time to first page displayed; next-page latency,
  sequential, steady state; latency of a jump to the middle, to the end, and
  back to the start; total time to read every page sequentially; peak memory.
- **Q2 — Which path was taken?** For each file on the current version:
  header-index fast path or libarchive fallback (and why it declined); solid
  or not; RAR4 or RAR5; whether the trailing-error recovery fired.
- **Q3 — Decoder throughput.** For a solid archive, raw decode throughput
  (MB/s of output) of the vendored libarchive against XADMaster on the same
  file, independent of cooViewer's caching.
- **Q4 — Look-ahead and caching.** Does the current version prefetch the next
  page(s) for RAR as v1.3.7's look-ahead thread did? How do the `NSCache`
  limit (256 MB) and eviction interact with backward page turns in solid
  archives?
- **Q5 — Options.** For each confirmed cause, fixes with size and risk, e.g.
  background sequential decode-ahead for solid RAR, checkpointing decoder
  positions to shorten backward jumps, widening the header-index fast path
  (e.g. RAR4 Unicode names), or a libarchive update. Note anything that would
  touch the image-quality rule (none should: this is the decode side, before
  the `NSImage`).

Corpus: owner-provided files where available, otherwise generated fixtures.
Cover at least RAR4 non-solid, RAR4 solid, RAR5 non-solid, RAR5 solid, a
large archive (≥ 500 MB), many small images, a RAR4 archive with Unicode
names, and one CBZ as a control. Record each file's size, entries, format,
solid flag and compression method. In the committed report, describe owner
files generically (`AGENTS.md` ▸ Public Repository). If owner files are
needed, ask the owner in chat where they are; do not search their folders.

Method:

- Prefer a command-line harness calling the archive classes directly for
  Q1/Q3; use the app only to confirm time to first page.
- At least three runs each; report the median. State whether the file cache
  was purged (`purge` needs sudo; if unavailable, say so and report warm
  numbers only).
- Same machine, same power state, both versions in the same session.
- Build the current version with the `CLAUDE.md` build command, following
  its note on `getconf DARWIN_USER_TEMP_DIR` (in its own call; literal path
  to `xcodebuild`, `cp`, `rm`). This is the first use of that note: if it
  does not work as written, record exactly what happened.
- If the app must be run, use `open build/cooViewer.app` (main app only,
  `CLAUDE.md` ▸ On-Device Verification Procedure). Before any screen
  operation, ask the owner in chat to stand by and wait for the reply.

Report contents: answers to Q1–Q5 with a results table; a ranked list of
causes for any case where the current version is slower than v1.3.7; and
recommended next tasks with size estimates, or the statement that it is not
slower and what the owner may be noticing instead.

### Part 2 — E

1. **Code review.** Review `Sources/` (and the helper and QuickLook
   extension sources), not `vendor/`. Look for correctness defects: memory
   management (MRC over-/under-release, KVO/notification observers not
   removed), threading (UI from background threads, races on shared state),
   error paths, and anything that would affect the render path rule
   (`CLAUDE.md` ▸ INVIOLABLE). For each finding: file:line, what goes wrong
   and when, severity (high / medium / low), and a proposed fix with size.
   Rank most severe first. Check each against `docs/KNOWN_ISSUES.md` and say
   when it is already recorded.
2. **Dead code.** List candidates and verify each against every check in
   `CLAUDE.md` ▸ Dead Code (sources, XIB outlets/actions, `Info.plist`,
   build settings, selectors, KVC/KVO key paths, notification names,
   `NSClassFromString` / `performSelector`, plug-in and QuickLook entry
   points). Classify each as **proven unreachable** or **not provable**.
   Include the macOS 10.13–11 compatibility code that the 12.0 minimum may
   make removable, starting from the list in
   `docs/tasks/2026-10-02-02-launch-drain-replaces-front-window.md` ▸
   Follow-up Suggestions: `Sources/FilterPanelController.m:50` (the
   `@available(macOS 10.13, *)` else-branch); `Sources/AppleRemote.m:42-48`
   and `:135-148` (AppKit 10.4/10.5 branches); the
   `MAC_OS_X_VERSION_MAX_ALLOWED >= 1040` /
   `respondsToSelector:@selector(finalize)` guards at
   `Sources/PreferenceController.m:2007`, `Sources/COPDFImageRep.m:46`,
   `Sources/COImageLoader.m:434` and `Sources/CustomImageView.m:1406`.
   Line numbers may have moved.
3. Record **not provable** candidates in `docs/KNOWN_ISSUES.md`, as
   `CLAUDE.md` requires. Proven ones go only in the report.
4. Propose the follow-up tasks: which fixes, and which deletions, grouped into
   tasks of reasonable size, with the order you recommend.

Do not change any source file. Build once at the end to confirm the tree is
unchanged and still builds.

### Git

Commit each part when it is done. Before every push, `git fetch` and merge
`origin/main` if it moved (never rebase or amend); other sessions push
template syncs in parallel. Push with the owner's approval in chat.

## Verification

- `git status` shows no change to `Sources/`, `vendor/`, `Resources/` or the
  Xcode project at the end of each part.
- The final build succeeds; `build/` holds only `cooViewer.app`; the
  intermediate build directory is removed afterwards.
- No v1.3.7 worktree, harness binaries or test copies are left in the
  repository or registered with LaunchServices under production bundle IDs
  (`docs/KNOWN_ISSUES.md` #15).
- The Permission / Sandbox field of the Completion Report is counted from
  `~/Library/Logs/claude-permission-requests.log` since the task started.

## Progress

- Last completed step: Part 2 report, KNOWN_ISSUES #37 note and #39–#41,
  DEV_LOG entry; final build; cleanup.
- Current partial state: none — task complete.
- Exact next step: none.

## Implementation Result

**Status:** Completed with follow-up issues

### Changes

- **Part 1 (`cff2b13`):** `docs/cbr-performance-20261003.md`.
  - **Measurements:** Q1–Q4 compare v1.6.5 with v1.3.7 on 13 generated
    archives plus one owner book: RAR4/RAR5, solid and non-solid, large, many
    small, RAR4 Unicode names, and a CBZ control. Medians of 3 runs, warm
    cache.
  - **Not generally slower.** Two regressions:
    1. Solid RAR4 is unreadable past page 1 (libarchive; also on upstream
       master).
    2. Non-solid archives stored out of page order reopen the forward-only
       cursor: 1.3× slower read-through on the owner book, 3.3–3.9× on
       2000 small pages.
  - **Faster:** paging back in solid books (NSCache 0 ms vs 2.4–9 s) and
    decoder throughput (+25–60%).
  - **Q5:** options and sizes. No tool committed; a benchmark under
    `tools/` is proposed, not added.
- **Part 2:** `docs/code-review-20261003.md`.
  - **Defects:** 5 high, 12 medium/low-medium, 11 low, with verification
    level per finding. H2 and M6 were reproduced in scratch harnesses; H3
    partly.
  - **Render path:** the render-path rule holds.
  - **Dead code:** 20 proven-unreachable candidates; 5 not provable.
  - **Follow-ups:** ten tasks proposed, in order.
- **`docs/KNOWN_ISSUES.md`:**
  - #37 note on new spurious-error triggers.
  - #39 solid RAR4.
  - #40 dead code not provable.
  - #41 open high-severity defects.
- **`docs/DEV_LOG.md`:** one entry.
- **Deviation:** none from scope. Part 2's KNOWN_ISSUES commit also carries
  the Part 1 finding #39, because the TASK puts all KNOWN_ISSUES entries in
  Part 2.

### Verification

- **Build:**
  - The `CLAUDE.md` build command succeeded twice, at the start and at the
    end. `build/` holds only `cooViewer.app`.
  - The intermediate directory was removed. `rm` inside the sandbox failed as
    `CLAUDE.md` predicts, and succeeded with a sandbox bypass.
  - The `getconf DARWIN_USER_TEMP_DIR` note worked as written. One slip: an
    `xcodebuild … | grep` call ran sandboxed and failed; rerun on its own, it
    succeeded.
- **Automated verification:**
  - `git status` shows no change to `Sources/`, `vendor/`, `Resources/` or
    the Xcode project after either part.
  - Harness runs: 336 Q1 runs, 81 Q3 runs, 30 Q4 runs, plus diagnostics
    (reopen trace, no-prefetch build, first-decode order test).
- **Manual verification**, in `build/cooViewer.app` (main app only, owner
  standing by):
  - The solid RAR4 page 2 shows "broken or not image file".
  - Page 1 of the 557 MB solid RAR5 appeared within 1–2 s of `open`.
- **Not performed:**
  - **Cold-cache numbers:** `purge` needs sudo.
  - **H1 reproduction:** the real click into the empty New Window was denied
    by the auto mode classifier ("Unverifiable Deletion Target"); not worked
    around.
  - **Exact in-app timing:** screenshots cannot resolve it.
  - **macOS 12–15** for the finalize-guard question.
- **Cleanup:**
  - The v1.3.7 worktree was removed, and `rar` 6.24 was deleted after use.
    The scratch corpus was deleted.
  - LaunchServices: this session's registrations were unregistered —
    `build/cooViewer.app` from the `open` launch, and the deleted
    intermediate-build paths Xcode had registered.
  - `pluginkit` resolves the QuickLook extensions only to `/Applications`.
  - Two older `/private/tmp/cooViewer-NewWindow-Manual.*` scratch apps from
    an earlier session remain registered; they were not touched.

### Remaining Issues

- Solid RAR4 unreadable (KNOWN_ISSUES #39).
- Non-solid out-of-order cursor reopens (report, cause 2).
- The five high-severity defects (KNOWN_ISSUES #41).

### Follow-up Suggestions

- **CBR:** A1 (refuse solid RAR4 clearly, S), then an owner decision on real
  solid-RAR4 support (A2 upstream patch or A3 second decoder, L); B1+B2
  (non-solid direct positioning, M); optional C1 (solid decode-ahead, M); D1
  (libarchive update when the RAR5 fix ships).
- **Code review:** the ten tasks in `docs/code-review-20261003.md`, starting
  with the crash fixes (H1, H4, H5, M2, L7) and the untrusted-input hardening
  (H2, H3, L9, L10, M7, L1).
- **`CLAUDE.md` ▸ On-Device Verification Procedure ▸ Main app only** says
  that `open build/cooViewer.app` registers nothing with LaunchServices. In
  practice the launch registered `build/cooViewer.app`, and every
  `xcodebuild` registers the intermediate products. The procedure could add
  an `lsregister -u` cleanup step. Editing `CLAUDE.md` needs the owner's
  approval.
- Optionally commit the benchmark as `tools/cbr_bench/` so the CBR fixes can
  be re-measured.
