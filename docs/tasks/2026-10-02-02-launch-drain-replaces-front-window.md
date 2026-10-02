# TASK: Launch-time Finder open replaces the front restored window; raise minimum macOS to 12.0

## Background

### Extra windows (owner-confirmed cause)

TASK A (`docs/tasks/2026-10-02-01-window-routing-diagnostics.md`, hypothesis
H4) found that a Finder open that *launches* cooViewer never goes through the
front-window-replace policy. The owner reproduced it on the released v1.6.3
on 2026-10-02:

1. With "Close windows when quitting an application" off (System Settings ▸
   Desktop & Dock), quit cooViewer with two book windows open.
2. Double-click a different book in Finder.
3. cooViewer launches, restores the two windows, and opens the requested
   book in a **third** window.

Repeated over days, every Finder-launched session adds one window. This is
the owner's "more windows than I created" report.

Mechanism: requests that arrive before launch settles are queued
(`KNOWN_ISSUES` #32) and drained in `-[AppController settleLaunch]` through
`-openBookInNewWindow:` only. After launch, `-application:openFiles:`
de-duplicates first and then loads the first not-already-open file into the
front window (`d393955`, v1.6.2). The drain was left on the older policy.

**Owner decision (2026-10-02):** the drain must behave like a Finder open
while running — replace the front window's book.

### Minimum macOS

Xcode 27 rejects the main app's deployment target of macOS 10.13 (`KNOWN_ISSUES`
#38), so the build command in `CLAUDE.md` fails without an override. The
helper and the Quick Look extensions already target 12.0.

**Owner decision (2026-10-02):** raise the minimum to macOS 12.0.

## Goal

1. A launch-time Finder open follows the same per-file rules as a Finder open
   while running:
   - De-duplicate first, unchanged: a book that a restored window is showing
     brings that window forward at its restored page (the reason the #32
     queue exists).
   - The first not-already-open file replaces the book in the front window,
     subject to the same gate as today (`front` exists, `-hasBookOpen`, not
     `-isBookLoadInFlight`).
   - Every other file goes to `-openBookInNewWindow:` (dedup, empty-window
     reuse, or a new window), as today.
   - With no restored book window (only the bookless launch window), the
     result is unchanged: the empty window is filled.
2. That rule exists in **one** method, used by both the post-launch
   `-application:openFiles:` path and the drain. No second copy of the gate.
   (TASK C will later extend this method with drag and drop and ⇧-open.)
3. `WindowRouting` logging stays accurate: drain lines show the launch-drain
   entry point and the new decision and reason values.
4. Minimum macOS 12.0:
   - `MACOSX_DEPLOYMENT_TARGET = 12.0` for every configuration still at
     10.13 (`project.pbxproj`, around lines 1213, 1288, 1363, 1500, 1533 —
     verify which targets/levels they belong to).
   - The build command in `CLAUDE.md` succeeds without command-line
     overrides.
   - `README.md` ▸ Requirements: change the macOS row to `12 Monterey`. The
     owner explicitly requests this README change; change nothing else in
     the README.
   - Resolve `KNOWN_ISSUES` #38.

## Scope

### In scope

- The four goals above.
- Comments in `AppController.m` that state the drain deliberately skips the
  front-window-replace behavior (for example around `-application:openFiles:`
  and `-settleLaunch`) must be corrected to describe the new behavior.
- `docs/DECISIONS.md`: one entry covering the launch-drain change (it
  supersedes the part of the 2026-07-30 queue decision that kept the drain on
  `-openBookInNewWindow:`), and one entry for the macOS 12.0 minimum and why.
- `docs/KNOWN_ISSUES.md`: close #38; update #32 if its text states the old
  drain behavior as current.

### Out of scope

- Removing code made unnecessary by dropping 10.13–11 support (availability
  checks, fallbacks). List candidates in Follow-up Suggestions for the later
  dead-code review (TASK E); do not delete them here.
- Drag and drop, ⇧-open, New Window, helper icon (TASK C).
- The other hypotheses from TASK A (H1, H6, H7). Do not change them.
- Changing the OpenLastFolder fallback or restoration itself.

## Implementation notes

- **Which window is "front" at drain time.** After restoration,
  `-frontController` returns `frontWindowController`, or
  `[windowControllers lastObject]` when nil. Confirm on device that this is
  the window the user sees as frontmost after restoration. If it is not
  reliable, choose the frontmost book window from AppKit's window order
  (e.g. `-[NSApp orderedWindows]`) inside the shared method, and say which
  rule was used and why.
- **Restoration timeout path** ("window restoration did not finish in time"):
  the front window may still be loading. The existing gate then sends the
  file to a new window. This is acceptable; make sure the log line states the
  reason.
- **A restored window whose book is gone** stays hidden and empty (MW-8). It
  must not be shown or replaced by accident. Empty-window reuse rules stay as
  they are.
- The replaced window's restorable state should follow the new book, as for
  any replace.
- MRC and surrounding style. Keep the existing explanatory comments that are
  still true.

## Verification

- Build with the command in `CLAUDE.md`, **without** a deployment-target
  override. `build/` contains only the app.
- Check `LSMinimumSystemVersion` (or the effective minimum) in the built
  Info.plists of the main app, the helper, and both `.appex` bundles: all
  12.0.
- On-device, with a renamed test copy (own bundle identifier and executable
  name, per `CLAUDE.md`), because the scenarios need quit and relaunch with
  saved state. Use `open -a <test copy> <book>` to stand in for a Finder
  double-click: both arrive through `-application:openFiles:`, while a real
  Finder double-click would go to the installed release. Record whether
  "Close windows when quitting an application" is off; do not change the
  owner's system setting.
  1. Two book windows, quit, open a different book → still **two** windows;
     the front one shows the new book.
  2. Two book windows, quit, open the book shown in the *back* restored
     window → two windows; that window comes forward at its restored page;
     nothing is replaced.
  3. Two book windows, quit, open three different books at once → the first
     replaces the front window, the other two open new windows → four.
  4. Close all windows, quit, open a book → one window.
  5. While running: a Finder-style open still replaces the front window
     (regression check of the v1.6.2 behavior).
  6. `/usr/bin/log show` shows a `WindowRouting` line per request with the
     launch-drain entry point and correct reasons.
- Clean up the test copy and its saved state and defaults domain afterwards.

## Progress

- Last completed step: implementation, build, on-device check (second run),
  docs.
- Current partial state: Implementation Result written.
- Exact next step: archive and commit.

## Implementation Result

**Status:** Completed with follow-up issues

### Changes

- `Sources/AppController.m`, `Sources/AppController.h`:
  - New `-openFilesPreferringFrontWindow:entry:` holds the per-file Finder
    rule (dedup → first not-already-open file replaces the front window's book
    when `front` exists, has a book and is not mid-load → everything else to
    `-openBookInNewWindow:entry:reason:`). It is the loop that used to be inline
    in `-application:openFiles:`, moved verbatim apart from the `entry` label;
    there is no second copy of the gate.
  - `-application:openFiles:` calls it once the launch has settled.
  - The launch queue `pendingLaunchOpenPaths` became `pendingLaunchOpenRequests`:
    one entry per request with its paths and its kind (`finder-openFiles` or
    `helper-url`). `-settleLaunch` drains Finder requests through the shared
    method (so "first file of the call" keeps its meaning per request) and
    helper requests through `-openBookInNewWindow:` as before.
  - Logging: drain lines use entry `launch-drain`, or
    `launch-drain/restore-timeout` when the restoration deadline expired;
    decisions/reasons are those of the shared method (`replace-front`/`front-ok`,
    `dedup-focus`/`gate:already-open`, `new-window`/`gate:front-slot-used`,
    `reuse-empty`/`gate:front.hasBookOpen=NO`, …); a queued helper request
    drains with reason `helper:explicit-new-window`.
  - Comments that said the drain skips the front-window replace were rewritten
    (`-application:openFiles:`, the queue ivar, `-handleGetURLEvent:…`,
    `-settleLaunch`).
- Front window at drain time: kept `-frontController` (no `orderedWindows`
  rule added). Measured on device with the app active: on every drain line the
  front was the tracked `frontWindowController` (`front=#n(tracked)`) and equal
  to AppKit's main window (`appMain=#n`); it was usually *not*
  `[windowControllers lastObject]` (e.g. front `#3` with seven windows), because
  the restored books open in an order of their own and the last one to open
  becomes main. See Remaining Issues for the inactive-app case.
- `cooViewer.xcodeproj/project.pbxproj`: `MACOSX_DEPLOYMENT_TARGET` 10.13 → 12.0
  in the five **project-level** configurations (Development, Development2,
  Deployment, Deployment2, Default); the `cooViewer` target inherits them, the
  helper and both extensions already set 12.0. **Edited by the owner**: the
  agent's own edit was denied by its auto-mode classifier ("Modify Shared
  Resources"), as was a build with a command-line override; the owner made the
  change and approved the override-free build. Diff confirmed: exactly the five
  lines, nothing else.
- `README.md` ▸ Requirements: macOS row → `12 Monterey` (owner request; nothing
  else changed).
- `docs/KNOWN_ISSUES.md`: #38 marked fixed; #32 notes the new drain behavior.
- `docs/DECISIONS.md`: "The launch drain applies the running-app Finder rule"
  (supersedes part 2 of the 2026-07-30 queue decision) and "Minimum macOS is
  12.0".
- No render-path involvement: routing only, no change between decode and
  `drawInRect:`. A replaced window's restorable state follows the new book via
  the existing `-imageDisplay` → `invalidateRestorableState` path; observed
  indirectly in that books opened by the drain were restored in the next
  launch (S4 run below restored the S3 session's seven windows).

### Verification

- Build: the `CLAUDE.md` command (overrides only for SYMROOT/OBJROOT/DerivedData,
  no deployment-target override) with Xcode 27.0 — succeeded, no errors, only
  the existing deprecation warnings. `build/` contains only `cooViewer.app`.
- Automated verification: `LSMinimumSystemVersion` is `12.0` in the built main
  app, `cooViewer (New Window).app`, `cooViewerPreview.appex` and
  `cooViewerThumbnail.appex`; `vtool -show-build` reports `minos 12.0` for both
  slices (arm64, x86_64) of the main executable.
- Manual verification: the owner ran a scratch script (not committed) that drove
  a renamed, re-identified, ad hoc-signed copy of `build/cooViewer.app`
  (bundle id `jp.coo.cooViewer.draintest`, executable `cooViewer-draintest`,
  own URL scheme, no extensions/helper inside, document types ranked `None`)
  with `open -a` and the private new-window URL. The system-wide
  `NSQuitAlwaysKeepsWindows` was read only (value `1`, i.e. "Close windows when
  quitting" off); the test copy also had it set in its own domain. Run 1 was
  discarded (the app never became active and the state reset did not work —
  see Remaining Issues). Run 2 (app active, macOS 26.6.2):
  1. **Launch with a book no window shows → replaced, no new window.** S4 run:
     7 restored windows, request → `launch-drain replace-front #3` (front-ok),
     7 windows after. (The intended 2-window starting state could not be set up;
     the count is unchanged either way, which is the point of the change.)
  2. **Launch with a book a back window shows → that window focused, nothing
     replaced.** Three runs with 5 restored windows: `launch-drain dedup-focus`
     to `#1`, `#2`, `#3` (`gate:already-open`), each a window that was not the
     front when the request was queued; 5 windows after, no replace line.
  3. **Launch with three books at once → first replaces, others new.** 5
     restored windows: `replace-front #2`, `new-window #5`, `new-window #6`
     (`gate:front-slot-used`) → 7 = 5 + 2.
  4. **No restored book window → the empty launch window is filled.** Every
     setup launch (restoration suppressed, request queued): `launch-drain
     reuse-empty #0` (`gate:front.hasBookOpen=NO`), 1 window.
  5. **While running (v1.6.2 regression):** `finder-openFiles replace-front`
     twice (count unchanged), helper `new-window` once.
  6. One `route` line per request throughout; no `restore-timeout` drains
     occurred; no book name appeared unredacted.
- Not performed:
  - The literal two-window starting state of scenarios 1–3: see Remaining
    Issues. The rule was verified from larger starting states instead.
  - Scenario 4 as written ("close all windows, quit"): replaced by
    restoration-suppressed launches, which give the same starting state (only
    the bookless launch window).
  - "Comes forward at its restored page": no page turns were possible
    (no Accessibility permission), so every restored page was 1; that a
    dedup-focus does not reload the book is shown by the absence of a
    replace/new-window line.
  - A real Finder double-click (stand-in: `open -a`, as the task specifies) and
    the restoration-timeout path.

### Remaining Issues

- If the app is *not* active when the drain runs, no window has become main,
  `frontWindowController` is nil and `-frontController` falls back to
  `[windowControllers lastObject]`, which after restoration need not be the
  window on top (run 1, where the app stayed inactive, used the fallback on
  every line). A Finder double-click activates the app, so this was not
  treated as a blocker; choosing from `-[NSApp orderedWindows]` when the pointer
  is nil would close it (small, separate task).
- Test residue on the owner's machine: the test identities' saved window state
  is not under `~/Library/Saved Application State` on macOS 26 and was not
  removed (its location was not found), and `defaults delete` left empty
  `~/Library/Preferences/jp.coo.cooViewer.draintest.plist` and
  `…routingtest.plist`. Harmless (unused bundle ids), listed as owner actions.
- Test-method findings for future scripts: `rm -rf ~/Library/Saved Application
  State/<id>.savedState` does not reset restoration on macOS 26; a launch with
  `-ApplePersistenceIgnoreState YES` skips restoration but its quit does **not**
  overwrite the previously saved state.

### Follow-up Suggestions

- Dead-code review (TASK E) candidates that the 12.0 minimum makes removable
  or that were already dead: `Sources/FilterPanelController.m:50` (the
  `@available(macOS 10.13, *)` else-branch); `Sources/AppleRemote.m:42-48` and
  `:135-148` (AppKit 10.4/10.5 branches); the
  `MAC_OS_X_VERSION_MAX_ALLOWED >= 1040` / `respondsToSelector:@selector(finalize)`
  garbage-collection-era guards at `Sources/PreferenceController.m:2007`,
  `Sources/COPDFImageRep.m:46`, `Sources/COImageLoader.m:434` and
  `Sources/CustomImageView.m:1406`. Not verified unreachable here.
- `-[NSApp orderedWindows]` fallback for a nil front pointer (Remaining Issues).
- A way to set up an exact restored-window state for on-device tests on macOS 26
  (e.g. quit from a session built with the intended windows after first
  clearing state from inside the app), so the literal two-window scenarios can
  be run.
