# KNOWN_ISSUES #24 + quit-during-password-prompt

Two small, independent items, bundled because each is a modest code change
carrying one behavior decision. They share no code — expect separate
commits.

---

# Item A — #24: restore the All Bookmark browser's entry path

## Background

Since MW-4's menu retargeting sweep, the All Bookmark browser has had **no
UI entry path** — the feature exists but cannot be reached. This is a
regression introduced by the multi-window arc, not a pre-existing gap.

First establish which of these is actually true, since the fix differs:

- the menu item was removed from the nib, or
- the item still exists but points at First Responder, where nothing
  implements the action, leaving it permanently disabled.

## Decision (already made — implement this)

Selecting a bookmark in the browser:

- if that book is **already open** in some window → bring that window
  forward;
- if it is **not open** → open it in the **front window**.

Navigating to the bookmarked page is assumed to be the point of activating
a bookmark, in both cases. If the code suggests otherwise, stop and report
rather than guessing.

## Scope

1. Restore the menu entry.
2. **Target it at the application level** (`AppController` or the shared
   `AllBookmarkController`) — **not** First Responder. The All Bookmark
   browser has been a single app-wide instance since MW-5, which is also
   why MW-6 deliberately left its autosave name `"AllBookmark"`
   unsuffixed while giving every per-window panel a per-window name. This
   item is a deliberate exception to MW-4's First-Responder sweep; record
   that in `docs/DECISIONS.md` so a future sweep doesn't "fix" it back.
3. Implement the activation behavior above, reusing the existing
   resolution/dedup path (`+resolvedBookPath:` and the `AppController`
   registry) rather than writing a second lookup.
4. **Verify the browser itself still works.** It has been unreachable for
   the entire arc, so nothing in MW-1..MW-9 exercised it. Treat it as
   unverified code, not as a known-good feature that merely lost its
   button.

## Edge cases to settle while in the code

- **No book windows open, only the browser.** With quit-on-last-close in
  place, is the All Bookmark browser counted as a window that keeps the
  app alive? The MW-7 follow-ups made per-window panels close on every
  window close specifically so a stray visible panel couldn't block
  termination — but that mechanism is per-window, and this browser is
  app-wide, so it is probably not covered. Determine the current behavior,
  then decide: should the browser keep the app running, and what does
  "open in the front window" mean when there is no front window (open a
  new window, presumably)?
- Bookmarks pointing at a book whose file has moved or been deleted —
  degrade the way MW-8 established for a failed restore (one console line,
  no crash, no broken window).

---

# Item B — make the app quittable while a password prompt is showing

## Background

Surfaced during the #30/#33 task: with a password sheet up, Cmd+Q, the
Quit menu item, and the AppleEvent are all discarded. Measured identical in
the pre-change build, so it is **not** a regression from that work — but
an unresponsive Cmd+Q is user-visible breakage, so it gets fixed.

The proposed fix from that session was to close in-flight sheets in
`applicationShouldTerminate:` — one method, but it carries the behavior
decision below.

## Decision (already made — implement this)

**The app must be quittable while a password prompt is showing.**

## Scope

1. Dismiss in-flight password sheets on termination and let the quit
   proceed. With multiple sheets up on multiple windows, all of them must
   be dismissed.
2. Treat a dismissed prompt as a cancel, consistent with the cancel
   behavior settled in the #30/#33 task (a window that had a book keeps
   it; a bookless window stays bookless).
3. **Do not let a never-opened book leak into persisted state.** An
   archive whose password was never entered must not land in
   `RecentItems` / `LastPages`, and must not produce a half-open window in
   the next launch's restoration.
4. **Check the two adjacent modal paths and report what you find:**
   - The nested-archive prompt is still synchronous by decision 3 of the
     #30/#33 task, and a synchronous modal loop may never reach
     `applicationShouldTerminate:` at all. If it also blocks quit and
     fixing it would require undoing that decision, **report rather than
     force it**.
   - The archive-load progress sheet is driven by an `NSApp` modal session
     (#33's loading half, deliberately pending). If it blocks quit too,
     note it — the fix likely belongs with the deferred background-loading
     work, not here.

---

# Out of scope (both items)

- #28 (`-[FilterPanelController deleteFilter:]` releasing a KVO-registered
  `CIFilter`), #29 (Alias Manager `CFString` leak), #31 (first-open layout
  jitter).
- #33's book-loading half / background archive loading — pending by
  decision, not a bug.
- Version bumps, notarization, GitHub Release, Homebrew tap — the release
  task.

# Verification plan

- Build: warning-count/content diff against the current baseline — 312
  lines = 310 source + 2 "not stripping binary". Re-measure the baseline
  in the same session.
- Image quality: render path untouched, so same-session spread captures
  should be byte-identical. Capture both sides in one session, windows
  positioned non-overlapping, and expect #31's first-open jitter on
  single-page cover captures — compare against a second run of the
  baseline rather than treating the first run as truth.
- `leaks` / `NSZombieEnabled`, particularly around item B (dismissing
  sheets during termination is a classic place to strand a block or
  over-release a controller) and around item A's browser, which has not
  been exercised in a long time.
- Defaults domain (`jp.coo.cooViewer`) zero-diff before/after; test
  fixtures out of Recent Books; saved application state from testing
  discarded.
- Manual, test build only — launch from `build/` directly; do not install
  to `/Applications` or `~/Applications`:

  **Item A**
  - The menu item exists, is enabled, and opens the browser.
  - The browser lists bookmarks across multiple books.
  - Select a bookmark for a book already open in another window → that
    window comes forward, at the bookmarked page; no second window.
  - Select a bookmark for a book that is not open → it opens in the front
    window, at the bookmarked page.
  - Select a bookmark whose file has moved or been deleted → graceful.
  - Open/close book windows while the browser is up → it stays consistent.
  - The edge case above: only the browser open, no book windows.

  **Item B**
  - Cmd+Q with one sheet up → the app quits.
  - Quit menu item, and `osascript -e 'quit app "cooViewer"'` → same.
  - Two sheets on two windows → both dismissed, app quits.
  - After quitting that way, relaunch → no half-open window, and the
    never-opened archive is absent from Recent Books.
  - Quit attempted during a nested-archive prompt, and during an
    archive-load progress sheet → record the actual behavior either way.

# Notes for the implementing session

- Per established practice: read the actual code before finalizing the
  commit plan, and if measurement contradicts anything stated above, trust
  the measurement and correct the record — the #32 and #30/#33 sessions
  both did this to good effect.
- The two items are independent; if one turns out to be much larger than
  it looks, split it out rather than letting it hold up the other.
- If a decision surfaces that isn't covered above, stop and report rather
  than picking silently.

---

## Implementation Result

**Status:** Completed with follow-up issues

Two independent items, two commits. Item A's premise and item B's proposed
mechanism both turned out to be wrong on measurement; both are corrected in the
record and the decided *behaviour* was delivered either way.

### Item A — #24: the All Bookmark browser's entry path

**Which of the two candidate causes was true:** neither exactly. The menu item
was **not** removed from the nib. `Bookmark ▸ Edit Bookmark…` exists, has
targeted First Responder since MW-4, and dispatches on whether the front window
has a book — the per-book sheet if it does, the app-wide browser if it does not.
With no book window nothing in the responder chain implements the action, so
AppKit disables the item and the browser's branch is unreachable. Measured
before touching anything: with zero book windows the item reports
`enabled = false`; the browser is unreachable in the other state too, because
there the item takes the per-book branch.

**Changes**

- `Resources/Base.lproj/MainMenu.xib` + `en/ja` `MainMenu.strings` — a new
  `Bookmark ▸ All Bookmarks…` item, action `allBookmarks:` on `AppController`.
- `Sources/AppController.h/.m` — `-allBookmarks:`, and
  `-windowControllerShowingBook:` promoted to the header (the browser needs the
  "already open" test on its own).
- `Sources/BookWindowController.m` — the Bookmark menu's fixed head was
  hard-coded as 2 in the two places that rebuild the menu, so a third static
  item would have been deleted by both. They go through
  `kBookmarkMenuFixedItemCount` now.
- `Sources/AllBookmarkController.m` — `-openInSelf:` (the browser's "Open"
  button) called `-application:openFile:` on the book window controller, a
  method **MW-7 deleted**; it would have raised an unrecognized selector for
  anyone who reached the browser. It now brings the window forward if that book
  is already open, and otherwise replaces the front window's book, both through
  `+resolvedBookPath:` and the existing registry lookup.

**Reported, not implemented (the task asked for exactly this):** the decision
assumed that activating a bookmark navigates to its page. **There is no such
gesture, and never was.** The browser's left table lists books, the right table
lists that book's bookmarks as editable name/page rows, and the only open
affordance — the "Open" button — acts on the *book* selection and carries no
page. The per-book panel is the same shape; bookmark *navigation* lives in the
Bookmark menu. The window behaviour the decision specifies (already open →
bring forward; not open → open in the front window) was implemented on the
gesture that does exist. Adding a page-navigating gesture would be new UI and is
left for the project owner.

**Verification (manual, on device, test build from `build/`)**

| Check | Result |
|---|---|
| The item exists, is enabled with no book window, opens the browser | `All Bookmarks…` enabled `true` with zero windows, `Edit Bookmark…` still `false`; the browser opens |
| Lists bookmarks across multiple books | listed the owner's two bookmarked books plus the test books |
| Bookmark for a book open in another window → forward, no second window | one window, content **byte-identical** — the book was not re-opened, so the page is kept |
| Bookmark for a book that is not open → opens in the front window | the front window switched to that book; no new window; no crash where the old code would have raised an unrecognized selector |
| Bookmark whose file was deleted | app alive, no broken window, the front window kept its book |
| Per-window bookmark menus still rebuild correctly | each window's Bookmark menu = the three fixed items + that window's own bookmarks |
| Cancel leaves `BookSettings` untouched | verified against the pre-test export |
| Edge case: only the browser, no book windows | it opens, Open creates/uses a window, and closing the browser does **not** quit the app — the browser is an `orderOut:` panel, so quit-on-last-close never sees it. While it is up the app cannot terminate at all (it runs `-runModalForWindow:`) |

### Item B — quit while a password prompt is showing

**The proposed fix does not work, measured not assumed.**
`-applicationShouldTerminate:` was instrumented: it fires for an ordinary quit
and **not at all** for a quit attempted with a prompt up. AppKit's `-terminate:`
refuses while a sheet is attached, before consulting the delegate.

**Changes**

- `Sources/COApplication.h/.m` (new, and added to the Xcode project) — a
  two-method `NSApplication` subclass. `-terminate:` asks the delegate to cancel
  any password prompt and, when there was one, re-enters `-terminate:` one
  run-loop pass later, because `-endSheet:` only starts AppKit's dismissal.
- `Resources/Info.plist` `NSPrincipalClass` and the nib's File's Owner class.
- `Sources/AppController.h/.m` — `-cancelPasswordPrompts` (returns whether
  anything was dismissed), the `kAEQuitApplication` handler, and
  `-applicationShouldTerminate:` kept as a backstop.
- `Sources/BookWindowController.h/.m` — `-cancelPasswordPromptForTermination`
  ends the window's sheet with a non-OK response, which is the ordinary cancel
  path, so the "a window that had a book keeps it" rule holds here too.

**An intermediate approach was tried and rejected**, and the rejection is the
reason for the subclass: retargeting the Quit menu item at an `AppController`
action works for Cmd+Q and the menu, but loses the **"Quit and Close All
Windows"** alternate item AppKit generates for a menu item bound to
`-terminate:`. Confirmed both ways on device.

**Verification**

| Check | Result |
|---|---|
| Cmd+Q with one prompt up | quits |
| Quit menu item | quits |
| `osascript -e 'quit app "cooViewer"'` | quits — this one needs the AppleEvent handler; the subclass alone was **not** enough, measured |
| Two prompts on two windows | both dismissed, app quits |
| Relaunch after such a quit | one restored window for the real book, no sheets, no half-open window |
| The never-opened archives in persisted state | absent from `RecentItems`, `LastPages` and `BookSettings` |
| "Quit and Close All Windows" alternate item | present |
| Ordinary quit, decision 4 (last window closes), File ▸ Close All | all unchanged |
| Quit during the **nested-archive** prompt | blocked while up, then **deferred** — answering it lets the quit fire. Not forced: fixing it would undo decision 3 of the password-prompt task |
| Quit during the **archive-load progress sheet** | Cmd+Q swallowed by the `NSApp` modal session; the AppleEvent quit works immediately. Belongs with #33's deferred loading half |

### Verification (both items)

**Build:** clean Deployment build, `** BUILD SUCCEEDED **`, 312 `warning:` lines
= 310 source + 2 "not stripping binary". Compared against a clean build of the
previous commit (`3e8257c`) in the same session: identical totals and identical
per-symbol deprecation counts (38 distinct symbols). `build/` holds
`cooViewer.app` only.

**Image quality:** same-session captures against that baseline build. The
two-page spread is **byte-identical** in all three comparisons. The single-page
cover capture differs between the baseline's *own* two runs by exactly the
amount it differs from this build (mad 0.459207, maxdelta 53) — `KNOWN_ISSUES`
#31's first-open jitter — and baseline run 2 is byte-identical to this build.

**`NSZombieEnabled` + `MallocScribble`:** quit with two prompts up, then a
relaunch, the browser opened, a book opened from it and the browser cancelled.
No crash, no message-to-deallocated-instance abort.

**`leaks`:** 321 leaks / 19 792 bytes over the same ground, all `CFString` roots
(`KNOWN_ISSUES` #29) plus the known `NSBezierPath` root. **Zero** leaks naming
`COImageLoader`, `BookWindowController`, `AllBookmarkController`, `COApplication`
or `NSAlert`.

**Defaults hygiene:** domain exported before testing and restored afterwards,
byte-identical, with no test fixture in Recent Books. One near-miss worth
recording: an over-eager cleanup deleted `NSWindow Frame AllBookmark`, a key the
owner's profile already had — caught by the comparison and restored from the
backup. Fixtures created for this pass were deleted and both throwaway worktrees
removed.

**Not performed:** Apple Remote on hardware (impossible — `docs/DECISIONS.md`);
the QuickLook/Thumbnail extensions (untouched by either item).

### Remaining Issues

- The All Bookmark browser has no way to activate a *bookmark* (as opposed to a
  book) — see the report above. Nothing regressed; it never had one.
- Quit is still blocked during the nested-archive prompt (deferred, not
  dropped) and Cmd+Q is still swallowed during an archive load. Both are the
  adjacent modal paths the task asked me to check and report.
- The browser itself is application-modal, so book windows cannot be operated
  while it is up, and it lists only what has been *persisted* to `BookSettings` —
  a book whose window is still open does not appear until that window closes.
  Both pre-existing.

### Follow-up Suggestions

- Decide whether the browser should get a bookmark-activation gesture
  (double-click a bookmark row, or an "Open at this bookmark" button) — the
  behaviour for it is already settled, only the UI is missing.
- The browser's modality is the same shape MW-1 removed from the password
  prompt; making it a non-modal panel would also fix "quit is blocked while the
  browser is up" and would let it refresh as windows open and close.
