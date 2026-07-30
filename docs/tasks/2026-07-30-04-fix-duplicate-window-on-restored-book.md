# KNOWN_ISSUES #32: duplicate window when reopening a restored book from Finder

## Goal

Fix #32: quitting with a book's window open (Cmd+Q), then opening that same
book from Finder, produces two windows for it — the restored one plus a new
one.

## Decision (already made — implement this, don't re-litigate)

**The restored window's saved page wins.** The Finder request should bring
the restored window forward, leaving it on its saved page. It must not
reset that window to page 1, and must not open a second window.

This means no new page-injection logic is needed: the dedup-and-refront
behavior MW-7 already built for `-openInNewWindow:` is exactly the desired
outcome. The work is a timing fix, not a behavior change.

## Root cause (from the MW-9 report)

`application:openFile:` runs **before** AppKit decodes window-restoration
state. At the moment the dedup check runs, no window holds a book yet, so
the check finds nothing to dedup against and opens a new window. The
control case confirms this: closing all windows before quitting (nothing to
restore) produces only one window.

## Scope

1. **Queue Finder-open requests received during launch.** Hold the
   requested path(s) instead of acting immediately, then drain the queue
   once restoration has finished, routing each through the **existing**
   registry / `+resolvedBookPath:` dedup path — do not reimplement
   resolution or dedup.
2. **Determine when restoration is actually complete — measure, don't
   assume.** `restoreWindowWithIdentifier:state:completionHandler:`
   completion handlers are asynchronous, so it is not safe to assume every
   restored window holds its book by `applicationDidFinishLaunching:`.
   Instrument the real ordering on this macOS version (as MW-8 did when it
   found AppKit doesn't send the `NSWindowController` restoration hooks at
   all) and pick the drain trigger from what's measured. If a count-based
   wait is used, give it a timeout so a failed or never-arriving
   restoration can't strand the queue and silently drop the user's
   double-clicked file.
3. **Reconcile with `OpenLastFolder`.** It currently fires when the system
   restored zero windows. A pending explicit Finder request should take
   precedence — otherwise the fallback opens the last folder *and* the
   requested book, which is a duplicate-window outcome again (a different
   one, but the same class of bug this task exists to remove). Decide and
   document the precedence in `docs/DECISIONS.md`.
4. **Post-launch path must not regress.** Once launch is over,
   Finder-open should behave exactly as it does today (immediate, no
   queueing). Confirm which entry point(s) are actually implemented
   (`application:openFile:` and/or `application:openFiles:`) and cover both
   if both exist — MW-9 item 10 tested simultaneous multi-file open, so
   whichever handles that case must keep working.

## Out of scope

- #30 and #33's password-prompt half — the agreed separate task.
- #33's book-loading half / background archive loading — deliberately
  pending (not a bug; local archives open in under 0.2s).
- #24, #28, #29 — unrelated pre-existing items.
- Any change to what page a *newly opened* book starts on. This task only
  governs the collision case with an already-restored window.

## Verification plan

- Build: warning-count/content diff against the current baseline — 312
  lines = 310 source + 2 "not stripping binary" (per MW-8/MW-9).
  Re-measure the baseline in the same session; per the follow-ups task,
  `xcodebuild` warning output isn't perfectly reproducible run to run.
- Image quality: untouched render path, so a same-session spread-capture
  comparison should be byte-identical. Capture both sides within one
  session (the hash embeds window-corner anti-aliasing and isn't stable
  across sessions), and position windows non-overlapping before capturing
  (region capture grabs whichever window is frontmost).
- `leaks` / `NSZombieEnabled` across quit-with-N-windows → relaunch-with-
  pending-Finder-open cycles, including the timeout path from item 2 if one
  is implemented.
- Defaults domain (`jp.coo.cooViewer`) zero-diff before/after, and confirm
  test fixtures don't linger in Recent Books. Discard saved application
  state created during testing.
- Manual, test build only — launch from `build/` directly, per MW-8/MW-9
  practice; do not install to `/Applications` or `~/Applications`:
  - **The bug itself:** quit with book A open → open A from Finder → exactly
    one window, showing **A's saved page**, not page 1.
  - Quit with A open → open a *different* book B from Finder → two windows
    (restored A at its saved page, new B), both correct.
  - Quit with A and B open → open A from Finder → two windows, A fronted,
    neither reset.
  - Multiple files opened at once from Finder at launch, where some match
    restored windows and some don't — correct mix, no duplicates.
  - System restoration disabled (`NSQuitAlwaysKeepsWindows = NO`) + a
    Finder open at launch → item 3's decided precedence holds, no
    double-open.
  - No restoration and no Finder request → `OpenLastFolder` still opens
    exactly one book (MW-7-follow-ups behavior preserved).
  - Finder open while the app is already running, with windows open →
    unchanged from today (dedup refronts an open copy; otherwise new
    window).
  - Drag a file onto the dock icon while the app is not running.
  - Restored book whose file moved or was deleted, *plus* a Finder request
    for a different book — graceful degradation (MW-8 behavior: one console
    line, no crash, no broken window) and the requested book still opens.
  - Quit with zero windows open → relaunch with a Finder open → no crash,
    correct single window.

## Notes for the implementing session

- Per established practice: read the actual launch/restoration code before
  finalizing the commit plan. The scope order above is a hypothesis; items
  1 and 2 are inseparable in practice, 3 and 4 may or may not be.
- The "window exists but its book isn't loaded yet" state this task has to
  reason about is the same state that any future background-archive-loading
  work would need. Keeping the state handling clean and not special-cased
  to restoration is worth a little care — but do **not** scope-creep into
  async loading itself, which is deliberately pending.
- If any part of the fix turns out to need a design decision that isn't
  settled here, stop and report rather than picking one silently — the
  same split that kept #25 out of MW-6 and #32 out of MW-9.

---

## Implementation Result

**Status:** Completed

### Changes

- `Sources/AppController.h/.m`
  - `-application:openFiles:` **holds** the requested paths while the launch is
    unsettled (`pendingLaunchOpenPaths`) and replies success immediately;
    once settled it behaves exactly as before — immediate, no queue.
  - New `-settleLaunch`: the single point at which the launch's restoration is
    known to be over. It polls `-isRestoredBookUnfinished` across the registry
    (bounded by a 3 s deadline), then drains the queue through the **existing**
    `-openBookInNewWindow:` — so resolution and de-duplication are the ones
    MW-7 already built, not a second copy — and finally runs the
    `OpenLastFolder` fallback if nothing else opened a book. Kicked from both
    `-applicationDidFinishRestoringWindows:` and
    `-applicationDidFinishLaunching:`, either of which may come first, and
    idempotent.
  - `-applicationDidFinishLaunching:` no longer runs the `OpenLastFolder` gate
    itself; it records the notification, marks the launch as finished and kicks
    `-settleLaunch`. `-settleLaunch` waits for that flag, so the fallback still
    runs no earlier than it used to.
  - On the deadline path it logs one console line and drains anyway.
- `Sources/BookWindowController.h/.m`
  - New `restoredBookOpening` flag and `-isRestoredBookUnfinished`, covering all
    three stages of a restoration: AppKit deciding, decoded but not yet opened,
    and the open itself. The third stage is the one `-isAwaitingRestoredBook`
    deliberately does not cover (it goes NO at the *start* of
    `-openRestoredBook`, so the window is reusable if the open fails), and it
    matters because `-openPage:last:` spins the run loop — a drain scheduled
    with `-performSelector:afterDelay:` could otherwise land inside a restored
    book's open.
- `docs/DECISIONS.md` — the measured launch order, why the queue was chosen
  over a pending-path lookup, the restored window winning, the bounded poll,
  and the `OpenLastFolder` precedence (scope item 3). Also marks the part of
  the MW-8 entry this re-measurement supersedes.
- `docs/KNOWN_ISSUES.md` — #32 marked FIXED, with its original report kept and its
  cause paragraph corrected.
- `docs/DEV_LOG.md` — short entry.

**No render-path change.** Nothing was added between the decoded `NSImage` and
`[page drawInRect:fromRect:]`. What changed is *when* a launch-time Finder
open runs (one run-loop pass later, after the launch has settled), not how any
page is drawn.

### Measured launch order (scope item 2 — measured, not assumed)

Every hook instrumented in a throwaway worktree build, three windows to
restore plus a Finder open, macOS 26:

```
applicationWillFinishLaunching:
+restoreWindowWithIdentifier:   x3
-restoreStateWithCoder:         x3     <- each window's book is known here
NSApplicationDidFinishRestoringWindows
-application:openFiles:
applicationDidFinishLaunching:
-openRestoredBook               x3     <- ~0.3 s later; the books open here
```

Two results changed the design:

- **The task's root-cause note (inherited from MW-8) is wrong on one point.**
  Restorable state is decoded *before* `-applicationDidFinishLaunching:`, not
  after it. What has not happened when the open request arrives is the restored
  **book open**, which `-restoreStateWithCoder:` defers by a run-loop pass. The
  symptom and the fix are unaffected — de-duplication asks which window is
  *showing* a book — but the drain trigger had to be chosen from this, and the
  stale claim is now corrected in both `DECISIONS.md` and `KNOWN_ISSUES.md`.
- **`NSApplicationDidFinishRestoringWindows` fires even when nothing is
  restored** (measured separately), so it is a reliable "restoration is over"
  signal — but there is no signal for "the restored books are open". Hence the
  bounded poll rather than a notification.

### Verification

**Build:** clean Deployment build, `** BUILD SUCCEEDED **`, 312 `warning:`
lines = 310 source + 2 "not stripping binary". Compared against a clean build
of the previous commit (`5320276`) made **in the same session**: 46 distinct
warning messages, counts identical, the only differing lines being the two
"not stripping binary" ones whose text embeds the build directory. `build/`
contains `cooViewer.app` and nothing else, and it launches.

**Manual, on device** (`build/cooViewer.app` run in place; `/Applications` and
`~/Applications` untouched, so no LaunchServices registration — `KNOWN_ISSUES`
#15). Every page position below was confirmed by capture rather than by
counting keystrokes, after MW-9's lesson that an unverified `keystroke` can
silently miss its window.

| Check | Result |
|---|---|
| **The bug itself:** quit with A open → open A from Finder | **1 window**, and its content differs from the same book at page 1 (mad 91.9) — the saved page was kept |
| Quit with A open → open a *different* book B | 2 windows; A still on its saved page, B at page 1 |
| Quit with A and B open → open A | 2 windows, A fronted (`AXMain` = A), neither reset |
| Several files at once at launch, some restored, some not (`test.zip` restored + `test.7z`, `folder6` new, `test.cbr` restored) | exactly 4 windows, one per book, no duplicates |
| `NSQuitAlwaysKeepsWindows = NO` + a Finder open at launch | 1 window (the request), no `OpenLastFolder` book beside it |
| No restoration, no request | `OpenLastFolder` opens exactly one book |
| `OpenLastFolder` + a request for a *different* book (most recent = `test.cbr`, requested `folder6`) | 1 window, `folder6` only — the request wins |
| Finder open while already running: same book / different book / three at once | refronts (1 window) / new window / one window per file — unchanged from before |
| Restored book deleted between quit and relaunch, plus a request for another book | requested book opens, 1 window, no broken window, app alive |
| Quit with zero windows → relaunch with a Finder open | 1 window, no crash |
| **Timeout path**, `-openRestoredBook` stalled 2 s in a probe build: real 3 s deadline | the poll waits, de-duplication still wins — **1 window** |
| Same stall, deadline forced to 0 s | **file still opens**, degrading to the old duplicate (2 windows) rather than to a lost file |

**Image quality:** same-session capture comparison against a build of the
previous commit, same fixture, same frame (200,100 1200×900), windows
non-overlapping. The two-page spread is **byte-identical** (mad 0, sharpness
delta 0.0000). The single-page cover capture differed in one pairing — and the
control shows why: two runs of the **unchanged baseline build** differ from
each other by exactly the same amount (mad 0.459207, maxdelta 53, 140 953
samples, diff map pure outlines), which is `KNOWN_ISSUES` #31, the first-open
layout variability. Two runs of the fixed build are byte-identical to each
other, and the fixed build is byte-identical to the baseline's second run. The
fixed build lands consistently on the *sharper* of the two variants
(sharpness 6.0970 vs 5.2751) — the opposite of what an added resampling step
would do. Deferring the launch-time open by one run-loop pass evidently lets
the view learn its bounds first, which is exactly the mechanism #31 describes;
recorded as an observation, not a fix.

**`NSZombieEnabled` + `MallocScribble`:** quit with 3 windows → relaunch with a
2-file pending Finder open → restore → close windows one by one. No crash and
no message-to-deallocated-instance abort. (`leaks` is meaningless under
`NSZombieEnabled`, since every freed object is retained on purpose, so it was
re-run separately.)

**`leaks`** on the same cycle without zombies: 371 leaks / 27 728 bytes, all
`CFString` roots from the Alias Manager helpers (`KNOWN_ISSUES` #29) plus the
known `NSBezierPath` root in `-[AccessoryView setFrame:]`. No leaked `NSURL`,
`NSData`, window controller or queue array.

**Defaults hygiene:** the `jp.coo.cooViewer` domain was exported before testing
and restored afterwards; the final export is byte-identical to the pre-test one
and no test fixture appears in Recent Books. Saved application state created
during testing was discarded (the app was left quit with no windows open, so
nothing is pending). Test fixtures created for this pass were deleted and the
throwaway worktree removed.

**Not performed:**
- **A literal drag onto the Dock icon while the app is not running.** It would
  require adding this test build to the owner's Dock, which the on-device
  procedure avoids. It is the same `kAEOpenDocuments` event as every case
  above — instrumentation confirmed `-application:openFiles:` is the only
  entry point, `-application:openFile:` being absent — and the multi-file
  launch-open case exercises the same code with the same shape.
- Apple Remote on hardware (impossible — `docs/DECISIONS.md`), and the
  QuickLook/Thumbnail extensions (untouched by this task).

### Remaining Issues

None for #32.

Two behaviours worth knowing rather than defects:

- A launch-time Finder open is now serviced one run-loop pass later than
  before (measured ~0.3 s when there are books to restore, essentially
  immediately when there are none). Nothing waits on it but the window
  appearing.
- If the deadline is ever hit — a restoration that hangs — the old duplicate
  window comes back for that launch. That is the deliberate trade: a duplicate
  window is recoverable, a dropped double-click is not.

### Follow-up Suggestions

- `KNOWN_ISSUES` #31 now has a concrete lead: the launch-time open path stopped
  varying once it ran a run-loop pass later, which points at the first open
  happening before the view has its final bounds. Whoever picks #31 up should
  start there — and must count resampling steps before and after, per
  `CLAUDE.md`.
- `KNOWN_ISSUES` #33 (the open is still application-modal) is untouched and
  remains the agreed separate task.
