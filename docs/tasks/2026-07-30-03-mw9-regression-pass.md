# MW-9: Regression pass and release readiness

## Goal

Run the manual regression matrix from `docs/multiwindow-plan.md` as the
acceptance gate for the whole multi-window arc (MW-1 through MW-8), then
close out the arc's remaining documentation.

## Background

- Depends on MW-8 (done). This is the last task in the arc.
- Per the plan: follow the On-Device Verification Procedure in `CLAUDE.md`
  for anything touching QuickLook — nothing in this matrix should, but the
  app-install steps still apply.
- This is a verification pass, not an implementation task. If any matrix
  item fails, stop and report rather than silently patching around it —
  a fix belongs in its own task with its own commit/verification cycle,
  consistent with how MW-5's KNOWN_ISSUES #25 was split out rather than
  folded into MW-6.

## Scope — regression matrix

1. ZIP and RAR shown simultaneously in separate windows.
2. Different page / reading direction / zoom / rotation per window.
3. Closing one window does not disturb the other.
4. Two archives opened consecutively, and simultaneously.
5. The password prompt attaches to the correct window.
6. Thumbnail and Bookmark panels act on their own window.
7. A Preferences change reaches every window.
8. Closing another window while a slideshow runs.
9. Full screen, minimize, application deactivation — including two windows
   where one is full screen.
10. Opening several files at once from Finder.
11. No lost `RecentItems` / `LastPages` updates across concurrent closes.
12. An encrypted archive and a plain archive open concurrently.
13. The same book opened twice brings the existing window forward
    (decision 2).
14. Quitting with the last window (decision 4) records state before
    terminating.
15. Folder-as-book and `.cvbdl` package open correctly in their own
    windows.
16. **Image quality unchanged from the pre-MW baseline.** Capture the same
    page from the same fixture, at the same window size and
    `fitScreenMode`, on a pre-MW-1 build and on the final build, as a
    single-page view and as a two-page spread, and compare pixels (mean
    absolute difference + a sharpness measure — not a visual check). Per
    the plan, take the pre-MW-1 baseline with `BufferingMode = 1` (the
    default and the owner's setting; `BufferingMode = 0` renders spreads
    differently and is not a valid comparison point). Per the MW-7
    follow-ups finding, a spread-capture hash is not stable cross-session
    (window-corner anti-aliasing) — capture both sides of the comparison
    within the same session.

## Scope — build/release hygiene

- Build with no new warnings versus the current baseline (312: 310 source
  + 2 "not stripping binary", per MW-8).
- `build/` contains only `cooViewer.app`.
- Update `docs/DEV_LOG.md` and `docs/KNOWN_ISSUES.md`.

## Scope — documentation addendum (this session's decision)

- Record the Apple Remote (IR) decision made ahead of this task: current
  Macs have had no built-in IR receiver since the 2014 Mac mini, so the
  feature is inert regardless of code; `RemoteControlWrapper` stays in
  place for Preferences ▸ Input settings-compatibility only; on-hardware
  verification remains impossible; removal is deliberately not being done
  now (the only benefit — minor license cleanup — wasn't judged worth the
  Preferences-UI touch it would require). One line in either
  `docs/DECISIONS.md` or `docs/KNOWN_ISSUES.md` (not both, to avoid a
  future ambiguity about which is authoritative) is enough — suggested
  wording:

  > Apple Remote (IR) support is suspended, not removed: no current Mac
  > has a built-in IR receiver (last was the 2014 Mac mini), so the
  > feature is inert on any modern hardware. `RemoteControlWrapper` is
  > kept only for Preferences ▸ Input settings compatibility.
  > On-hardware verification remains impossible. Revisit removal only if
  > a concrete cost (e.g. an actual licensing conflict) appears.

## Out of scope

- Everything under "Explicitly out of scope for the whole arc" in
  `docs/multiwindow-plan.md` (NSDocument migration, Alias Manager → NSURL
  bookmark migration beyond MW-8's restoration-only use, `imageFileTypes`
  → `imageTypes`, the remaining `NSRunAlertPanel`/`NSBeginAlertSheet`
  sites, `validateMenuItem:` selector-dispatch refactor, the QuickLook/
  Thumbnail extensions, background archive loading).
- KNOWN_ISSUES #28 (`FilterPanelController` KVO/`CIFilter` release), #29
  (Alias Manager `CFString` leak), #30 (password-cancel quit UX decision)
  — pre-existing, not part of this gate.
- Fixing anything the matrix finds — see Background above.

## Notes for the implementing session

- This is the arc's acceptance gate — take the full matrix seriously
  rather than sampling it, and report failures as failures rather than
  reframing scope to route around them.
- If item 16's baseline capture requires reverting to a pre-MW-1 build,
  confirm the checkout/build process for that baseline doesn't disturb
  the current `main` working tree before starting.

---

## Implementation Result

**Status:** Completed with follow-up issues

This was a verification pass, so there is no product code change. Two
defects the matrix surfaced are recorded, not fixed, per the task's own
Background section.

### Changes

- `docs/KNOWN_ISSUES.md` — new #32 (a Finder open of a book that window
  restoration is bringing back gives two windows on the same book) and #33
  (loading a book, including the password sheet, still blocks the other
  windows).
- `docs/DECISIONS.md` — the Apple Remote (IR) suspension decision (the
  documentation addendum this task asked for; recorded in `DECISIONS.md`
  only, pointing at `KNOWN_ISSUES.md` §16 rather than restating it).
- `docs/DEV_LOG.md` — MW-9 / arc-closed milestone.
- No source, resource or project file was touched.

### Verification

**Build:** clean Deployment build of `main` @ `b28b135` with intermediates
outside the repository; `** BUILD SUCCEEDED **`. 312 `warning:` lines = 310
source warnings + 2 "not stripping binary because it is signed", i.e. the
documented baseline exactly. `build/` contains `cooViewer.app` and nothing
else; the QuickLook extensions are embedded in
`cooViewer.app/Contents/PlugIns/`.

**Method.** `System Events` UI scripting to drive the app, plus
`screencapture -R` of each window's content area (title bar excluded) and a
purpose-built comparator (mean absolute difference, mean |Laplacian|
sharpness, the softness measure used in MW-8, a diff bounding box and an
edge-vs-interior split). Two habits mattered and are worth reusing:

- Window frames were set **non-overlapping** before any pixel comparison. A
  region capture samples whatever window is in front, and an early run of
  item 2 produced a spurious "the other window changed" result purely
  because the Preferences panel and the second book window overlapped the
  capture rectangle.
- Every keystroke whose effect was *supposed* to be "nothing changes" was
  paired with a capture proving the keystroke had landed somewhere. An early
  "page updates are lost on Cmd+Q" result was **a harness artefact**:
  `keystroke` had not reached the target window at all, so the recorded page
  0 was correct (the window was still on the cover). Re-run with each
  advance confirmed by capture, all three windows recorded correctly.

**Matrix — 15 of 16 pass, 1 fails.**

| # | Item | Result |
|---|---|---|
| 1 | ZIP and RAR shown simultaneously in separate windows | PASS |
| 2 | Different page / reading direction / zoom / rotation per window | PASS |
| 3 | Closing one window does not disturb the other | PASS |
| 4 | Two archives opened consecutively, and simultaneously | PASS |
| 5 | The password prompt attaches to the correct window | PASS (see #33) |
| 6 | Thumbnail and Bookmark panels act on their own window | PASS |
| 7 | A Preferences change reaches every window | PASS |
| 8 | Closing another window while a slideshow runs | PASS |
| 9 | Full screen, minimise, deactivation, incl. one of two full screen | PASS |
| 10 | Opening several files at once from Finder | PASS |
| 11 | No lost `RecentItems` / `LastPages` updates across concurrent closes | PASS |
| 12 | An encrypted archive and a plain archive open concurrently | PASS |
| 13 | The same book opened twice brings the existing window forward | PASS in session, **FAIL across a relaunch** (#32) |
| 14 | Quitting with the last window records state before terminating | PASS |
| 15 | Folder-as-book and `.cvbdl` package in their own windows | PASS |
| 16 | Image quality unchanged from the pre-MW baseline | PASS (byte-identical) |

Item detail:

1. `test.zip` and `test.cbr` side by side, each rendering its own book.
2. test.zip rotated left + Fit to Screen; test.cbr Fit to Screen Width +
   next page + Left-to-Right. Per-window check marks confirmed in both the
   View menu and Setting ▸ Read from. test.zip's render before vs after all
   of test.cbr's changes: 692 of 3 345 192 samples differ, **all** within
   60 px of a window edge (chrome/shadow) — content untouched.
3. Cmd+W on test.cbr: test.zip stayed open, app alive, content identical,
   still responsive to input.
4/10. Consecutive opens 1 → 2 → 3 windows; one Finder open of four files
   gave exactly four windows, each with its own book.
5. The sheet reported `sheets = 1` on the newly created window and
   `sheets = 0` on the existing one, with the right archive name in its
   text. Attachment is correct; the app-wide modality is #33.
6. Two thumbnail panels coexisted, each naming its own book and page count
   (`1-4/4 test.zip`, `1-6/6 folder6`); a thumbnail click moved only its own
   window (mad 28.8 there, mad 0 on the other). A bookmark added in one
   window appeared only in that window's Bookmark menu.
7. Appearance ▸ View ▸ Background Black → Red with two windows open: both
   re-rendered by the same amount (mad 48.10 / 48.08, softness +36.158 % /
   +36.159 %). No crash on OK (#25's fix holds), focus returned to the
   window Preferences was opened from (MW-6 item 4), and restoring the
   colour returned both windows byte-identically to the pre-change render.
8. 24-page book with `LoopCheck = 0` so the slideshow could not self-stop:
   closing the other window left it running (three consecutive captures,
   mad 91.9 / 91.9 / 84.2) and Start/Stop then stopped it cleanly. With the
   owner's real `LoopCheck = 3` a slideshow stops at the last page by design
   (`-lockedImageDisplay`), which an earlier run of this item was actually
   observing.
9. Native full screen on one window (frame 0,0 1920×1080, menu bar
   auto-hiding, "Exit Full Screen" in the Window menu); the windowed sibling
   was untouched on its own Space and byte-identical afterwards; minimise,
   app deactivation/reactivation and unminimise all clean; exiting full
   screen restored the previous frame and both windows still responded.
11. Three books at three capture-confirmed page positions, closed together
    by File ▸ Close All **and** by Cmd+Q: all three recorded in
    `RecentItems` with distinct correct pages both ways (Close All: 1 / 3 /
    4; Cmd+Q: 3 / 1 / 4). `LastPages` stays empty because
    `AlwaysRememberLastPage = 0` in the owner's profile.
12. After the password was accepted the encrypted book opened in its own
    window beside the plain one, each navigable independently; the plain
    window's content was unaffected (all differing samples in a right-edge
    strip = the neighbour's shadow).
13. In-session: re-opening an open book from Finder brought its window
    forward instead of creating one; a single image *inside* an open folder
    book resolved to that book and brought its window forward;
    Open in New Window… on an already-open book likewise brought the
    existing window forward, and on a new book created a window;
    File ▸ Open… replaced the front window's book (decision 3).
    **Across a relaunch this fails — see `docs/KNOWN_ISSUES.md` #32.**
14. Closing the last window with Cmd+W quit the app (decision 4) *and*
    recorded the page (the book's `RecentItems` entry went 9 → 3 for the
    state it was left in). Cmd+Q with windows open records equally.
15. `folder6` (a folder of images) and `test.cvbdl` (a package) each opened
    in their own window, rendered correctly and navigated independently.

**Item 16 — image quality, in detail.** The pre-MW-1 baseline is `20c4919`
(the commit before MW-1), built in a detached `git worktree` under the
scratch directory so `main`'s working tree was never modified — confirmed
before starting, as the task asked. `vendor/lib` and `vendor/include` are
gitignored and unchanged since 2026-07-25, so they were copied into the
worktree rather than rebuilt. The owner's profile has `BufferingMode = 1`,
which is the comparison point the plan requires. Baseline and final build
were captured in the **same session**, same fixture (`test.zip`), same
window frame (200,100 1200×900), driven by one identical scripted sequence:

| state | Fit to Screen | Fit to Screen Width |
|---|---|---|
| cover, drawn as a single page | mad 0, maxdelta 0 | mad 0, maxdelta 0 |
| 002/003 two-page spread | mad 0, maxdelta 0 | mad 0, maxdelta 0 |
| single-page display mode | mad 0, maxdelta 0 | mad 0, maxdelta 0 |

All six pairs byte-identical, sharpness delta 0.0000 in every pair — a
stronger result than the mean-absolute-difference-plus-sharpness threshold
the task asked for. Sensitivity controls: cover vs spread on the same build
= mad 41.9; Fit to Screen vs Fit to Screen Width on the same build = mad
29.4 and 123.5. So the pipeline does detect real render differences, and
the arc adds no resampling step.

**Defaults hygiene:** `jp.coo.cooViewer` was exported before testing and
restored afterwards; the final export is **byte-identical** to the pre-test
one (one stray `NSWindow Frame GoToSheet` key written during testing was
removed). Test fixtures created for this pass (`folder6`, `folder24`,
`enc_images.zip`) were deleted; `tests/fixtures/generated/` is back to its
prior contents. The throwaway worktree was removed.

**Not performed:**
- Apple Remote on hardware — impossible, and now recorded as a decision
  rather than an open question (`docs/DECISIONS.md`).
- QuickLook / Thumbnail extension checks — out of scope for the arc, and no
  `/Applications` or `~/Applications` install was made, so no LaunchServices
  registration happened (`docs/KNOWN_ISSUES.md` #15).
- `leaks` / `NSZombieEnabled` — MW-7 and MW-8 both ran these on the same
  code; this pass added no code to instrument.

### Remaining Issues

- `docs/KNOWN_ISSUES.md` #32 — the one matrix failure: quitting with a book
  window open and then opening that same book from Finder gives two windows
  on it. Reproducible on default settings; a control with all windows closed
  before the quit gives one window.
- `docs/KNOWN_ISSUES.md` #33 — a book load, including the password sheet,
  is still application-modal, so the other windows cannot be operated while
  it is up. Pre-existing and deferred by design in MW-1; promoted to the
  issues list because multiple windows make it user-visible.
- Pre-existing and untouched: #28, #29, #30, #31.

### Follow-up Suggestions

- Fix #32 in its own task. The design question to settle first: when a
  restoration and an open request name the same book, which window survives
  — the restored one at its saved page, or the requested one at page 1?
- Fix #33 by making the open asynchronous, which MW-1 already named as the
  right end state once MW-7 landed.
- An **environment** observation, not a defect of this build: a stale
  QuickLook thumbnail extension from a deleted build directory
  (`$TMPDIR/cooViewer-step2/…/cooViewerThumbnail.appex`) is still registered
  with LaunchServices and gets launched when Finder draws the fixture
  folders. Same family as #15. Worth clearing with `pluginkit`/`lsregister`
  at some point; it did not affect this pass (the app was run in place from
  `build/`).
