# MW-8: Window restoration

## Goal

Implement Step-0 decision 5 — restore, on relaunch, every window that was
open at quit (not just one) — reconciled with `OpenLastFolder` and verified
against the native fullscreen state MW-2 introduced.

## Background (from `docs/multiwindow-plan.md`)

- **Scope basis:** decision 5. `AppController` needs a restoration class;
  `BookWindowController` needs `encodeRestorableStateWithCoder:` /
  `restoreStateWithCoder:` carrying the book path **as a security-scoped
  bookmark, not a raw path**, plus the current page and the per-book view
  mode.
- **`OpenLastFolder` reconciliation:** recommendation from the plan is to
  keep it as a fallback used only when the system restored zero windows —
  restoration is governed by the system's "Close windows when quitting an
  app" setting, so the preference must not double-open a book when the
  system already restored one.
- **Fullscreen interaction (MW-2):** confirm restoration works correctly
  with native fullscreen, not just windowed state.
- **Acceptance (from the plan):** quit with three books open, relaunch, get
  the same three windows at the same pages and fullscreen states; with
  system window restoration disabled, `OpenLastFolder` still reopens one
  book and nothing is double-opened.
- **Image quality:** the plan's cross-cutting scan already marked MW-8
  clean — restoring into fullscreen re-enters `-recomposeForCurrentSize`
  via `windowDidEnterFullScreen:`, the existing path. Restorable state must
  carry book path / page / view mode only, **never a rendered image**. No
  new resample step is acceptable anywhere in this task.
- **Depends on:** MW-7 (done, plus the follow-ups: decision 4, Finder-open
  routing, lookahead join — Window menu needed no code).

## Scope

1. `NSWindowRestoration` restoration class on `AppController`.
2. `encodeRestorableStateWithCoder:` / `restoreStateWithCoder:` on
   `BookWindowController`: book path as a security-scoped bookmark
   (`NSURL` bookmark data, not the Alias Manager path used elsewhere in
   the app — this is the one exception the plan carves out of "Alias
   Manager → NSURL bookmarks" being out of scope for the whole arc),
   current page, per-book view mode.
3. Reconcile with `OpenLastFolder` (`applicationDidFinishLaunching:`
   579-583 → `openTheLastPage:`): fallback path only, gated on the system
   having restored zero windows.
4. Verify — don't assume — that native fullscreen state (window style
   mask) round-trips through `NSWindowRestoration` correctly, at the right
   page, for a window that was fullscreen at quit.

## Out of scope

- Any broader Alias Manager → `NSURL` bookmark migration beyond what
  restoration itself needs (explicitly carved out in the plan's
  "Explicitly out of scope for the whole arc").
- Anything not part of decision 5.
- KNOWN_ISSUES #28/#29/#30 — pre-existing, unrelated to this task.

## Verification plan

- Build: warning-count/content diff against the current baseline (310).
- Image quality: same spread-capture SHA-256 methodology as prior tasks,
  but specifically on a *restored* window — capture a page/spread
  immediately after restoration and compare against the established
  single-resample baseline. Take the comparison baseline within the same
  session (per the follow-ups task's finding that the hash isn't stable
  cross-session due to window-corner anti-aliasing).
- `leaks` / `NSZombieEnabled` across a quit-with-N-windows → relaunch
  cycle, including at least one fullscreen window among them.
- Manual, on a test build only (`~/Applications`, not `/Applications`):
  - Open 3 books in 3 windows, put one in native fullscreen, at different
    pages each; quit; relaunch — same 3 windows, same pages, the
    fullscreen one comes back fullscreen.
  - With system window restoration disabled (System Settings ▸ Desktop &
    Dock ▸ "Close windows when quitting an app"), quit and relaunch —
    `OpenLastFolder` reopens exactly one book, no duplicate window.
  - Quit with zero windows open (if reachable given decision 4's
    quit-on-last-close) and relaunch — confirm no crash and correct
    fallback behavior.
  - A book whose file has moved or been deleted since quit — confirm the
    security-scoped bookmark failure path degrades gracefully (no crash,
    reasonable message) rather than restoring a broken window.

## Notes for the implementing session

- Per established practice: read the actual restoration-adjacent code
  before finalizing a commit plan.
- Worth a quick check, not necessarily in this task's scope: the plan's
  MW-7 section also listed "Route Apple Remote events from `AppController`
  to the key window," which the MW-7 completion report doesn't mention
  addressing. Confirm whether it was covered elsewhere or is still open —
  if still open, it's unrelated to decision 5 and probably belongs in its
  own follow-up rather than folded into MW-8, but worth flagging rather
  than silently leaving it unowned. (No hardware to test with, per prior
  sessions' notes — same long-standing verification gap as before.)

---

## Implementation Result

**Status:** Completed

### Changes

- `Sources/AppController.h/.m`
  - `AppController` adopts `<NSWindowRestoration>` and implements
    `+restoreWindowWithIdentifier:state:completionHandler:`. It hands back
    a book window: the empty launch window for the first restored window,
    a newly created one for each window after that. `-beginRestoration`
    takes a window out of the "empty window" pool immediately, so two
    restoration requests cannot land on the same window.
  - New exported constant `CooViewerBookWindowRestorationIdentifier`
    (`@"cooViewerBookWindow"`) — one shared `NSWindow` identifier; the
    saved state keeps a separate record per window and the coder says
    which book each record is.
  - `-emptyWindowController` skips a window that is mid-restoration
    (`-isAwaitingRestoredBook`).
  - `-applicationDidFinishLaunching:` gates `OpenLastFolder`: it runs only
    when the system asked for **zero** windows to be restored.
  - Backstop: `NSApplicationDidFinishRestoringWindowsNotification` ends any
    restoration a window never received a `-restoreStateWithCoder:` for.
  - `-applicationSupportsSecureRestorableState:` returns YES.
- `Sources/BookWindowController.h/.m`
  - `-windowDidLoad` sets the window's `identifier` and `restorationClass`.
  - `-encodeRestorableStateWithCoder:` / `-restoreStateWithCoder:` carry a
    **security-scoped `NSURL` bookmark** for the book, the current page and
    the per-book view mode (`fitScreenMode`). They are driven by the window
    delegate pair `-window:willEncodeRestorableState:` /
    `-window:didDecodeRestorableState:` — see "Deviation" below.
  - The bookmark is made once per book open (in `-openPage:last:`, next to
    `bookOpen = YES`), not at encode time.
  - `-restorablePageIndex` converts `nowPage` to the page `-openPage:last:`
    takes, the same conversion the RecentItems/LastPages writers use.
  - `-openRestoredBook` runs one run-loop pass after the restoration pass:
    it applies the view mode, then opens the book at the restored page with
    `goToLastPageMode` temporarily forced to 2 so the "go to the last
    page?" alert cannot appear for a page the restore already knows.
  - `[[self window] invalidateRestorableState]` at the end of
    `-imageDisplay` and in the four fit-mode actions.
  - Security scope and the pending `-openRestoredBook` are released in
    `-windowWillClose:` / `-dealloc`; the bookmark is dropped when the
    book is torn down.

**No render-path change.** Nothing was added between the decoded `NSImage`
and `[page drawInRect:fromRect:]`. A restored window reaches the screen
through the ordinary `-openPage:last:` → `-imageDisplay` →
`-[CustomImageView setImages:]` path, and a window restored into full
screen is recomposed by the pre-existing
`-windowDidEnterFullScreen:` → `-recomposeForCurrentSize`.

### Deviation from the task text (recorded, not silent)

The task names `-encodeRestorableStateWithCoder:` /
`-restoreStateWithCoder:` on `BookWindowController`. Those methods **are**
the implementation, but AppKit does not call them on a plain,
document-less `NSWindowController`: instrumenting all four candidate hooks
on macOS 26 showed only the `NSWindowDelegate` pair
(`-window:willEncodeRestorableState:` /
`-window:didDecodeRestorableState:`) firing. `BookWindowController` is the
book window's delegate as well as its window controller, so those two
one-line methods forward into the named ones. Decoding is guarded against
running twice in case a future AppKit calls both.

### Verification

- **Build:** clean Deployment build, `** BUILD SUCCEEDED **`. 312 `warning:`
  lines = 310 source warnings + 2 "not stripping binary because it is
  signed" lines, i.e. the documented 310 baseline. The normalised warning
  multiset (file + message + count, line numbers stripped) is **identical**
  to a baseline build of the pre-change tree taken in the same session.
- **Manual, on device** (`build/cooViewer.app` run in place; `/Applications`
  and `~/Applications` untouched, so no LaunchServices/QuickLook
  registration — see `docs/KNOWN_ISSUES.md` #15):
  - Three books in three windows, one in native full screen, one in "Fit
    to Screen Width", all advanced to the last spread; quit; relaunch →
    the same three windows, the same books, the same page (index 10 in
    each), BookA back in full screen, and the View menu check-marks
    confirming per-window view modes (BookB = Fit to Screen Width,
    BookC = Fit to Screen).
  - `OpenLastFolder` reconciliation: with restoration on, the preference
    did not run and nothing was double-opened. With window restoration
    disabled for the app (`NSQuitAlwaysKeepsWindows = NO`, the per-app form
    of "Close windows when quitting an app"), a relaunch restored nothing
    and `OpenLastFolder` reopened **exactly one** book in one window.
  - Book *renamed* between quit and relaunch: the bookmark tracked it and
    the window came back on the renamed folder — the reason the plan asked
    for a bookmark rather than a path.
  - Book *deleted* between quit and relaunch: one console line
    (`window restoration skipped, the book could not be found`), no crash,
    no broken window; the other two windows restored normally, and the
    empty window was then reused by the next Finder open instead of a
    fourth window being created.
  - Quit with zero windows ever shown, then relaunch: nothing restored,
    no crash.
- **Image quality**, on a *restored* window, same session:
  - Restored BookC spread vs. the same book/page re-opened in the same
    window: a ~1 px offset, thin edge outlines only. A control run with
    restoration disabled shows the **same** difference between a first
    open into a fresh window and a re-open — so it is a pre-existing
    property of the open path, not something restoration introduced
    (recorded as `docs/KNOWN_ISSUES.md` #31).
  - Softness measurement (fraction of non-pure-black/white pixels, which
    is what an extra resampling step would raise): restored 0.655 % vs.
    re-opened 0.806 %. The restored render is not softer; there is no
    extra resample.
- **`NSZombieEnabled` + `MallocScribble`:** quit with three windows (one
  full screen) → relaunch → restore → close windows → quit. No zombie
  messages, no crash.
- **`leaks`** on a restored process: 312 leaks / 22 912 bytes, all of them
  the already-documented `CFString`s from the Alias Manager helpers
  (`KNOWN_ISSUES` #29, reached here through `-openRestoredBook` →
  `-openPage:last:` like any other open) plus the known `NSBezierPath`
  root leak in `-[AccessoryView setFrame:]`. No leaked `NSURL`, `NSData`
  or window controller.
- **Defaults hygiene:** the owner's `jp.coo.cooViewer` domain was exported
  before testing and compared afterwards — no keys added, removed or
  changed, and the test books are not in Recent Books. The saved
  application state written during testing was discarded before restoring
  the domain.
- **Not performed:** Apple Remote (no hardware — the long-standing gap);
  QuickLook/Thumbnail extension checks (untouched by this task).

### Remaining Issues

None for decision 5 itself.

Two behaviours worth knowing rather than defects:

- The restored window that ends up key is the last one whose book finishes
  opening, because `-openPage:last:` orders its window front. Which window
  was key at quit is not restored.
- If *every* restored book has gone missing, `OpenLastFolder` still does
  not run: the gate is "did the system restore any windows", which is
  decided before the books are resolved. The windows are empty and usable,
  so nothing is lost, and it matches the plan's wording.

### Follow-up Suggestions

- `docs/KNOWN_ISSUES.md` #31 (new): two opens of the same book at the same
  page in the same window are not pixel-identical when one of them is the
  first open into a freshly shown window — a ~1 px layout difference,
  which is a "when does the view learn its bounds" question and therefore
  in the image-quality area.
- **Apple Remote routing is still unowned.** The plan's MW-7 section listed
  "Route Apple Remote events from `AppController` to the key window"; the
  MW-7 report does not mention it. Checked here:
  `-[AppController remoteButton:pressedDown:clickCount:]` resolves
  `-frontController` once and dispatches to that window, which *is* the
  routing the item asked for — it landed in MW-3's move of that method
  rather than in MW-7, and the front window is the one whose window last
  became main. What has never been verified is the *hardware* path (no
  Apple Remote available), which is the same long-standing gap. Nothing
  further to implement; the item can be closed as covered, with the
  hardware verification still outstanding.
- MW-9 (regression pass and release readiness) is now unblocked.
