# Multi-Window Support — Implementation Task Breakdown

Date: 2026-07-28
Basis: `docs/multiwindow-pass1.md`, `docs/multiwindow-pass2.md`,
Step 0 decisions recorded in `docs/DECISIONS.md`.

This document is the task index. Each `MW-n` below becomes its own
`TASK.md` at the repository root, in order, and is archived to
`docs/tasks/` on completion. Do not run two of them in one task.

---

## Step 0 decisions (settled)

| # | Question | Decision |
|---|---|---|
| 1 | Fullscreen | **Drop the legacy custom fullscreen; migrate to native AppKit `toggleFullScreen:`.** No behaviour from the current implementation is worth preserving. |
| 2 | Same book reopened | **Bring the existing window to the front.** |
| 3 | File ▸ Open | **Replaces the current window's book.** |
| 4 | Last window closed | **Quit the application.** |
| 5 | Startup restore | **macOS standard: restore every window that was open at quit**, not just one. |

Consequences that follow from these and are treated as settled:

- Decision 1 deletes, rather than adapts, most of `CustomWindow`
  (§MW-2). It also retires the `DontHideMenuBar` preference (native
  fullscreen auto-hides the menu bar with reveal-on-hover) and changes
  the meaning of the `Fullscreen` preference.
- Decision 2 de-duplicates on the **resolved book path**, not the URL
  that was passed in — a single image file resolves to its parent
  folder (`Controller.m:741-749`), and `public.directory` is itself a
  document type.
- Decision 4 means no empty-window state is needed: a window always
  has a book.
- Decision 5 means `NSWindowRestoration` (§MW-8), which supersedes
  part of the `OpenLastFolder` preference.

### Two assumptions carried, flagged for confirmation

Neither blocks work before the task that needs it.

- **A1 — How is a second window created?** Decisions 3 + 4 leave no
  in-app route: File ▸ Open replaces, and there is no empty window. As
  written, a second window can only come from Finder / Dock / drag
  while a book is already open. **Recommendation:** add
  **Open in New Window… (⌥⌘O)** alongside File ▸ Open. Scoped in MW-7;
  drop that sub-item if the answer is "Finder only".
- **A2 — Does a new window open in full screen?** The `Fullscreen`
  preference currently defaults to **YES**, so the app launches
  fullscreen today. **Recommendation:** retire that launch behaviour —
  new windows open windowed, full screen becomes a per-window state
  reached by the standard green button / ⌃⌘F and remembered by
  restoration. Decided in MW-2.

---

## Task list

| Task | Title | Windows | User-visible change |
|---|---|---|---|
| MW-1 | Load-time concurrency and modality safety | 1 | none |
| MW-2 | Migrate to native AppKit fullscreen | 1 | **yes** (intended) |
| MW-3 | Extract `AppController` | 1 | none |
| MW-4 | Menu actions onto the responder chain | 1 | none |
| MW-5 | `BookWindow.xib` + `BookWindowController` | 1 | none |
| MW-6 | Per-window window behaviour | 1 | none |
| MW-7 | Enable multiple windows | N | **yes** (the feature) |
| MW-8 | Window restoration | N | **yes** (intended) |
| MW-9 | Regression pass and release readiness | N | none |

MW-1 through MW-6 keep the app single-window. MW-2 and MW-8 are the
only earlier tasks that intentionally change what the user sees.

---

## MW-1 — Load-time concurrency and modality safety

**Why first:** this is the highest-risk existing code and it is fully
verifiable while the app is still single-window. It is also the one
defect that would silently corrupt input across windows later.

**Scope**

1. **Stop discarding other windows' events during archive load.**
   `-[Controller archiveReadProgress:total:]` (`Sources/Controller.m:1134`)
   pumps `[NSApp nextEventMatchingMask:NSEventMaskAny …
   dequeue:YES]` and drops every event that is not Esc.
   Required outcome: no input is silently discarded, and the load is
   visibly scoped to the window that owns it.
   Two acceptable implementations — pick one and record why:
   - *(recommended, bounded)* a progress **sheet on the loading
     window** driven by `-[NSApplication beginModalSessionForWindow:]`
     / `runModalSession:`, with Esc replaced by the sheet's Cancel
     button. Other windows become normally, visibly modal-blocked
     instead of losing events.
   - *(larger, better end state)* move `COArchive`'s read to a
     background queue and marshal progress to the main queue. Note
     that `-[COImageLoader initWithPath:…]` is synchronous and
     `openPage:last:` is written around that, so this ripples.
     If chosen, it must not be combined with any other MW task.
2. **Password prompt becomes a window sheet.**
   `-[Controller askArchivePassword:wrongPassword:]`
   (`Sources/Controller.m:1161`) uses `[alert runModal]`, blocking the
   whole app with no visible association to a window. Convert to
   `beginSheetModalForWindow:completionHandler:`. Preserve the
   existing fail-closed contract exactly: Cancel **and** an empty
   entry both return nil, and `COImageLoader` leaves the archive
   closed.
3. **Lookahead cancellation and teardown barrier.**
   Add a generation counter / cancellation token to `-lookahead` and
   `-lookaheadAndCompose`, and an explicit teardown method that
   guarantees no thread callback runs after it returns. Today
   `windowWillClose:` only does `[lock lock]; [lock unlock];`
   (`Controller.m:2904`), which waits for an in-flight pass but does
   not prevent a newly detached one, and there is no `threadCount == 0`
   barrier. This is latent only because `Controller` is a nib
   singleton that is never deallocated — MW-5 removes that safety net.
   Note `threadStop` is set/cleared at ~40 sites in
   `Controller_input.m`; do not attempt to rewrite those in this task,
   only to make teardown correct.

**Out of scope:** any ownership split; any nib change.

**Acceptance**
- Opening a large archive keeps the spinner live and Cancel works.
- Keystrokes sent during a load are either delivered or blocked by a
  visible modal state — never silently dropped.
- An encrypted ZIP prompts on a sheet attached to the window; wrong
  password re-prompts; Cancel and empty-entry both leave the previous
  book displayed.
- Closing the window mid-load and mid-lookahead does not crash and
  leaves no running thread.

**Risk:** high (threading). **Depends on:** nothing.

---

## MW-2 — Migrate to native AppKit fullscreen

**Why second:** per decision 1 this is a *deletion*, and it removes a
large share of the single-window entanglement before anything is
split — making MW-4, MW-5 and MW-6 materially smaller.

**Scope**

1. Adopt `NSWindowCollectionBehaviorFullScreenPrimary` and
   `toggleFullScreen:`. Replace the Window ▸ Fullscreen menu item with
   the standard Enter/Exit Full Screen item; the window gains the
   standard full-screen control.
2. Delete from `Sources/CustomWindow.m`: `setFullScreen:`,
   `isFullScreen`, `constrainFrameRect:toScreen:`, `setHideMenuBar:`,
   `updateTrackingRect`, `mouseEntered:`, `mouseExited:`, the
   `makeKeyAndOrderFront:` / `becomeKeyWindow` / `performClose:` /
   `performMiniaturize:` / `deminiaturize:` overrides, the ⌘M special
   case in `performKeyEquivalent:`, and every
   `[NSMenu setMenuBarVisible:]` call. Keep `keyDown:` forwarding,
   `setFrame:display:` → `setAccessoryWindowFrame`, and the cursor
   auto-hide timer (re-key it off
   `[self styleMask] & NSWindowStyleMaskFullScreen`).
3. Remove `hidesOnDeactivate="YES"` from the main window in
   `MainMenu.xib`.
4. Retire the `DontHideMenuBar` preference and its
   `dontHideMenubarCheck` UI (`Controller.m:288, 1930`;
   `PreferenceController`). Decide and record whether the stored key is
   deleted or simply ignored.
5. Resolve **A2**: what the `Fullscreen` preference means now.
   Recommendation: retire the default-YES launch-fullscreen behaviour;
   new windows open windowed.
6. Replace `[[NSScreen mainScreen] frame]` with the window's own
   screen or the view's bounds at the 9 non-`CustomWindow` sites:
   `Controller.m:1479` (`returnComposeImage:` — should use the view,
   not a screen), `Controller_input.m:2008, 2058`,
   `FullImagePanel.m:151, 225`, `ThumbnailController.m:43, 944`,
   `ThumbnailPanel.m:43, 48`.
7. Update `-[Controller validateMenuItem:]`'s Fullscreen branch
   (`Controller.m:2113`).

**Out of scope:** ownership split; the `Fullscreen`-per-window
question beyond A2 (there is still only one window).

**Acceptance**
- Green button / ⌃⌘F enters and exits full screen; the window gets its
  own Space; the menu bar reveals on hover; Mission Control behaves.
- The accessory (page-bar) child window and the loupe child window
  follow the fullscreen transition and are correctly positioned
  afterwards.
- Two-page compose, fit modes and rotation are correct in full screen
  on a non-main display.
- Minimise, deactivate and quit no longer leave the menu bar hidden.

**Risk:** medium-high (large deletion, user-visible).
**Depends on:** nothing (independent of MW-1; run after it to keep the
diffs separable).

---

## MW-3 — Extract `AppController`

**Scope** — move out of `Controller`, behaviour unchanged:

- All `NSApplicationDelegate` methods, including
  `application:openFile:` and `applicationDockMenu:`
  (`Controller.m:1191`, which currently reads the per-window
  `[imageView image]` — it must query the front window instead).
- The `awakeFromNib` defaults bootstrap and version-migration block
  (`Controller.m:32-549`), and `applicationWillTerminate:`.
- `setupRemoteControl` plus `applicationWillBecomeActive:` /
  `applicationWillResignActive:`.
- `dontSleepTimer` (`Controller_input.m:2921`) — it retains one
  controller via `target:self` and is never rebuilt.
- `prefController`, `preferences:`, `clearRecent:`, and the
  `openRecentMenuItem` / `openSameFolderMenuItem` / `bookmarkMenuItem`
  outlets.
- A **single-writer persistence API** for the `RecentItems`,
  `LastPages` and `BookSettings` defaults. The three existing
  read-modify-write blocks (`openPage:last:` ~790-880,
  `windowWillClose:` 2924-3024, `strongSetBookmark`) all route through
  it.
- A window registry (still exactly one entry).
- `PreferenceController` posts a `PreferencesDidChange` notification
  instead of calling `[controller setPreferences]`
  (`PreferenceController.m:1611`); `Controller` observes it.

`Controller` remains in `MainMenu.xib` and remains the window's
delegate — nil-targeted actions must still reach it.

**Acceptance:** single window, no behavioural difference; `Controller`
is no longer the application delegate; Open Recent, book settings and
last-page recording all still work.

**Risk:** medium. **Depends on:** MW-1, MW-2.

---

## MW-4 — Menu actions onto the responder chain

**Scope**

- Retarget the book/view actions in `MainMenu.xib` from `target="484"`
  to First Responder: `slideshow:`, `editBookmark:`,
  `changeReadModeMenu:` (×4), `changeSortModeMenu:` (×4),
  `switchSingle:`, `deleteSettings:`, `fitToScreen:`,
  `fitToScreenWidth:`, `fitToScreenWidthDivide:`, `noScale:`,
  `rotateLeft:`, `rotateRight:`.
- Keep `open:`, `openTheLastPage:`, `preferences:` and `clearRecent:`
  on `AppController`.
- The 8 `contextAction:` items on the image-view context menu
  (`RightMenu`) and `sheetOk:` / `sheetCancel:` stay connected —
  `RightMenu` moves into `BookWindow.xib` in MW-5.
  (Nib references to object 484 total 42: 9 outlets + 33 action
  targets.)
- Split `-[Controller validateMenuItem:]` along the same line. It
  dispatches on **localized menu-item titles** — 44
  `isEqualToString:NSLocalizedString(…)` branches. Preserve that
  behaviour in this task; converting it to selector-based dispatch is
  a separate follow-up, not part of this work.
- Verify no retargeted selector collides with a view method. Note the
  near-miss: `CustomImageView` declares `-rotateLeft` / `-rotateRight`
  **without** a sender argument, which are different selectors from
  `rotateLeft:` / `rotateRight:` — confirm at build time.

**Acceptance:** every retargeted menu item and its enable/disable
state behaves exactly as before, with one window and with no window
open.

**Risk:** low-medium. **Depends on:** MW-3.

---

## MW-5 — `BookWindow.xib` + `BookWindowController`

The largest mechanical task. **No logic changes in this task.**

**Scope**

1. Create `Resources/Base.lproj/BookWindow.xib` containing: the main
   window, `CustomImageView`, the progress indicator, the accessory
   (page-bar) window + `AccessoryView`, `RightMenu`, the thumbnail
   panel + `ThumbnailController` + `ThumbnailMatrix` +
   `ThumbnailMenu`, the per-book bookmark panel, the full-image panel
   + view, and the filter panel + `FilterPanelController`.
   `MainMenu.xib` keeps: the menus, Preferences and its sub-panels
   (key/mouse config, dispose-settings), and the AllBookmark panel.
   Both localizations (`Base`, `ja`) must be updated.
2. Rename `Controller` → `BookWindowController`, superclass `NSObject`
   → `NSWindowController`; `Controller_input.m` becomes its category.
   Update `CustomImageView.h` (`Controller *target;`) and the other
   `IBOutlet id controller` holders.
3. **Handle the `window` collision explicitly.** `NSWindowController`
   already declares `-window`/`-setWindow:` with its own storage;
   `Controller` has `IBOutlet id window` (`Controller.h:107`, 94
   references). Delete the ivar and route through the accessor —
   keeping both means bare `window` and `[self window]` can disagree.
4. Review `awakeFromNib` against `-windowDidLoad`, and confirm nib
   top-level object ownership under MRC with the window controller as
   File's Owner.
5. Split `BookmarkController` into a per-window part (the per-book
   Bookmark panel) and an app-wide part (the AllBookmark browser).
6. `AppController` instantiates exactly **one** `BookWindowController`.

**Acceptance:** the app is byte-for-byte equivalent in behaviour with
one window. Every panel opens, tracks the book, and closes as before.
No leaked nib top-level objects (check with Instruments or a dealloc
log).

**Risk:** high (volume). **Depends on:** MW-4.

---

## MW-6 — Per-window window behaviour

Still one window; this removes the remaining "there is only one"
assumptions.

**Scope**

- Replace the shared `saveFrameUsingName:@"NormalWindow"` /
  `setFrameUsingName:` (`CustomWindow.m:19,41`;
  `Controller.m:3062,3066`) with saved-frame-for-the-first-window plus
  `cascadeTopLeftFromPoint:` thereafter.
- Per-window frame autosave names for the panels that currently share
  one: `"Bookmark"` / `"AllBookmark"` (`BookmarkController.m:20-21`)
  and `"FilterPanel"` (`FilterPanelController.m:13`).
- Rebuild the shared main-menu state on `windowDidBecomeMain:`:
  bookmark menu, "Open from same folder" submenu, and the read-mode /
  sort-mode check-marks. Note read and sort mode are **per-book
  overrides** on a global default
  (`currentBookSetting[@"readMode"]`/`[@"sortMode"]`,
  `Controller.m:979-980, 1028-1029`), so the check-marks reflect the
  front book, not a preference.
- Replace `[window isVisible]` as the "a book is open" predicate with
  explicit controller state (`windowWillClose:` 2906,
  `openPage:last:` 757/776, `applicationDidFinishLaunching:` 580,
  `Controller_input.m:2924`).
- Fix `[[NSApp keyWindow] makeKeyAndOrderFront:self]` in
  `PreferenceController.m:1609,1628`.

**Acceptance:** no behavioural difference with one window; menu state
is rebuilt from the front window rather than assumed.

**Risk:** medium. **Depends on:** MW-5.

---

## MW-7 — Enable multiple windows

**Scope**

- `AppController` creates a `BookWindowController` per book and keeps
  the registry ordered.
- `application:openFiles:` (replacing `application:openFile:`) opens
  one window per file.
- **Decision 2:** de-duplicate on the resolved book path — if that
  book is already open, bring its window forward instead of opening a
  second.
- **Decision 3:** File ▸ Open replaces the front window's book.
- **Decision 4:** implement
  `applicationShouldTerminateAfterLastWindowClosed:` returning YES,
  and confirm the per-book persistence in `windowWillClose:` still
  completes before termination.
- **A1:** add **Open in New Window… (⌥⌘O)** — drop this sub-item if
  the owner decides Finder-only.
- Route Apple Remote events from `AppController` to the key window.
- Standard Window menu window list.

**Acceptance:** the MW-9 matrix, cases 1-6 and 10-13.

**Risk:** medium. **Depends on:** MW-6.

---

## MW-8 — Window restoration

**Scope** — decision 5.

- Implement `NSWindowRestoration`: a restoration class on
  `AppController`, `encodeRestorableStateWithCoder:` /
  `restoreStateWithCoder:` on `BookWindowController` carrying the book
  path (as a security-scoped bookmark, not a raw path), the page, and
  the per-book view mode.
- Reconcile with `OpenLastFolder` (`applicationDidFinishLaunching:`
  579-583 → `openTheLastPage:`). Recommendation: keep it as the
  fallback used only when the system restored no windows — restoration
  is governed by the system's "Close windows when quitting an app"
  setting, so the preference must not double-open a book.
- Confirm restoration interacts correctly with the native fullscreen
  state from MW-2.

**Acceptance:** quit with three books open, relaunch, and get the same
three windows at the same pages and fullscreen states; with system
window restoration disabled, `OpenLastFolder` still reopens one book
and nothing is double-opened.

**Risk:** medium. **Depends on:** MW-7.

---

## MW-9 — Regression pass and release readiness

Manual matrix, run as the acceptance gate for the whole arc. Follow
the On-Device Verification Procedure in `CLAUDE.md` for anything
touching QuickLook (nothing here should, but the app-install steps
apply).

1. ZIP and RAR shown simultaneously in separate windows.
2. Different page / reading direction / zoom / rotation per window.
3. Closing one window does not disturb the other.
4. Two archives opened consecutively, and simultaneously.
5. The password prompt attaches to the correct window.
6. Thumbnail and Bookmark panels act on their own window.
7. A Preferences change reaches every window.
8. Closing another window while a slideshow runs.
9. Full screen, minimise, application deactivation — including two
   windows where one is full screen.
10. Opening several files at once from Finder.
11. No lost `RecentItems` / `LastPages` updates across concurrent
    closes.
12. An encrypted archive and a plain archive open concurrently.
13. The same book opened twice brings the existing window forward
    (decision 2).
14. Quitting with the last window (decision 4) records state before
    terminating.
15. Folder-as-book and `.cvbdl` package open correctly in their own
    windows.

Also: build with no new warnings; `build/` contains only
`cooViewer.app`; update `docs/DEV_LOG.md` and `docs/KNOWN_ISSUES.md`.

**Depends on:** MW-8.

---

## Explicitly out of scope for the whole arc

- Any `NSDocument` migration.
- Alias Manager → `NSURL` bookmarks (`Controller.m`), except where
  MW-8 needs bookmark data for restoration.
- `[NSImage imageFileTypes]` → `imageTypes` (5 sites).
- The 4 remaining `NSRunAlertPanel` / `NSBeginAlertSheet` sites in
  `PreferenceController.m`.
- Converting `validateMenuItem:`'s 44 localized-title branches to
  selector dispatch.
- The QuickLook and Thumbnail extensions.
- Background archive loading, if MW-1 takes the modal-session route.

Each of these is a legitimate follow-up task; none is a prerequisite.
