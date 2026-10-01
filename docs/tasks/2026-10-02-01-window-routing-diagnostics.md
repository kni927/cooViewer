# TASK: Investigate extra book windows and add window-routing diagnostics

## Background

The owner has observed, without proof, that after a longer session the number
of book windows exceeds the number of windows they explicitly created
(File ▸ Open in New Window… / ⌥⌘O, or Finder Open With ▸ cooViewer (New
Window)). Ordinary Finder double-click should replace the book in the front
window (`d393955`, `docs/tasks/2026-07-31-06-finder-open-reuses-window.md`),
so the count should not grow on its own.

What is known about the occurrences:

- The app was already running (not a cold launch).
- The previous book had finished loading.
- Over the session, roughly 3–5 files had been opened, one at a time.
- It has never been seen while only one window existed; creating a second
  window explicitly seems to be the precondition. Details beyond that are
  unknown.

The behavior is not reproducible on demand, so this task has two parts:
a source audit that may find the path outright, and permanent low-volume
logging so the next real occurrence can be diagnosed from the system log.

## Goal

1. Produce an audit of every code path that can bring a new book window on
   screen, and of every routing decision for an incoming open request, with
   file:line references.
2. Add diagnostic logging of those decisions to the shipped app, so that the
   owner can, after a suspicious session, run one `log show` command and see
   why each window was created.
3. Report which hypotheses below the audit confirms, refutes, or leaves open,
   and propose (not implement) a fix for anything confirmed.

## Scope

### In scope

- Audit, covering at least:
  - `-[AppController application:openFiles:]`, including the
    front-window-replace gate and its fallthrough to `-openBookInNewWindow:`.
  - The private new-window URL handler used by the bundled helper.
  - `-openBookInNewWindow:`, `-emptyWindowController`,
    `-windowControllerShowingBook:`, `-newWindowController`,
    `-frontController` / `-windowControllerDidBecomeFront:` /
    `-retireWindowController:`.
  - Launch-time queueing and `-settleLaunch`.
  - Window restoration (MW-8) and its duplicate-window fix
    (`docs/tasks/2026-07-30-04-fix-duplicate-window-on-restored-book.md`).
  - Bookmark browsers, Open Recent, the Dock menu, "Open from same folder",
    and any other caller that can end in a new window.
- Hypotheses to confirm or refute from source (do not assume any is true):
  - H1: `bookLoadInFlight` (or `passwordOpenInFlight` / restoration flags)
    can remain YES after some load outcome — e.g. an Objective-C exception
    mid-load, a failure branch, a cancelled password sheet, a book replaced
    while loading — making every later Finder open fall through to a new
    window.
  - H2: `frontWindowController` can point to a window other than the one the
    user sees as front (closed, hidden, miniaturized, on another Space, in
    full screen, or a window whose controller never received
    `-windowControllerDidBecomeFront:`), so `-frontController` returns a
    controller that fails the replace gate.
  - H3: the dedup lookup (`-windowControllerShowingBook:`) or empty-window
    reuse can miss because of path form differences (resolved vs. unresolved
    path, symlinks, `/private` prefixes, case, Unicode normalization).
  - H4: a relaunch during the session (manual quit, logout, OS update) lets
    restoration bring back more windows than existed.
  - H5: a Finder selection of several files, or a Finder event delivering the
    same file twice, routes files after the first into new windows by design.
- Logging:
  - Use `os_log` with a dedicated category (for example `WindowRouting`)
    under the main app's bundle identifier as subsystem.
  - Log at the default level (persisted without configuration), never
    per page turn or per draw — only at open-request routing decisions and
    window creation/reuse/retirement.
  - Each line states: entry point (Finder openFiles, helper URL, menu, D&D
    later, restoration, launch drain…), decision (replace front / dedup focus
    / reuse empty / new window / queued), the reason for that decision
    (which gate condition failed, e.g. `front=nil`, `front.hasBookOpen=NO`,
    `front.loadInFlight=YES`), and the window count after the action.
  - File paths and names must use `os_log`'s default private redaction
    (`%{private}@` or the default for objects). Do not mark paths public.
- Document the retrieval command in the Implementation Result, e.g.
  `log show --last 1d --predicate 'subsystem == "<bundle id>" AND category == "WindowRouting"'`,
  verified to work without `sudo` on the owner's macOS.

### Out of scope

- Any change to routing behavior. If the audit finds a definite defect,
  report it with a proposed fix and size estimate; the fix is a separate
  task.
- Logging anywhere in the render path, archive layer, or page navigation.
- New preferences or UI.

## Implementation notes

- Background analysis from the planning session (verify, do not trust):
  `bookLoadInFlight` is set at the top of `-openPage:last:`
  (`Sources/BookWindowController.m` ~1172) and cleared at the success tail
  (~1461), in `-abandonOpenWithLoader:…` (~856), `-discardPendingOpen:…`
  (~1925), and `-windowWillClose:` (~3443). No early `return` between the
  split point and the success tail was found other than the abandon path,
  but exceptions were not considered.
- `-frontController` falls back to `[windowControllers lastObject]` when
  `frontWindowController` is nil. `frontWindowController` is cleared only in
  `-retireWindowController:`.
- Keep the logging helper small (a static function or macro in one place),
  matching MRC and the surrounding style.

## Verification

- Build with the command in `CLAUDE.md`; `build/` contains only the app.
- Main-app-only on-device procedure (`CLAUDE.md`): open two windows
  explicitly, then open several files one at a time from Finder, one file
  that is already open in the other window, a multi-file Finder selection,
  and one helper (New Window) open. Confirm that `log show` prints one
  routing line per request with the correct decision and reason, and that
  no file name appears unredacted.
- Confirm that page turning produces no `WindowRouting` lines.
- If UI scripting is used, follow the renamed-test-copy rule in `CLAUDE.md`.

## Progress

- Last completed step: audit, logging, build, owner-run on-device check.
- Current partial state: Implementation Result written.
- Exact next step: docs update, archive, commit.

## Implementation Result

**Status:** Completed

### Audit

Line numbers are for the committed source of this task.

#### Every way a book window comes into existence

`-[AppController newWindowController]` (`Sources/AppController.m:630`) is the
only creator; it registers the controller *before* loading the nib and never
shows the window (only `-[BookWindowController openPage:last:]` does, with
`makeKeyAndOrderFront:` at `Sources/BookWindowController.m:1174`). It has
exactly three callers:

| Caller | Line | When |
|---|---|---|
| `-awakeFromNib` | `AppController.m:67` | once, the launch window (#0) |
| `-openBookInNewWindow:entry:reason:` | `AppController.m:672` (creates at 712) | only after dedup and empty-window reuse both miss |
| `+restoreWindowWithIdentifier:state:completionHandler:` | `AppController.m:785` | per saved window, after empty-window reuse misses |

A *visible* window can also appear without a new controller: reusing a
registered, hidden, bookless window (`-emptyWindowController`,
`AppController.m:734`). Such windows exist after a bookless window's open is
abandoned with `closeWindow:NO` (password cancel or an unreadable archive after
a password, `BookWindowController.m:849-882`, `orderOut:` at 880) and after a
restoration whose book is gone (`BookWindowController.m:1074-1079`).

`-openBookInNewWindow:entry:reason:` has four callers:

| Entry | Line | Notes |
|---|---|---|
| Finder `-application:openFiles:` fallthrough | `AppController.m:254`, gate at 293 | only when the front-window-replace gate fails |
| Helper URL `-handleGetURLEvent:withReplyEvent:` | `AppController.m:327` | always (explicit new window) |
| ⌥⌘O `-openInNewWindow:` | `AppController.m:518` | always (explicit new window) |
| Launch drain in `-settleLaunch` | `AppController.m:860`, drain after 903 | every request queued during launch |

Everything else loads into an existing window and cannot create one: File ▸
Open (`AppController.m:508` → front's `-open:`, `BookWindowController.m:810`),
Open Recent (`-openFromOpenRecent:`, `BookWindowController.m:1157`, no target,
resolves to the key window), Open from same folder
(`BookWindowController.m:1149`), the Dock menu's "Open the last page"
(`AppController.m:378`/`535`, front window, only offered when it has no book),
the OpenLastFolder fallback (`AppController.m:940`, front window), and the All
Bookmarks browser (`-openInSelf:`, `Sources/AllBookmarkController.m:257`:
dedup-focus or replace the front window, no gate). There is no drag-and-drop
onto a book window (no `registerForDraggedTypes:` anywhere in `Sources/`); a
drop on the Dock icon arrives as `-application:openFiles:`.

#### Routing decisions

- **Finder open, launch settled** (`AppController.m:254-318`): per file,
  replace the front window iff the per-call slot is unused, `-frontController`
  is non-nil, `hasBookOpen`, not `isBookLoadInFlight`, and the resolved path is
  not shown by any window. Otherwise `-openBookInNewWindow:` → dedup focus →
  reuse empty → new window.
- **Finder open or helper URL during launch**: queued
  (`pendingLaunchOpenPaths`) and drained by `-settleLaunch` through
  `-openBookInNewWindow:` — the front-window-replace gate never applies to the
  drain (by design, documented on `-application:openFiles:`).
- **Dedup** (`-windowControllerShowingBook:`, `AppController.m:653`): exact
  `isEqualToString:` of `+resolvedBookPath:` (`BookWindowController.m:165`)
  against each window's `currentBookPath`, counting windows that have a book
  *or* a load in flight.
- **Empty** (`-isWindowControllerEmpty:`, `AppController.m:762`): no book, no
  load in flight, not awaiting a restored book, no password sheet.
- **Front** (`-frontController`, `AppController.m:596`):
  `frontWindowController`, set only by `-windowControllerDidBecomeFront:`
  (`AppController.m:955`, called from `-windowDidBecomeMain:`,
  `BookWindowController.m:3566`), cleared only by `-retireWindowController:`
  (`AppController.m:967`); falls back to `[windowControllers lastObject]`.
- **Retirement**: `-windowWillClose:` (`BookWindowController.m:3420`) →
  `-retireWindowController:`, which keeps the last controller registered.

#### `bookLoadInFlight` lifecycle

Set at `BookWindowController.m:1172` (top of `-openPage:last:`). Cleared at the
success tail (1461), `-abandonOpenWithLoader:…` (856), `-discardPendingOpen:…`
(1925) and `-windowWillClose:` (3443). Every non-exceptional exit of an open
reaches one of them: the loader-failure branch (1249-1254) and archive-load
cancel both go through `-abandonOpenWithLoader:`; every password-sheet outcome
(`-askPasswordForLoader:…`, 1798-1897: cancel/blank, OK, wrong password re-ask,
unreadable after password, window closed) ends in the success tail, abandon,
or discard; the synchronous no-sheet fallback (1804-1816) likewise.

### Hypotheses

- **H1 — stuck in-flight flag: refuted for every normal exit, open for
  exceptions only.** The project has no `@try` anywhere and no
  `NSApplicationCrashOnExceptions`, so an Objective-C exception between
  `BookWindowController.m:1172` and `1461` would be logged by AppKit, the app
  would keep running, and that window would keep `bookLoadInFlight == YES`
  for the rest of its life. Every Finder open while it is front would then fail
  the gate (`gate:front.loadInFlight=YES`) and open a new window. No concrete
  throwing statement was found in that range (e.g. `-loadImage:` never returns
  nil — `COImageLoader -itemAtIndex:` falls back to the "broken" image —
  and the Open Recent submenu always keeps its fixed items, so
  `itemAtIndex:0` at 1370 is safe). The new log shows this state directly: a
  window listed as `B,L` across requests with no open in progress.
- **H2 — front pointer differs from the visible front window: refuted as a
  source of new windows.** `frontWindowController` is never dangling (cleared
  before the controller is removed). It can lag AppKit's main window while the
  app is inactive or a non-book window is main, but it then still names the
  last book window that was main. A wrong but valid front leads to replacing
  the wrong window, not a new one. The only window-adding variant is narrow:
  after the front window is retired with no other window becoming main, the
  `lastObject` fallback can be a hidden empty window, which the next Finder open
  would bring back on screen (reuse-empty). In the on-device run `front` and
  `appMain` agreed on every routing line.
- **H3 — path spelling defeats dedup: refuted as a cause of extra windows from
  ordinary Finder opens.** For a Finder open, a dedup miss means the gate
  *passes* and the front window is replaced (worst case: two windows on the same
  book), never a new window. Misses only matter on paths that already create a
  window (helper, ⌥⌘O, second and later files of a multi-file open, launch
  drain). Spellings can differ in principle — the helper path goes through
  `URLByStandardizingPath` (`Sources/CONewWindowURL.m:49`, which can drop
  `/private`), Open Recent through alias resolution — but measured: a Finder
  open given a different-case path was canonicalized by the system and
  deduplicated normally. The new log tags any such miss with `nearMatch=#n`.
- **H4 — relaunch/restoration: confirmed as a mechanism, not shown to be the
  occurrence.** Restoration itself creates exactly one window per saved window
  and reuses the launch window first. But a Finder double-click that *launches*
  the app (or arrives before `-settleLaunch` finishes) is queued and drained
  through `-openBookInNewWindow:`, never the front-window-replace gate. With N
  restored windows, double-clicking a file that is not already open gives N+1
  windows. This is the documented KNOWN_ISSUES #32 design, not a bug, but it is
  the one ordinary-looking double-click that adds a window. If the app had quit
  or crashed mid-session and was relaunched by a double-click, the owner would
  see this.
- **H5 — multi-file / duplicate delivery: multi-file confirmed by design;
  duplicate delivery refuted.** Only the first file of one
  `-application:openFiles:` call may replace the front window; each further
  file goes to `-openBookInNewWindow:` (measured: `gate:front-slot-used`
  → `new-window`). The same file twice in one call hits dedup (the first
  open is synchronous, and dedup also matches in-flight windows), so it
  focuses rather than adds a window.
- **Additional H6 — helper as default handler: refuted on this machine, open
  elsewhere.** The helper ships the main app's 20 document types with the same
  (unspecified) `LSHandlerRank`. If LaunchServices ever picked
  `cooViewer (New Window)` as the default for a type, every double-click of that
  type would be a helper new-window open. Queried read-only with
  `NSWorkspace -URLForApplicationToOpenContentType:` on this machine:
  `.cbz`/`.cbr` default to the main cooViewer; `.zip`/`.rar`/`.7z`/`.pdf` to
  other apps. Other machines were not checked. The log separates the two
  (`entry=helper-url` vs `entry=finder-openFiles`).
- **Additional H7 — a genuinely in-flight front window: confirmed by design.**
  A Finder open that arrives while the front window's own open is still running
  opens a new window (`gate:front.loadInFlight=YES`). The open stays in flight
  while a password sheet is up (window-modal, so Finder opens are processed),
  during a long archive load's modal session, and while the "Go to the last
  page?" alert (`BookWindowController.m:1336-1345`, shown whenever
  `GoToLastPage` is 0, the default, and the book has a remembered page) is up.
  Whether an `odoc` event is serviced during that `runModal` was not tested.

No definite defect was found, so no routing change is proposed as a bug fix.
Conditional proposals, all separate tasks:

- If the log shows H1 (`B,L` stuck): clear `bookLoadInFlight` in an
  `@finally` around the body of `-openPageWithLoader:…` and find the throwing
  statement from the AppKit exception log line. Small (~10 lines).
- H4, if the owner wants a launch-time double-click to behave like a running
  one: tag queued requests by source and let the drain apply the
  front-window-replace gate to Finder requests only (never helper requests).
  Small to medium (~30 lines), needs a launch-order re-test (KNOWN_ISSUES #32).
- H6 hardening: add `LSHandlerRank = Alternate` to the helper's document types
  in its "Configure helper Info.plist" build phase so it can never become a
  default handler. Small, but needs a Finder Open With check that the entry
  still appears.
- H7: queue a Finder open that meets an in-flight front window and replay it
  when that open ends, instead of opening a new window. Medium; product
  decision.

### Changes

- `Sources/AppController.m`: an `os_log` channel
  (subsystem = the main bundle identifier, `jp.coo.cooViewer`; category
  `WindowRouting`; default level) in one static function plus two logging
  methods. Lines are written:
  - `route …` once per open request, after the structural step
    (focus / reuse / window creation) and *before* the load, so the line
    survives a load that never returns: entry (`finder-openFiles`,
    `helper-url`, `menu-open-in-new-window`, `launch-drain`, `restoration`,
    `launch-open-last-folder`, `all-bookmarks`), decision (`queued`,
    `replace-front`, `dedup-focus`, `reuse-empty`, `new-window`, `rejected`,
    `front-window`), target window, reason (the first failing gate condition
    for a Finder open, e.g. `gate:front.loadInFlight=YES`; `nearMatch=#n` for
    H3), and the book path as `%{private}@`.
  - `window created|retired|closed-kept|became-front …` for window lifecycle;
    `became-front` only when the front window actually changes, not on every
    app reactivation.
  - Every line ends with a snapshot: window count, visible count, which window
    `-frontController` resolves to and whether via the tracked pointer or the
    `lastObject` fallback, AppKit's main window, whether the app is active,
    and per window `#slot(B,L,R,P,vis|hid|min,fs,main,key)`.
  - Routing is unchanged; the only structural edit is that
    `-openBookInNewWindow:` became `-openBookInNewWindow:entry:reason:`
    (the two arguments only label the log line); its four callers pass their
    entry name.
- `Sources/AppController.h`: the renamed declaration and
  `-logRoutingEntry:decision:target:reason:path:`.
- `Sources/AllBookmarkController.m`: logs its dedup-focus/replace-front
  choice.
- No logging in the render path, archive layer, or page navigation:
  every call site is in `AppController` routing/lifecycle methods or the All
  Bookmarks open button.

Retrieval (verified without `sudo`; note `/usr/bin/log`, because zsh has a
builtin `log` that rejects these arguments with "too many arguments"):

```bash
/usr/bin/log show --last 1d --style compact --predicate 'subsystem == "jp.coo.cooViewer" AND category == "WindowRouting"'
```

### Verification

- Build: `xcodebuild -project cooViewer.xcodeproj -scheme cooViewer_deploy
  -configuration Deployment … build` with the `CLAUDE.md` overrides **plus
  `MACOSX_DEPLOYMENT_TARGET=12.0` on the command line**. Without the override
  Xcode 27.0 (the only Xcode on this machine) refuses the project before
  compiling: "The macOS deployment target 'MACOSX_DEPLOYMENT_TARGET' is set to
  10.13, but the range of supported deployment target versions is 12.0 to
  27.0.x". That is a pre-existing project setting, not this change; the
  project file was not edited (raising the minimum OS is a product decision —
  see KNOWN_ISSUES #38). The first overridden build hit a one-off failure in
  the `.appex` copy step; an immediate incremental rebuild succeeded. No new
  warnings in the changed files. `build/` contains only `cooViewer.app`.
- Automated verification:
  - `os_log` mechanics: a throwaway program logging at default level under
    subsystem `jp.coo.cooViewer`, category `WindowRoutingSelfTest`, was
    retrieved by `/usr/bin/log show` as the normal user (no `sudo`), with the
    `%{private}@` path printed as `<private>`.
  - Default handlers queried read-only via `NSWorkspace` (H6 above).
- Manual verification (owner ran a scratch script; Terminal had no
  Accessibility permission): a renamed, re-identified, ad hoc-signed copy of
  `build/cooViewer.app` (bundle id `jp.coo.cooViewer.routingtest`, executable
  `cooViewer-routingtest`, own URL scheme, QuickLook extensions and helper
  removed, document types ranked `None`, fresh preferences with
  `GoToLastPage = 2`) driven with `open -a` and the private new-window URL,
  then removed with its preferences, saved state and LaunchServices entry.
  The log (macOS 26.6.2) showed exactly one `route` line per request, all as
  expected:
  1. cold launch with A → `queued` (`launch-not-settled`), then
     `launch-drain reuse-empty #0`;
  2. helper B → `helper-url new-window #1`;
  3. Finder C → `replace-front #1` (`front-ok`);
  4. Finder D → `replace-front #1`;
  5. Finder A (open in #0) → `dedup-focus #0` (`gate:already-open`);
  6. Finder E+F in one call → E `replace-front #0`, F `new-window #2`
     (`gate:front-slot-used`);
  7. helper G → `helper-url new-window #3`;
  8. Finder D through an upper-case path → `dedup-focus #1` (the system
     canonicalized the spelling; no `nearMatch` needed);
  9. quit → `retired` ×3 and `closed-kept` for the last window.

  `front` equalled `appMain` on every routing line. A search of all the test
  subsystem's lines for the fixture book names found none: every path was
  `<private>`.
- Not performed:
  - Page-turn check on device: the keystrokes were not delivered (no
    Accessibility permission), so the window between steps 9 and 10 had no
    `WindowRouting` lines but also no page turns. Covered by source
    inspection instead: no logging call is reachable from page navigation or
    drawing (call sites listed under Changes), and `became-front` is
    logged only on a change of front window.
  - ⌥⌘O through the menu (needs UI scripting); it calls the same
    `-openBookInNewWindow:entry:reason:` as the helper, which was exercised.
  - Window restoration on device (the test identity had no saved state), the
    All Bookmarks button, and the H4 launch-with-restored-windows case.
  - Default-handler check (H6) on the owner's other machines.

### Remaining Issues

- The extra-window occurrence itself is still unexplained: the audit narrows
  an ordinary single-file Finder open adding a window to H1 (exception), H4
  (launch-time open with restored windows), H6 (helper as default handler on
  some machine), and H7 (front window still opening). The next real
  occurrence should be read with the command above.
- KNOWN_ISSUES #38 (new): Xcode 27 rejects the main targets' 10.13
  deployment target, so the documented build command fails as written.

### Follow-up Suggestions

- Decide the deployment-target question (KNOWN_ISSUES #38) before the next
  release; CI uses `macos-latest` and breaks the same way once that image
  ships Xcode 27.
- After a suspicious session, run the retrieval command and look for the
  `route` line that preceded the extra window: its `entry`, `decision` and
  `reason` identify which of H1/H4/H6/H7 it was.
- Conditional fixes listed under Hypotheses, each as its own task.
