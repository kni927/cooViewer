# TASK: Fix double-click open not switching document — phase 9

## Background

Reported behavior: with `A.cbz` already open in cooViewer, double-clicking
`B.cbz` in Finder brings cooViewer to the foreground (focus/activation
works) but the window keeps showing `A.cbz` — `B.cbz` is never loaded.

cooViewer is architecturally a single-window app (Controller.m is a large
single-window controller; multi-window support has been explicitly
deferred in past work). The expected behavior for a single-window app
receiving a second "open file" request while already running is to
replace the current document in the existing window (not open a second
window) — so this is a functional bug, not a multi-window feature gap.

This may be a pre-existing latent bug that went unnoticed, or a
regression introduced in phase 7 when QuickLook's UTI/CFBundleDocumentTypes
declarations were added — investigate both possibilities rather than
assuming either.

A secondary, likely-unrelated observation was also reported: `.cbz` file
icons in Finder don't update after `qlmanage -r`. This is probably an
Icon Services cache issue distinct from QuickLook's own cache (`qlmanage
-r` resets `quicklookd`, not Finder's icon cache store), but confirm
rather than assume, and fix if it's actually a cooViewer-side icon
declaration problem rather than pure caching.

## Goal

- With cooViewer already running and `A.cbz` open, double-clicking
  `B.cbz` (or any other supported archive) in Finder loads and displays
  `B.cbz` in the existing window, with the app correctly activated/
  focused (which already works).
- This works for all currently supported formats/UTIs (zip/cbz, rar/cbr),
  not just one.
- Finder icon thumbnails for `.cbz`/`.cbr` display correctly (the cover
  image, or at minimum a correct generic icon) after appropriate cache
  invalidation, confirming whether this was a real bug or just a stale
  local cache.

## Scope

### In scope

**1. Diagnose the open-file handling path**

- Locate the current implementation of Finder's "open this file" entry
  point — likely `application(_:open:)` / `application(_:openFiles:)`
  (modern) or the older `application:openFile:` delegate method — in
  the app delegate / Controller.m.
- Add temporary logging (or use existing logging infra) to confirm:
  - Is the delegate method actually being called when double-clicking
    a second file while the app is already running?
  - If called, what arguments does it receive, and what does the
    existing code do with them (does it attempt to load the file into
    the current window, silently no-op, or something else)?
- Compare against phase 7's changes: check whether
  `CFBundleDocumentTypes` / UTI declarations in the main app's
  Info.plist were touched, added, or left ambiguous in a way that could
  affect how Launch Services routes the open request (e.g. routing to
  the QuickLook extension's UTI instead of the expected document type,
  or a duplicate/conflicting UTI declaration causing Finder to treat
  the open differently).
- Determine root cause: pre-existing bug (delegate method missing/
  incomplete logic) vs. phase 7 regression (UTI/Info.plist change) vs.
  something else. State this clearly in the Implementation Result
  before implementing a fix.

**2. Fix**

- Implement the open-file handling so a new file replaces the current
  document in the existing window, reusing the same load path the
  "File > Open" menu command already uses (do not duplicate loading
  logic — call the same internal method).
- If multiple files are dropped/selected at once and opened
  simultaneously (Finder can send multiple paths in one call), decide
  and document a reasonable behavior (e.g. open the first, ignore the
  rest, given single-window constraints) rather than crashing or
  silently mishandling it.

**3. Icon cache check**

- Confirm whether `.cbz`/`.cbr` icon display is a pure Finder/Icon
  Services cache staleness issue (test with `killall Finder` /
  `killall Dock` and, if still unresolved, clearing the Icon Services
  cache store) vs. a cooViewer-side issue (e.g. missing/incorrect
  `CFBundleIconFile` or per-UTI icon declarations, or no icon at all
  being declared for these UTIs).
- If it's a real cooViewer-side gap, fix it. If it's purely a caching
  artifact with no underlying app issue, document that finding — no
  code change needed.

### Out of scope

- Multi-window support (opening a second file in a *new* window) —
  explicitly deferred, not part of this task.
- Any change to the QuickLook extensions themselves (phase 7), unless
  the root cause investigation shows their UTI declarations are the
  actual cause of the open-file regression, in which case fix only
  what's needed to resolve the conflict.
- Any performance work (phases 1–6) or new format support (phase 8's
  cb7/cbt decision stands).

## Verification

- Manual: with cooViewer running and `A.cbz` open, double-click `B.cbz`,
  `B.cbr`, and one more of each format in Finder; confirm each replaces
  the window content correctly and the app is focused.
- Manual: double-click a file while cooViewer is *not* running (cold
  launch) — confirm this still works as before (regression check on
  the more common path).
- Regression: File > Open menu command still works identically.
- Icon: document findings and, if fixed, confirm updated icons appear
  after appropriate cache-clearing commands.

## Implementation Result

**Status:** Completed with follow-up issues

### Changes

- **Root-cause investigation (open-file bug):** confirmed via `git log
  -p` that phase 7's commit (`4ebb11a`) made zero changes to
  `Sources/Controller.m`/`.h` — its Info.plist changes were limited to
  UTI/`LSItemContentTypes`/`CFBundleShortVersionString`, nothing
  touching the open-file delegate. The only Finder-open hook in the
  codebase is `-(BOOL)application:(NSApplication *)theApplication
  openFile:(NSString *)filename` (`Controller.m:645`), which calls
  `setCurrentBookPathAndOldBookPath:` then `openPage:0 last:NO` — the
  exact same internal pair the `File > Open` menu's `open:` action
  (`Controller.m:659`) calls. Neither method has any "already open"
  guard, and `COImageLoader` does all its work synchronously on the
  main thread (no async/race window).
- **Extensive reproduction attempts, all unsuccessful:** added
  temporary `NSLog` diagnostics to `application:openFile:` and
  `openPage:last:`, rebuilt, and tested live via real Finder
  double-clicks (and `open -a`, which exercises the identical
  LaunchServices "open with running app" path) across: same-format
  switch (`.cbz` → `.cbz`), cross-format switch (`.cbz` → `.cbr`),
  two installed copies of cooViewer sharing the same bundle ID
  (discovered as leftover artifacts of this session's own repeated
  dev-build installs — a plausible theoretical cause, tested
  explicitly), and simultaneous multi-file open (two files passed to
  `open -a` in one call). In every case the window correctly switched
  to the newly requested file and the unified log confirmed
  `application:openFile:`/`openPage:last:` ran to completion each
  time. **The reported symptom did not reproduce under any of these
  conditions.**
- **Independent minor fix found and applied:** `application:openFile:`
  always `return NO;`, even on success — this violates
  `NSApplicationDelegate`'s documented contract (return `YES` if the
  file was opened, `NO` otherwise) and could affect Recent
  Items/LaunchServices bookkeeping, though no causal link to the
  reported symptom was established (the load always succeeded in
  testing). Changed to `return YES;` (`Controller.m:654`). No other
  behavior was changed; `open:` (the `File > Open` action) was not
  touched.
- **Icon-cache question — confirmed pure caching, no app-side bug:**
  `CFBundleTypeIconFile` = `coo_cbz`/`coo_cbr` in `Info.plist`'s
  `CFBundleDocumentTypes` are correctly declared; the actual bundled
  `coo_cbz.icns` was converted to PNG and visually matches exactly
  what Finder currently displays for `.cbz` files — no missing/wrong
  icon declaration exists. Confirmed `qlmanage -r` only resets
  `quicklookd`'s own cache, not Finder's separate Icon Services cache
  store, matching the task's own hypothesis. No code change needed.
- Along the way, discovered and cleaned up genuine LaunchServices
  registration debris (multiple stale claim entries for
  `jp.coo.cooviewer.cbz-archive`/`public.cbz-archive` pointing at
  different paths) — a byproduct of this session's own repeated
  install/test cycles across phases 7–9, not evidence of a real
  product bug, but confusing enough during investigation to be worth
  noting for future debugging.
- All temporary diagnostic `NSLog` lines were removed before
  finalizing; the only lasting change is the one-line return-value
  fix (plus incidental whitespace cleanup from the same edits).

### Verification

- **Build:** `xcodebuild -configuration Deployment` succeeds.
- **Manual:** extensive real-Finder and `open -a`/LaunchServices
  testing as described above; every scenario tried updated the window
  content correctly and activated the app correctly. Could not
  reproduce the reported "focus works, content doesn't update"
  symptom.
- **Regression:** the shared internal load path
  (`setCurrentBookPathAndOldBookPath:` + `openPage:0 last:NO`) was
  exercised repeatedly via `application:openFile:` and worked
  correctly each time; `open:` itself (the `File > Open` menu path)
  was not modified by this fix.
- **Not performed:** a GUI-driven `File > Open` menu-click regression
  test specifically — an unrelated app unexpectedly kept stealing
  focus during that part of the computer-use session. Not a concern
  here since `open:` was not touched by this change and its shared
  internal load path was already verified extensively via the
  `application:openFile:` path.
- **Icon:** documented above — confirmed to be pure caching, verified
  by direct visual comparison of the bundled `.icns` against what
  Finder displays, not by assumption.

### Remaining Issues

- The reported "double-clicking a second file doesn't switch the
  window" bug could not be reproduced despite testing same-format
  switching, cross-format switching, duplicate app registrations, and
  simultaneous multi-file opens, all via real Finder interaction. Root
  cause is undetermined. Console logs during testing showed only
  unrelated Accessibility-service TCC calls — no file-access denials —
  so a silent TCC/permission failure wasn't observed, though it wasn't
  ruled out for file locations not tested (e.g. cloud-synced folders).

### Follow-up Suggestions

- If the bug recurs, capture more specific repro details: exact
  double-click timing, whether multiple cooViewer copies might be
  installed on the affected machine, the exact file's location
  (particularly any cloud-synced or otherwise TCC-sensitive folder),
  and whether it happens every time or intermittently.
- Consider whether `openPage:last:`'s silent-revert-on-load-failure
  branch (`Controller.m:754`, `/*表示出来ない時は元に戻す*/`) should
  surface an error to the user instead of silently reverting to the
  previous book — today a failed load looks, from the user's
  perspective, identical to "nothing happened," which would produce
  exactly the reported symptom if a load ever does fail silently for
  a reason not exercised in this investigation.
