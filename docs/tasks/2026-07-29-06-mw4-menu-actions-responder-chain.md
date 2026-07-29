# MW-4 — Menu Actions onto the Responder Chain

## Context

MW-3 is fully closed (commit 6ba7f28, pushed) — AppController now owns the
app delegate role, remote control, and the persistence API. See
`docs/multiwindow-plan.md` MW-4 section, `docs/DECISIONS.md`, and the
cross-cutting image-quality constraint at the top of `CLAUDE.md` (read
before starting — this task retargets several render-path actions).

## Scope

- Retarget the book/view actions in `MainMenu.xib` from `target="484"` to
  **First Responder**:
  `slideshow:`, `editBookmark:`, `changeReadModeMenu:` (×4),
  `changeSortModeMenu:` (×4), `switchSingle:`, `deleteSettings:`,
  `fitToScreen:`, `fitToScreenWidth:`, `fitToScreenWidthDivide:`,
  `noScale:`, `rotateLeft:`, `rotateRight:`.
- Keep `open:`, `openTheLastPage:`, `preferences:`, `clearRecent:` on
  `AppController` (unchanged from MW-3).
- The 8 `contextAction:` items on the image-view context menu (`RightMenu`)
  and `sheetOk:`/`sheetCancel:` stay connected as-is — `RightMenu` moves
  into `BookWindow.xib` in MW-5, not this task.
  (Nib references to object 484 total 42: 9 outlets + 33 action targets —
  use this as a completeness check on what should remain vs. move.)
- Split `-[Controller validateMenuItem:]` along the same line. It dispatches
  on **localized menu-item titles** (44 `isEqualToString:NSLocalizedString(…)`
  branches) — preserve that behavior exactly. Converting to selector-based
  dispatch is an explicit non-goal for this task.
- Verify no retargeted selector collides with a view method. Known
  near-miss: `CustomImageView` declares `-rotateLeft` / `-rotateRight`
  **without** a sender argument — different selectors from `rotateLeft:` /
  `rotateRight:`. Confirm no collision at build time.

## Cross-cutting constraint (read before touching anything)

`fitToScreen:`, `fitToScreenWidth:`, `fitToScreenWidthDivide:`, `noScale:`,
`rotateLeft:`, `rotateRight:` are render-path actions. **This task changes
only their target, never their bodies.** Do not "tidy" scaling/rotation
logic while rewiring the menu item — see the inviolable image-quality rule
at the top of `CLAUDE.md`.

## Acceptance

- Every retargeted menu item, and its enable/disable state, behaves exactly
  as before — with one window open and with no window open (First Responder
  targeting means these must correctly enable/disable based on window
  state, unlike the old fixed target).
- Build clean, zero new warnings.
- No render-path behavior change (per the constraint above) — a quick
  visual sanity check of fit/rotate actions is enough here; MW-9's case 16
  is the rigorous pixel check for the whole arc.

## Verification

- Build with the documented command
  (`BUILD_TMP=... xcodebuild ... -scheme cooViewer_deploy -configuration Deployment ...`).
- On-device: exercise each retargeted menu item with a book open, and
  confirm graceful (correctly disabled, not crashing) behavior with no
  window open. This needs a real interactive session (screen sharing), not
  just CLI — menu enable/disable state and First-Responder targeting can't
  be fully verified headlessly.
- Follow `docs/task-workflow.md` on completion: append the Implementation
  Result here, archive to `docs/tasks/2026-07-29-NN-mw4-...md`, update
  `docs/DECISIONS.md` / `docs/DEV_LOG.md` / `docs/KNOWN_ISSUES.md` as
  needed.

## Depends on

MW-3 (done).

Risk noted in the plan: low-medium.

## Implementation Result

**Status:** Completed

### Changes

- `Resources/Base.lproj/MainMenu.xib`: retargeted the 18 listed actions
  (`slideshow:`, `editBookmark:`, `changeReadModeMenu:` ×4,
  `changeSortModeMenu:` ×4, `switchSingle:`, `deleteSettings:`,
  `fitToScreen:`, `fitToScreenWidth:`, `fitToScreenWidthDivide:`,
  `noScale:`, `rotateLeft:`, `rotateRight:`) from `target="484"` to
  `target="-1"` (First Responder). Verified against the file directly:
  before the change there were 28 `target="484"` action references (18 of
  the above + 2 `sheetOk:`/`sheetCancel:` + 8 `contextAction:`) and 9
  `destination="484"` outlets, 37 total. After: exactly the 18 changed to
  `target="-1"`, the other 10 action references and all 9 outlets
  untouched. (Note: the task text's "42 total: 9 outlets + 33 action
  targets" doesn't match what's actually in the current
  `Resources/Base.lproj/MainMenu.xib` — actual is 9 + 28 = 37. Not
  investigated further since the explicit selector list was unambiguous
  and is what this task worked from; flagging in case it points at a stale
  count or a file this task wasn't meant to touch.) `localize/*.xcloc` were
  left untouched — they are stale translation-export snapshots, not part
  of the build (the build uses `Resources/{en,ja}.lproj/*.strings` against
  `Base.lproj/MainMenu.xib`).
- `Sources/Controller.h`/`.m`: extracted the "Open the last page" branch out
  of `-validateMenuItem:` into a new `-validateOpenTheLastPageMenuItem`
  accessor; body unchanged. All other branches in `-validateMenuItem:`
  (the 18 retargeted actions' titles, `RightMenu`/sheet items) untouched.
- `Sources/AppController.h`/`.m`: `-validateMenuItem:` no longer forwards
  wholesale to `Controller`; now checks only "Open the last page" (via the
  new accessor) and returns `YES` for its other items (Open/Preferences/
  Clear Recent), matching what `Controller`'s old default fallthrough
  produced for them.
- No render-path action bodies changed — `fitToScreen:`,
  `fitToScreenWidth:`, `fitToScreenWidthDivide:`, `noScale:`,
  `rotateLeft:`, `rotateRight:` keep their exact implementations; only
  their nib target changed.
- Confirmed no selector collision: `CustomImageView` declares `-rotateLeft`
  /`-rotateRight` (no colon) — different selectors from `rotateLeft:`/
  `rotateRight:` (with colon), and neither view overrides
  `nextResponder`/`acceptsFirstResponder`, so First-Responder resolution
  correctly walks past it to `Controller` via the window's delegate.
- See `docs/DECISIONS.md` ("MW-4 `validateMenuItem:` split...") for the
  design rationale and `docs/DEV_LOG.md`/`docs/KNOWN_ISSUES.md` #23 for the
  on-device session notes.

### Verification

- **Build:** `xcodebuild -project cooViewer.xcodeproj -scheme
  cooViewer_deploy -configuration Deployment` with `SYMROOT`/`OBJROOT`
  under `$TMPDIR`, per `CLAUDE.md`. Clean build, zero errors.
  `Controller.m`/`AppController.m` recompiled (arm64 + x86_64) with only
  pre-existing deprecation warnings (`NSUnarchiver`, Carbon Alias Manager
  calls, `NSCancelButton`/`NSOKButton`, etc.) — none new, none touching the
  changed lines. `build/` verified to contain only `cooViewer.app`.
  Confirmed the built app launches and quits cleanly.
- **Automated verification:** none (no test suite for this codebase; see
  `docs/KNOWN_ISSUES.md` #10).
- **Manual verification:** on-device, via a live screen-sharing session
  using `System Events` UI scripting (`osascript`) against the running
  test build (`build/cooViewer.app`), with `tests/fixtures/generated/test.cbz`:
  - With the book open: all 18 retargeted items report `enabled=true`;
    invoking `rotateRight:` visibly rotated the page image, invoking
    `fitToScreenWidth:` moved the View-menu checkmark to it (started/ended
    on `Fit to Screen`, the default), `editBookmark:` opened its sheet
    (cancelled without changes), `Switch Single/Bind` and `Delete Settings`
    ran without error, `Start/Stop` (slideshow) toggled cleanly. Read-mode
    and sort-mode checkmarks reflect `readMode`/`sortMode` correctly
    (`Right to Left` and `Name` checked, matching defaults;
    `Creation Date`/`Modification Date` correctly disabled for a ZIP
    source, unrelated to this task).
  - With the window closed (no book open): all 18 items report
    `enabled=false`, and the app did not crash or misbehave.
    `Open the last page` (AppController) correctly stayed `enabled=true`
    (real `RecentItems` was non-empty) and invoking it correctly reopened
    the last book, confirming the extracted
    `-validateOpenTheLastPageMenuItem` accessor behaves identically to the
    original inline branch.
  - App quit cleanly via the menu afterward; process count confirmed zero
    remaining.
- **Not performed:** MW-9's pixel-level rendering regression check (not
  this task's scope — only a qualitative sanity check of fit/rotate was
  required here, and that passed via the rotation/fit-mode checks above).

### Remaining Issues

None directly related to this task's scope.

### Follow-up Suggestions

- The task text's action-reference count ("42 total") doesn't match the
  current `MainMenu.xib` (37). Worth a quick check next time `TASK.md` or
  `docs/multiwindow-plan.md` cites a specific count against this file, in
  case the plan doc's number is stale elsewhere too.
- `docs/KNOWN_ISSUES.md` #23 (new): `open <app> <file>` without `-a` can
  silently launch the wrong app when a same-bundle-ID production copy is
  installed (as it is on this dev machine, per #18) — worth a project-wide
  reminder if this keeps coming up across future on-device sessions.

None of the above were implemented as part of this task.
