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
