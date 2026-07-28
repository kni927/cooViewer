# Multi-Window Support — Pass 1 (independent investigation)

Date: 2026-07-28
Scope: current codebase only. Written before reading
`docs/audit-20260711.md` or `docs/codex-audit-20260728.md`.

---

## 1. Current architecture

cooViewer is a **non-document, single-nib, single-window** AppKit app.

- `Resources/Base.lproj/MainMenu.xib` is the only nib
  (`NSMainNibFile = MainMenu`). It contains *everything*: the main
  window, every panel, and every controller object as a top-level
  `customObject`.
- `Controller` (`Sources/Controller.m`, 3675 lines +
  `Controller_input.m`, 3120 lines) is simultaneously:
  - the `NSApplication` delegate (File's Owner outlet
    `delegate → 484` in the nib),
  - the window/view controller for the single main window,
  - the book/document model (path, page list, page cache, bookmarks),
  - the persistence layer for `RecentItems` / `LastPages` /
    `BookSettings` in `NSUserDefaults`.
- `Info.plist` declares 20 `CFBundleDocumentTypes` and **no**
  `NSDocumentClass`. `NSDocumentController` is never used.
- Collaborators do **not** reach the controller through a global or
  `[NSApp delegate]` — they hold an IB outlet named `controller`
  (`ThumbnailController`, `BookmarkController`, `PreferenceController`,
  `CustomWindow`, `AccessoryView`). There is no `sharedController`
  singleton and almost no file-scope mutable state. This is the single
  most favourable fact for multi-window work.

Object graph, per current nib:

```
NSApplication (File's Owner) ──delegate──▶ Controller (id 484)
                                             │
   window  ──────────────────────────────────┤ CustomWindow (21)
   imageView ────────────────────────────────┤ CustomImageView (263)
   progressIndicator ────────────────────────┤ (2051)
   thumController ───────────────────────────┤ ThumbnailController (1113) → ThumbnailPanel (1084)
   bookmarkController ───────────────────────┤ BookmarkController (617) → BookmarkPanel (561), AllBookmarkPanel (983)
   fullImagePanel / fullImageView ───────────┤ FullImagePanel (772) / FullImageView (777)
   prefController ───────────────────────────┤ PreferenceController (1673) → Preferences (448), KeyConfigPanel (520), MouseConfigPanel (1436)
   openRecentMenuItem / openSameFolderMenuItem / bookmarkMenuItem ─┘ (main menu items)

CustomImageView ──child window──▶ AccessoryWindow (2809) / AccessoryView  (page bar)
                └─child window──▶ lensWindow (loupe, created in code)
FilterPanelController (7Ik-II-pge) → Filter panel (EcN-5h-84Q)   [no controller outlet]
```

---

## 2. NSDocument vs. multiple NSWindowControllers

### What NSDocument would buy

`NSDocument` + `NSDocumentController` would provide for free: one
window per file, `application:openFiles:` handling, "already open →
bring that window forward" de-duplication, window cascading, Open
Recent, and window state restoration.

### Why it is the wrong fit here

1. **The app already reimplements the parts it would gain.**
   Open Recent is a hand-rolled `RecentItems` array in
   `NSUserDefaults` that stores `{alias, page, temppath}` — the
   *page number* is the point of it (`openFromOpenRecent:`,
   `openTheLastPage:`). `NSDocumentController`'s recent-documents list
   cannot carry that payload, so the custom list must survive anyway
   and we would be maintaining two recent lists.
2. **A "document" here is frequently a folder.**
   `public.directory` is a declared document type (and `.cvbdl` is a
   package, `LSTypeIsPackage = true`). `NSDocument` can be pointed at a
   directory URL, but the whole read/write/save/autosave/versions/
   `isDocumentEdited` machinery is dead weight for a read-only viewer
   and has to be explicitly disabled (`isDocumentEdited` → NO,
   `autosavesInPlace` → NO, `+readableTypes`, save menu suppression).
3. **Opening is asynchronous and interactive.**
   `COImageLoader` reports progress through
   `-[Controller archiveReadProgress:total:]` (which pumps the event
   loop with `nextEventMatchingMask:`) and can put up a **modal
   password sheet** (`askArchivePassword:wrongPassword:`).
   `NSDocument -readFromURL:ofType:error:` is a synchronous, non-UI
   contract; wiring this in means fighting the framework
   (`canConcurrentlyReadDocumentsOfType:` = NO, custom
   `openDocumentWithContentsOfURL:display:completionHandler:`).
4. **Book identity is not URL identity.**
   Opening a single image file re-points the book at its *parent
   folder* (`openPage:last:` lines 741–749). `NSDocument`'s
   `fileURL`-keyed de-duplication would therefore be wrong for exactly
   the case where de-duplication matters.
5. The nib/menu rework (section 5) is required under either option, so
   NSDocument does not reduce the work — it adds to it.

### Recommendation

**Multiple `NSWindowController`s.** Split `Controller` into:

| New class | Role | Lifetime |
|---|---|---|
| `AppController : NSObject <NSApplicationDelegate>` | defaults bootstrap + version migration, remote control, Preferences, global persistence (`RecentItems` / `LastPages` / `BookSettings`), `application:openFiles:`, main-menu maintenance, window registry | one, from `MainMenu.xib` |
| `BookWindowController : NSWindowController` | one book: window, image view, page state, caches, bookmarks, thumbnail/bookmark/full-image/accessory/filter panels, slideshow, all input handling | one per window, from a new `BookWindow.xib` |

`Controller_input.m` becomes a category on `BookWindowController`
essentially unchanged — its state (`nowPage`, `marksArray`,
`imageView`, `window`, …) is all per-window.

De-duplication ("same book already open") is then implemented
explicitly against the *book path* rather than a URL, which is what
this app actually needs.

---

## 3. Shared vs. per-window state

### Must stay per-window

Book identity and page state:
`currentBookPath` / `currentBookName` / `currentBookAlias`,
`oldBook*`, `currentBookSetting`, `nowPage`, `imageLoader`,
`completeMutableArray`, `imageMutableArray`, `marksArray`,
`bookmarkArray`.

Rendering and caches:
`cacheArray`, `screenCacheArray`, `firstImage` / `secondImage` /
`composedImage` / `useComposedImage`, `lock`, `threadCount`,
`threadStop`, `lastArchiveProgressPump`.

Per-book view mode (global default, per-book override — see
`currentBookSetting[@"readMode"]`, `[@"sortMode"]`):
`readMode`, `sortMode`, `rotateMode`, `fitScreenMode`, `fitMode`,
`useComposedImage`.

Per-window UI:
`window`, `imageView`, `progressIndicator`, `thumController`,
`bookmarkController` (per-book panel), `fullImagePanel` /
`fullImageView`, accessory (page-bar) window, loupe window, filter
panel, slideshow `timer` / `timerSwitch`.

### Must stay app-global (one instance)

- `remoteControl` / `remoteControlBehavior` — `AppleRemote` is opened
  with `setOpenInExclusiveMode:YES`; a second instance would fail or
  steal the device. Events must be **routed to the key window's**
  controller.
- `prefController` and its panels (Preferences, key/mouse config,
  dispose-settings, font panel).
- `BookmarkController`'s **AllBookmark** panel (cross-book bookmark
  browser) — as opposed to the per-book Bookmark panel, which is
  per-window. `BookmarkController` currently owns both; this class has
  to be split.
- The main menu itself, including `openRecentMenuItem`,
  `openSameFolderMenuItem`, `bookmarkMenuItem`, the read-mode /
  sort-mode check-marks, and the Fullscreen check-mark. These are
  single instances whose *contents reflect the front book*, so they
  must be rebuilt on `windowDidBecomeMain:`.
- `dontSleepTimer` (`Controller_input.m:2921`, file-scope `static`) —
  conceptually one caffeinate timer for the app, but it currently
  retains one specific controller as `target:` and is never rebuilt,
  so with multiple windows it would keep a dead controller alive and
  stop working when that window closes.
- `appleRemoteHoldDown` (`Controller_input.m:8`, file-scope `static`).
- `NSMenu setMenuBarVisible:` state — global by definition (see §4).

### Shared persistent state (one writer needed)

`NSUserDefaults` keys `RecentItems`, `LastPages`, `BookSettings` are
read-modify-**written wholesale** in three places
(`openPage:last:` ~790–880, `windowWillClose:` 2924–3024,
`strongSetBookmark`). Each site re-reads the current value first, so
sequential main-thread writes are safe, but:

- two windows on the **same book** will silently overwrite each
  other's page/bookmark record (last close wins);
- `setOpenRecentMenu` must be re-run on *all* windows' behalf when any
  window writes.

Recommendation: move these three read-modify-write blocks behind an
`AppController` API (`-recordBookState:` / `-noteRecentBook:page:`) so
there is exactly one writer, and de-duplicate windows by book path so
the same-book case cannot arise.

### Preferences

All preference-derived ivars (`cacheSize`, `screenCache`,
`interpolation`, `bufferingMode`, `maxEnlargement`,
`wheelSensitivity`, `keyArray*`, `mouseArray*`, `openRecentLimit`,
`alwaysRememberLastPage`, `goToLastPageMode`, `openLinkMode`,
`changeCurrentFolderMode`, `rememberBookSettings`, `readSubFolder`,
`pageBar`, `numberSwitch`, `resolutionSwitch`, `prevPageMode`,
`canScrollMode`, `loopCheck`, `sliderValue`) are global values
*mirrored* into the controller. `PreferenceController` currently
notifies exactly one controller (`[controller setPreferences]`,
`PreferenceController.m:1611`). This must fan out to every open
window — cleanest as an `NSNotification` that each
`BookWindowController` observes.

### QuickLook / Thumbnail extensions

Out of scope. `PreviewExtension` / `ThumbnailExtension` are separate
processes that use `COArchive` / `COCoverExtractor` only; they share
no state with `Controller` and are unaffected.

---

## 4. Inventory of single-window assumptions

Ordered by blast radius.

### 4.1 Legacy custom fullscreen — **highest risk**

`CustomWindow` implements a hand-rolled fullscreen that predates
`NSWindowCollectionBehaviorFullScreenPrimary`:

- `setFullScreen:` resizes to `[[NSScreen mainScreen] frame]` — always
  the *main* screen, not the window's own screen;
- `constrainFrameRect:toScreen:` forces that same rect;
- `setHideMenuBar:`, `becomeKeyWindow`, `mouseEntered:`,
  `mouseExited:`, `performClose:`, `performMiniaturize:`,
  `deminiaturize:` all call the **global** `[NSMenu setMenuBarVisible:]`;
- the flag is stored as the **global** default `Fullscreen`
  (default **YES** — the app launches fullscreen out of the box), and
  `-[Controller fullscreen:]` toggles that global default plus the
  single menu item's check-mark;
- `hidesOnDeactivate` is set to YES in fullscreen.

Two "fullscreen" windows would occupy the same rect on the same
screen and fight over menu-bar visibility. This is the one place where
multi-window is not merely a refactor.

Options: (a) make `fullscreen` per-window, key the screen off
`[window screen]`, and drive `setMenuBarVisible:` only from
`becomeKeyWindow` / `resignKeyWindow` of the fullscreen window; or
(b) migrate to native fullscreen (`toggleFullScreen:`), which solves
menu bar, spaces and multi-display correctly but changes long-standing
user-visible behaviour. Decide explicitly; do not leave it implicit.

### 4.2 Menu items hard-wired to the single Controller

23 of 38 main-menu actions are connected with `target="484"` — a
direct pointer to the one `Controller` instance:

```
preferences:  open:  openTheLastPage:  clearRecent:  slideshow:
editBookmark:  changeReadModeMenu: (×4)  changeSortModeMenu: (×4)
switchSingle:  deleteSettings:  fitToScreen:  fitToScreenWidth:
fitToScreenWidthDivide:  noScale:  rotateLeft:  rotateRight:
fullscreen:
```

Every book/view action among these must be retargeted to **First
Responder** (nil target) so the responder chain delivers it to the key
window's controller. `preferences:` and `clearRecent:` stay app-level
and move to `AppController`. `-validateMenuItem:` (Controller.h:208)
moves with them and must be split the same way.

Note that `CustomWindow -keyDown:` already forwards to
`[controller keyAction:]` through its own outlet, so keyboard input is
already per-window once each window has its own controller — only the
menu is centralised.

### 4.3 Window frame autosave

`saveFrameUsingName:@"NormalWindow"` / `setFrameUsingName:` in
`CustomWindow.m:19,41` and `Controller.m:3062,3066`. A single shared
name means every window snaps to the same frame. Needs cascading
(`NSWindow -cascadeTopLeftFromPoint:`) with the saved frame used only
for the first window.

`BookmarkController.m:20-21` (`Bookmark`, `AllBookmark`) and
`FilterPanelController.m:13` (`FilterPanel`) have the same problem for
their panels.

### 4.4 `[window isVisible]` as the "is a book open" flag

`windowWillClose:` (2906), `slideshow:` (`Controller_input.m:2924`),
`applicationDidFinishLaunching:` (580) and `openPage:last:` (757,776)
use window visibility as the model's "a book is loaded" predicate, and
`openPage:` closes the window when a book fails to load. With N
windows this needs an explicit per-controller state and a decision on
"what does the app show when no book is open" (currently: nothing —
there is no empty window).

### 4.5 `[NSApp keyWindow]` used as "the main window"

`PreferenceController.m:1609,1628` calls
`[[NSApp keyWindow] makeKeyAndOrderFront:self]` after the preferences
sheet closes. Harmless today, wrong once panels from several windows
are open.

### 4.6 `application:openFile:` (single file only)

`Controller.m:646` implements the legacy single-file delegate and
always replaces the current book. Multi-window needs
`application:openFiles:` (or `application:openURLs:`) so a multi-file
Finder selection opens N windows, plus a policy for "already open".

### 4.7 File-scope statics

`dontSleepTimer`, `appleRemoteHoldDown` (see §3). Small but real.

### 4.8 Blast radius, mechanically

Identifier occurrences across `Controller.m` + `Controller_input.m`
(6795 lines total):

| symbol | refs | destination |
|---|---|---|
| `defaults` | 265 | split: bootstrap → AppController, reads → both |
| `imageView` | 227 | BookWindowController |
| `window` | 94 | BookWindowController |
| `thumController` | 27 | BookWindowController |
| `fullImageView` | 24 | BookWindowController |
| `openSameFolderMenuItem` | 21 | AppController (rebuilt per front window) |
| `fullImagePanel` | 20 | BookWindowController |
| `bookmarkMenuItem` | 7 | AppController (rebuilt per front window) |
| `progressIndicator` | 6 | BookWindowController |
| `bookmarkController` | 3 | split (per-book panel vs. AllBookmark) |
| `prefController` | 3 | AppController |
| `openRecentMenuItem` | 3 | AppController |

The overwhelming majority of `Controller` is per-window and moves
verbatim. The genuinely app-global surface is small: the `awakeFromNib`
defaults bootstrap/migration block (lines 32–549), remote control
setup, the three menu outlets, `preferences:`, `clearRecent:`, and the
recents/booksettings persistence blocks.

---

## 5. Staged implementation plan

Each stage must build, launch, and behave identically to the previous
one unless the stage's own goal says otherwise.

### Stage 0 — Responder-chain preparation (no visible change)

- Retarget the 21 book/view menu actions from `target=484` to First
  Responder in `MainMenu.xib`; leave `preferences:` and `clearRecent:`
  on the Controller for now.
- Verify every retargeted action and its `validateMenuItem:` still
  works with the one existing window.
- Acceptance: no behavioural difference, single window.

### Stage 1 — Split `AppController` out of `Controller`

- New `AppController` becomes the `NSApplication` delegate; takes the
  `awakeFromNib` defaults bootstrap + version migration,
  `setupRemoteControl` and the activate/resign hooks, `prefController`,
  `openRecentMenuItem` / `openSameFolderMenuItem` / `bookmarkMenuItem`,
  `preferences:`, `clearRecent:`, `applicationWillTerminate:`,
  `application:openFile:`.
- Introduce the single-writer persistence API for `RecentItems` /
  `LastPages` / `BookSettings` and move the three read-modify-write
  blocks behind it.
- Introduce a `PreferencesDidChange` notification;
  `PreferenceController` posts it instead of calling
  `[controller setPreferences]` directly.
- `Controller` stays in `MainMenu.xib` as the sole window controller.
- Acceptance: single window, identical behaviour, `Controller` no
  longer the app delegate.

### Stage 2 — Extract `BookWindow.xib` / `BookWindowController`

- Move the main window, `CustomImageView`, progress indicator,
  accessory (page-bar) window, thumbnail panel + `ThumbnailController`,
  per-book bookmark panel, full-image panel + view, and the filter
  panel into a new `BookWindow.xib`.
- Keep in `MainMenu.xib`: menus, Preferences and its sub-panels,
  AllBookmark panel, dispose-settings panel.
- Rename `Controller` → `BookWindowController : NSWindowController`;
  `Controller_input.m` becomes its category.
- Split `BookmarkController` into a per-window part and the global
  AllBookmark browser.
- `AppController` instantiates exactly **one** `BookWindowController`
  at launch.
- Acceptance: still one window, still identical behaviour. **This is
  the minimum viable step** — after it, "N windows" is a policy change
  rather than a refactor.

### Stage 3 — Actually allow N windows

- `AppController` keeps an ordered registry of open
  `BookWindowController`s.
- Implement `application:openFiles:`; open-in-new-window; a `New
  Window` / ⌘N-equivalent entry point; and same-book de-duplication by
  book path (bring the existing window forward instead of opening a
  second).
- Per-window fullscreen decision from §4.1 implemented.
- Per-window frame handling: saved frame for the first window,
  cascading afterwards.
- Rebuild bookmark / same-folder / read-mode / sort-mode / fullscreen
  menu state on `windowDidBecomeMain:`.
- Route Apple Remote and `dontSleepTimer` through `AppController` to
  the key window.
- Acceptance: two books open side by side; page state, bookmarks and
  recents for both are recorded correctly on close.

### Stage 4 — Polish

- Window menu with the standard window list
  (`[NSApp addWindowsItem:]` or `NSWindowController` defaults).
- Per-window slideshow and caffeinate behaviour.
- Window state restoration (`NSWindowRestoration`) so open books come
  back after relaunch — this can replace part of the
  `OpenLastFolder` behaviour.
- Revisit "what shows when no book is open".

---

## 6. Open questions for the project owner

1. **Fullscreen**: keep the legacy custom fullscreen (made
   per-window), or migrate to native `toggleFullScreen:`? This changes
   user-visible behaviour and the `Fullscreen`-defaults-YES launch
   experience. It is the largest single decision.
2. **Same book opened twice**: bring the existing window forward
   (recommended, matches `NSDocumentController`) or genuinely allow
   two windows on one book (then per-book persistence needs a
   conflict rule)?
3. **How is a second window created?** Only by opening a second file
   from Finder / Open panel, or also an explicit "New Window" menu
   item that opens an empty window (which the app has no concept of
   today)?
4. **Does `OpenLastFolder` restore one book or all previously open
   books?**

## 7. Pass 1 conclusion

Multi-window is **feasible without an NSDocument migration**, and the
NSWindowController route is clearly preferable here (§2). The
codebase is unusually well-positioned for it — collaborators already
reach the controller through an injected outlet rather than a
singleton, and there is essentially no global mutable state.

The real cost is concentrated in three places, not in the 6795 lines
of `Controller`:

1. the legacy custom fullscreen in `CustomWindow` (§4.1),
2. the 23 menu items wired directly to the one controller instance
   (§4.2),
3. splitting one monolithic nib into an app nib and a per-window nib
   (Stage 2).

Stages 0–2 are pure refactors with no user-visible change and can be
verified against current behaviour at each step; Stage 3 is where
multi-window actually appears.
