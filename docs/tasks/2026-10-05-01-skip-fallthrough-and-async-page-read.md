# TASK: Fix the mouse skip fall-through (#45) and the UI freeze while a solid book rewinds (#46)

## Background

The cleanup-and-performance task (C1–C4, B1–B3) recorded two issues in
`docs/KNOWN_ISSUES.md` that the owner wants fixed before v1.6.7:

- **#45:** the mouse action "skip" (`mouseAction:` case 5) has no `break`
  and falls through into the next-page action.
- **#46:** in a solid archive, a page that has left the `NSCache` is decoded
  again from the start of the stream (B3's disk cache mitigates the cost),
  and while that happens the UI is frozen, because a page that is not ready
  is read synchronously on the main thread (`-lockedImageDisplay` path; the
  2026-10-04 sample showed the main thread in `archive_read_data_skip`).

## Goal

The skip action does exactly one thing, and no page read blocks the main
thread: a page that is not ready is shown when it arrives, and the window
stays responsive (menus, other windows, Cmd+Q, slideshow stop) meanwhile.

## Scope

### In scope

The two parts below and the documentation they change.

### Out of scope

- Any change to the render path (CLAUDE.md, INVIOLABLE): the decoded
  `NSImage` still reaches the view through `-setImages:` and one
  `drawInRect:` per page. Only *when* the image is handed over changes.
- Release work, libarchive, `vendor/`.
- Other `mouseAction:` cases (KNOWN_ISSUES #5: case 59 stays as is).

### Parts

**P1. #45: mouse skip.**
- Add the missing `break` (or the equivalent) so case 5 does only the skip.
- Check the neighbouring cases in the same switch for the same fall-through
  and list what you found; fix only clear fall-through defects, each named in
  the commit message.

**P2. #46: no synchronous page read on the main thread.**
- When the page to show is not decoded yet, request it on the read queue and
  return; show it from the completion on the main thread, if it is still the
  page wanted (the user may have moved on: drop stale results).
- While waiting, keep the current page on screen and give light feedback
  (for example the existing progress indicator after a short delay). Do not
  draw a placeholder that changes what is drawn for a ready page.
- Paging, jumps and the slideshow keep working while a read is pending: a new
  request supersedes the old one; the slideshow waits for the page instead of
  piling up requests.
- Spreads: both pages of a spread are shown together, never one without the
  other.
- Cmd+Q, closing the window and opening another book while a read is pending
  work and leave no stray completion behind.
- If the change turns out to need restructuring beyond the display/request
  flow in `BookWindowController` (for example `COImageLoader`'s threading
  model), stop after a written proposal and report instead of widening scope.

## Implementation notes

- Count resampling steps before and after (CLAUDE.md). The expected count is
  unchanged: this part changes when `-setImages:` is called, not what it
  draws.
- MRC project (KNOWN_ISSUES #1). Completion blocks must retain what they use
  and must not message a closed window (see the window-lifetime fixes in
  `docs/DECISIONS.md`).
- Reproduce #46 deterministically before fixing it, with a generated solid
  RAR5 and a small cache limit or an explicit cache purge (a debug-only
  switch is fine if it is removed or compiled out), not by waiting for memory
  pressure.
- Use the `build-app` and `device-check` skills; `tools/device_check.sh diag 3`
  shows whether the main thread is blocked.

## Verification

- Build per `CLAUDE.md`; `tests/engine/` passes; add a test where the request
  and stale-drop logic has an engine-side seam.
- On device (main app only, `device-check` skill):
  - P1: with skip assigned to a mouse button, one press skips once and does
    not also turn the page.
  - P2: with the forced cache purge on a solid RAR5, page back past the cache:
    the window stays responsive (`diag 3` shows the main thread idle, menus
    open, another window pages), the page appears when decoded, and a jump
    during the wait lands on the jump target. Slideshow over the same book:
    no freeze, no skipped or doubled pages. Spread mode: both pages appear
    together. Cmd+Q and window close during a pending read.
  - A normal (non-solid) book: paging looks and feels unchanged.
- Do not push; report and wait for the owner's approval in this session.

## Progress

- Last completed step: P1 committed (d2e1bee); P2 implemented, reviewed,
  verified on device and committed with this archive.
- Current partial state: none.
- Exact next step: owner approves the push.

## Implementation Result

**Status:** Completed with follow-up issues

### Changes

- **P1 (#45), d2e1bee.** `case 5` (skip/back skip) of the mouse-action switch
  in `-getMouseAction:mod:mode:left:` gets its missing `break`. Every other
  case of that switch and of the key-action switch was checked by reading and
  with clang `-Wimplicit-fallthrough` (one warning before, none after); no
  other fall-through. Deviation: committed before its on-device check,
  because P2 restructures the same code; the check followed (pass).
- **P2 (#46).** "Decode first, then replay": `-requestDisplay:argument:after:`
  plans the pages each legacy body reads (`CODisplayPlanFor`), runs the body
  at once when they are on hand, otherwise decodes them on a per-book
  `COBookReadLane` (new `Sources/COBookReadLane.{h,m}`, added to the app
  target) and replays the body from a main-thread completion. Legacy bodies
  extracted from the key/mouse switches (prev, half prev/next, last, first,
  go to, skip, back skip, switch single, redisplay, open last); all lookahead
  waits removed; the lane owns `decodeLock`; re-sort waits for the lane by
  `tryLock` or a lane barrier; slideshow timer one-shot; spinner after 0.2 s;
  close/quit/book switch drop results by token; old pages kept (stale) on a
  book switch until the new page commits. Deviations from the approved
  design, all smaller in effect: the book switch keeps the old pages instead
  of blanking at once; an open on a given page reads the next page only when
  the probe needs it; skip start and bookmark jumps are clamped into the
  book (the legacy code could read page −1 or past the end); a slideshow
  whose next book fails to open stops. An independent review found six
  defects (wrong page recorded on a close during a slow switch, an old page
  cached under the new book's name, a synchronous re-read of an unreadable
  page, deferred-request loss around a re-sort, slideshow rescheduling during
  a next-book load, state left after a cancelled quit); all fixed before the
  commit.
- Compiled-out repro switch `COVIEWER_REPRO_46` (COArchive.m, COImageLoader.m)
  kept and documented.
- Docs: KNOWN_ISSUES #45 and #46 fixed; DECISIONS new P2 entry and an update
  to "Lookahead threads…"; DEV_LOG.
- Render path unchanged: bodies still call `-setImage:`/`-composeImage` →
  `-setImages:` → one `drawInRect:` per page; only the moment moved (plus
  `setImage:nil` to blank stale pages, no resampling).

### Verification

- Build: normal Deployment build per CLAUDE.md (build-app skill), `build/`
  holds only `cooViewer.app` and contains no repro marker; the repro variant
  was built separately for the device checks.
- Automated verification: `tests/engine/run_tests.sh` test_coarchive 504
  checks, test_imageloader 169 checks (57 planner table rows, lane delivery,
  supersede, cancel, serialization under a held decodeLock, at most one
  thread inside `-itemAtIndex:`, reverse reads of a solid RAR, nil pages
  delivered as NSNull). Independent read-only review of P2.
- Manual verification (device-check skill, preferences backed up and
  restored with a verified match, `lsregister -u`):
  - #46 before the fix (repro build): each back step on a 300-page solid
    RAR5 froze the main thread 6–7 s (`prevPage` → main-thread lookahead →
    `dataForEntry:` → `archive_read_data_skip`), menus dead.
  - P2 (repro build): during 5–10 s back steps the main thread waited in its
    run loop and the lane thread decoded; menus answered; repeated presses
    collapsed into one step; jumps during a wait landed on 151-152 and 1-2;
    slideshow advanced and stopped (key and menu); about 40 screenshots of
    spreads never showed an old and a new page together; close, quit (about
    1 s), book switch and re-sort (Shuffle/Name) during a wait worked; a close
    during a slow switch recorded the page being opened; non-solid books felt
    unchanged; no "unplanned page" fault, no crash report.
  - P1: plain click temporarily bound to Skip/BackSkip value 10 (MouseArray
    written with `defaults write`, approved by the owner in chat): 1-2 → 11-12
    → 1-2 → 11-12 → 21-22 → 11-12, one move per click, no extra turn.
- Not performed: the spinner was not confirmed visually; a thumbnail click
  during a wait (the panel hides while the app is inactive); a full-sequence
  record of the 0.1 s slideshow; stopping the slideshow from the menu while a
  page was pending (forward solid reads were too fast). Full-screen
  computer-use actions were again interrupted ("user interrupt", not the
  owner), so background actions were used. The `os_log_fault` for an
  unplanned page uses the default log, so the subsystem predicate cannot see
  it; a process-wide search was also empty.

### Remaining Issues

- Thumbnail panel and page-bar bubble still decode on the main thread
  (residue of #46); `ThumbnailController` reads `nowPage` right after
  `goToLast`/`goToFirst`, which is stale while a request is pending.
- A decode in flight cannot be cancelled: a jump during a rewind lands after
  the current page finishes.
- During the stale window of a book switch, `showThumbnail` and the view's
  read mode can briefly mix the old pages with the new book's settings
  (cosmetic, up to 0.2 s).

### Follow-up Suggestions

- Make the thumbnail panel and page-bar bubble read through the lane.
- A cancellable foreground read (`-itemAtIndex:` down to `-dataForEntry:`).
- Give the unplanned-page fault the app's log subsystem.
