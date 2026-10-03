# TASK: Stability fixes, RAR survey tool, per-window filters, dead-code removal

## Background

`docs/code-review-20261003.md` and `docs/cbr-performance-20261003.md`
(task record `docs/tasks/2026-10-03-04-cbr-perf-and-code-review.md`) list
defects, dead code and a solid-RAR4 regression. The owner chose to fix them
together in this task. The owner's decisions (in the cooViewer HQ chat):

- Solid RAR4: refuse clearly now (A1). Whether to support it for real is
  decided later, after the owner surveys their own books with a tool from
  this task. Password-protected RAR stays unsupported.
- `KeyspanFrontRowControl` (R2): delete.
- Filter settings (L6): per window instead of shared by all windows.
- GC-era guards C6–C8: simplify (remove the guard, keep the body).
- H1, owner's check on device: with ⌘N's empty window, clicking the left half
  did not crash, but a "1" with a balloon appeared depending on the spot.
  The owner's `LoopCheck` is 3; the recursion crashes with `LoopCheck` = 0.

No version change, tag or release in this task.

## Goal

The high-severity defects H1–H5 and the listed medium/low items are fixed and
covered by tests where practical; solid RAR4 fails with a clear message;
filters apply per window; the listed dead code is gone; and the owner has a
tool to classify their RAR books.

## Scope

### In scope

The parts below, with the IDs from `docs/code-review-20261003.md` and
`docs/cbr-performance-20261003.md`.

### Out of scope

- Real solid-RAR4 support (A2/A3), non-solid positioning (B1/B2),
  solid decode-ahead (C1), libarchive update (D1).
- Review items not listed here (M1, M3–M6, M8–M12, L2–L5, L8, L11), U12
  (XIB edit), S1, and C3b (stays; see KNOWN_ISSUES #40).
- Vendored sources. README.md. Version numbers.

### Parts

0. **Preflight.** `build/cooViewer.app` and its extensions were registered
   with LaunchServices when the owner launched it for the H1 check. Unregister
   them (`lsregister -u`, outside the sandbox) and confirm with
   `pluginkit -m | grep -i coo` that the extensions resolve only to
   `/Applications`. No commit.
1. **RAR survey tool.** `tools/rar_survey.py` (Python 3 from the macOS
   Command Line Tools, standard library only). Given one or more folders, walk
   them and, for each `.cbr`/`.rar`, read only the archive headers (never
   extract) and report: format (RAR4 / RAR5 / not RAR, e.g. a ZIP named
   `.cbr`), solid, multi-volume, header-encrypted, and for RAR4 whether the
   first file header uses `LHD_UNICODE` names; for RAR5, whether the first
   file is encrypted if that is cheap to read, else "unknown". Output one line
   per file (TSV) plus a summary count per category. Read-only; must not
   follow into or modify anything else. Test it on generated fixtures
   (`tests/fixtures/` and fixtures made with `rar` if available) covering each
   category. Then show the owner the exact command to run on their own folders,
   noting that Dropbox "online-only" files would be downloaded when read.
   Do not run it on the owner's folders yourself unless the owner asks in
   chat, and do not commit any of its output. One commit.
2. **Crash fixes.** H1 (bookless window page input: guard so no page action
   runs without a book; also fixes the "1" balloon the owner saw), H4, H5,
   M2 (cancel the thumbnail fill chain on window close), L7. One commit.
3. **Untrusted-input hardening.** H2, H3 together with L10, L9, M7, L1. Add
   engine-suite fixtures: a long entry name, a `../` entry with a `.zip`
   extension inside a book, a mislabelled `.cbr` (ZIP data). Keep fixtures
   synthetic and small. One commit.
4. **Solid RAR4 refused clearly (A1).** Detect `MHD_SOLID` (0x0008) in the
   RAR4 main header that `CORarHeaderIndex` already reads, and for the
   libarchive fallback path too. Fail the open with a clear, localized message
   (en/ja) instead of a book of broken pages; the QuickLook extensions should
   fail the same way (no partial cover decode). Add a test with a small solid
   RAR4 fixture (generate with `rar -s -ma4` if available; if not, report how
   one could be obtained). Record the limitation in `docs/KNOWN_ISSUES.md`
   #39. One commit.
5. **Per-window filters (L6).** Make filter changes apply only to the front
   window's view. The filter panel shows and edits the front window's
   settings and follows window switching. Keep the existing persistence
   behavior, applied per window; describe in the report what was persisted
   before and after. The filter is applied as before (no new resampling step;
   count the steps per `CLAUDE.md` ▸ INVIOLABLE before and after). Also fix
   KNOWN_ISSUES #28 (`deleteFilter:` KVO) if it is in the code you touch.
   One commit.
6. **Dead-code removal.** Proven items C1, C2, C3a, C4, C5, C9, C10, U1–U11;
   R2 (`KeyspanFrontRowControl.[mh]`, its `project.pbxproj` references and the
   `AppController.h` import); C6–C8: remove the
   `MAC_OS_X_VERSION_MAX_ALLOWED >= 1040` / `respondsToSelector:@selector(finalize)`
   guards and dead fallbacks, **keeping the guarded bodies** (they are live:
   font-panel mode mask, PDF links, `.savedSearch`). Re-verify each item
   against `CLAUDE.md` ▸ Dead Code just before deleting it; anything no longer
   provable goes to `docs/KNOWN_ISSUES.md` #40 instead. Update #40 and #16 for
   what was removed. One commit.

## Implementation notes

- MRC and the surrounding style. Keep explanatory comments that stay true.
- Each part: build with the `CLAUDE.md` command (getconf in its own call;
  `xcodebuild` on its own, no pipe), run `tests/engine/run_tests.sh`, and
  commit only when both pass.
- `AppleRemote.m` cannot be exercised on Apple Silicon; the edits there must
  be provably behavior-preserving on macOS 12+.
- Before any screen operation, ask the owner in chat to stand by and wait
  for the reply.

## Verification

- Engine suite passes after every part; report the check count.
- On device (main app only, `CLAUDE.md` procedure including step 4
  `lsregister -u`), in one pass after Part 6:
  - ⌘N empty window: click both halves, wheel, arrow keys, page-number entry
    → no balloon, no action, no crash. Repeat with `LoopCheck` = 0 only if it
    can be set in the app's preferences and restored afterwards; otherwise
    say so.
  - Bookmark edit sheet then close the window; slideshow running then close
    the window; thumbnail panel filling then close the window → no crash.
  - A solid RAR4 fixture shows the clear message; normal RAR4/RAR5/CBZ books
    still open and page.
  - Two windows with different filters: each keeps its own; the panel follows
    the front window.
  - A book with a PDF and a `.savedSearch` still work if fixtures exist
    (C7/C8); the font panel opens from Preferences (C6).
- `build/` holds only `cooViewer.app`; intermediates removed; nothing left
  registered under production bundle IDs.
- Before every push: `git fetch`, merge `origin/main` if it moved (never
  rebase or amend). Push with the owner's approval in chat.
- The Permission / Sandbox field is counted from
  `~/Library/Logs/claude-permission-requests.log` since the task started.

## Progress

- All parts committed: Part 1 bda0ff6 (+ 308e0ed `--solid-only`, requested
  by HQ for the owner), Part 2 5fb4dd2, Part 3 6b2ba0b, Part 4 68aa629,
  Part 5 841381a, Part 6 d4c5d0b, on-device fix 0a0f4be. Part 0 needed no
  commit. On-device pass done; preferences restored; registrations and
  intermediates cleaned up.
- Exact next step: none (archive and report).

## Implementation Result

**Status:** Completed with follow-up issues

### Changes

- **Part 0.** `build/cooViewer.app` unregistered (`lsregister -u`); the
  QuickLook extensions resolved only to `/Applications` before and after.
- **Part 1.** `tools/rar_survey.py` (stdlib, Python 3.9 from the Command Line
  Tools): reads only RAR headers of every `.cbr`/`.rar` under the given
  folders and prints TSV (format RAR4/RAR5/other, solid, volume
  no/first/later, header-encrypted, RAR4 `LHD_UNICODE` on the first file
  header, first-file encryption, online-only) plus a category summary on
  stderr. Read-only, does not follow symlinks; `--skip-online-only` lists
  cloud placeholders (`SF_DATALESS`) without reading them; `--solid-only`
  (added at the owner's request via HQ) prints only solid archives while the
  summary still counts all. Tests: `tests/tools/test_rar_survey.py` (10
  cases; RAR4 fixtures hand-written, RAR5 made with `rar` 7.23). The command
  was shown to the owner; the tool was not run on the owner's folders.
- **Part 2.** H1: `-lockedImageDisplay` returns with no pages (ended the
  `LoopCheck` 0 recursion); in a bookless window key, mouse, gesture, wheel,
  page-bar, context-menu and `switchSingle:` input runs only the window
  actions (close, open the last page, full screen, minimize); the page-bar
  bubble is drawn only with a page shown (the stray "1"). H4 `bookName = nil`
  after release; H5 `timer = nil` after every invalidate (15 sites); M2
  `-closePanel` cancels the thumbnail fill chain and wheel timers; L7
  `COPopUpTextField -dealloc`.
- **Part 3.** H2 heap buffers in `-finderCompareS:` for strings over
  `MAXPATHLEN`; H3 nested-archive entries that are absolute or contain `..`
  are skipped (`COIsContainedEntryPath`), L10 `mkdtemp` on an own buffer
  with its failure checked; L9 RAR4 data size past the file rejected; M7
  reader chosen by signature, then extension, and
  `+[COArchive lazyArchiveWithPath:]` (no full-extraction fallback) used by
  the cover extractor; L1 ZIP entries over 512 MB refused, prefetch only up
  to 64 MB. Engine fixtures from `tests/fixtures/make_hostile_fixtures.py`
  (long names, `../escape.zip`, oversized RAR4) plus mislabelled RAR-as-cbz
  and 7z-as-cbr.
- **Part 4.** `CORarIsSolidRAR4AtPath` (main header `MHD_SOLID`) checked in
  `-[COArchive initWithPath:]` before any reader, so both the header index
  and the libarchive fallback are covered; `-refusedSolidRAR4`; the app
  shows "Cannot open "<name>"." with an explanation (en/ja), as a sheet on a
  window that stays on screen, otherwise application-modal; the QuickLook
  cover extractor gets nil. `make_rar4_fixture.py --solid
  [--unicode-names]`. KNOWN_ISSUES #39 updated.
- **Part 5.** Filters per window: `FilterUIValueDidChange` is posted with the
  window controller as object and each `CustomImageView` listens only to
  its own (registered in `-setTarget:`); `-windowDidLoad` hands the restored
  filters to the view; an open Filter panel follows the main window.
  Persistence before and after: `CIFilters`/`CIFilterKeys` written on every
  change and read when a window is created; before, every window's view
  took every change (and a new window re-applied the saved set to all
  windows); after, a change and the restore apply only to the own window.
  #28 fixed (`-deleteFilter:` unregisters KVO). Render path: one
  `drawInRect:fromRect:` per page before and after; the filter is still a
  layer filter.
- **Part 6.** Removed C1, C2–C5 (AppleRemote, behaviour-preserving on 12+:
  AppKit ≥ 2113 makes both version tests false, leaving `leopardEmulation`),
  C9, C10, U1–U11 and R2 (`KeyspanFrontRowControl.[mh]`, 8 `project.pbxproj`
  lines, the `AppController.h` import); C6–C8 guards and fallbacks removed,
  bodies kept. Each re-checked against sources, XIBs, Info.plist, build
  settings, selector/KVC/class lookups. KNOWN_ISSUES #16 and #40 updated.
- **On-device fix (0a0f4be).** Part 5's `-ownerWindowBecameMain` and
  `-openFilterPanel:` read `filterPanel` through `frontPanelController`,
  which is nil until a panel has been opened — SIGSEGV on the first click
  into a window. Found in the on-device pass; guarded.
- Docs: KNOWN_ISSUES #16, #28, #39, #40, #41; DEV_LOG; DECISIONS (solid RAR4
  refusal, per-window filters, RemoteControlWrapper/GC guards);
  `tests/fixtures/README.md`.

### Verification

- Build: Deployment build succeeded after every part and after the fix (no
  new warnings; existing ones only).
- Automated verification: `tests/engine/run_tests.sh` ALL PASS after every
  part — 204 checks at start, 226 after Part 3, 246 from Part 4 on. Built
  against the pre-fix `NSString_Compare.m` the harness crashes (SIGSEGV) on
  the long-name fixture, and against the pre-fix `CORarHeaderIndex.m` the
  L9 check fails, so both tests detect their defects.
  `tests/tools/test_rar_survey.py`: 10 tests OK.
- Manual verification (on device, `build/cooViewer.app`, main app only,
  screen operation with the owner standing by):
  - ⌘N empty window with `LoopCheck` 3 and again with `LoopCheck` 0 (set in
    Preferences ▸ General ▸ Loop, restored afterwards): clicks on both
    halves, corners and the page-bar area, hover over the page-bar area,
    wheel, arrow keys, space, digits + Return, Home/End → no balloon, no
    action, no crash. Delivery was confirmed by the same inputs turning
    pages once a book was opened into that window.
  - The first attempt crashed (Part 5 defect above); everything after the
    fix ran in one process without a crash.
  - CBZ, RAR5 and RAR4 fixtures open and page. The solid RAR4 fixture shows
    the message as a sheet and the window keeps its previous book.
  - Two windows: a filter added in one, removed in the other → each keeps
    its own; the Filter panel shows the front window's filters when
    switching both ways.
  - Slideshow running (pages observed changing) then window closed; Edit
    Bookmark… sheet closed with OK then window closed → no crash.
  - Preferences ▸ Appearance ▸ Select… opens the font panel (C6).
  - Preferences were backed up with `defaults export` before and restored
    with `defaults import` afterwards; the three window-frame keys the test
    windows added were deleted; the final export is byte-identical to the
    backup.
- Not performed:
  - The application-modal form of the solid-RAR4 alert (open into a new,
    not yet shown window): the open panel's Go to Folder field could not be
    driven reliably; only the sheet form was seen.
  - Closing a window while its thumbnail panel is still filling: the panel
    covers the window and the 4-page fixture fills at once; the M2 change is
    verified by reading only.
  - C7/C8 on device: no PDF or `.savedSearch` fixture exists.
  - QuickLook extensions on device (solid RAR4 gives no cover): main-app-only
    procedure; covered by the engine test of `+lazyArchiveWithPath:`.
  - A solid RAR4 made by a real RAR4 compressor: `rar` 7.23 cannot write
    RAR4 and `rar` 6.x was not installed.
  - The H5 path "slideshow stopped earlier, window closed later" was not run
    separately (closing during a running slideshow was).

### Remaining Issues

- Review items not in scope stay open (KNOWN_ISSUES #41): M1, M3–M6,
  M8–M12, L2–L5, L8, L11; U12 needs an XIB edit (#40).
- Solid RAR4 is still unreadable (refused); real support awaits the owner's
  survey.

### Follow-up Suggestions

- Owner: run `tools/rar_survey.py` (or `--solid-only`) on the book folders to
  decide on A2/A3.
- On-device check of the application-modal solid-RAR4 alert and of the
  QuickLook extensions with a solid RAR4, ideally with a fixture from
  `rar` 6.x `-ma4 -s`.
- `pluginkit`/`lsregister`/`defaults` writes fail silently or are blocked in
  the sandbox (an in-sandbox `defaults export <file>` and `defaults import`
  wrote nothing without an error); worth a note in `CLAUDE.md` next to the
  existing sandbox notes.
- computer-use `open_application` resolves by bundle ID and launched the
  `/Applications` copy instead of `build/`; worth a note in `CLAUDE.md`'s
  test-copy guidance (launch with `open build/cooViewer.app` instead).
