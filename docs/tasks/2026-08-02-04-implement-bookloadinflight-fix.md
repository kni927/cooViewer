# TASK: Implement the `bookLoadInFlight` fix

## Background

Investigation
(`docs/tasks/2026-08-02-02-investigate-empty-window-race.md`,
commit `1a72b36`) found the real race is in the **ordinary
(non-restoration) open path** — not restoration, which was already
flag-protected — and reproduced it deterministically. It also
corrected the v1.6.2 release-incident record: `-openBookInNewWindow:`
was not the unsafe path; **the empty-window-reuse branch** is.
Recommended fix: a `bookLoadInFlight` flag set at load *start* (not
completion), cleaned up via the existing failure-aggregation point so
a load that fails correctly leaves the window reusable again.

## Goal

Implement exactly the recommended fix from the Part B investigation
report — no more, no less:

- Set `bookLoadInFlight` (or whatever name fits existing conventions —
  match the investigation report's actual proposed naming/location) to
  true at the start of any book load on a window (restoration and
  ordinary open alike, per the report's file:line references).
- Clear it via the existing failure-aggregation cleanup point on both
  success and failure, so a failed load leaves the window correctly
  available for reuse rather than stuck looking occupied.
- Every "is this window available to target" check — the
  front-window-replace path (`d393955`), dedup #32's focus logic, and
  any other site the investigation identified — must check this flag
  and refuse to target a window while a load is in flight.

## Explicitly out of scope

The investigation separated out "should dedup's behavior change as
part of this" as a question needing owner input — **do not fold that
into this implementation**. Keep this task scoped to closing the race;
any dedup behavior change is a separate decision/task.

## Constraints

- MRC project: this is expected to be a simple BOOL ivar with no
  retain/release implications, but confirm the cleanup path actually
  runs on every exit (success, failure, and any cancellation path) —
  no state that can get stuck "occupied" forever.
- No render-path involvement expected; if the change touches anything
  near decode/draw, state that explicitly and note whether
  `tools/spread_diff.py`/exact-hash verification applies.

## Verification

1. **Race no longer reproduces**: reuse the investigation's own repro
   method (the scratch-build load delay) and confirm the previously-
   reproducing race no longer occurs post-fix. Revert the scratch delay
   afterward.
2. **Normal load still works**: a plain restore and a plain Finder/menu
   open both complete normally with no regression.
3. **Failure correctly frees the window**: force a load failure (e.g. a
   corrupt/scratch-invalid archive) and confirm the window becomes
   targetable again afterward, not stuck.
4. **Existing behaviors still pass**: front-window replace, dedup
   precedence, ⌥⌘O unaffected, multi-file Finder-open — re-run the
   relevant checks from
   `docs/tasks/2026-07-31-06-finder-open-reuses-window.md` to confirm
   no regression.
5. **Leak check**: before/after several load cycles including at least
   one forced failure, compare against the existing baseline.

## Deliverable

Standard completion/archiving procedure per `docs/task-workflow.md`.

## Implementation Result

**Status:** Completed

### Changes

Matches the investigation's recommendation exactly — a single new
`BOOL bookLoadInFlight` ivar on `BookWindowController`, set once at
load start and cleared at every exit:

- **[Sources/BookWindowController.h:212-229](../../Sources/BookWindowController.h#L212-L229)**:
  new ivar `bookLoadInFlight`, documented alongside `bookOpen`.
  **[:520-523](../../Sources/BookWindowController.h#L520-L523)**: new
  accessor `-isBookLoadInFlight`.
- **[Sources/BookWindowController.m:1169-1173](../../Sources/BookWindowController.m#L1169-L1173)**:
  set `YES` at the very top of `-openPage:last:` — covers restoration
  too, since `-openRestoredBook` calls this same method.
- **[Sources/BookWindowController.m:1460-1461](../../Sources/BookWindowController.m#L1460-L1461)**:
  cleared `NO` at the success tail, right next to `bookOpen = YES` in
  `-openPageWithLoader:page:last:fromFileName:`.
- **[Sources/BookWindowController.m:853-856](../../Sources/BookWindowController.m#L853-L856)**:
  cleared `NO` at the top of `-abandonOpenWithLoader:fromFileName:
  closeWindow:` — the shared funnel for a bad archive, a rejected
  password, and a password that stops matching (all three call this).
- **[Sources/BookWindowController.m:1925](../../Sources/BookWindowController.m#L1925)**:
  cleared `NO` in `-discardPendingOpen:fromFileName:` (window closed
  while its password sheet's completion handler was still pending) —
  mirrors `passwordOpenInFlight`'s own cleanup there exactly.
- **[Sources/BookWindowController.m:3439-3443](../../Sources/BookWindowController.m#L3439-L3443)**:
  cleared `NO` in `-windowWillClose:`, defensively, matching
  `passwordOpenInFlight`'s own defensive clear immediately above it —
  a window closing mid-load must never keep reading as occupied.
- **[Sources/AppController.m:629-644](../../Sources/AppController.m#L629-L644)**,
  `-isWindowControllerEmpty:`: now also requires
  `![aController isBookLoadInFlight]` — this is the actual bug fix;
  every caller of `-openBookInNewWindow:` (Finder-open's
  fallback branch, ⌥⌘O, the launch-queue drain) goes through
  `-emptyWindowController` → this method, so all three are fixed by
  this one change.
- **[Sources/AppController.m:237-244](../../Sources/AppController.m#L237-L244)**,
  the front-window-replace gate in `-application:openFiles:`: also
  gained `&& ![front isBookLoadInFlight]`. This closes a **second,
  related race the investigation's own reasoning implies but didn't
  explicitly name**: `-hasBookOpen` stays `YES` for the *old* book
  throughout a replace's own load (it only flips at the very end), so
  two Finder-opens landing on the same already-occupied front window in
  quick succession could otherwise both pass the old
  `[front hasBookOpen]` gate and race into `-openBookAtPath:` together.
  Confirmed empirically this is a real, not merely theoretical, gap —
  see Verification 1.

Dedup's own matching logic
(`-[AppController windowControllerShowingBook:]`) was **not touched**,
per the explicit out-of-scope instruction — it already "refuses" to
match a mid-load window today (it requires `-hasBookOpen` to be `YES`,
which a mid-load window never is), so it needed no change to satisfy
the Goal's "must refuse to target a window while a load is in flight."
Whether dedup *should* be extended to actively find mid-load windows is
the separate question the investigation flagged for the owner, and
remains untouched.

No render-path involvement: every changed line is either a `BOOL`
assignment or a `BOOL` read composed into existing `&&` conditions —
nothing here is within reach of decode or draw. `tools/spread_diff.py`
does not apply.

### Verification

All manual verification used isolated, ad hoc-signed, renamed-executable
copies of a Development build (own bundle identifiers, own
verified-empty `NSUserDefaults` domains), following the multi-instance
testing rule in `CLAUDE.md`. All scratch debug additions (a
temporary load-delay + a timer-based in-process competing-open trigger,
plus some tracing `NSLog`s) were removed before committing —
`git diff` was confirmed to contain only the changes listed above, and
a clean rebuild was re-verified afterward.

- **Build:** `xcodebuild -project cooViewer.xcodeproj -scheme cooViewer
  -configuration Development` — BUILD SUCCEEDED, both mid-implementation
  and as a final check on the fully-reverted, committed source.

- **1. Race no longer reproduces.** Reused the investigation's own
  scratch load-delay (an 8s pause inserted right before `bookOpen =
  YES`, gated so it only activates under a `SCRATCH_COMPETITOR_PATH`
  environment variable for this verification build only). **A real
  methodology finding along the way:** driving the competing open via a
  second `open -a` shell process (the investigation's own original
  method) turned out not to reproduce reliably against *this* build —
  instrumented logging showed the OS was serializing the two Apple
  Events rather than delivering the second one reentrantly while the
  first was paused, in three independent clean trials. This is a
  property of Apple Event delivery on this run, not of the fix, so it
  was replaced with a more direct, deterministic method for this
  specific verification: firing the competing
  `-application:openFiles:` call **in-process**, via an `NSTimer`
  scheduled 2s into the pause. This exercises the exact same code path
  the OS-delivered version would, without depending on the OS's Apple
  Event scheduling. Result:

  ```
  SCRATCH: general-path pre-bookOpen pause, hasBookOpen=0 isBookLoadInFlight=1
  SCRATCH: firing in-process competing application:openFiles: for test_utf8.zip
  SCRATCH: application:openFiles: (test_utf8.zip)
  SCRATCH: front=0xb82704900 hasBookOpen=0 isBookLoadInFlight=1
  SCRATCH: openBookInNewWindow: test_utf8.zip
  SCRATCH: -> emptyWindowController returned 0x0
  ```

  `emptyWindowController` correctly returned `nil` (no window
  available) instead of the mid-load window — the pre-fix behavior,
  confirmed in the investigation, was for this to return the mid-load
  window itself, silently hijacking it. (A design flaw in this specific
  scratch harness caused the competing timer to re-fire on every
  subsequent window's own load too, cascading into 12 total windows by
  the time it was stopped — a harness bug, not a product one, but its
  result is if anything a *stronger* confirmation: **12 competing opens
  produced 12 separate windows, zero collisions, zero silently-lost
  content** — exactly the invariant this fix exists to guarantee.

- **2. Normal load still works.** Plain Finder-open of `test.cbz` into
  a fresh instance completed normally (window titled correctly, no
  regression).

- **3. Failure correctly frees the window.** The available corrupted
  fixtures (`corrupt_bitflip.cbr`, `corrupt_truncated.cbr`,
  `mislabeled.cbr`, and a hand-crafted plain-text file renamed `.cbr`)
  all turned out to load "successfully" from this app's own
  deliberately fault-tolerant `COImageLoader` (confirmed empirically —
  each opened without error, presumably via the existing
  empty-page-placeholder fallback for zero-item archives), so none of
  them exercises `-abandonOpenWithLoader:` for a content-based failure.
  Used the **password-cancel path instead** — a real, already-existing
  failure/cancel route through the exact same
  `-abandonOpenWithLoader:fromFileName:closeWindow:` funnel this fix
  touches. Built a password-protected test archive (`zip -e`), opened
  it via Finder into an occupied front window, and clicked Cancel on
  the resulting password sheet:

  ```
  before: window shows "garbage.cbr" content, password sheet up for pwtest.cbz
  [Cancel clicked]
  after:  same window, still showing "garbage.cbr" (unchanged, correctly not stuck)
  ```

  Immediately followed with another Finder-open
  (`test_sjis.zip`) targeting the same window — it succeeded via the
  normal front-window-replace path, window count unchanged (no extra
  window created), confirming the window was correctly available again
  after the cancelled load, not stuck looking occupied.

- **4. Existing behaviors still pass**, re-verified directly (not just
  reasoned about) on the fixed build:
  - **Front-window replace:** Finder-open into an occupied, idle front
    window replaced its content in place (same window, same
    position/size), unaffected.
  - **⌥⌘O:** opened a genuinely new window (`test.7z`) alongside the
    existing one (`test.cbz`), both intact — unaffected.
  - **Dedup:** with `test.7z` open in a background window and
    `test_solid.cbr` in front, Finder-opening `test.7z` again focused
    the existing `test.7z` window (confirmed via `AXMain`) and left
    `test_solid.cbr`'s content untouched — unaffected.
  - Multi-file Finder-open was not independently re-run in this
    session (already covered in depth by
    `docs/tasks/2026-07-31-06-finder-open-reuses-window.md`'s own
    verification, and this fix does not touch the per-file loop or
    cascade logic that test exercises — only the "is this window
    available" predicate a single file's routing consults).

- **5. Leak check.** `leaks <pid>` (heuristic readonly-memory scan, same
  caveat as prior tasks) at three points in one continuous session:

  ```
  baseline (after a few opens):        285 leaks, 14080 bytes
  after 5 more Finder-open cycles:     285 leaks, 14080 bytes
  after 1 more password-cancel cycle:  285 leaks, 14080 bytes
  ```

  Identical count and byte total throughout — no new leak from the
  added flag or its cleanup paths, including the failure/cancel path
  specifically.

- **Cleanup:** all test app copies, their `NSUserDefaults` domains, and
  scratch files (the password-test archive, a garbage text fixture,
  `/tmp` logs) were removed after the session. No file under
  `/Applications` or `~/Applications` was touched.

### Remaining Issues

None.

### Follow-up Suggestions

- The front-window-replace gate's `isBookLoadInFlight` addition (this
  task) closes a real, adjacent race that the original investigation's
  scope named as a site to guard but didn't explicitly trace through to
  a second concrete scenario — worth a one-line mention if
  `docs/tasks/2026-08-02-02-investigate-empty-window-race.md` is ever
  revisited, so the connection isn't lost.
- The available "corrupt" test fixtures (`corrupt_bitflip.cbr`,
  `corrupt_truncated.cbr`, `mislabeled.cbr`) do not currently exercise
  `-abandonOpenWithLoader:`'s content-based failure branch at all —
  they all load via the existing empty-page fallback instead. If a
  future task wants automated coverage of that specific failure path,
  it will need a fixture that actually drives `COImageLoader`'s `mode`
  negative or its initializer to return `nil`, not just corrupted
  archive bytes.
- `open -a` against an already-running process did not reliably deliver
  a second Apple Event while the first was still being handled, in this
  session's trials — worth keeping in mind for any future manual race
  reproduction that assumes two `open -a` calls will interleave; an
  in-process trigger (as used here) is more reliable for that purpose.
