# KNOWN_ISSUES #30 + #33 (password half): window-modal password prompt

## Goal

Make the archive password prompt window-modal so other windows stay usable
while it is up (#33's password half), and settle the cancel behavior that
#30 left as an open design question. Both live in the same code path, so
they are one task.

## Background

- The prompt is currently a modal `NSAlert` + `NSSecureTextField` accessory
  (no NIB), chosen when password-protected ZIP support was restored.
- **#33 (password half):** the prompt is *app*-modal, so it blocks every
  other window. MW-9 matrix item 5 confirmed the prompt already attaches to
  the correct window — association is right, modality is the problem.
- **#30:** canceling the prompt as literally the first action of a session
  used to quit the app (`-openPage:last:`'s failure path closes the
  just-fronted window, and quit-on-last-close then terminated). A
  session-state guard added in the MW-7 follow-ups stops the quit, but the
  underlying question was never answered: what *should* happen on cancel?
- The open path expects the password as a synchronous return value with a
  retry loop. `beginSheetModalForWindow:completionHandler:` requires
  restructuring that into continuation-passing — this is the bulk of the
  work, not the sheet itself.
- The QuickLook/Thumbnail extensions show the default icon for encrypted
  archives rather than prompting, so they don't exercise this path — but
  they do share the archive layer, so don't break it.

## Design decisions to settle (decide explicitly, record in DECISIONS.md)

1. **Cancel behavior.** Candidates: (a) close the window — today's
   behavior minus the quit bug; (b) leave the window open and empty, ready
   to be reused by the next open; (c) if the window previously showed a
   book, leave that book displayed. Note (b) matches what MW-8 established
   for a failed restore (empty slot, cleanly reused), and (a) interacts
   badly with quit-on-last-close — canceling on the last window would quit
   the app, which is exactly the surprise #30's guard currently papers
   over. (b) looks right, but confirm against the actual code before
   committing to it.
2. **Wrong password.** Re-present the sheet in place with an error, or
   give up after N attempts and fall to the cancel behavior?
3. **Whether #30's session-state guard is still needed** once the cancel
   behavior is settled. If the new behavior makes it dead weight, remove
   it — but verify that, don't assume it.

## Scope

1. Convert the prompt to a window-modal sheet
   (`beginSheetModalForWindow:completionHandler:`), keeping the existing
   no-NIB `NSSecureTextField` accessory approach unless the code makes that
   awkward.
2. Restructure the open path's synchronous password/retry loop into
   continuation-passing.
3. Implement the decided cancel and wrong-password behavior; simplify or
   remove #30's guard if genuinely obsolete.
4. **Reconcile with #32's launch settle logic.** `-[AppController
   settleLaunch]` polls until no window has restoration work outstanding,
   with a 3-second deadline. A restored encrypted book now waits on *human
   input*, which can easily exceed 3 seconds — the deadline would fire and
   the queued Finder open would drain early, reintroducing the duplicate
   window #32 just removed. Decide whether "waiting on a password sheet"
   should count as outstanding restoration work (and so pause the poll
   rather than race the deadline), and test it. This is the one place the
   two tasks genuinely collide.

## Out of scope

- #33's book-loading half / background archive loading — deliberately
  pending (not a bug; local archives open in under 0.2s).
- #24, #28, #29, #31 — unrelated open items.
- Encrypted RAR — already declined; the workflow is to decrypt externally
  and re-compress as encrypted ZIP.

## Verification plan

- Build: warning-count/content diff against the current baseline — 312
  lines = 310 source + 2 "not stripping binary". Re-measure the baseline in
  the same session (`xcodebuild` warning output isn't perfectly
  reproducible run to run).
- Image quality: render path untouched, so same-session spread captures
  should be byte-identical. Capture both sides in one session, windows
  positioned non-overlapping. Expect #31's first-open jitter to show up on
  single-page cover captures — per the #32 session, compare against a
  second run of the baseline rather than treating the first run as truth.
- `leaks` / `NSZombieEnabled` across encrypted-open cycles including
  cancels and wrong passwords — the continuation restructure is exactly
  the kind of change that strands a retained block or controller.
- Defaults domain zero-diff; test fixtures out of Recent Books; saved
  application state from testing discarded.
- Manual, test build only — launch from `build/` directly; do not install
  to `/Applications` or `~/Applications`:
  - **The point of the task:** with book B open in window B, open an
    encrypted archive in window A — window B stays fully interactive
    (page turns, menus, panels, scrolling) while A's sheet is up.
  - Correct password → book opens normally.
  - Wrong password → the decided behavior, repeatedly.
  - Cancel → the decided behavior.
  - **The #30 scenario:** cancel the prompt as literally the first action
    of a cold-launched session → app must not quit.
  - Cancel on the last remaining window → app must not quit.
  - **Two sheets at once:** restore two encrypted books (or open a second
    encrypted archive while the first sheet is up) → each sheet is
    independent and attached to its own window; answering one doesn't
    disturb the other; canceling one doesn't cancel the other.
  - **Scope item 4:** relaunch with a restored encrypted book *and* a
    Finder open queued, and leave the sheet sitting for well over 3
    seconds before answering → no duplicate window, no stranded request.
  - Cmd+W while a sheet is up; quit while a sheet is up.
  - A restored encrypted book at launch, answered correctly → opens at its
    saved page (MW-8 behavior preserved).

## Notes for the implementing session

- Per established practice: read the actual open/password path before
  finalizing the commit plan, and if measurement contradicts anything
  stated above, trust the measurement and correct the record — the #32
  session did exactly that with the launch ordering, to good effect.
- Scope item 4's interaction is a prediction from reading the #32 report,
  not something observed. Verify the deadline actually behaves as described
  before designing around it.
- If a decision surfaces that isn't covered by the three above, stop and
  report rather than picking silently.

---

## Implementation Result

**Status:** Completed

### Changes

- `Sources/COImageLoader.h/.m`
  - Opt-in `deferPasswordPrompt` on a new designated initializer. A loader
    built with it never blocks to ask for a password: it reports
    `-needsPassword` and the host drives the prompt. Both existing
    initializers pass NO, so nothing but an explicit opt-in changes behaviour
    — nested archives and the QuickLook/Thumbnail extractors are untouched.
  - `-tryPassword:` — one attempt, returning `COArchiveCryptoStatus`. On
    success it finishes exactly what `-content` would have done had the
    password been known at init time (re-scan, enumerate, drop the
    placeholder page), so the loader is indistinguishable from one that never
    needed asking.
- `Sources/BookWindowController.h/.m`
  - `-openPage:last:` split after the loader is constructed;
    `-openPageWithLoader:page:last:fromFileName:` is the rest of it. Three
    things cross the seam (loader, page request, `fromFileName`); everything
    else was already ivars.
  - `-abandonOpenWithLoader:fromFileName:closeWindow:` — the old failure tail,
    extracted so a cancelled prompt can take it with `closeWindow:NO`.
  - `-askPasswordForLoader:page:last:fromFileName:wrongPassword:` — the sheet,
    with `beginSheetModalForWindow:completionHandler:` and **no** modal loop.
    OK → `-tryPassword:` → open, or re-present on a wrong password; Cancel →
    abandon without closing. Falls back to the synchronous prompt when there
    is no window to attach a sheet to.
  - `passwordOpenInFlight` / `-isWaitingForUserInput`, and
    `-isRestoredBookUnfinished` extended by it. `windowClosed`, set in
    `-windowWillClose:`, guards the sheet's completion handler and the
    re-ask — AppKit dismisses a sheet with its parent, so both can fire for a
    window that is gone.
  - The synchronous `-askArchivePassword:wrongPassword:` stays, for nested
    archives.
- `Sources/AppController.h/.m`
  - `-emptyWindowController` factored through `-isWindowControllerEmpty:`,
    which now also excludes a window whose open is waiting on a password.
  - `-settleLaunch` pushes its drain deadline forward while any window is
    waiting on user input.
- `docs/DECISIONS.md`, `docs/KNOWN_ISSUES.md` (#33's password half marked
  fixed, the loading half kept; #30 resolved and its stale "how to reach the
  failure path" note corrected), `docs/DEV_LOG.md`.

**No render-path change.** Nothing was added between the decoded `NSImage` and
`[page drawInRect:fromRect:]`; `-openPageWithLoader:...` is the same code that
used to be the second half of `-openPage:last:`.

**One incidental fix, recorded rather than silent:** the extracted failure tail
releases `fromFileName`, which the old failure branch leaked (it carries the
retain `-openPage:last:` takes from `currentBookPath`, and only the success
path released it). The cancel path needed it; the pre-existing path gets it too.

### Decisions settled (recorded in `docs/DECISIONS.md`)

1. **Cancel** — a window that already had a book keeps showing it; a window
   with none is left bookless and **ordered out, not closed**. That is MW-8's
   failed-restore state (registered, not shown, reused by the next open) and
   it cannot trip quit-on-last-close, which is what #30 was about. Confirmed
   against the code first, as the task asked: the "restore the old identity
   strings" branch already did half of this.
2. **Wrong password** — re-present in place with "Incorrect password", no
   attempt cap. Cancel is the existing exit; a cap would only add a second way
   to fail and buys nothing for a local file.
3. **#30's session guard stays, and is still load-bearing.** Verified rather
   than assumed: the other live route into that failure branch is a cancelled
   archive *read*, which still closes a fresh window. Reproduced with a 104 MB
   `.7z` — progress sheet, Esc, window closed, app alive because of the guard.
4. **Scope item 4** — "waiting on a password sheet" counts as outstanding
   restoration work *and* pauses #32's drain deadline.

### Verification

**Build:** clean Deployment build, `** BUILD SUCCEEDED **`, 312 `warning:`
lines = 310 source + 2 "not stripping binary". Compared against a clean build
of the previous commit (`81a34b8`) made in the same session: 45 distinct
warning messages, **multiset identical**. `build/` holds `cooViewer.app` only.

**Manual, on device** (`build/cooViewer.app` run in place; `/Applications` and
`~/Applications` untouched):

| Check | Result |
|---|---|
| **The point of the task:** book B open, encrypted archive opening in A | with A's sheet up, B was raised, became main, its View/Setting items were enabled and a page turn changed its content (mad 79.6). Before: the whole menu bar was disabled |
| Correct password | book opens normally, window title becomes the book's |
| Wrong password ×3 | sheet re-presented in place each time, "Incorrect password", then the correct one opened the book |
| Cancel, with another book open | the sheet's window disappears, app alive, the other book byte-identical (mad 0), and the next open **reused the empty slot** rather than adding a window |
| **The #30 scenario:** cancel as the first action of a cold launch | app alive, zero visible windows, and the next open reused the slot |
| Cancel on the last remaining window (via File ▸ Open) | app alive, the previous book still displayed byte-identically |
| **Two sheets at once** | two windows, two independent sheets naming their own archives; answering one opened only its book and left the other's sheet up; cancelling the other disturbed neither remaining window |
| **Scope item 4:** restored encrypted book + queued Finder open, sheet held 12 s (deadline 3 s) | exactly **one** window after answering, at the restored page — no duplicate, no stranded request |
| Same, with the deadline pause removed in a probe build | **two** windows — the pause is what does the work |
| Restored encrypted book, answered correctly | opens at its saved page (mad 115 vs a page-1 render of the same book) |
| Nested encrypted archive (encrypted ZIP inside a plain ZIP) | still prompts, still opens, menu bar disabled — the synchronous path, unchanged by design |
| Cmd+W while a sheet is up | ignored; the sheet stays, app alive |
| Quit while a sheet is up | dropped, not deferred — **measured identically on the pre-change build**, so unchanged by this task |

**Image quality:** same-session capture comparison against a build of the
previous commit, same fixture and frame, windows non-overlapping. The two-page
spread is **byte-identical** in all three comparisons. The single-page cover
capture differs between the baseline's *own* two runs by exactly the amount it
differs from this build (mad 0.343543, maxdelta 58) — `KNOWN_ISSUES` #31's
first-open jitter — and baseline run 2 is byte-identical to this build.

**`NSZombieEnabled` + `MallocScribble`:** two rounds of wrong-password →
cancel, then a successful encrypted open and a close, with a second book open
throughout. No crash, no message-to-deallocated-instance abort.

**`leaks`** on the same cycles without zombies: 331 leaks / 21 392 bytes, all
`CFString` roots (`KNOWN_ISSUES` #29) plus the known `NSBezierPath` root. No
`COImageLoader`, `BookWindowController`, `NSAlert` or `NSSecureTextField` leak;
the only block leaks are system ones (`NSXPCConnection`, `AppIntents`). The
continuation restructure strands nothing.

**Defaults hygiene:** domain exported before testing and restored afterwards;
final export **byte-identical**, no test fixture in Recent Books. The app was
left quit with no windows open, so no saved application state is pending.
Fixtures created for this pass (`enc_images.zip`, `enc_images2.zip`,
`outer_with_enc.zip`, `enc_unsupported.7z`, `big.tar`, `big.7z`) were deleted
and the throwaway worktree removed.

**Not performed:** Apple Remote on hardware (impossible — `docs/DECISIONS.md`);
the QuickLook/Thumbnail extensions (they never reach this path —
`COCoverExtractor` has no controller — and the loader changes are opt-in, so
their behaviour is unchanged by construction).

### Remaining Issues

None for #30 or #33's password half.

Known and deliberate:

- `KNOWN_ISSUES` #33's **loading** half is still open: a load blocks the other
  windows, because the progress sheet is driven from an `NSApp` modal session.
  Out of scope here.
- The prompt for an archive nested inside another archive is still synchronous
  and app-modal (decision 3).
- The app cannot be quit while the prompt is up. Pre-existing and measured
  identically on the previous build.

### Follow-up Suggestions

- Make quit work while a password sheet is up (an `applicationShouldTerminate:`
  that dismisses in-flight sheets). It is a one-method change, but it is a
  behaviour decision and this task only asked me to test the case.
- The loading half of #33, when someone wants it: the seam this task added
  (`-openPageWithLoader:...` plus a loader that can be resumed) is where an
  asynchronous open would attach.
