# TASK: Cleanup and performance (C then B)

## Background

v1.6.6 is released. Since then main has gained the auto-hide page number fix
(#42), the Resolution section in Preferences, direct positioning and page-order
prefetch for non-solid RAR (B1+B2 of `docs/cbr-performance-20261003.md`), and
the remaining code-review fixes (#41). Before v1.6.7 the owner wants two groups
of work in this order:

- **C (small, safe items first):** open issues that are small and well
  understood, plus a cleanup of `docs/KNOWN_ISSUES.md`.
- **B (felt performance, after C):** the loading half of #33 and the
  remaining reading-speed items from the 2026-10-03 survey and the
  2026-10-04-01 task's follow-ups.

## Goal

Every part below is implemented, built, verified and committed in order, one
commit per part, and `docs/KNOWN_ISSUES.md`, `docs/DECISIONS.md` and
`docs/DEV_LOG.md` reflect the result. No release work.

## Scope

### In scope

The parts below, and the documentation each one changes.

### Out of scope

- Version number, tag, release notes, release, Homebrew tap. v1.6.7 is a
  separate task after the owner has tried the build.
- Any change to the render path (see Implementation notes).
- Solid RAR4 support (it stays refused at open, #39), libarchive updates (#37),
  editing anything under `vendor/`.
- The All Bookmarks browser's missing page-jump gesture (a feature gap).

### Parts

**C1. #30: an empty or unreadable book fails clearly.**
- Distinguish "this book has no readable pages" (empty folder, archive with no
  image entries, archive that cannot be read at all) from "one page failed to
  decode". Only the second keeps the `empty.png` placeholder page.
- The first ends the open with an alert naming the file and the reason, opens
  no window (or leaves an existing window's book unchanged), and adds nothing
  to Recent Books.
- Make the guard in `-[BookWindowController openPage:last:]` live again, or
  replace it; do not leave dead code behind.
- A cancelled archive read keeps its current behaviour (no alert).

**C2. #20: quitting while a modal is up.**
- Case 1, All Bookmarks browser: Cmd+Q, the application menu and an
  AppleEvent quit work while it is open (end the modal session, then let the
  quit proceed). Unsaved state must not be lost compared with closing the
  browser first.
- Case 2, nested-archive password prompt: the deferred quit stays as it is
  (it already fires after the prompt); only re-verify and document.
- Case 3, archive-load progress sheet: fixed in B1, not here. Note it in the
  entry.
- Update the DECISIONS entry that recorded these as "decided not to fix".

**C3. Front window when the launch drain runs while the app is inactive.**
- From `docs/tasks/2026-10-02-02-launch-drain-replaces-front-window.md`,
  Remaining Issues: when `frontWindowController` is nil, choose the
  topmost book window from `-[NSApp orderedWindows]` instead of
  `[windowControllers lastObject]`. Keep the Finder double-click path
  unchanged.

**C4. `docs/KNOWN_ISSUES.md` cleanup.**
- Duplicate numbers: there are two #20, two #21 and two #23 (one #23 is the
  "v1.6.0 Release — Known Limitations" block whose #34/#35 repeat #20 and
  #21). Merge true duplicates into one entry; give the remaining second
  entries new numbers after the current highest, and leave a one-line
  "formerly #NN" note in the heading. Update references in living documents
  (`docs/DECISIONS.md`, `docs/DEV_LOG.md`, `docs/multiwindow-plan.md`, and
  any other non-archived file). Do not edit archived task files under
  `docs/tasks/`.
- Bring stale entries up to date with the current repository, at least #10
  "No Automated Tests" (there is `tests/engine/` and `tools/cbr_bench/`) and
  build paths such as `build/Deployment/cooViewer.app` that no longer match
  `CLAUDE.md`. Entries fixed by C1, C2, C3 and the B parts are marked FIXED
  in the existing style.
- Documentation only; do not change entries' substance beyond what the
  repository now shows.

**B1. #33: loading a book no longer blocks the other windows.**
- Replace the `NSApp` modal session in `-runArchiveLoadNamed:usingBlock:` with
  a window-modal progress sheet and the continuation-passing open the password
  prompt already uses (`docs/DECISIONS.md`, "The archive password prompt is
  window-modal…"). While one window loads, the others can be raised, paged
  and driven from the menus.
- Cancel (Esc / the sheet's button) still cancels the read. Cmd+Q during a
  load cancels it and quits (this closes #20 case 3).
- Opening another book into the loading window stays refused, as now.
- The nested-archive password prompt keeps its synchronous path (decision 3
  of that DECISIONS entry) unless the change falls out naturally; if it
  stays, say so.

**B2. Reading speed and memory.**
- Continue on the open libarchive cursor when the requested page is the next
  stored entry, instead of opening a fresh positioned stream per page
  (non-solid RAR; measure 7z/ZIP paths too if they share the code).
- Make prefetch cancellable: a jump cancels queued and running prefetches that
  are no longer wanted, so the jump does not wait behind them on the serial
  read queue.
- Check whether `-lockedImageDisplay` now waits for up to two prefetched
  pages before showing the requested one on slow books (a possible regression
  of the 2026-10-04-01 prefetch change). If it does, show the requested page
  as soon as it is decoded.
- C3 of the survey: scale the `NSCache` limit with physical RAM (no new
  preference unless needed); record the chosen formula in DECISIONS.

**B3. Decode-ahead for solid archives (C1 of the survey).**
- After open, for solid archives that are readable (solid RAR5, solid 7z;
  solid RAR4 is refused), an idle-priority pass decodes the stream once and
  stores entries in a size-bounded disk cache in the per-book temp directory,
  so later jumps and back-steps read decoded bytes.
- It must yield to foreground reads, stop when the book closes, clean up its
  files, and respect a size bound (state the bound and why).
- If measurement shows the cost outweighs the benefit, stop, record the
  numbers, and report instead of shipping it.

## Implementation notes

- **Image quality (CLAUDE.md, INVIOLABLE).** None of these parts may touch the
  path from the decoded `NSImage` to `drawInRect:`. B2 and B3 work on the
  decode side (compressed bytes to file bytes, before the `NSImage` exists).
  Count resampling steps before and after; the count must not change.
- MRC project (KNOWN_ISSUES #1); nib changes per #2; defaults per #8 and #19.
- Measure with `tools/cbr_bench/` and generated corpora only. Do not use the
  owner's books. Record before/after numbers (open, read-through, jump, back
  step, peak memory) in the task archive, against the current main.
- Hand heavy work (builds, bench runs, investigations, computer-use checks) to
  subagents, as `docs/sessions.md` describes.
- If a part turns out larger than described, finish and commit the parts
  before it, record the state, and report rather than widening scope.

## Verification

- Build with the command in `CLAUDE.md`; `build/` holds only the app.
- `tests/engine/` passes; add tests where a part has a testable engine-side
  seam (C1's "no readable pages" detection, B2's cursor continuation and
  cancellation).
- Main app on device per the On-Device Verification Procedure (main app only):
  - C1: empty folder, archive with no images, garbage file: alert, no window,
    no Recent Books entry; a book with one corrupt page still opens with the
    placeholder for that page.
  - C2: quit with the All Bookmarks browser open (Cmd+Q and AppleEvent).
  - C3: the inactive-launch case, if it can be reproduced safely; otherwise
    say how it was verified.
  - B1: two windows; load a large generated 7z in one and page the other
    during the load; Cmd+Q during a load.
  - B2/B3: bench numbers; a quick visual check that pages display normally.
- Before each key or click in computer use, confirm the frontmost app is the
  test build (launched by path). Back up and restore defaults as earlier tasks
  did. Run `lsregister -u` afterwards.
- Do not push. When all parts are committed, report and wait; the owner
  approves the push in this session.

## Progress

- Last completed step: all parts committed (C1 6f29395, C2 4573739, C3
  8502eff, C4 ffd5428, B1 f36048f, B2 7fd0149, B3 b14f5da); task archived.
- Current partial state: none.
- Exact next step: owner approves the push.

## Implementation Result

**Status:** Completed with follow-up issues

### Changes

- **C1 (#30), 6f29395.** A book with no readable pages (empty folder, archive
  with no images, unreadable archive, encrypted RAR/7z) fails the open with
  an alert naming the file and the reason; no window is left, an existing
  window keeps its book, Recent Books is untouched, a cancel stays silent.
  `-[COImageLoader pagesStatus]`; the `empty.png` stand-in is gone (now
  unused, recorded in KNOWN_ISSUES #40). Found and fixed on device: a reused
  window's stale `windowClosed` made a cancelled password prompt leave the
  cancelled book as the window's book (wrong Recent Books entry, lost
  position, a stray spinner window).
- **C2 (#20 case 1), 4573739.** Quit, Quit and Close All Windows and the
  AppleEvent quit end the All Bookmarks browser (saving as OK) and quit;
  `-[COApplication worksWhenModal]` only for that modal. Case 2 re-verified,
  kept.
- **C3, 8502eff.** With no tracked front window, `-frontController` takes the
  topmost visible book window in `-[NSApp orderedWindows]`; routing log names
  the rule.
- **C4, ffd5428.** KNOWN_ISSUES duplicates resolved (#43 formerly #20, #44
  formerly #21 — the later-added bookmark entry, because archived tasks cite
  the composed-spread #21; the v1.6.0 limitations block merged into #20/#44);
  stale entries brought up to date. Deviation: the task said to renumber the
  "second" #21; the one added later was renumbered instead.
- **B1 (#33, #20 case 3), f36048f.** The archive read of the book being opened
  runs off the main thread behind a window-modal progress sheet; other
  windows stay usable; Cancel stops it; quit during a load cancels and quits,
  persisting nothing; a new window stays hidden until it has a book (no C1
  flash). Nested and folder-inner archive reads, and the nested password
  prompt, stay synchronous. `-cancelPasswordPrompts` became
  `-cancelPendingOpensForTermination`.
- **B2, 7fd0149.** Prefetch cancellation (a cache-missing read cancels other
  pages' prefetches; running RAR prefetches stop only when cheap), cursor
  continuation shown by a counter and test (it already existed), the
  lookahead decodes outside the controller lock and `-lockedImageDisplay`
  waits only for the pages it shows (the wait was real), NSCache limit
  clamp(RAM/32, 256 MB, 1 GB). Deviation: the pre-waits before
  `-imageDisplay` in seven next-page/slideshow paths were dropped (needed for
  the goal). A B2 race that could discard a solid cursor was found and fixed
  before the commit. `tools/cbr_bench/` gained back/idlejump scenarios, more
  corpus files, peak footprint and counters.
- **B3, b14f5da.** Solid RAR5 decode-ahead into a per-book disk cache with
  write-through, bounded by min(2 GB, a tenth of free space), stopped and
  deleted on close and at exit. Solid 7z excluded by owner decision (7z is
  fully extracted into memory at open). A pass/reader deadlock found in
  review was fixed with a regression test before the commit.
- Docs: KNOWN_ISSUES #20, #30, #33, #40, #43–#46; DECISIONS entries for C1,
  B1, B2, B3 and updates to the password/quit, launch-drain, lookahead and
  encrypted-RAR entries; DEV_LOG.
- Render path untouched in every part: one `drawInRect:` per page, no new
  resampling step.

### Verification

#### B2 bench

`BEFORE_REF=f36048f LARGE=1 SCENARIOS="open seq paced jump back"
tools/cbr_bench/run_bench.sh`, 3 runs, medians; Apple M1, 8 GB, macOS
26.6.2; machine busy (load 4–5, swapping), so absolute values are
indicative. Before = f36048f, current = working tree with B2 engine changes.
Peak = peak physical footprint (ru_maxrss under-reports).

| file | open ms b/c | seq s b/c | jump →mid ms b/c | jump total ms b/c | back −300 ms b/c | seq peak MB b/c |
|---|---|---|---|---|---|---|
| r4n | 4.5/6.3 | 0.05/0.05 | 1/1 | 3/3 | — | 189/189 |
| r5n | 4.7/3.5 | 1.66/1.65 | 27/13 | 84/52 | — | 183/184 |
| r5n_small | — | 1.61/1.50 | 2/1 | 6/3 | 0/0 | 171/171 |
| r5n_ordered | 3.0/3.5 | 1.63/1.66 | 26/14 | 79/56 | — | 187/189 |
| r5s | 2.9/3.3 | 1.81/1.73 | 784/875 (noise) | 2003/2071 | — | 219/218 |
| r5n_large | 4.6/5.2 | 5.76/5.60 | 28/13 | 83/55 | 29/14 | 589/596 |
| r5s_large | 4.4/10.9 | 5.54/5.64 | 2759/2724 | 6787/6842 | 1373/1314 | 613/624 |
| s7s (7z) | 7835/8662 | 0/0 | 0/0 | 0/0 | — | 388/390 |
| s7s_large (7z) | 26550/26206 | 0/0 | 0/0 | 0/0 | 0/0 | 1180/1179 |

Paced reading unchanged (median 0 ms, max 13–17 ms RAR5). Counters
(current): r5n_ordered seq 1 stream open, cursorContinueCount 119; non-solid
jumps stream opens 6 → 4 with prefetchCancelled 3; no cancellations in
seq/paced. Cache limit on this 8 GB Mac is 256 MB either way, so the RAM
scaling was not measured. "1st decode" differences in open are ImageIO's
first-call cost depending on build order, not the archive layer.

B2 on device (2026-10-04, device-check skill, tools/device_check.sh first
Mac run): single page and spreads (wide/small pairing), wheel, page bar,
number-key and thumbnail jumps, first/last, book switch, shuffle sort and
window close during a lookahead, two windows in parallel — pass, no crash
report. Slideshow on a 300-page solid RAR5 (2 MB pages) from page 241 under
heavy memory pressure: 10–13 s per step and a frozen UI — traced (headless
simulation of all four old/new engine × old/new lookahead pairings) to
NSCache losing pages a solid cursor had passed, pre-existing (KNOWN_ISSUES
#46); the same investigation found and fixed a B2 race that could discard a
solid cursor. Engine tests 461 + 96 pass after the fix.

#### B3 bench

`BEFORE_REF=7fd0149`, FILES r5s r5s_large s7s s7s_large r5n, scenarios open
seq jump back idlejump (30 s idle), 3 runs, same machine (load 2–5).

| file | item | before | current |
|---|---|---|---|
| r5s (170 MB solid) | open ms | 3.7 | 8.8 |
| r5s | seq s | 1.61 | 1.80 |
| r5s | jump mid / last / ¼ ms | 782 / 749 / 405 | 846 / 808 / 1 |
| r5s | idlejump mid / last / ¼ ms | 809 / 774 / 406 | 2 / 1 / 1 |
| r5s_large (557 MB solid) | open ms | 3.9 | 8.4 |
| r5s_large | seq s | 5.34 | 5.77 |
| r5s_large | jump mid / last / ¼ ms | 2595 / 2567 / 1295 | 2735 / 2730 / 1 |
| r5s_large | back −200 / −300 ms | 2642 / 1296 | 1 / 1 |
| r5s_large | idlejump mid / last / ¼ ms | 2587 / 2545 / 1293 | 2 / 1 / 1 |
| r5n, s7s, s7s_large | all | — | unchanged (s7s open 7.5 s, s7s_large 25 s) |

Peak footprint (MB): jump 80 → 44, idlejump 82 → 38, seq 612 → 609, back
662 → 612. Pass cost for r5s_large: 5.5–6.2 s wall, 5.4–5.5 s CPU, 564 MB
disk; r5s 1.7 s, 170 MB.

- Build: Deployment build per CLAUDE.md (build-app skill) after every part;
  `build/` holds only `cooViewer.app`.
- Automated verification: `tests/engine/run_tests.sh` 504 + 101 checks pass
  at the end (C1 added COImageLoader cases; B1 deferred-read cases; B2
  cursor/cancellation/limit cases; B3 decode-ahead, write-through, bound,
  deadlock regression, cleanup); `run_encryption_test.sh` and
  `run_password_test.sh` pass. Independent read-only reviews of B2 and B3
  (findings fixed before the commits).
- Manual verification (main app, device-check procedure; preferences backed
  up and restored with a verified match, `lsregister -u` after every check):
  - C1: empty folder, text-only folder/zip, five garbage files, encrypted 7z
    alerts; existing window keeps book and page; ⌘N window stays empty;
    corrupt page shows the broken image; cancelled password leaves no
    window and nothing in Recent Books (after the windowClosed fix).
  - C2: menu Quit, Quit and Close All Windows, `osascript` quit (front and
    background) with an unsaved browser edit — saved as with OK; case 2
    deferral re-verified.
  - C3: inactive launch (`open -g`) logged `fallback-ordered`; in that run
    the topmost window was also the last created, so old and new rules
    coincide.
  - B1: two windows, 322 MB solid 7z loading in one while the other was
    raised, paged and driven from menus; Cancel; quits during a load;
    routing during a load; restored slow book holding the launch drain;
    no window flash for an unreadable book.
  - B2: single/spread paging, wheel, jumps, book switch/sort/close during
    a lookahead, two windows. Slideshow stall under memory pressure traced
    to pre-existing #46.
  - B3: jumps after and right after open, temp files removed on close/exit,
    slideshow without stalls (#46), solid RAR5 with a nested zip, close
    during the pass, two windows, non-solid unaffected.
- Not performed:
  - Password entry, Esc and Cmd+Q as key presses, File ▸ Open panel routes,
    page-bar clicks (B3), closing a window while its progress sheet is up
    (B1): the computer-use tooling's full-screen actions were interrupted
    every time ("user interrupt", not by the owner), so background actions
    were used, which cannot type into secure fields, reach the Open panel
    process or move the real cursor.
  - A slideshow over solid pages the B3 pass has not reached yet.
  - The RAM-scaled cache limit on a Mac with more than 8 GB.

### Remaining Issues

- KNOWN_ISSUES #46 part 2: a page that is not ready is read synchronously on
  the main thread, so a read that needs a rewind (books past the B3 bound,
  a jump right after open) freezes the UI for its duration.
- KNOWN_ISSUES #45: mouse skip action falls through into next page
  (pre-existing).
- B1: nested and folder-inner archive reads still use the app-modal
  progress session (Cmd+Q is swallowed there).
- B3: a crash leaves the decode-ahead files in the temporary directory;
  closing a fully cached large book can block the main thread ~0.1 s.
- KNOWN_ISSUES #40: `Resources/empty.png` is now unused.

### Follow-up Suggestions

- Move the main-thread page read in `-lockedImageDisplay` off the main
  thread (#46 part 2).
- Fix #45 (one `break`).
- Remove stale `cooViewer.*` temp directories at launch; delete the cache
  directory asynchronously on close.
- Remove `Resources/empty.png` in a dead-code task.
- A device check on a Mac with 16 GB or more for the cache limit.
- Investigate the computer-use "user interrupt" on full-screen actions.
