# Multi-Window Support — Pass 2 (reconciliation & final direction)

Date: 2026-07-28
Inputs: `docs/multiwindow-pass1.md` (independent, this round),
`docs/audit-20260711.md` §2a (Claude Code, prior round),
`docs/codex-audit-20260728.md` (Codex, this round).

---

## 1. Points of agreement

All three analyses converge on the same architecture, independently:

- **Do not migrate to `NSDocument`.** Pass 1 and Codex both reject it
  explicitly, for overlapping reasons (existing custom open/recent
  logic, read-only viewer vs. save/revert/duplicate machinery,
  synchronous archive extraction vs. `readFromURL:`).
- **Split into `AppController` (app delegate) + `BookWindowController :
  NSWindowController` (one per window), with a per-window
  `BookWindow.xib`.** This is verbatim the same recommendation in
  `audit-20260711.md` ("Split into `AppDelegate` … + `BookWindowController`
  (one xib per window)"), Codex §推奨アーキテクチャ, and Pass 1 §2.
- **Do not enable multiple windows in the first task.** All three say:
  separate ownership first, keep one window, verify no regression, and
  only then allow N windows. Codex states this most emphatically
  (最終提案 #5) and Pass 1's Stage 2 acceptance criterion says the same.
- **Menu actions must move to the responder chain** (nil target /
  First Responder) so they reach the key window's controller.
- **Auxiliary controller ownership** is agreed and identical:
  `ThumbnailController` / `FilterPanelController` / `FullImagePanel` /
  `AccessoryView`+`Window` → per window; `PreferenceController` → app;
  `BookmarkController` → **split** (per-book panel per window, the
  all-books browser app-wide).
- **Apple Remote must be owned once by the app and routed to the key
  window** (exclusive-mode device).
- **`NSUserDefaults` `RecentItems` / `LastPages` / `BookSettings`
  read-modify-write must be serialized through a single owner.**
- **`CustomWindow`'s legacy fullscreen + the shared `"NormalWindow"`
  frame key conflict across windows.**
- **Preference changes must fan out to all windows**, not to one fixed
  controller.
- Overall scale: large; multiple tasks, not one.

---

## 2. Raised by Codex / the prior audit, missed by Pass 1

These are real gaps in Pass 1. All verified against the current code.

### 2.1 Synchronous archive load pumps and *discards* app-wide events

`-[Controller archiveReadProgress:total:]` (`Sources/Controller.m:1134`)
runs on the main thread during `COImageLoader` open and does:

```objc
while ((ev = [NSApp nextEventMatchingMask:NSEventMaskAny
                                untilDate:nil
                                   inMode:NSEventTrackingRunLoopMode
                                  dequeue:YES])) { … }   // Esc → cancel
```

Every dequeued event that is not Esc is **dropped**. Today that only
costs input during the one window's own load; with N windows, opening
a book in window B silently swallows keystrokes and clicks aimed at
window A, and "which load did Esc cancel?" becomes ambiguous. Pass 1
did not identify this at all. Codex is correct that this is a
first-class blocker.

### 2.2 The password prompt is app-modal, not a window sheet

`-[Controller askArchivePassword:wrongPassword:]`
(`Sources/Controller.m:1161`) uses `[alert runModal]`, which blocks the
entire application and shows no association with the window whose book
needs the password. Must become
`beginSheetModalForWindow:completionHandler:` on the requesting
window. Pass 1 mentioned the prompt only as an obstacle to
`NSDocument`, not as a multi-window defect in its own right.

### 2.3 Lookahead thread lifetime once controllers become deallocatable

Pass 1 correctly classified `lock` / `threadCount` / `threadStop` /
`imageMutableArray` as per-window, but missed the consequence Codex
raises: today `Controller` is a nib singleton that is **never
deallocated**, so a lookahead thread outliving a "closed" window is
harmless. Once each window owns a controller that must be released,
detached `@selector(lookahead)` threads (`Controller.m:1760` and
several sites in `Controller_input.m`) and their UI callbacks can
touch a torn-down window.

`windowWillClose:` does `[lock lock]; [lock unlock];` at the top
(`Controller.m:2904`), which waits for an *in-flight* lookahead, but
nothing prevents a new one being detached afterwards and there is no
`threadCount == 0` barrier. A cancellation token / generation counter
plus an explicit teardown barrier is required.

### 2.4 Dock menu is an app-level delegate reading per-window state

`-[Controller applicationDockMenu:]` (`Controller.m:1191`) branches on
`[imageView image]` — a per-window value read from an application
delegate callback. Must move to `AppController` and query the front
window (or the window registry). Pass 1 missed it entirely; Codex
lists "Dock menu" under `AppController`.

### 2.5 Behaviour spec is a mandatory gate, not an appendix

Codex "Step 0: 動作仕様を決定" makes deciding user-visible behaviour a
prerequisite. Pass 1 relegated the same material to §6 "open
questions" *after* the plan. Codex is right — the answers change the
plan itself. Codex also raises two questions Pass 1 did not:

- Does **File ▸ Open** replace the current window's book or open a new
  window?
- Does the app **quit when the last window closes**?
  (Today `applicationShouldTerminateAfterLastWindowClosed:` is not
  implemented, so the app survives with no window — and there is no
  empty-window UI to fall back to.)

### 2.6 Regression-test matrix

Codex Step 7 gives a concrete 11-case manual matrix. Pass 1 only wrote
per-stage acceptance sentences. The matrix is adopted below.

### 2.7 Nib coupling count

Codex's "42 references to object 484" is exact: 9 outlets + 33
`target="484"` actions. Pass 1 said 23, which counted only the *main
menu*. The other 10 are 8 `contextAction:` items on the image-view
context menu (`RightMenu`) plus `sheetOk:` / `sheetCancel:`. The 8
context-menu items are lower risk — that menu moves into
`BookWindow.xib` with the view — but the count in Pass 1 §4.2 is
corrected here.

### 2.8 Effort estimate

Codex: 5–8 weeks of focused work. Pass 1 gave none. The estimate is
plausible for the full arc (Steps 0–8 below); Steps 1–4, which produce
no user-visible change, are the smaller half.

---

## 3. Raised by Pass 1, missed by both prior audits

### 3.1 Book identity is not file-URL identity — the decisive anti-`NSDocument` argument

Both prior audits reject `NSDocument` on cost grounds. Pass 1 adds a
*correctness* argument neither raises: `openPage:last:`
(`Controller.m:741-749`) re-points the book at the **parent folder**
when a single image file is opened, and `public.directory` is a
declared document type (with `.cvbdl` as a package). So
`NSDocumentController`'s `fileURL`-keyed "already open" de-duplication
would be wrong for exactly the case where de-duplication matters. Any
de-dup we implement must key on the resolved **book path**, not the
URL that was passed in.

Related: the hand-rolled `RecentItems` entries carry a **page number**
(`{alias, page, temppath}`), which `NSDocumentController`'s recent
list cannot store — so the custom list survives an `NSDocument`
migration anyway, and we would maintain two.

### 3.2 The legacy fullscreen is the single largest decision, not just a conflict

Codex notes that `CustomWindow` changes menu-bar visibility
process-wide and forces `mainScreen`. Pass 1 §4.1 goes further and
this matters for planning:

- `Fullscreen` defaults to **YES** — the app launches in this mode out
  of the box, so multi-window is *first* experienced in fullscreen.
- `constrainFrameRect:toScreen:` hard-forces `[[NSScreen mainScreen]
  frame]` regardless of which screen the window is on — so two
  fullscreen windows do not merely conflict on the menu bar, they
  occupy the identical rect.
- `hidesOnDeactivate` is turned on in fullscreen.
- The state is stored as a **global default plus the single menu
  item's check-mark** (`-[Controller fullscreen:]`, `Controller.m:2864`).

Therefore an explicit choice is required, and it is a product
decision, not an implementation detail:
**(a)** keep the legacy fullscreen, made per-window (screen from
`[window screen]`, `setMenuBarVisible:` driven only from
`becomeKeyWindow`/`resignKeyWindow`), or
**(b)** migrate to native `toggleFullScreen:` /
`NSWindowCollectionBehaviorFullScreenPrimary`, which fixes menu bar,
Spaces and multi-display correctly but changes long-standing
user-visible behaviour.

### 3.3 `dontSleepTimer` is not benign

`audit-20260711.md` lists `dontSleepTimer` and `appleRemoteHoldDown`
as "process-wide; **acceptable to stay global**". For
`appleRemoteHoldDown` that is fine. `dontSleepTimer`
(`Controller_input.m:2921`) is not: it is created with
`target:self`, so it **retains one specific controller forever** and
is never rebuilt. With per-window controllers it would keep a closed
window's controller alive and stop working once that window is gone.
It must move to `AppController`.

### 3.4 `[window isVisible]` is the model's "a book is open" predicate

`windowWillClose:` (2906), `openPage:last:` (757, 776),
`applicationDidFinishLaunching:` (580) and `slideshow:`
(`Controller_input.m:2924`) all use window visibility as the state
flag, and `openPage:` **closes the window** when a book fails to load.
The app has no concept of an empty window. This has to become explicit
per-controller state, and it is what makes "New Window" (§2.5) a new
UI state rather than a menu item.

### 3.5 Panel frame-autosave collisions beyond `"NormalWindow"`

Both audits name `"NormalWindow"`. Also collide once panels are
per-window: `"Bookmark"` and `"AllBookmark"`
(`BookmarkController.m:20-21`) and `"FilterPanel"`
(`FilterPanelController.m:13`).

### 3.6 `[NSApp keyWindow]` used as "the main window"

`PreferenceController.m:1609,1628` calls
`[[NSApp keyWindow] makeKeyAndOrderFront:self]` after the preferences
sheet closes — harmless today, wrong with several windows' panels open.

### 3.7 Read/sort mode are per-book overrides on a global default

`currentBookSetting[@"readMode"]` / `[@"sortMode"]`
(`Controller.m:979-980, 1028-1029`) override the `ReadMode` default per
book. So the read-mode and sort-mode **check-marks in the shared main
menu** must be rebuilt on `windowDidBecomeMain:` — they are not a
global preference display.

### 3.8 `NSWindowController` has its own `window`

Not mentioned anywhere else, and it is a concrete trap for the rename
step: `NSWindowController` declares `-window`/`-setWindow:` backed by
its own storage. `Controller` has `IBOutlet id window`
(`Controller.h:107`, 94 references). Keeping both means
`[self window]` and bare `window` can disagree. The ivar must be
deleted and the references routed through `NSWindowController`'s
accessor (or a local `NSWindow *window = self.window;` per method).

Likewise `awakeFromNib` must be re-examined against
`-windowDidLoad`, and MRC nib top-level object ownership is handled
correctly only when the window controller is the nib's File's Owner.

### 3.9 Mechanical blast radius

Pass 1 §4.8 quantifies where the 6795 lines actually go
(`imageView` 227, `window` 94, `thumController` 27,
`openSameFolderMenuItem` 21, `defaults` 265, …). The conclusion —
that the overwhelming majority of `Controller` is per-window and moves
verbatim, and the genuinely app-global surface is small (the
`awakeFromNib` defaults/migration block, remote setup, three menu
outlets, `preferences:`, `clearRecent:`, the persistence blocks) —
supports scoping the split as a mechanical move rather than a rewrite.

---

## 4. One genuine disagreement: how `BookWindowController` relates to `Controller`

| | Codex Step 2 | Pass 1 Stage 2 |
|---|---|---|
| approach | new `BookWindowController` **contains** the existing `Controller` as a "viewing session" object | **rename** `Controller` → `BookWindowController : NSWindowController` |
| upside | no mass rename; smallest mechanical diff | no permanent indirection layer; ends in the intended shape |
| downside | permanent wrapper; nil-targeted menu actions land on the window controller, not the wrapped session, so ~25 IBActions need explicit forwarding | rename churn across 2 `.m` + 1 `.h` + the nib, plus the `window` ivar collision (§3.8) |

**Resolution: adopt Pass 1's rename, executed with Codex's discipline.**
`NSWindowController` is already the window's delegate and therefore
already sits in the responder chain, so making it the controller
itself removes the forwarding problem instead of creating it. The
rename is a mechanical, greppable change (`Controller` →
`BookWindowController`, superclass `NSObject` → `NSWindowController`)
with **no logic change in the same commit**, and the `window` ivar
collision is handled as its own explicit sub-step. Codex's underlying
concern — don't rewrite while you restructure — is honoured by keeping
the rename commit behaviour-neutral.

---

## 5. Is the original reason for "pending" still valid?

`audit-20260711.md` deferred multi-window with: *"large, mechanical but
risky refactor; recommend doing the 'quick wins' in §2c first."*
Status of those six quick wins today:

| # | Quick win | Status |
|---|---|---|
| 1 | XADWrapper retain cycle + `[archive init]` in `dealloc` (unbounded memory growth per opened archive) | **Resolved.** XADMaster/XADWrapper are gone; the engine is now `COArchive`/`COZipArchive`/`CORarArchive` on libarchive/libzip. Only attribution comments remain. |
| 2 | Delete dead files, remove `ja.xliff` from the Resources phase | **Resolved** (repo-root cleanup tasks, 2026-07-24). |
| 3 | `INFOPLIST_FILE` case fix | **Resolved** — now `Resources/Info.plist`. |
| 4 | `NSRunAlertPanel`/`NSBeginAlertSheet` → `NSAlert` | **Mostly done.** 4 sites remain, all in `PreferenceController.m`; `Controller.m` / `Controller_input.m` / `CustomImageView.m` are clean. |
| 5 | Alias Manager → `NSURL` bookmarks | **Not done** (`Controller.m` still uses `AliasHandle`/`FSRef`). |
| 6 | `imageFileTypes` → `imageTypes` | **Not done** (5 sites). |

**Verdict: the original reason for deferring is substantially resolved.**
The blocking item was #1 — a per-archive leak of the whole archive
object graph, which would have been multiplied by every open window.
That is gone. #5 and #6 are deprecation cleanups with no bearing on
window ownership; #4's remainder is confined to the app-global
preferences UI. None of them blocks this work, and none should be
folded into it (they are separate tasks).

What has **replaced** the old reason is a different, sharper list:
the app-wide event pump (§2.1), the app-modal password prompt (§2.2),
thread teardown (§2.3), and the legacy fullscreen (§3.2). These are
specific, bounded, and fixable — which is why the direction is now
"proceed", not "pending".

Codex's own conclusion ("multi-window は引き続き pending が妥当") is
a *sequencing* recommendation — do not attempt it in one task — not an
objection to proceeding. Read that way, it agrees with the task
direction.

---

## 6. Final design direction

1. **No `NSDocument`.** `AppController` (app delegate) +
   `BookWindowController : NSWindowController` (one per window) +
   `BookWindow.xib`.
2. **One window at a time throughout Steps 1–5.** Multi-window is
   switched on only in Step 6, after ownership, lifecycle and
   concurrency are safe.
3. **`Controller` is renamed, not wrapped** (§4), in a behaviour-neutral
   commit.
4. **Single writer for shared persistence.** `RecentItems` /
   `LastPages` / `BookSettings` are updated only through an
   `AppController` API.
5. **De-duplicate by resolved book path, not by URL** (§3.1).
6. **Fullscreen behaviour is a product decision taken in Step 0** (§3.2).
7. **Preferences fan out by notification** to every open window.
8. The QuickLook/Thumbnail extensions are untouched — they share no
   state with `Controller`.

---

## 7. Implementation plan

Merged from Pass 1 Stages 0–4 and Codex Steps 0–7. Each step must
build, launch, and be verified before the next. Steps 1–5 must produce
**no user-visible change**.

### Step 0 — Behaviour specification (decision only, no code)

Answer and record in `docs/DECISIONS.md`:

1. Fullscreen: keep legacy (per-window) or migrate to native? (§3.2)
2. Does opening from Finder always create a new window?
3. Same book already open → bring that window forward, or allow two?
   (recommended: bring forward, keyed on resolved book path)
4. File ▸ Open: replace current window's book, or new window?
5. Quit when the last window closes?
6. Is there an empty window / "New Window" at all? (§3.4)
7. `OpenLastFolder` at launch: one book or all previously open books?
8. Thumbnail / Bookmark panels: per window (agreed) — confirm.

### Step 1 — Concurrency & modality safety (single window)

Independent of the split, verifiable today, and the highest-risk code:

- Replace the `nextEventMatchingMask:` pump in
  `archiveReadProgress:total:` with a load that does not consume other
  windows' events (§2.1).
- Password prompt → per-window sheet (§2.2).
- Lookahead: cancellation token / generation counter + an explicit
  teardown barrier that guarantees no callback after teardown (§2.3).

### Step 2 — Extract `AppController`

Move out of `Controller`, behaviour unchanged: application-delegate
methods, the `awakeFromNib` defaults bootstrap + version migration,
`setupRemoteControl` and activate/resign hooks, `applicationDockMenu:`
(§2.4), `dontSleepTimer` (§3.3), `prefController`, `preferences:`,
`clearRecent:`, the three main-menu outlets, and the single-writer
persistence API. `PreferenceController` posts a
`PreferencesDidChange` notification instead of calling one controller.
Add the (still single-entry) window registry.

### Step 3 — Menu actions onto the responder chain

Retarget the book/view actions from `target="484"` to First Responder;
keep `open:` / `openTheLastPage:` / `preferences:` / `clearRecent:` on
`AppController`. Split `-validateMenuItem:` accordingly. Verify no
selector collides with an existing view method (note:
`CustomImageView` has `-rotateLeft`/`-rotateRight` **without** a
sender argument — different selectors from `rotateLeft:`/`rotateRight:`,
but confirm during the change).

### Step 4 — `BookWindow.xib` + `BookWindowController`

Move the main window, `CustomImageView`, progress indicator, accessory
(page-bar) window, `RightMenu`, thumbnail panel + `ThumbnailController`,
per-book bookmark panel, full-image panel/view and the filter panel
into `BookWindow.xib`. Keep menus, Preferences and sub-panels, the
AllBookmark panel and the dispose-settings panel in `MainMenu.xib`.
Rename `Controller` → `BookWindowController : NSWindowController`
(§4), including the `window` ivar removal and the
`awakeFromNib`/`windowDidLoad` review (§3.8). Split
`BookmarkController`. `AppController` instantiates exactly one window.

### Step 5 — Per-window window behaviour

Fullscreen per the Step 0 decision (§3.2); drop the shared
`"NormalWindow"` key in favour of saved-frame-for-first +
cascade-thereafter; per-window panel frame names (§3.5); rebuild
bookmark / same-folder / read-mode / sort-mode / fullscreen menu state
on `windowDidBecomeMain:` (§3.7); fix
`[NSApp keyWindow]` in `PreferenceController` (§3.6); replace
`[window isVisible]` as the "book is open" predicate (§3.4).

### Step 6 — Enable N windows

`application:openFiles:` routing; open-in-new-window; book-path
de-duplication (§3.1); Apple Remote routed to the key window;
last-window-closed policy from Step 0.

### Step 7 — Regression testing

Codex's matrix, adopted as the acceptance gate:

1. ZIP and RAR shown simultaneously in separate windows.
2. Different page / reading direction / zoom / rotation per window.
3. Closing one window does not disturb the other.
4. Two archives opened consecutively and simultaneously.
5. The password prompt attaches to the correct window.
6. Thumbnail and Bookmark panels act on their own window.
7. A Preferences change reaches every window.
8. Closing another window while a slideshow runs.
9. Fullscreen, minimise, application deactivation.
10. Opening several files at once from Finder.
11. No lost `RecentItems` / `LastPages` updates.

Plus, from Pass 1: 12. an encrypted archive and a plain archive open
concurrently; 13. the same book opened twice behaves per the Step 0
decision.

### Step 8 — Polish (optional, after Step 7 is green)

Window menu list, per-window slideshow/caffeinate review, window state
restoration (may subsume part of `OpenLastFolder`).

### Explicitly out of scope

Alias Manager → `NSURL` bookmarks; `imageFileTypes` → `imageTypes`;
the four remaining `NSRunAlertPanel` sites in `PreferenceController.m`;
QuickLook/Thumbnail extensions; any `NSDocument` migration.

---

## 8. Effort

Codex's 5–8 focused weeks is a reasonable envelope for Steps 0–7.
Steps 1–5 are the majority of the calendar time and produce no
user-visible change, which is precisely why they must not be
compressed into one task. Steps 2 and 4 are large but mechanical;
Steps 1 and 5 carry the real engineering risk.
