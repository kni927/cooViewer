# Task: MW-3 — Extract AppController

## Scope
Per `docs/multiwindow-plan.md` MW-3. The inventory and four design findings
recorded there during the previous session are the starting point — read them
first and follow them rather than re-deriving.

Recap of what those findings settle:
- `applicationDidFinishLaunching:` must be split, not moved — most of its
  body is window-side.
- Menu outlets move to AppController; the builder methods (`setBookmarkMenu`
  etc.) stay on Controller and reach items via accessors. Rebuild-on-window-
  switch is MW-6's job.
- `registerDefaults:` moves to `+initialize`, out of `awakeFromNib` — this
  structurally removes the nib ordering race (KNOWN_ISSUES #19).
- The remote-control delegate lives in `Controller_input.m:11`, not
  `Controller.m` — it moves together with `setupRemoteControl` and the
  `appleRemoteHoldDown` static.

Single-window throughout. No user-visible change.

## Before starting
Before writing code, assess whether MW-3 can be split into separately
committable halves — the registerDefaults→+initialize move and the
remote-control relocation look independent of the AppController class
itself. If so, do the independent parts first as their own commits, so a
budget shortfall doesn't leave the app delegate half-migrated.

Verify a PDF-based book renders correctly on the current build — the legacy
composited path removal changed `composeImage` for all books and PDFs were
left unverified there.

## Regression check (on device)
Open Recent, book settings persistence, dock menu, remote control setup, and
last-book-on-launch (`OpenLastFolder`) all behave as before.

## Note on session budget
This is a large mechanical change. If it becomes clear it cannot be finished
and verified in one session, stop and record the state rather than leaving a
half-migrated app delegate — the previous session made that call correctly.

Archive per `docs/task-workflow.md` on completion.

## Implementation Result

**Status:** Partially completed

### Changes

Per the "Before starting" assessment, this landed as two commits (a third,
described below, was deferred):

1. `41e875c` — moved `registerDefaults:` and the KeyArray/MouseArray "set
   default if absent" calls from `-[Controller awakeFromNib]` to
   `+[Controller initialize]`. The skip-page substitution and the four
   version-migration blocks stay in `-awakeFromNib` unchanged — see
   `docs/DECISIONS.md` ("MW-3 `AppController` extraction: implementation-time
   refinements") for why splitting them further would have been a real
   correctness risk (a fresh-install / old-profile migration bug), not just
   a style choice.
2. `3d6ce56` — created `Sources/AppController.h/.m` and made it
   `NSApplication`'s delegate in `MainMenu.xib`. Moved: all
   `NSApplicationDelegate` methods (with per-window bodies forwarded to
   `Controller`), `setupRemoteControl` + `-remoteButton:pressedDown:clickCount:`
   + the `appleRemoteHoldDown` state (now a real ivar/accessor, since it can
   no longer be a file-scope static shared across `Controller_input.m` and
   `AppController.m`), `dontSleepTimer`, `prefController`/`preferences:`/
   `clearRecent:`, and the `openRecentMenuItem`/`openSameFolderMenuItem`/
   `bookmarkMenuItem` outlets (builder methods stay on `Controller`, reached
   via `AppController` accessors). `PreferenceController` now posts
   `PreferencesDidChange` instead of calling `[controller setPreferences]`
   directly. Added small `Controller` accessors this needed:
   `-hasBookOpen`, `-thumController`, `-applicationDidFinishLaunchingSetup:`,
   `-preferencesDidChange:`. Also had to fix `-[AppController
   validateMenuItem:]` to forward to `Controller`'s existing 44-branch
   dispatch, since menu items whose target moved to `AppController`
   (Preferences, Clear Recent, Open, Open the last page) would otherwise
   never get validated.

Files changed: `Sources/AppController.h` (new), `Sources/AppController.m`
(new), `Sources/Controller.h`, `Sources/Controller.m`,
`Sources/Controller_input.m`, `Sources/PreferenceController.m`,
`Resources/Base.lproj/MainMenu.xib`,
`cooViewer.xcodeproj/project.pbxproj`, `docs/KNOWN_ISSUES.md` (#19 narrow
resolution note), `docs/DECISIONS.md` (new entry).

### Not implemented (deferred)

**The single-writer persistence API for `RecentItems`/`LastPages`/
`BookSettings`** (scope bullet 5) was not done. The three read-modify-write
call sites (`openPage:last:` ~L693-950, `windowWillClose:` ~L2694-2860,
`strongSetBookmark` ~L2213) and the three read helpers
(`searchFromBookSettings:key:[more:]`, `searchFromRecentItems:index:`,
`searchFromLastPages:index:`) are untouched — still inline on `Controller`,
exactly as before. This is the highest line-count, highest-regression-risk
piece (real user persisted data) and was deferred rather than rushed, per
the task's own session-budget note. `AppController`'s
`openRecentMenuItem`/`bookmarkMenuItem`/`openSameFolderMenuItem` accessor
plumbing that a follow-up would reuse already exists.

### Verification

- **Build:** clean (`xcodebuild -scheme cooViewer_deploy -configuration
  Deployment`), no new warnings after each of the two commits (verified with
  a full `clean build` at the end — every remaining warning is pre-existing,
  in files this task didn't touch: `GlobalKeyboardDevice.m`,
  `CustomImageView.m`, `AppleRemote.m`).
- **Automated verification:** none (no test suite for this codebase).
- **Manual verification:**
  - App launches without crashing, with the current build placed under
    `build/cooViewer.app` (main-app-only procedure, no QuickLook touched).
  - Menu bar structure loads correctly (`Apple, cooViewer, File, Edit,
    Slideshow, Bookmark, Setting, View, Window`).
  - **Open Recent** ("Recent Books" submenu) populates correctly from the
    real, persisted `RecentItems` — confirms the `AppController` outlet
    wiring works end to end (if `appController` were nil or mis-wired, the
    submenu would be empty since `[appController openRecentMenuItem]`
    would return nil).
  - Opened a real PDF via Finder-style `open -a`; app did not crash.
  - Preferences ("Settings…") and About panel actions run without
    crashing (confirmed indirectly: quit was blocked with "User canceled"
    immediately after invoking Preferences, consistent with
    `PreferenceController`'s unchanged `runModalForWindow:`-style modal
    session actually opening — not a hang or crash).
  - Clean quit (when no modal was left open) succeeds, and `defaults read`
    afterward shows the user's real preference values unchanged/intact
    (`OpenRecentLimit` before and after: 40).
- **Not performed / not reliable in this session's environment:**
  `screencapture` and AppleScript/System Events window enumeration
  (`count of windows`) did not work in this session even for completely
  stock, untouched behaviour (e.g. "About cooViewer" also reported 0
  windows) — this environment has no working interactive window-server
  session for accessibility introspection or screen capture, not something
  this task's changes affect. As a result: dock menu behaviour, remote
  control (no hardware assumed anyway), book-settings persistence
  round-trip, and `OpenLastFolder`-at-launch were **not visually verified**
  this session, only verified by code review (every moved/forwarded method
  was checked against its pre-move implementation for behavioural
  equivalence). The **PDF-rendering check** `TASK.md` asked for could not be
  done pixel-wise either, for the same reason — only confirmed PDFs open
  without crashing.

### Remaining Issues

- The persistence-API refactor (see "Not implemented" above) is the
  concrete remainder of MW-3's stated scope.
- On-device visual/UI verification (dock menu, book settings round-trip,
  `OpenLastFolder`, PDF rendering pixel comparison) should be re-run in an
  environment with a real interactive session before this is considered
  fully verified, even though code review gives high confidence.

### Follow-up Suggestions

- A future task should implement the persistence API (commit 3 as
  originally planned), then re-run the full MW-3 acceptance checklist
  including the on-device items this session couldn't verify.
- Continue with MW-4 per `docs/multiwindow-plan.md` once MW-3 is fully
  closed out (MW-4 depends on MW-3).