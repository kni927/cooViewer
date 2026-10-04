# TASK: Fix the remaining code-review findings

## Background

`docs/code-review-20261003.md` listed defects; the high-severity ones and
part of the rest were fixed in `docs/tasks/2026-10-03-05-stability-fixes-and-rar-survey.md`.
The owner wants the remaining findings fixed before the next release
(cooViewer HQ chat, 2026-10-04). `docs/KNOWN_ISSUES.md` #41 tracks them.

## Goal

Every remaining finding below is fixed and covered by a test or an on-device
check, or recorded with the reason it was not fixed.

## Scope

### In scope

The findings named in the parts below, with their IDs from
`docs/code-review-20261003.md`.

### Out of scope

- New features, version change, tag, release (a separate task).
- Solid-archive decode-ahead (C1), libarchive update.
- Performance follow-ups suggested by the last TF (continuing the cursor when
  the next page is also next in stored order, cancellable prefetch, cache
  limit by RAM) — record them as follow-ups only.

### Parts

Commit each part separately, in this order. If your context passes two thirds
before the end, wrap up after the current part and report what remains
(`docs/sessions.md`).

1. **Data loss and book state:** M1 (Save Image… onto its own source deletes
   the original), M3 (menu opens while a password sheet is up cross book
   settings), M4 (next/previous folder walks a stale or empty submenu), M11
   (page-bar click in the last 2 px goes past the last page), M12
   (`characterAtIndex:0` on an empty key string), L2 (one unreadable nested
   archive aborts the whole book), L5 (`objectAtIndex:0` after `-lookahead`
   on a one-page book).
2. **Archive consistency:** M6 (RAR link entries counted differently by the
   header index and the cursor; check it on the direct-positioning path added
   in `docs/tasks/2026-10-04-01-autohide-resolution-rar-positioning.md`), L4
   (duplicate entry names resolve to the first entry), M9 (wrong ZipCrypto
   password accepted about 1 in 128), L3 (QuickLook extensions keep decoding
   after returning the cover).
3. **Lookahead synchronisation:** M5 and M8. Higher regression risk: add a
   stress check (key-repeat paging, slideshow, window close during load,
   `ImageCache` not 0 for M8).
4. **Small items:** L8 (`keyArray`/`mouseArray` mutated while enumerated),
   L11 (bookmark-icon removal skips entries, uninitialised shadow colour,
   negative `ImageCache`, 256 KB stack buffers on 512 KB threads), U12 (unused
   outlets `contextMenuItem`/`contextMenu`, with the XIB connections).
5. **Spread geometry, M10:** the spread path truncates the image size to whole
   points for `fromRect`. This changes output pixels on purpose. It must not
   add a resampling step (`CLAUDE.md` ▸ INVIOLABLE: count the steps before
   and after; the count must stay one). Verify with the Spread Capture and
   Comparison Methodology in `CLAUDE.md` (`tools/spread_diff.py`): an image
   with integral size is unchanged; a fractional-size image (e.g. a 595.28 pt
   PDF page, or a high-DPI scan with `IgnoreImageDpi` off) loses no edge. If
   any doubt remains about the render path, stop and report instead of
   committing this part.

## Implementation notes

- Read each finding's detail in the report before changing code; the line
  numbers have moved since. If a finding no longer reproduces or is already
  fixed, say so and do not change the code.
- MRC and the surrounding style. Keep explanatory comments that stay true.
- Update `docs/KNOWN_ISSUES.md` #41 (and #40 for U12) as items are fixed.

## Verification

- Each part: `CLAUDE.md` build command (getconf in its own call;
  `xcodebuild` alone), `tests/engine/run_tests.sh` ALL PASS (302 checks or
  more), new engine tests where the finding is in the engine.
- On device after all parts, main app only (`CLAUDE.md` procedure including
  step 4 `lsregister -u`): ask the owner to stand by first; launch by path;
  confirm the frontmost app and window before every keystroke or click. Save
  and restore preferences with `defaults export DOMAIN -` and an
  out-of-sandbox import, then read them back. Check at least M1, M3, M4,
  M11, the lookahead stress check, and the M10 spread capture.
- Before every push: `git fetch`, merge `origin/main` if it moved (never
  rebase or amend). Push with the owner's approval in chat.
- Permission / Sandbox counted from `~/Library/Logs/claude-permission-requests.log`.

## Progress

- All five parts committed: Part 1 73feb80, Part 2 4c3b7c1, Part 3 f91e50c,
  Part 4 8f7bedf, Part 5 3186618 (committed after the spread capture).
  On-device pass done; preferences restored; test bundles unregistered.
- HQ correction (2026-10-04): the "two thirds" wrap-up line is withdrawn;
  follow docs/sessions.md (local TF wraps up from 80%, at the latest after
  90%); after completion, wait for the next TASK. Confirmed by the owner.
- Exact next step: none (archive and report).

## Implementation Result

**Status:** Completed with follow-up issues

### Changes

- **Part 1 (73feb80).** M1: Save Image… onto its own source (same file
  resource identifier) does nothing; replacing another file copies into an
  `NSItemReplacementDirectory` and swaps in with `replaceItemAtURL:`. M3:
  `-refuseOpenWhileBusy` (beep) at the top of `-open:`, `-openTheLastPage:`,
  `-openBookAtPath:` (All Bookmark browser), `-openFromSameDir:last:` (menu
  and next/previous-folder keys) and `-openFromOpenRecent:` while
  `bookLoadInFlight` or `passwordOpenInFlight`. M4: `-refreshSameFolderMenu`
  (claims the submenu delegate, `-checkCurrentFolderUpdated`, rebuild) runs
  before next/previous folder, which share `-sameFolderItemStepping:`; the
  check-mark path no longer needs `oldBookPath`. M11: `-goToPar:` clamps to
  the last page. M12: empty key strings and dead keys guarded at every
  `characterAtIndex:0` that can see them (the Apple Remote paths always
  build one-character strings and were left). L2: an unreadable nested
  archive is skipped with a log line. L5: `-lastSpreadStartPage` (never
  below 0) at the eight last-spread sites, each guarded for two loaded
  pages. New `tests/engine/test_imageloader.m` (COImageLoader harness;
  embeds `Resources/Info.plist`, overrides `NSTemporaryDirectory` with
  `$TMPDIR` for sandboxed runs) and `broken_nested.cbz`.
- **Part 2 (4c3b7c1).** M6: `CORarEntryCounts` (directory, symbolic link,
  hard link, zero size, encrypted, AppleDouble) shared by the libarchive
  index pass and the cursor; the cursor skips non-counting headers right up
  to the page it lands on (also when continuing on the direct-positioning
  path) and fails closed when the landed header's size disagrees;
  `CORarHeaderIndex` skips RAR5 redirection records (extra record 0x05) and
  RAR4 Unix symbolic links. L4: `entryIndicesByRawName` and
  `duplicatePagePaths`; the n-th page of a repeated path is the n-th entry
  (or nested loader page) of that name; repeated nested archives extract to
  `.dup-<index>/`; prefetch page order follows the same rule. M9: CRC,
  zlib, compressed-data, inconsistency and data-length errors in the
  validation entry count as a wrong password (ZipCrypto's one-byte check;
  AES HMAC failures are reported as CRC errors too). L3:
  `-[COArchive disablePrefetch]` / `-prefetchCount`; the cover extractor
  disables prefetch before reading the cover. Fixtures: RAR4 symlink
  (`make_rar4_fixture.py --symlink`, plain and Unicode), RAR5 symlink plus
  hard link (`rar -ol -oh`), `dup_names.cbz`.
- **Part 3 (f91e50c).** M5/M8: `-waitForLookahead` / `-stopLookahead`
  (wait on `pendingLookaheadCount`, bounded 2 s, then one `lock` barrier)
  replace the 62 ad-hoc barriers and run at the top of
  `-lockedImageDisplay`, `-prevPage`, `-halfprevPage`, `-goTo:array:`,
  `-goToFirst`, `-goToLast`, the bookmark steps, `-changeReadMode:`,
  `-switchSingle:`, `-setSortMode:page:`, `-goBookmark:` and
  `-setPreferences`; `-detachLookaheadComposing:` counts and tags every
  detach with `lookaheadGeneration` (bumped on a timed-out wait and on book
  teardown); `-switchSingle:` no longer detaches uncounted threads;
  `cacheArray` goes through `cacheLock` helpers. `-lockedImageDisplay` reads
  a missing page synchronously instead of polling. DECISIONS entry added.
- **Part 4 (8f7bedf).** L8 indexed loops in the legacy key/mouse migration;
  L11 bookmark icons removed backwards, shadow radius starts at 1.0 for a
  nil white conversion, negative `ImageCache` counts as 0, 256 KB read
  buffers on the heap; U12 outlets `contextMenuItem`/`contextMenu` and their
  two `BookWindow.xib` connections removed (the menus stay attached to the
  table and the matrix).
- **Part 5 (3186618).** M10: the spread's `fromRect` is each page's exact
  `[image size]`, as on the single-page path. Resampling steps per page:
  one `drawInRect:fromRect:` before and after.
- Docs: KNOWN_ISSUES #40 (U12) and #41 (closed); DECISIONS (lookahead
  barrier); `tests/fixtures/README.md`.

### Verification

- Build: Deployment build after every part, no new warnings (one
  `-Wincomplete-implementation` introduced in Part 2 was fixed before its
  commit).
- Automated verification: `tests/engine/run_tests.sh` ALL PASS after every
  part — 302 checks at start, 350 after M6, 359 from L3 on, plus the new
  COImageLoader harness (4, then 10 checks). `run_password_test.sh` PASSED
  (M9: 3000 wrong passwords, 0 accepted). Against the pre-fix sources the new
  tests fail: L2 harness aborts (empty book), L4 2 of 10 fail, M6 RAR4
  fixtures show an empty page or shifted pages and RAR5 shifted pages, M9
  22 of 3000 wrong ZipCrypto passwords accepted.
- Manual verification (on device, owner standing by; `build/cooViewer.app`
  launched by path, frontmost app checked before input; `ImageCache` 5 for
  the stress part):
  - M10, Spread Capture & Comparison (same session, pre-M10 build from the
    Part 4 commit vs. the fixed build, `screencapture -l`, same window
    frame): integral-size spread byte-identical; a 595.28 pt PDF spread
    byte-identical too, because `NSPDFImageRep` reports 596 × 842 on macOS
    26; a 350 dpi PNG spread: before, no pixel of the 1 px red right column
    or blue top row; after, both on both pages, and every differing pixel
    (13,472) lies in those edge strips; page placement unchanged.
  - Lookahead stress: 40/50/60-key bursts forward and back through a
    60-page book (1/60 ↔ 60/60, stops at the end with LoopCheck 3); a
    slideshow at the profile's 0.1 s delay ran 6/60 → 60/60; a window
    closed during that slideshow → normal quit, no crash report.
  - M11: a click at the page bar's far (last-page) end showed 60/60, no
    wrap.
  - M3: with the password sheet up, File ▸ Open… and Recent Books ▸ (a
    test book) opened nothing; Cancel left the previous book in the window.
  - M4: bookA → control+C → bookB → bookC, control+D → bookB, without the
    submenu ever opened.
  - M1: Save Image… onto its own `001.png` with Replace → file unchanged
    (hash, mtime); onto `003.png` → replaced with the page's bytes, no
    leftover temporary item.
  - Preferences exported before and imported afterwards; the final export
    is byte-identical to the backup. `build/cooViewer.app`, the comparison
    app and the intermediate New Window helper were unregistered
    (`lsregister -u`); `pluginkit` resolves the extensions to
    `/Applications`.
- Not performed:
  - Closing a window while a book is still loading (no slow-loading book
    at hand); the slideshow close covers the lookahead teardown.
  - M12 dead-key input, L3/L4/L6 on device (engine-tested), the
    application-modal variants of M3 (no window), Open from Same Folder
    menu clicks during a password sheet (same guard as the keys).
  - M11's exact 2 px zone cannot be confirmed from a screenshot; the click
    was about 0.6 pt inside the bar's outer edge.

### Remaining Issues

- During the on-device pass a thumbnail extension process from the
  comparison app (in the scratch directory) was running after the app quit,
  although `pluginkit` elected the `/Applications` extension; it was gone
  after `lsregister -u` (whether that ended it was not established). Launching a second test copy registers its
  extensions too (KNOWN_ISSUES #15 territory).

### Follow-up Suggestions

- Performance follow-ups from the previous TF, unchanged: continue the
  cursor when the next page is also next in stored order; a cancellable
  prefetch; a cache limit by RAM.
- `-lockedImageDisplay` now waits for a running lookahead to read both of
  its pages; if page turns feel slower on slow books (solid RAR backwards),
  finer locking of `imageMutableArray` is the next step.
- `tools/spread_diff.py` needs Pillow and NumPy, which the Command Line
  Tools Python lacks; a note on using a scratch venv would help.
