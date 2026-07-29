# MW-5 — BookWindow.xib + BookWindowController

## Context

MW-4 is done and pushed (commit 3d88521). This is the largest mechanical
task in the arc — **no logic changes**, per `docs/multiwindow-plan.md`.
Risk is rated **high**, driven by volume rather than complexity. Read the
cross-cutting image-quality constraint at the top of `CLAUDE.md` before
starting — this task moves `CustomImageView`, which is on the render path,
even though it changes no rendering logic.

## Scope (from docs/multiwindow-plan.md)

1. Create `Resources/Base.lproj/BookWindow.xib` containing: the main
   window, `CustomImageView`, the progress indicator, the accessory
   (page-bar) window + `AccessoryView`, `RightMenu`, the thumbnail panel +
   `ThumbnailController` + `ThumbnailMatrix` + `ThumbnailMenu`, the
   per-book bookmark panel, the full-image panel + view, and the filter
   panel + `FilterPanelController`. `MainMenu.xib` keeps: the menus,
   Preferences and its sub-panels (key/mouse config, dispose-settings),
   and the AllBookmark panel. Both localizations (`Base`, `ja`) must be
   updated.
2. Rename `Controller` → `BookWindowController`, superclass `NSObject` →
   `NSWindowController`; `Controller_input.m` becomes its category.
   Update `CustomImageView.h` (`Controller *target;`) and other
   `IBOutlet id controller` holders.
3. **Handle the `window` collision explicitly.** `NSWindowController`
   already declares `-window`/`-setWindow:` with its own storage;
   `Controller` has `IBOutlet id window` (`Controller.h:107`, 94
   references). Delete the ivar and route through the accessor — keeping
   both means bare `window` and `[self window]` can disagree.
4. Review `awakeFromNib` against `-windowDidLoad`, and confirm nib
   top-level object ownership under MRC with the window controller as
   File's Owner.
5. Split `BookmarkController` into a per-window part (the per-book
   Bookmark panel) and an app-wide part (the AllBookmark browser).
6. `AppController` instantiates exactly **one** `BookWindowController`.

## Acceptance

The app is byte-for-byte equivalent in behavior with one window. Every
panel opens, tracks the book, and closes as before. No leaked nib
top-level objects (check with Instruments or a dealloc log).

## Should this be split into sub-commits?

Yes — recommended, same reasoning as MW-3. Before writing code, check
whether these six items decompose into independently-buildable,
independently-verifiable pieces, given the size and the risk of leaving
the app half-migrated if the session runs out of budget. A reasonable
first cut (confirm/revise after actually reading the code, as MW-3's
own pre-implementation inventory did):

- **Commit A — item 3 (`window` collision) in isolation**, if it can be
  done against the *current* `Controller` before the rename — smallest,
  most mechanical, and removes a latent footgun early.
- **Commit B — items 1+2 together** (new xib + rename + superclass
  change): these are likely inseparable, since the rename only makes
  sense once the class is the window controller for the new xib's File's
  Owner.
- **Commit C — item 4** (`awakeFromNib`/`windowDidLoad`/ownership review):
  do this as part of B if it surfaces naturally, or as a fast follow-up
  if it needs its own focused pass.
- **Commit D — item 5** (`BookmarkController` split): touches a
  different class with its own panel, plausibly separable from the
  window/xib work.
- **Commit E — item 6** (`AppController` instantiates one
  `BookWindowController`): small, wires B through D together, natural
  last commit.

Land B before D/E — nothing downstream works until the rename and new
xib exist. State the final breakdown and why before writing code, the
same way the MW-3 session did.

## Verification (per each commit, and again at the end)

- Build with the documented command
  (`BUILD_TMP=... xcodebuild ... -scheme cooViewer_deploy -configuration Deployment ...`),
  zero new warnings.
- No image-quality regression: confirm no code sits between decode and
  `drawInRect:` beyond what already existed (per CLAUDE.md's inviolable
  rule) — MW-5's hazard #1 in the cross-cutting scan is specifically that
  `CustomImageView`'s external configuration (`setUseCalayer:`,
  `setInterpolation:`, `setIgnoreImageDpi:`, autoresizing) must be
  preserved exactly when it moves into the new nib. **Verify by comparing
  actual rendering before and after, not by checking that the window
  "looks fine."**
- Hazard #2: the spread geometry now comes entirely from the view
  (`-[CustomImageView getDrawImagesInfo:and:]`) — this task must not
  change when or how `CustomImageView` learns its bounds.
- On-device (screen sharing / GUI Claude Code, per current setup): every
  panel (thumbnail, bookmark, full-image, filter, accessory page-bar)
  opens, tracks the book, and closes correctly; no leaked nib top-level
  objects.
- Follow `docs/task-workflow.md` on completion: append the Implementation
  Result to this file, archive to `docs/tasks/2026-07-29-NN-mw5-...md`
  (one archive per sub-commit or one for the whole task — match whatever
  granularity the actual commit breakdown ends up being), update
  `docs/DECISIONS.md` / `docs/DEV_LOG.md` / `docs/KNOWN_ISSUES.md`.

## Session-budget checkpoint

If the full task can't be finished and verified this session, stop after
whichever commit leaves the app in a fully working, single-window state —
never mid-rename or with the xib half-populated. Update this TASK.md with
exact remaining steps before stopping.

## Depends on

MW-4 (done, pushed).

Risk noted in the plan: **high** (volume).

---

## Implementation Result

**Status:** Completed with follow-up issues

All six scope items are implemented, built, and verified on device with one
window. Two pre-existing defects were found while verifying and are recorded
in `docs/KNOWN_ISSUES.md` rather than fixed here (this task is
no-logic-change by definition).

### Commit breakdown (revised before writing code, as instructed)

TASK.md's first cut proposed A(item 3) → B(items 1+2) → C(item 4) →
D(item 5) → E(item 6), with "land B before D/E". Reading the code changed
that ordering in one place, and merged three items:

- **Item 5 must come *before* items 1+2, not after.** `BookmarkController`
  was a single nib object owning *two* panels with different lifetimes: the
  per-book Bookmark sheet (destined for `BookWindow.xib`) and the app-wide
  All Bookmark browser (staying in `MainMenu.xib`). One nib object cannot own
  top-level objects in two nibs, so the class split is a prerequisite for the
  nib split, not an independent follow-up.
- **Items 1, 2, 4 and 6 are one commit.** The rename only makes sense once
  the class is File's Owner of the new nib (1+2 were already judged
  inseparable); the `-awakeFromNib`/`-windowDidLoad` review (4) is forced by
  becoming an `NSWindowController` rather than optional; and once
  `MainMenu.xib` stops instantiating the object, *someone* has to create it,
  which is item 6. Splitting them would leave the app non-building in between.

Final breakdown, each independently buildable and verified:

| commit | scope |
|---|---|
| `adedac9` MW-5 (1/5) | item 3 — the `window` collision, against the old class |
| `2cacdc2` MW-5 (2/5) | item 5 — `BookmarkController` split |
| `1119261` MW-5 (3/5) | items 1, 2, 4, 6 — `BookWindow.xib` + `BookWindowController` |

### Changes

**Item 3 — `window` collision (`adedac9`)**
- `Sources/Controller.h/.m`, `Controller_input.m`: `IBOutlet id window`
  replaced by a private `_window` plus `-window`/`-setWindow:` named exactly
  like `NSWindowController`'s; ~80 direct reads rewritten to `[self window]`.
  The nib's outlet connects through `-setWindow:`. Deleting the ivar in the
  next step was then a pure deletion.

**Item 5 — `BookmarkController` split (`2cacdc2`)**
- New `Sources/AllBookmarkController.h/.m` — the app-wide All Bookmark
  browser. Reaches the book window through `AppController` (new `-controller`
  / `-allBookmarkController` accessors) instead of a window-side outlet.
- `Sources/BookmarkController.h/.m` reduced to the per-book sheet.
  `-ok:`/`-cancel:` no longer branch on which panel is visible (the sheet ends
  a sheet, the browser ends its modal session); the `window` outlet is gone
  because `-editBookmark:` always overwrote it with `[NSApp keyWindow]`.
- `MainMenu.xib`, `AppController.h/.m`, `Controller.m`, `project.pbxproj`.

**Items 1, 2, 4, 6 — the nib split and the window controller (`1119261`)**
- New `Resources/Base.lproj/BookWindow.xib` with the window,
  `CustomImageView`, the progress indicator, the accessory (page-bar) window +
  `AccessoryView`, `RightMenu`, the thumbnail panel + `ThumbnailController` +
  `ThumbnailMatrix` + `ThumbnailMenu`, the per-book bookmark panel + its
  `TableMenu`, the full-image panel + view, and the filter panel +
  `FilterPanelController`. `MainMenu.xib` keeps the menus, Preferences and its
  sub-panels, and the AllBookmark panel.
- Localization: `ja`/`en` `MainMenu.strings` split into `BookWindow.strings`
  by object id (34 ja entries moved). Orphaned entries for objects deleted in
  earlier tasks were left in `MainMenu.strings` untouched.
- `Controller` → `BookWindowController`, `NSObject` → `NSWindowController`,
  File's Owner of the new nib. `Controller_input.m` →
  `BookWindowController_input.m` (still a category).
- Item 4: `-awakeFromNib` became `-windowDidLoad`. It runs once, after every
  object in the nib is instantiated and connected, which `-awakeFromNib` does
  not guarantee — and the body pushes settings into `imageView`,
  `thumController` and `fullImagePanel`. Same hazard class as
  KNOWN_ISSUES #19. Nib top-level object ownership is `NSWindowController`'s
  (it releases them on dealloc), so no manual release was added.
- Item 6: `-[AppController awakeFromNib]` creates the one
  `BookWindowController` with `-initWithWindowNibName:@"BookWindow"`, assigns
  itself with `-setAppController:` (before the nib loads, since
  `-windowDidLoad` reads it), then calls `-window` to force the load at the
  same launch-time moment `MainMenu.xib` used to instantiate the object.
  `-[AppController dealloc]` releases it.
- Seven connections crossed the new nib boundary; all seven rewired:
  `BookWindowController`'s `bookmarkController` and the per-book panel's
  connections became internal to `BookWindow.xib`; its `appController` outlet
  became programmatic; `AppController`'s `controller` outlet was removed;
  `PreferenceController` swapped its `controller`/`window` outlets for an
  `appController` outlet and reaches the window through it;
  `-sheetOk:`/`-sheetCancel:` moved to `AppController` (with the
  `DIALOG_OK`/`DIALOG_CANCEL` constants) because the Preferences panel stays
  in `MainMenu.xib`; and the Filter menu item now targets First Responder,
  resolving to a one-line forwarder on `BookWindowController`.

### Intentional deviations from scope

1. **`AllBookmarkController`'s Add New Bookmark now reads
   `allNewBookmarkTextField`.** The unsplit class read `newBookmarkTextField`
   there — the *per-book* panel's field, which is not on screen at that point
   — so the button could only ever beep or add a stale page number.
   `allNewBookmarkTextField` was connected in the nib and read nowhere. The
   old outlet cannot cross the nib boundary, so preserving the bug exactly
   would have required an artificial cross-nib outlet. This is the one
   behavioural change in the task; verified working on device.
2. **`docs/en.lproj/MainMenu.strings` was split too**, though it is not in the
   Xcode project and never reaches the bundle (only `Base` + `ja` are built).
   Leaving it would have made an already-stale file staler.

### Verification

- **Build:** clean build with the documented command, `** BUILD SUCCEEDED **`.
  Warning count is **312, byte-identical to the previous commit's warning
  set** (all pre-existing deprecations). The `NSRightTextAlignment`
  deprecation is counted twice more than before MW-5 (4 vs 2) because the
  table data-source code is genuinely duplicated by the `BookmarkController`
  split; no new *kind* of warning.
- **Image quality (the task's hazard #1 and #2):** verified by pixel
  comparison, not by looking at the window. A per-window `screencapture -l`
  of the book window was taken before the nib move and again after, at the
  same window size and `fitScreenMode`, for a **single page** and for a
  **two-page spread**. Both pairs are **byte-identical (same SHA-256)** —
  mean absolute difference 0, so no resampling step was added and
  `setUseCalayer:`/`setInterpolation:`/`setIgnoreImageDpi:`/autoresizing all
  survived the move intact. Repeated after the final build of commit 3/5.
- **On-device (manual, GUI-driven):** every panel opened, tracked the book,
  and closed — thumbnail panel, per-book Bookmark sheet (add bookmark → OK →
  the item appears in the Bookmark menu), full-image panel, filter panel
  (which exercises the new First Responder forwarding), accessory page-bar,
  and the image-view context menu with its dynamic left/right item titles.
  Preferences opens and Cancel works. Closing the window and reopening a book
  works. The All Bookmark browser was verified in commit 2/5 by temporarily
  forcing that branch in a throwaway build — see KNOWN_ISSUES #24 for why it
  cannot be reached from the UI.
- **Not verified:** no-leaked-nib-top-level-objects could not be *exercised*.
  `NSWindowController` owns and releases its nib's top-level objects, but with
  exactly one window the controller is never deallocated, so nothing frees
  them during a run. This becomes testable at MW-7 and should be checked
  there. Also not exercised: slideshow, Apple Remote, encrypted archives,
  multi-display.

### Remaining Issues

- **KNOWN_ISSUES #25 — Preferences ▸ OK crashes when a book is open.**
  Pre-existing: bisected by building and running `3d88521` (MW-4, last
  pushed), `2cacdc2` and the final MW-5 build — all three crash identically.
  `EXC_BAD_ACCESS` in `objc_msgSend`; `NSZombieEnabled` names it
  `-[CFString copyWithZone:]: message sent to deallocated instance`. Not
  fixed here; MW-5 is a no-logic-change task.
- **KNOWN_ISSUES #24 — the All Bookmark browser has no UI entry point.**
  Pre-existing since MW-4 retargeted `Edit Bookmark...` to First Responder;
  with no window open there is no target, so the item is disabled.

### Follow-up Suggestions

- Fix KNOWN_ISSUES #25 (the Preferences-OK crash) as its own task, before
  MW-6. `NSZombieEnabled` plus a breakpoint on the zombie message should name
  the string in one run.
- Decide KNOWN_ISSUES #24 when MW-7 lands: decision 4 ("last window closed
  quits") makes the no-book state unreachable, which may retire the branch
  rather than needing a fix.
- `IBOutlet id normalWindow` in `BookWindowController.h` is connected in
  neither nib and referenced nowhere. It looks dead; per CLAUDE.md it was not
  removed as a side effect of this task.
- `Resources/en.lproj/MainMenu.strings` / `BookWindow.strings` are not in the
  Xcode project and never ship. Either add them or delete them.
