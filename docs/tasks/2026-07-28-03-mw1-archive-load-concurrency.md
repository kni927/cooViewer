# Task: MW-1 — Archive-Load Concurrency & Modal Safety

## Background
Per the Codex audit, archive loading currently:
- Pumps app-wide events during load progress (`nextEventMatchingMask:`,
  originally noted around Controller.m:1134) — in a single-window app this
  is harmless, but once multiple windows exist it will silently swallow
  input meant for other windows.
- Blocks the entire app during password entry via `NSAlert runModal`
  (originally noted around Controller.m:1161) instead of a window-scoped
  sheet.

This is the highest-risk defect identified for multi-window and the one
concrete correctness bug in the current single-window app (not just
future-proofing). Note: line numbers may have shifted since the audit
(MW-2 already touched CustomWindow/fullscreen code) — verify current
locations before editing rather than trusting the cited line numbers.

## Scope
- Replace the event-pumping progress mechanism with a background load
  (archive read off the main thread) that reports progress without
  consuming unrelated `NSApp` events.
- Replace the app-modal password `NSAlert runModal` with a window-scoped
  sheet (`beginSheetModalForWindow:completionHandler:`).
- Design cancel/Esc handling so it is unambiguous per load operation —
  doesn't need multiple windows to test, but should not hardcode "the one
  window" as an assumption.
- Must remain fully single-window; no behavior change visible to the user
  except modality (sheet vs. app-modal) and load no longer blocking via
  event-pumping.

## Out of scope
- Enabling multiple windows (MW-7).
- Anything already handled by MW-2 (fullscreen).

## Regression check
- Open a plain ZIP/RAR and a password-protected ZIP; confirm progress
  display, password prompt, and cancel all behave the same from a user
  perspective.
- Confirm via code review (and logging if needed) that load no longer
  calls `nextEventMatchingMask:` and password entry is no longer
  app-modal.

Archive per `docs/task-workflow.md` on completion.

---

## Implementation Result

**Status:** Completed

### Correction to the task's premise

TASK.md states "MW-2 already touched CustomWindow/fullscreen code". **MW-2
has not been done.** `git log` shows only documentation commits since
v1.5.2, and `Sources/CustomWindow.m` still contains the whole legacy
fullscreen implementation (`setFullScreen:`, `[NSMenu setMenuBarVisible:]`,
etc.). The cited line numbers had not shifted: `nextEventMatchingMask` was
at `Controller.m:1141` (the comment above it at 1134) and
`askArchivePassword:` at exactly 1161. Locations were verified before
editing regardless, as instructed.

### Changes

**`Sources/Controller.m` / `Controller.h`**

- `-archiveReadProgress:total:` no longer dequeues NSApp's event queue. It
  now only records progress into atomics and returns whether the load was
  cancelled. This is the actual bug fix — the old loop consumed *every*
  pending event and discarded everything that was not Esc.
- New `-runArchiveLoadNamed:usingBlock:` runs the archive read on a
  `QOS_CLASS_USER_INITIATED` queue. The main thread waits 150 ms first;
  if the read finishes within that, nothing is shown at all. Otherwise a
  progress sheet is attached to the window and the main thread drives an
  `NSModalSession` until the read completes.
- The modal loop's exit condition is the semaphore, **not** a `-stopModal`
  posted from the background thread. A `-stopModal` delivered before the
  loop started would be a no-op and the loop would then never end; polling
  the semaphore has no such race. The timed wait also paces the loop, so
  `-runModalSession:` is not spun continuously.
- New progress sheet built in code (no nib change, which keeps MW-5's nib
  split smaller): label, determinate progress bar, Cancel button with Esc
  as its key equivalent — so Esc still cancels a load, as before.
- `-askArchivePassword:wrongPassword:` presents as a sheet on the owning
  window instead of `[alert runModal]`. The caller needs an answer
  synchronously, so the sheet runs its own modal loop. Falls back to
  app-modal if no window can host a sheet.
- `-sheetParentWindow` added as the single place that decides which window
  a load's sheets belong to. One window today; the seam exists so MW-5 can
  make it per-window without hunting for `window` references.
- Removed the now-unused `lastArchiveProgressPump` ivar (it existed only
  to throttle the deleted event pump).

**`Sources/COImageLoader.m`** — the `COArchive` construction in `-content`
is handed to the host via `-runArchiveLoadNamed:usingBlock:` when one is
available. Only the read moves off the main thread; `-checkArchiveContainer:`
and its password prompt still run on the caller's thread exactly as before,
which is why the prompt needs no thread marshalling. Hosts without a
controller — the QuickLook and Thumbnail extensions — keep the plain
synchronous read.

**`Sources/CORarArchive.h`** — its thread-safety note required the index
pass to run on the main thread *because* the progress callback pumped
NSApp's event queue. That rationale is gone, so the note was rewritten: the
real constraint is that the pass stay confined to a single thread, which it
still is.

**`Resources/{en,ja}.lproj/Localizable.strings`** — added `Opening “%@”…`
and `Cancelling…`.

Nesting: an archive inside an archive re-enters through the same host hook.
`archiveLoadDepth` ensures only the outermost load gets a background thread
and a sheet; inner ones run inline, as every load did before, minus the
event pump.

### Verification

- **Build:** `BUILD SUCCEEDED`, Deployment configuration, via the CLAUDE.md
  command. No warnings from any changed line (checked by line range across
  `Controller.m`, `COImageLoader.m`, `CORarArchive.h`). The 143 warnings in
  the build are pre-existing deprecations in untouched code.
  Note: an early "0 warnings" baseline was a cached no-op build and was
  discarded; a clean baseline in a `git worktree` was not possible because
  the vendored libs (`vendor/`, gitignored) are absent there.
- **Automated:** none added. There is no test harness for this path —
  `tests/engine` covers the archive engine below the UI, not load modality.
- **Manual, on device** (`build/cooViewer.app`, main app only per CLAUDE.md;
  `/Applications` and `~/Applications` untouched, no LaunchServices
  registration):
  - `sample(1)` during a slow load shows `-[COArchive readArchiveWithProgress:]`
    running on `DispatchQueue_16: com.apple.root.user-initiated-qos` while
    the main thread sits in `-[Controller runArchiveLoadNamed:usingBlock:]`
    → `-[NSApplication runModalSession:]`. Read off-main and main thread in
    a real AppKit modal loop, both confirmed directly.
  - No `nextEventMatchingMask` from cooViewer code in any sample (only
    AppKit's own event loop).
  - Progress sheet renders correctly, attached to the window, with a live
    determinate bar fed from the background thread (screenshot).
  - Esc during a load cancels: process alive, modal session gone, main
    thread back to idle in `-[NSApplication run]`, window closed — the same
    end state Esc produced before MW-1.
  - Fast opens show no sheet: `test.cbz`, `test.cbr`, `test.7z`, `test.tar`
    and the `test.cvbdl` package all open normally. A 129 MB tar loaded in
    ~92 ms and correctly stayed under the grace period.
  - Encrypted ZIP: prompt appears as a sheet; correct password opens the
    book and the page renders; wrong password re-prompts with "Incorrect
    password"; Cancel fails closed with no hang.
- **Not verified:** behaviour with more than one window (there is only one
  — MW-7); the Japanese rendering of the two new strings (system locale is
  English here; the entries were verified to parse back out of both
  `.strings` files); RAR's libarchive fallback path specifically (the
  fixtures take the fast header-parser path).

### Remaining Issues

- The progress sheet and its subviews are created once and retained for the
  process lifetime. Consistent with the rest of this MRC codebase, where
  `Controller` is a nib singleton that is never deallocated, but it becomes
  a per-window teardown concern in MW-5.
- The 150 ms grace period is a hardcoded constant. It is the value that
  keeps the common formats (which never report progress at all) from
  flashing a sheet; it is not tuned beyond that.

### Follow-up Suggestions

- `Resources/en.lproj/Localizable.strings` is UTF-16LE while
  `ja.lproj/Localizable.strings` is UTF-8. Appending to the former with a
  UTF-8 tool silently corrupts it (this happened during this task and was
  caught and reverted). Worth normalising both to UTF-8, or documenting it
  in `docs/KNOWN_ISSUES.md`.
- The remaining task-scope item deferred by design: making the *whole*
  open asynchronous, so other windows stay live during a load rather than
  being modally blocked. Not needed for correctness — nothing is dropped
  now — but it is the better end state once MW-7 lands.