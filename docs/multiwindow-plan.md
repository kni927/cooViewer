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

### Assumptions carried (both now settled)

- **A1 — How is a second window created?** *(decided 2026-07-28)*
  Add **Open in New Window… (⌥⌘O)** to the File menu, alongside
  File ▸ Open. Implemented in **MW-7**, not before — MW-1 must not
  introduce it.

  Decisions 3 + 4 otherwise leave no in-app route to a second window
  (File ▸ Open replaces, and there is no empty window), so without this
  a second window could only come from Finder / Dock / drag while a book
  is already open.

  **Flagged for MW-7 — verify the shortcut before finalising it.**
  ⌥⌘O must be checked against the existing user-configurable input
  mappings before it is committed to: `KeyArray`, `KeyArrayMode2` and
  `KeyArrayMode3` in `NSUserDefaults` (defaults populated by
  `+[PreferenceController setDefaultKeyArray]` and its Mode2/Mode3
  siblings, loaded at `Controller.m:95-100`). Entries store `key` plus a
  `modifier` bitmask (option = 1, control = 2, command = 4 — see
  `CustomWindow.m:119-126`), so the collision to look for is
  `key == "o"` with `modifier == 5`. Note the menu shortcut wins over
  the app's own key handling for the key window, so a collision would
  silently disable a user's mapping rather than produce a visible
  conflict. If ⌥⌘O is taken, pick another shortcut rather than
  overriding the mapping.

  Preliminary check done 2026-07-28 — **no collision found, but this
  does not discharge the MW-7 check.** The shipped defaults bind `o`
  with `modifier = 0` (plain `o`, action 20;
  `PreferenceController.m:215-220`), and the owner's live `KeyArray`
  matches; `KeyArrayMode2` and `KeyArrayMode3` bind no `o` at all.
  Plain `o` is unaffected by an ⌥⌘O menu equivalent. Because these
  arrays are user-editable and persisted per profile, MW-7 must still
  re-check at implementation time rather than relying on this sample of
  one.

- **A2 — Does a new window open in full screen?** *(resolved by
  investigation, 2026-07-28 — decision unchanged)* New windows open
  **windowed**; full screen becomes a per-window state reached by the
  standard green button / ⌃⌘F and remembered by restoration.

  The rationale originally given for A2 was wrong and is corrected here
  — see `docs/tasks/2026-07-28-02-fullscreen-default-investigation.md`.
  It claimed the `Fullscreen` preference "defaults to YES, so the app
  launches fullscreen today". Accurately:

  - `-[Controller awakeFromNib]` **does** register `Fullscreen` = YES
    (`Controller.m:70, 74, 90`). That part was correct.
  - It does **not** follow that the app launches fullscreen. The main
    window is `visibleAtLaunch="NO"` (`MainMenu.xib:15`) — no window is
    shown at launch at all. It appears only when a book opens
    (`Controller.m:714`), and a book opens at launch only under
    `OpenLastFolder`.
  - The registered default is effectively one-shot: `Controller.m:273`
    writes the value back into the persistent domain on every launch,
    so from the second launch onward it is never consulted again.
  - **On this machine the stored value is `0`** — set by a prior
    Window ▸ Fullscreen menu toggle (`Controller.m:2864-2874` is the
    only writer of NO). Current on-device behaviour is therefore
    already non-fullscreen.

  Consequence for MW-2: retiring the launch-fullscreen behaviour is a
  **no-op for any profile that has ever toggled the menu item**, which
  lowers the risk of this part of MW-2 to nil. It is not a behaviour
  change users will notice.

  One hazard identified in the investigation and left **unverified at
  runtime**: on a genuinely fresh profile, `CustomWindow -awakeFromNib`
  reads the key (`CustomWindow.m:12`) while `Controller -awakeFromNib`
  registers the default (`Controller.m:90`), and AppKit does not define
  the relative order of `awakeFromNib` across nib objects — so the first
  launch may read NO regardless. **MW-2 resolves this by elimination:**
  removing the legacy fullscreen state removes the key, both
  `awakeFromNib` readers, and the ordering dependency entirely. No
  separate fix is needed, and the hazard must not be "fixed" in place
  ahead of MW-2.

---

## Cross-cutting constraint: image quality (read before every MW task)

The inviolable rule is at the top of `CLAUDE.md`: **no MW task may add a
resize/rescale step between the decoded image and the display.** Since
2026-07-29 there is exactly one spread path: each page is drawn straight
into the view by `-[CustomImageView drawImages:and:]`, one resampling
step. There is no intermediate composite and no compose cache.

Scan of MW-3 … MW-9 against that rule, done 2026-07-29 and revised the
same day after the legacy composited path was removed.

- **MW-3 — clean.** Nothing it moves touches the render path.

- **MW-4 — low.** It retargets `fitToScreen:`, `fitToScreenWidth:`,
  `fitToScreenWidthDivide:`, `noScale:`, `rotateLeft:` and
  `rotateRight:`, which *are* render-path actions. The task changes only
  their **target**, never their bodies. Do not "tidy" scaling logic while
  rewiring a menu item.

- **MW-5 — highest risk in the arc.** Two distinct hazards:
  1. `CustomImageView` moves into a new nib. Its rendering depends on
     state configured from outside — `setUseCalayer:` (layer-backing
     changes how AppKit resamples), `setInterpolation:`,
     `setIgnoreImageDpi:` — plus its autoresizing setup. Recreating the
     view in `BookWindow.xib` must preserve all of it. Verify by
     comparing actual rendering before and after, not by checking that
     the window "looks fine".
  2. Hazard 2 previously concerned `returnComposeImage:` and the
     `window` ivar. That method no longer exists. What remains: the
     spread geometry now comes entirely from the view
     (`-[CustomImageView getDrawImagesInfo:and:]`), so MW-5 must not
     change when or how `CustomImageView` learns its bounds — a wrong
     bounds value at draw time is now a rendering bug with no compositor
     in between to absorb it.

- **MW-6 — no longer applicable.** This flagged `screenCacheArray`, a
  cache of composed screen-resolution images that per-window controllers
  would have multiplied. **The composited path and its cache were deleted
  on 2026-07-29** (`docs/tasks/2026-07-29-02-remove-legacy-composited-path.md`),
  so there is nothing left to multiply. Nothing to do in MW-6.

- **MW-7 — no longer applicable.** This flagged the compose cache being
  keyed by page pair + `fitScreenMode` but not by screen, with no
  invalidation on a screen change (`KNOWN_ISSUES` #21). **Resolved by
  deletion** in the same task: there is no compose cache. `KNOWN_ISSUES`
  #21 is closed. Nothing to do in MW-7.

- **MW-8 — clean.** Restoring into full screen re-enters
  `-recomposeForCurrentSize` via `windowDidEnterFullScreen:`, which is
  the existing path. Restorable state must carry the book path, page and
  view mode only — never a rendered image.

- **MW-9 — gap.** The matrix as written verifies behaviour but nothing
  verifies *rendering*. Case 16 has been added for this.

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
5. Retire the `Fullscreen` preference entirely (**A2**, resolved).
   Remove the registered default (`Controller.m:70, 74`), the
   write-back (`:273`), both `awakeFromNib` readers
   (`Controller.m:199`, `CustomWindow.m:12`), and both menu-item
   uncheck sites (`Controller.m:200-202`, `CustomWindow.m:23`). New
   windows open windowed; full screen is per-window and carried by
   restoration (MW-8). Decide and record whether the stored key is
   deleted or left orphaned.
   This also collapses the **third source of truth** for the state: the
   Window ▸ Fullscreen menu item's `state`, hardcoded `state="on"` in
   the nib (`MainMenu.xib:339`), read as authoritative by
   `FullImagePanel.m:27, 209`, and driven by the `SwitchFullscreen`
   key/mouse actions via `performActionForItemAtIndex:`
   (`Controller_input.m:772-781` case 49, `1762-1771` case 61). Those
   two input actions must be re-pointed at `toggleFullScreen:`.
   Removing the key is also what resolves the fresh-install
   `awakeFromNib` ordering hazard (see A2) — by elimination, not by a
   separate fix.
6. Replace `[[NSScreen mainScreen] frame]` with **the window's own
   screen** at the 9 non-`CustomWindow` sites: `Controller.m:1479`
   (`returnComposeImage:`), `Controller_input.m:2008, 2058`,
   `FullImagePanel.m:151, 225`, `ThumbnailController.m:43, 944`,
   `ThumbnailPanel.m:43, 48`.

   **Corrected 2026-07-29.** This item originally said
   `returnComposeImage:` "should use the view, not a screen". That was
   wrong and was **not** implemented; only *which screen* is measured
   changed at that site. The reason to keep a screen-sized canvas is
   that the composite is cached and reused across window sizes, so it
   can always be downscaled to the current view rather than upscaled
   after a window enlargement.

   A first version of this note justified it as "composing at view size
   would add a second resampling step". That was imprecise — for a view
   smaller than the screen it would *remove* one. See the two-path table
   at the top of `CLAUDE.md`: this whole site is on the composited
   ("Old") path, which costs two resampling steps either way and is not
   the default. The default and higher-quality path draws each page
   straight into the view and never reaches this code.

   **Superseded 2026-07-29:** the composited path was removed entirely,
   so `returnComposeImage:` and this site no longer exist. Retained as a
   record of what MW-2 actually did.
7. Update `-[Controller validateMenuItem:]`'s Fullscreen branch
   (`Controller.m:2113`).

**Out of scope:** ownership split; per-window fullscreen state (there is
still only one window); the `Controller.m:273` write-back pattern as a
general problem — see `docs/KNOWN_ISSUES.md`. MW-2 removes the
`Fullscreen` key's own instance of it and nothing else.

**Acceptance**
- Green button / ⌃⌘F enters and exits full screen; the window gets its
  own Space; the menu bar reveals on hover; Mission Control behaves.
- The `SwitchFullscreen` key and mouse actions still toggle full screen.
- The accessory (page-bar) child window and the loupe child window
  follow the fullscreen transition and are correctly positioned
  afterwards.
- Two-page compose, fit modes and rotation are correct in full screen
  on a non-main display.
- Minimise, deactivate and quit no longer leave the menu bar hidden.

**Risk:** medium-high (large deletion, user-visible). Note that the
*preference* half is lower risk than originally assumed: on any profile
that has ever toggled Window ▸ Fullscreen off, the stored value is
already `0` and retiring it changes nothing the user sees (see A2).
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

### Findings from the pre-implementation inventory (2026-07-29)

Four things the scope list above does not say, established by reading the
code before starting. They change the shape of the work.

1. **`applicationDidFinishLaunching:` cannot simply move — it must
   split.** Almost its whole body is window-level: it pushes `keyArray`
   into `fullImagePanel` and `thumController`, derives the drag-scroll
   maps from `mouseArrayMode2/3` and pushes them into `imageView`, and
   ends with the `OpenLastFolder` → `openTheLastPage:` call gated on
   `[window isVisible]`. `AppController` should own the delegate method
   and forward the per-window half to the window controller.

2. **The menu outlets move but their builders do not.**
   `setBookmarkMenu`, `setSameFolderMenu:`, `setOpenRecentMenu` and
   `menuNeedsUpdate:` all read per-window book state (`bookmarkArray`,
   `currentBookPath`). Decision: `AppController` owns
   `openRecentMenuItem` / `openSameFolderMenuItem` / `bookmarkMenuItem`
   and exposes them via accessors; the builder methods stay on
   `Controller` and reach the items through those accessors. Rebuilding
   them when the front window changes is MW-6's job, not MW-3's.

3. **Put `registerDefaults:` in `+initialize` (or `main.m`), not in
   `-awakeFromNib`.** Registering from a nib object's `awakeFromNib`
   makes the registration race every other nib object's `awakeFromNib`
   — the hazard behind `docs/KNOWN_ISSUES.md` #19, and the reason the
   pre-MW-2 `Fullscreen` default was unreliable on a fresh profile.
   `+initialize` runs before any instance exists, so it cannot lose that
   race. Checked: the only other nib object that touches
   `NSUserDefaults` in `awakeFromNib` is `BookmarkController`
   (`AllBookmarkSplitPotision`), and that key is not registered, so
   nothing else depends on the current ordering. Note the bootstrap
   block assigns the `bufferingMode` **ivar** while building the
   dictionary — use a local when hoisting it to `+initialize`.
   This does **not** mean fixing #19's write-back pattern generally;
   that stays out of scope.

4. **The Apple Remote delegate method is in the other file.**
   `remoteButton:pressedDown:clickCount:` is at
   `Controller_input.m:11`, not in `Controller.m`, and moves with
   `setupRemoteControl` and the `applicationWillBecomeActive:` /
   `applicationWillResignActive:` pair. `appleRemoteHoldDown`
   (`Controller_input.m:8`, file-scope static) goes with it.

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
16. **Image quality unchanged from the pre-MW baseline.** The rest of
    this matrix checks behaviour, not rendering, and the whole arc must
    not cost a single resampling step (see the cross-cutting constraint
    above and the top of `CLAUDE.md`).

    **Simplified 2026-07-29.** This case previously had to be run three
    times (16a/16b/16c) because two spread-rendering paths existed and
    shared no code. The legacy composited path (`BufferingMode = 0`) has
    since been deleted, so **there is now exactly one path** — each page
    drawn straight into the view by `-[CustomImageView drawImages:and:]`,
    one resampling step — and `BufferingMode` / `ScreenCache` no longer
    do anything. One run covers everything.

    Capture the same page from the same fixture, at the same window size
    and `fitScreenMode`, on a pre-MW-1 build and on the final build, as a
    single-page view **and** as a two-page spread, and compare the pixels
    — mean absolute difference and a sharpness measure, not a visual
    check.

    Note when choosing the baseline build: a pre-2026-07-29 build with
    `BufferingMode = 0` will *not* match, and that is expected — the two
    paths laid spreads out differently (the composited one scaled each
    page independently, giving mismatched heights). Take the baseline
    with `BufferingMode = 1`, which is the default and renders identically
    across the removal.

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
