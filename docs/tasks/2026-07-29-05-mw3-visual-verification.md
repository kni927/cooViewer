# MW-3 — On-Device Visual Verification (Screen Sharing Session)

## Context

Both MW-3 code changes (AppController split, then the persistence API) are
committed locally but not pushed. Two prior CLI/Tailscale sessions couldn't
complete this checklist — no working interactive window-server session in
that sandbox. This task runs under a real screen-sharing session (Jump
Desktop / Screen Sharing), so it should finally be possible.

See `docs/KNOWN_ISSUES.md` #22 and the archived tasks
`docs/tasks/2026-07-29-03-mw3-extract-appcontroller.md` and
`docs/tasks/2026-07-29-04-mw3-persistence-api.md` for exact background.

## Scope — run each item and record pass/fail with a short note

1. **Dock menu** — right-click (or Cmd-Tab-hold) the Dock icon, with a book
   open and with none open. Confirm the menu content is correct in both
   states and `applicationDockMenu:`/`openTheLastPage:` wiring on
   AppController works end-to-end.
2. **Bookmark round-trip via UI** — open a book, add a bookmark through the
   normal UI action (not `defaults` directly), quit, relaunch, confirm the
   bookmark persisted and is usable.
3. **OpenLastFolder-at-launch** — with the relevant preference enabled, quit
   and relaunch the app; confirm it reopens the last folder/book correctly.
4. **PDF pixel rendering** — open a real PDF-based book and visually confirm
   correct rendering (not just "opens without crashing" — actual pixel
   check, since MW-2's composited-path removal was previously left
   unverified for PDFs).
5. **Apple Remote** (if hardware available) — verify
   `remoteButton:pressedDown:clickCount:` and `appleRemoteHoldDown` behave
   correctly now that they live on AppController. If no hardware, note as
   not verified (consistent with prior sessions) rather than skipping
   silently.
6. **Recent Books / Open Recent menu** — sanity-check against the earlier
   CLI-session finding that this already worked end-to-end, just to confirm
   nothing regressed since.

## Before you start

- Back up the real `jp.coo.cooViewer` defaults domain first (as the
  persistence-API session did), so any accidental corruption during manual
  testing is recoverable.

## On completion

- Update `docs/KNOWN_ISSUES.md` #22 (close it if everything passes, or
  narrow it to whatever specifically still fails).
- Append the Implementation Result here, then archive to
  `docs/tasks/2026-07-29-NN-mw3-visual-verification.md` per
  `docs/task-workflow.md`.
- If everything passes: MW-3 is fully closed. Update `docs/DECISIONS.md`
  accordingly and clear the way for MW-4.
- If something fails: do NOT proceed to MW-4. File what specifically broke
  (method, symptom, repro steps) so the next session can fix it with full
  context.

## Implementation Result

**Status:** Completed

**Note:** this result was updated in place after the project owner granted
Screen Recording permission mid-session (initially to the visible terminal
app, which did not help; the OS's own consent prompt then named the actual
process needing it — `tmux`, in this session's `launchd → tmux → -zsh →
claude → zsh` chain — and granting it there worked). The first version of
this report below described item 4 as only partially verified, blocked on
that permission; it has been corrected to the final, fully-verified outcome
rather than kept as a stale intermediate state. See
`docs/KNOWN_ISSUES.md` #22 for the full permission-troubleshooting story and
`docs/DECISIONS.md`'s corresponding update for the closure decision.

### Changes

No code changes — this was a verification-only task. Two defaults keys were
toggled temporarily for testing (`OpenLastFolder`) and one test bookmark was
added, both reverted; see Verification.

### Verification

- **Build:** not applicable (no code changed). Confirmed `build/cooViewer.app`
  from the prior session (commit `ce01cbf`) was still the artifact under test.
- **Environment discovery:** this session, unlike the two prior CLI/Tailscale
  ones, has a real screen-sharing session attached (`ScreensharingAgent`
  running, real displays present) — `System Events` UI scripting (window
  enumeration, menu/sheet/table introspection, clicking, setting field
  values, `AXShowMenu`) works correctly and reliably here, a first for this
  project's on-device verification attempts. Screen Recording (a separate
  TCC grant from Accessibility) was initially missing — `screencapture -x`
  failed ("could not create image from display") — and granting it to the
  visible terminal app (Ghostty) did not fix it. Triggering `screencapture`
  again surfaced the OS's own consent prompt (`System Settings`'s "Screen &
  System Audio Recording" pane), which named the actual requesting process:
  `tmux` (this session runs `launchd → tmux → -zsh → claude → zsh`), not the
  terminal emulator. Granting it there made `screencapture -x` work
  immediately for the remainder of the session. See `docs/KNOWN_ISSUES.md`
  #22 for the full finding, including a timing gotcha hit along the way (a
  screenshot taken immediately after a document opens can catch a
  mid-first-paint frame and look like a rendering defect that isn't one).
- **Manual verification (real device, via `System Events`, real defaults
  domain backed up before and restored after — `defaults export`/`import
  jp.coo.cooViewer`):**
  1. **Dock menu — PASS.** Right-clicked the real Dock icon
     (`perform action "AXShowMenu"` on the Dock's `cooViewer` UI element) in
     both states. With `test.cbz` open: `test.cbz, Options, Show All
     Windows, Hide, Hide Others, Quit, Force Quit` — no custom item, correct
     since `hasBookOpen` is YES. With no book open (fresh launch, no file
     argument): `Open the last page, Options, Show All Windows, Hide, Hide
     Others, Quit, Force Quit` — the custom item appears exactly when
     expected. Confirms `-[AppController applicationDockMenu:]` and
     `hasBookOpen` end-to-end.
  2. **Bookmark round-trip via UI — PASS.** Opened `test.cbz`, used the real
     `Bookmark ▸ Edit Bookmark...` sheet (`BookmarkController`'s
     `addNewBookmark:`) to add a bookmark, quit the app (`osascript -e
     'tell application "cooViewer" to quit'`, a direct Apple Event — this
     runs `NSApplication`'s normal terminate sequence, which sends
     `windowWillClose:`), confirmed via `defaults read jp.coo.cooViewer
     BookSettings` that `test.cbz` gained `bookmarks = ({name = bookmark1;
     page = 1;})` — written by `-[AppController
     recordBookSettingsOnWindowClose:...]`. Relaunched `test.cbz` and
     confirmed `bookmark1` appears directly in the `Bookmark` menu (built by
     `-[Controller setBookmarkMenu]` from `-[Controller strongSetBookmark]`,
     which now reads via `[appController searchFromBookSettings:...]`).
     Full add → persist-on-close → reopen → menu-restores cycle confirmed
     with real UI actions, not just `defaults` inspection.
  3. **OpenLastFolder-at-launch — PASS.** Set `OpenLastFolder` to `YES`
     (`defaults write`, equivalent to the Preferences checkbox), quit,
     relaunched with **no file argument** — the app automatically reopened
     `test.cbz` (window titled `test.cbz` appeared). Exercises
     `-applicationDidFinishLaunchingSetup:` → `-openTheLastPage:` →
     `[appController searchFromRecentItems:...]`, a different call path
     through the same moved read helper than items 1/2 exercised. Restored
     `OpenLastFolder` to its original value (`0`) afterward.
  4. **PDF pixel rendering — PASS.** Opened a real PDF
     (`/Users/kni/Dropbox/statistics/51_318.pdf`, the user's own file — no
     PDF fixture exists under `tests/fixtures/`) via `open -a` and took a
     real screenshot once Screen Recording was working. First screenshot
     showed the page content area solid black — investigated rather than
     accepted at face value: opened the same PDF in macOS Preview.app and
     confirmed the file itself has real, visible content on page 1 (ruling
     out a corrupt/blank source file), then navigated within cooViewer
     (page-down, page-up) and took further screenshots, all of which showed
     correctly rendered pages — sharp Japanese/English text and colour
     diagrams, matching Preview.app's rendering of the same content. A
     clean re-launch with a longer wait before the first screenshot also
     rendered page 1 correctly. Conclusion: the one black frame was a
     screenshot-timing artifact (window mid-first-paint), not a cooViewer
     rendering defect — see `docs/KNOWN_ISSUES.md` #22. PDF rendering is
     confirmed correct, closing the gap left open by the legacy
     composited-path removal (`docs/tasks/2026-07-29-02-remove-legacy-composited-path.md`)
     and MW-2, both of which had left PDFs visually unverified.
  5. **Apple Remote — not verified**, no hardware present (checked
     `system_profiler SPUSBDataType`/`SPBluetoothDataType` for "remote";
     none found). Consistent with prior sessions; noted per TASK.md's own
     instruction rather than skipped silently.
  6. **Recent Books / Open Recent menu — PASS.** Read the real submenu via
     `System Events` (`entire contents`/`name of every menu item`): 40 real
     entries with correct filenames and page numbers, `test.cbz (P1)` at the
     front after being opened. No regression from the CLI-session finding
     in the persistence-API task.
  - Cleaned up after testing: removed the test bookmark from `BookSettings`
    and restored `RecentItems`/`OpenLastFolder` to their pre-session values
    by re-importing the backed-up defaults domain; verified the restore.

### Remaining Issues

- Item 5 (Apple Remote) remains unverified for lack of hardware — an
  accepted, permanent gap across every session of the whole multi-window
  refactor, not a new problem, and not a blocker for closing MW-3.
- No functional defects were found in anything checked. Items 1, 2, 3, 4,
  and 6 all passed with real, positive evidence (real UI actions, real
  `defaults` state, and — once Screen Recording was working — real pixels
  cross-checked against Preview.app).

### Follow-up Suggestions

- **MW-3 is fully closed** (Apple Remote's hardware gap accepted, as in
  every prior session) — `docs/DECISIONS.md` updated accordingly. MW-4 can
  proceed per `docs/multiwindow-plan.md`.
