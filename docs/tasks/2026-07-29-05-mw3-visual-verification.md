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

**Status:** Completed with follow-up issues

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
  project's on-device verification attempts. **Screen Recording is a
  separate permission and was not granted** — `screencapture -x` still fails
  ("could not create image from display") even though Accessibility-based
  UI scripting works. See `docs/KNOWN_ISSUES.md` #22 (rewritten this
  session to capture the finer-grained finding) for the exact evidence and
  how to apply it in future sessions.
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
  4. **PDF pixel rendering — partially verified.** Opened a real PDF
     (`/Users/kni/Dropbox/statistics/51_318.pdf`, the user's own file — no
     PDF fixture exists under `tests/fixtures/`) via `open -a`: no crash,
     window titled `51_318.pdf` appeared, and the rendered image element
     reported a real, plausible non-zero size (1709×1020) via
     `AXSize` — consistent with a page having actually decoded and drawn,
     not a blank/zero view. **True pixel-level visual correctness was not
     checked** — `screencapture -x` fails in this session (Screen Recording
     not granted; see above), so this specific item from TASK.md's scope
     ("actual pixel check... not just opens without crashing") is not fully
     satisfied.
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

- Item 4 (PDF pixel rendering) is not fully verified — the app opens PDFs
  and renders a plausibly-sized image, but literal pixel-correctness could
  not be checked because Screen Recording permission is not granted to
  whatever process underlies this session (Accessibility is granted;
  Screen Recording is a separate, still-missing grant — see
  `docs/KNOWN_ISSUES.md` #22).
- Item 5 (Apple Remote) remains unverified for lack of hardware, an
  accepted gap per TASK.md's own instruction, not a new problem.
- No functional defects were found in any item that *could* be checked —
  everything checkable (1, 2, 3, 6, and the non-pixel parts of 4) passed
  with real, positive evidence, not just "no crash."

### Follow-up Suggestions

- If the project owner wants item 4 fully closed, grant Screen Recording
  permission to whichever process underlies this dev session (System
  Settings ▸ Privacy & Security ▸ Screen Recording) and re-run the PDF
  check with `screencapture`, or perform the visual check directly during
  the screen-sharing session. Given no defect was found in anything that
  could be checked, and the gap is a specific, understood permission issue
  rather than an unknown risk, whether to treat items 4/5 as an accepted
  gap (the same treatment already given to item 5 across every prior
  session) and close MW-3 now, or hold until item 4 gets a real pixel
  check, is a call for the project owner — **left open, MW-3 is not marked
  fully closed by this session.**
