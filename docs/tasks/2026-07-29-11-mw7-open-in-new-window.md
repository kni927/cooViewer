# MW-7: Open in New Window + per-window cleanup

## Goal

Add the "Open in New Window…" entry point (decision A1) and use it to close
out the two gaps MW-5/MW-6 could not verify or fix without a second live
window.

## Background

- A1 (`docs/DECISIONS.md`): add an in-app "Open in New Window…" (⌥⌘O) menu
  item. A2: new windows open windowed, not fullscreen; fullscreen is
  per-window state remembered by restoration.
- KNOWN_ISSUES #26: audit of `BookWindow.xib` found all 11 per-window
  classes lack `-dealloc` (surfaced while adding `AccessoryView`'s in MW-6
  item 6). Harmless with one window; becomes a real per-close leak once a
  second window can exist.
- KNOWN_ISSUES #27: Recent Books menu items are built targeting the window
  that constructed them, not necessarily the current/front window.
- MW-6 shipped four behaviors that structurally require a second window to
  verify and were left unverified: window cascade positioning, suffixed
  per-window autosave names for the Bookmark/Filter panels,
  `-windowDidBecomeMain:` actually changing menu state between windows, and
  `-[AccessoryView dealloc]` firing on close.

## Scope

1. **Open in New Window… command.** New menu item (⌥⌘O). Confirm the right
   target (First Responder vs. AppController, per the MW-4 retargeting) and
   that it goes through the same window-creation path `BookWindowController`
   already uses, so item-1/2 autosave-naming and cascade logic from MW-6
   apply to it for free.
2. **Per-window `-dealloc` audit (KNOWN_ISSUES #26).** Add `-dealloc` to the
   11 per-window classes identified in the audit, releasing/nil-ing owned
   ivars per the project's MRC convention. Re-run the same `leaks` /
   `NSZombieEnabled` methodology used for the AccessoryView fix in MW-6.
3. **Recent Books menu targeting fix (KNOWN_ISSUES #27).** Make Recent Books
   items resolve the current/front window at invocation time rather than
   capturing the window that built the menu.
4. **On-device two-window verification** (the items MW-6 could not check):
   - Second window cascades from the first (`-cascadeTopLeftFromPoint:`),
     slot-0 keeps the legacy frame-autosave name.
   - Bookmark/Filter panel autosave names are correctly suffixed per window
     and don't collide or cross-pollinate positions.
   - `-windowDidBecomeMain:` actually swaps read/sort checkmarks and the
     bookmark menu when switching focus between two different books.
   - Closing a second window runs `-[AccessoryView dealloc]` (and the other
     10 classes from item 2) — confirm via breakpoint/log or `leaks`, not
     just absence of crash.
   - Spot-check the Step 0 multi-window decisions still hold: reopening a
     book already open in another window brings that window forward instead
     of opening a duplicate; closing one window (not the last) leaves the
     app running; File ▸ Open still replaces the *current* window rather
     than opening a new one (only ⌥⌘O opens new).

## Out of scope

- Anything not required to ship and verify Open in New Window itself —
  no unrelated refactors.
- Fullscreen-per-window restoration behavior (already decided in A2, not
  re-litigated here) beyond confirming new windows don't launch fullscreen.

## Verification plan

- Build: compare warning count/content against the 312-warning baseline
  (file+message normalized diff), same as MW-3–MW-6.
- Spread capture: SHA-256 byte comparison against the existing baseline for
  the render path (single window) — must stay untouched by this task.
- `NSZombieEnabled` pass covering: open two windows, switch focus between
  them, close the non-front one, close the last one.
- `leaks` (MallocStackLogging) before/after opening and closing a second
  window, to confirm the new `-dealloc`s actually reduce/zero the
  per-window leak count rather than just compiling.
- Defaults domain (`jp.coo.cooViewer`) diffed before/after a full two-window
  session (open second window, use both, close both) — expect zero
  unexpected key diffs.
- Manual, on a test build only (`~/Applications`, not `/Applications`):
  full checklist in Scope item 4 above.

## Notes for the implementing session

- Per MW-5/MW-6 practice: read the actual code before committing to the
  commit breakdown above — prior tasks in this project have revised their
  own commit plans once dependencies became clear from the source (e.g.
  MW-5's class-split-before-nib-split, MW-6's item-1-before-item-2). Treat
  the ordering here as a starting hypothesis, not a constraint.
- `AllBookmark` is intentionally exempt from per-window naming (MW-6,
  single shared instance since MW-5) — don't add it to the #26 dealloc
  sweep as a per-window class; it isn't one.

---

## Implementation Result

**Status:** Completed

### Changes

Three commits on `main`, `44b3a82`..`e2032b3`, plus this docs commit. The
commit order in the task's Scope section was revised, and the reason stated
before code was written: **item 2's `-dealloc`s can only be verified because
of item 1**, and item 3 is a one-hunk change independent of both. So the two
small, independently-buildable ones land first and the feature last —
`44b3a82` (item 3), `7abc21a` (item 2), `e2032b3` (item 1).

- **Item 1 — Open in New Window… and the window registry** (`e2032b3`).
  - **⌥⌘O re-checked before committing to it**, as decision A1 requires: the
    only `o` binding in the live `KeyArray` is plain `o` with `modifier = 0`
    (action 20), and `KeyArrayMode2`/`KeyArrayMode3` bind no `o` at all. No
    `modifier == 5` entry anywhere, so no collision.
  - The menu item is in `MainMenu.xib` targeted at **AppController**, not
    First Responder. Creating a window is not something a window does, and
    the command must stay available when the front window has no book. It
    goes through the same `-[AppController newWindowController]` path the
    launch-time window uses, so MW-6's slot-keyed autosave naming and the
    cascade apply to it unchanged. Localized titles added to `en`/`ja`
    `MainMenu.strings`.
  - `AppController`'s single `controller` outlet became `windowControllers`
    (owning, creation order) plus `frontWindowController` (the window that
    last became main, reported by `-[BookWindowController
    windowDidBecomeMain:]`). The existing `-controller` accessor now answers
    `-frontController`, so every app-level caller — including
    `PreferenceController` and `AllBookmarkController` — keeps working with
    the meaning it always intended. Slots are handed out lowest-free-first,
    as MW-6's decision record specified.
  - **De-duplication (Step-0 decision 2)** is keyed on the resolved book
    path. `+[BookWindowController resolvedBookPath:]` was lifted out of
    `-openPage:last:` so that method and the already-open check share one
    definition of "the book at this path" and cannot drift.
  - **A closing window is retired** — unregistered and released — **except
    the last one**, which stays as the bookless window File ▸ Open, Open the
    last page and the dock menu reuse. Step-0 decision 4 (quit on last
    close) is *not* implemented; the reason, and the specific hazard in
    `-openPage:last:`'s failed-first-open path, is recorded in
    `docs/DECISIONS.md`.
  - A retired window's thumbnail/bookmark/full-image/filter panels are
    ordered out with it (new `-closePanel` on the three panel controllers).
    They are separate windows in the same nib, so they would otherwise stay
    on screen after their window is gone and then be deallocated under
    AppKit's feet.
  - The per-window half of `-applicationDidFinishLaunchingSetup:` moved to
    `-windowDidLoad` as `-setupInputMappings`: every window needs its
    key/mouse mappings pushed into its own panels and image view, not just
    the one that exists at launch.
- **Item 2 — per-window `-dealloc` sweep** (`7abc21a`). Nine classes gained
  one; `ThumbnailPanel`, `BookmarkPanel` and `AccessoryWindow` own no object
  ivars and got **none** rather than an empty one — an intentional deviation
  from the task's "add `-dealloc` to the 11", recorded here and in
  `docs/KNOWN_ISSUES.md` #26, and backed by instrumentation proving all
  three are destroyed anyway. Two of the nine are correctness rather than
  tidiness: `CustomImageView` and `BookWindowController` are notification
  observers, and `FilterPanelController` owns `CIFilter`s it observes via
  KVO.
- **Item 3 — Recent Books targeting** (`44b3a82`). `[menuItem
  setTarget:self]` dropped; `-openFromOpenRecent:` resolves through the
  responder chain. The submenu is `autoenablesItems="NO"`, so the explicit
  `setEnabled:NO` on missing files still stands.

Nothing in the render path was touched.

### Verification

- **Build:** clean `Deployment` build with the documented command.
  **310 warnings.** The measured pre-change baseline on this machine/SDK is
  also **310** (not the 312 recorded in MW-6 — the deprecation set has
  shifted with the toolchain), and the normalised (file + message,
  line numbers stripped) diff between the two is **empty**. The new
  `-openInNewWindow:` uses `NSModalResponseOK` rather than the deprecated
  `NSOKButton` the older `-[BookWindowController open:]` uses, specifically
  so it does not add two instances to that baseline. The intermediate tree
  at `7abc21a` was built separately to confirm the commit split leaves no
  unbuildable commit.
- **Render path:** spread capture at a fixed window frame (100,100
  1200×800), same book, from a build of `063d458` and from this build —
  **byte-identical, SHA-256 `b16c9892ec7c32ed2221d9cdfca0de2163f9a587d622e2f7f66bd4ceb974e1e7`**.
  The capture was eyeballed to confirm it is a real two-page spread and not
  a blank first-paint frame.
- **On device**, test build only. `/Applications` never touched, no
  `lsregister`/`pluginkit` (no QuickLook/Thumbnail change in this task).
  `jp.coo.cooViewer` exported before and restored after; final diff is
  **zero delta across all 81 top-level keys**.
  - **Cascade:** three live windows at AX top-left (73,30), (102,59),
    (131,88) — a +29/+29 offset per window, with slot 0 on its restored
    frame. New windows open **windowed**, not fullscreen (A2).
  - **Per-window panel autosave names:** `NSWindow Frame FilterPanel` =
    `208 465 …` and `NSWindow Frame FilterPanel-2` = `700 281 …`
    simultaneously — two panels, two keys, no collision, no
    cross-pollination.
  - **`-windowDidBecomeMain:` actually swaps state between windows:** bookA
    set to Left to Right + Shuffle; focus to bookB → Right to Left + Name
    (the globals); focus back to bookA → Left to Right + Shuffle again. The
    "Open in Same Folder" submenu check-mark followed the front book in both
    directions (both books share a parent folder, so this exercised the
    forced rebuild).
  - **De-duplication:** ⌥⌘O on a book already open brought that window
    forward and did **not** open a third window.
  - **Recent Books targeting:** with the slot-0 window front and the slot-1
    window the last to have rebuilt the menu, choosing a recent book
    replaced the **front** window's book and left the other window alone.
  - **Closing a non-last window destroys it:** an instrumented build logged
    exactly one `-dealloc` per retired window for **all thirteen**
    per-window classes — the nine given one in item 2, `AccessoryView`
    (its first ever execution, MW-6's open verification item), and the
    three that ship without one. The window/view group
    (`CustomWindow`, `CustomImageView`, `AccessoryWindow`, `AccessoryView`)
    is released one close behind, because AppKit holds the most recently
    closed window; this is recorded in #26 so it is not misread as a leak.
  - **Closing one window (not the last) leaves the app running**, and so
    does closing the last one; File ▸ Open then reopens into that surviving
    window. File ▸ Open **replaces** the current window's book throughout —
    only ⌥⌘O opens a window.
  - **`leaks` (MallocStackLogging)** before and after opening + closing a
    second window: **no cooViewer per-window object leaked** in either
    snapshot. The delta is ~4 small `CFString` blocks from the Alias Manager
    helpers plus the known `AccessoryView -setFrame:` `NSBezierPath` leak —
    both pre-existing, now recorded as #29.
  - **`NSZombieEnabled` run** on the shipping build (presence confirmed with
    `ps eww`, stderr redirected to a file and the redirect confirmed with
    `lsof`), covering: open two windows, switch focus repeatedly, open a
    filter panel, close the non-front window, close the last one, reopen a
    book. **No zombie message, no crash, empty log.**
- **Not performed:** Instruments; encrypted archives; Apple Remote;
  multi-display; QuickLook/Thumbnail (unchanged by this task); the
  behaviour of a window retired while an archive load or a Bookmark sheet
  is in flight.

### Remaining Issues

None for the three scoped items. Two pre-existing defects were found while
doing them and recorded rather than fixed (out of scope): `docs/KNOWN_ISSUES.md`
#28 (`-[FilterPanelController deleteFilter:]` drops an observed `CIFilter`)
and #29 (Alias Manager path helpers leak a few `CFString`s per book open).

### Follow-up Suggestions

- **Step-0 decision 4 — quit after the last window closes.** Deliberately
  not implemented here; see `docs/DECISIONS.md` for the failed-first-open
  hazard whoever implements it owns. Doing it also removes the current
  asymmetry where the last window is never retired and so never exercises
  the new `-dealloc`s.
- **A standard Window menu window list.** `NSApplication`'s `windowsMenu`
  outlet is not connected, so with several windows open there is no menu
  listing them; only ⌘` and clicking switch windows. It is in the plan's
  MW-7 scope but not in this task's.
- **`application:openFiles:`** (plural) — the plan's "one window per file"
  from the Finder. This task deliberately kept `application:openFile:`
  replacing the front window's book, since the task specified that only
  ⌥⌘O opens a window.
- **The lookahead threads still outlive `-windowWillClose:` in principle.**
  `+detachNewThreadSelector:toTarget:` retains the target, so a retired
  window controller cannot be freed under a running lookahead — but its
  `-dealloc` can then run on that background thread. Worth an explicit join
  before MW-8 adds restoration on top.
- **`-validateMenuItem:`'s 24 `[[self window] isVisible]` tests** are still
  the "is a book open" proxy MW-6 item 4 replaced elsewhere (carried over
  from MW-6's follow-ups).
- KNOWN_ISSUES #24 (All Bookmark browser has no UI entry path) remains open;
  MW-6 suggested reconsidering it when MW-7 adds a Window menu, which this
  task did not.
