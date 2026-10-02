# TASK: Accept dropped image files; verify Shift-open and drag and drop on device

## Background

The v1.6.5 features task (`docs/tasks/2026-10-03-01-v1.6.5-features.md`)
implemented Shift-open and drag and drop but could not verify them on device:
the computer-use approval card for screen control timed out.

It also found that a single dropped image file is rejected, because
`+[BookWindowController canOpenDroppedPath:]` accepts directories and the
extensions in `+[COImageLoader fileTypes]` only. The earlier task text said
"accept what File ▸ Open accepts", which excludes images. **Owner decision
(2026-10-03):** a drop must follow the same rule as a Finder double-click, so
anything cooViewer opens from Finder — including a single image file, which
opens its folder as the book at that page — is accepted.

## Goal

1. Drag and drop accepts exactly what a Finder double-click opens.
2. Shift-open and drag and drop are verified on device.

## Part 1 — Accept what Finder opens

- Change the acceptance rule so it matches the document types cooViewer
  declares for Finder (the main app's `CFBundleDocumentTypes` in
  `Resources/Info.plist`), plus directories. Use one source of truth; do not
  add a second hand-maintained extension list. If `Info.plist` is not usable
  at run time for this, explain the choice you made instead.
- A dropped image file then goes through
  `-openFiles:preferringWindow:entry:` like any other file (dedup, replace or
  fill the drop target, the rest in new windows).
- Unsupported files (for example `.txt`) are still rejected with the
  not-allowed cursor.
- Build, run the existing automated checks, commit once.

## Part 2 — On-device verification (Shift-open and drag and drop)

**Before starting any step that needs screen control, ask Master in chat to
stand by for the computer-use approval card, and wait for Master's reply.**
The card expires if nobody answers it. If it expires again, stop and report
instead of retrying in a loop.

Use `build/cooViewer.app` or a renamed test copy (`CLAUDE.md`). Check and
record each item:

- Shift-open after launch: with two book windows, hold ⇧ and open a third
  book → new window; open the same book again with ⇧ → its window comes
  forward; open a book without ⇧ → the front window is replaced.
- Shift-open at launch: quit with two windows, hold ⇧ while opening a book →
  three windows.
- Drag and drop from Finder: one book onto the back window → only that window
  changes; a book already open elsewhere → that window comes forward; three
  books → first into the target, two new windows; onto an empty window
  (File ▸ New Window) → fills it; a single image file → opens its folder at
  that image in the target window; a `.txt` → rejected cursor, nothing
  changes.
- Right-click menu, mouse actions and page turning still work.
- `/usr/bin/log show` shows one `WindowRouting` line per request, with entry
  names such as `finder-openFiles+shift` and `drop`.

Finder-specific Shift checks (⇧-double-click, Open With, ⇧⌘↓) and the helper's
Open With icon stay for the v1.6.5 release verification, where the installed
app is the one Finder uses.

At the end, clean up LaunchServices registrations of build output exactly as
in `docs/KNOWN_ISSUES.md` #15. Never touch `/Applications`.

## Git

- Commit Part 1 once; the final commit adds the task archive (and any
  documentation updates).
- Then push `main` (owner-approved for this task). Run `git fetch` first. If
  `origin/main` has moved, merge it (do not rebase or amend pushed history),
  then push. Report the resulting `origin/main` hash.

## Completion Report

Follow the usual format. In Permission / Sandbox, count dialogs from
`~/Library/Logs/claude-permission-requests.log` for this session's
`session_id`, grouped by cause and command; list computer-use requests
separately, including any that expired.

## Progress

- Part 1: done, `14a2fe3`. Build OK; `verify_bundles.py` PASS; engine tests
  ALL PASS (204); helper URL test 13 checks, 0 failures.
- Part 2: done. All listed checks performed on device (see Verification);
  LaunchServices cleaned up.
- Git: the archive commit follows; then `git fetch`, merge if `origin/main`
  moved, push (Master approved the push in chat on 2026-10-03).
- Exact next step: none in this task after the push and report.

## Implementation Result

**Status:** Completed

### Changes

Part 1 (`14a2fe3`)
- `+[BookWindowController canOpenDroppedPath:]` now accepts what a Finder
  double-click opens: folders, and files whose extension is declared in the
  app's `CFBundleDocumentTypes`, read from `Info.plist` at run time
  (`[[NSBundle mainBundle] objectForInfoDictionaryKey:]`), compared without
  case. No second extension list. Single image files are therefore accepted;
  they go through `-openFiles:preferringWindow:entry:` like any other file and
  open their folder at that page.
- Why extensions rather than UTIs: every declared `LSItemContentTypes` entry
  except `public.directory` (the folder case) carries its extensions in the
  same document type (checked in `Resources/Info.plist`: cvbdl, cbz, cbr), so
  extensions plus folders cover the declaration. Matching UTIs would need
  `UniformTypeIdentifiers` linked into the target (the project does not enable
  module auto-linking) or the `UTTypeConformsTo` API, deprecated at the 12.0
  deployment target.
- Comments in `BookWindowController.h` and `CustomImageView.m` updated.
- `docs/DECISIONS.md`: the 2026-10-03 routing entry amended for the new
  acceptance rule.

Image quality: no change between decode and `drawInRect:`.

### Verification

- Build: `CLAUDE.md` command (Deployment, intermediates under `$TMPDIR`),
  0 errors, no new warnings. `build/` contains only `cooViewer.app`.
- Automated verification: `python3 tests/helper/verify_bundles.py` PASS (one
  helper, 20 document declarations); `tests/engine/run_tests.sh` ALL PASS
  (204 checks); `tests/helper/run_tests.sh` 13 checks, 0 failures (run
  outside the sandbox: its `mktemp` in `/private/tmp` is denied inside);
  `git diff --check` clean.
- Manual verification (isolated test copy of `build/cooViewer.app`, bundle id
  `jp.coo.cooViewer.v165`, own executable and URL scheme, no extensions or
  helper, document types ranked None; Finder and the test copy driven with
  computer-use, Master standing by for the screen-control approval; macOS
  26.6.2). Routing from `log show` for the test copy's subsystem, one `route`
  line per request, paths `<private>`:
  - Shift-open after launch: book A open; ⇧ + open B →
    `finder-openFiles+shift new-window #1`; with two book windows ⇧ + open C →
    `finder-openFiles+shift new-window #2`; ⇧ + open A again (a back window) →
    `finder-openFiles+shift dedup-focus #0`, A's window came forward; open D
    without ⇧ → `finder-openFiles replace-target #0` (the front window).
    ⇧ was held with computer-use `hold_key` while `open -a` delivered the
    request.
  - Shift-open at launch: quit with two windows (B, D), relaunch with E
    without ⇧ → `launch-drain replace-target #1`, two windows (control); quit
    with two windows, relaunch with F holding ⇧ →
    `finder-openFiles+shift queued`, then `launch-drain+shift new-window #2`,
    three windows.
  - Drag and drop from Finder (real Finder window on the test folder):
    A onto the back D window → `drop replace-target #0`, the other windows
    unchanged; F (open in another window) → `drop dedup-focus #2
    gate:already-open`, F's window came forward, target unchanged; B, C and D
    selected together → `drop replace-target #0`, then `new-window #3` and
    `#4` (`gate:target-slot-used`); File ▸ New Window then A onto the empty
    window → `menu-new-window new-window #5`, `drop fill-target #5
    target-empty`; `book/04.jpg` (a folder of seven images) → `drop
    replace-target #5`, window titled `book` at `#4-5/7 (05.jpg 800x1200 |
    04.jpg 1200x1800)`; G onto a window that was behind the front one →
    `drop replace-target #0`, the previous front window unchanged; `note.txt`
    → no `route` line, nothing changed, and the drag image carried no copy
    badge while over the window.
  - Right-click shows the context menu (Go to LastPage, Start Slideshow, …);
    clicking the page and the left arrow key turn pages (`#1/4` → `#2-3/4` →
    `#4/4`).
  - LaunchServices cleanup (`docs/KNOWN_ISSUES.md` #15): before cleanup
    `pluginkit -m -A` listed the build-output Preview and Thumbnail
    extensions, and `lsregister -dump` the build-output app, its embedded and
    standalone helpers, `build/cooViewer.app` and the test copy. Removed with
    `pluginkit -r` (two `.appex`) and `lsregister -u` (five bundles).
    Afterwards only `/Applications/cooViewer.app` (and two pre-existing stale
    `/private/tmp/cooViewer-NewWindow-Manual.*` records, untouched) remain;
    `pluginkit -m -A` lists only the `/Applications` extensions.
    `/Applications` was not touched. Intermediate build, test copy and its
    defaults domain deleted.
- Not performed:
  - The cursor shape itself for the rejected `.txt` drag: screenshots do not
    include the mouse pointer. Rejection was shown by the missing copy badge,
    no `route` line and no change.
  - Finder-specific ⇧ checks (⇧-double-click, Open With, ⇧⌘↓) and the
    helper's Open With icon: left for the v1.6.5 release verification, as
    this task specifies.

### Remaining Issues

- None for this task. Note for test method: in `drop` lines the logged front
  window equals the drop target, because the drop activates the app and makes
  the target main before the deferred open runs; that the target need not be
  the previous front window was shown on screen (G onto a back window).

### Follow-up Suggestions

- In the v1.6.5 release verification, check the Finder-specific ⇧ cases and
  the helper's Open With icon with the installed release.
