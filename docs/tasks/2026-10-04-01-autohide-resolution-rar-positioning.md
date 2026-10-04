# TASK: Page-number auto-hide fix, Resolution preferences, non-solid RAR positioning

## Background

Three items the owner asked for together (cooViewer HQ chat, 2026-10-04):

1. **Page number sometimes never appears with auto-hide on.** Not reliably
   reproducible. With Preferences ▸ page number auto-hide on, the page number
   sometimes does not appear at all (moving the mouse does not bring it
   back); turning auto-hide off shows it. It often fixes itself later.
2. **Resolution gets its own Preferences section.** Today `ResolutionDisplay`
   is a pop-up (Off / In page number / Separate bar) inside the page-number
   settings (`bfc7922`, `docs/tasks/2026-10-03-01-v1.6.5-features.md` Part 2),
   and the separate bar is drawn with the page number's attributes and
   position. The owner wants a separate Resolution section, with an
   "In page number" checkbox on its right, and its own position and size.
3. **B1 + B2 from `docs/cbr-performance-20261003.md`** (cause 2): non-solid
   RAR archives whose stored order differs from page order reopen the
   forward-only cursor from the start for every page behind it (194 reopens
   on a 511-page owner book; 1.3–3.9× slower read-through than v1.3.7).

## Goal

The page number reliably reappears with auto-hide on; Resolution has its own
section with independent position and size; non-solid RAR pages are read by
direct positioning, with the read-through regression gone by measurement.

## Scope

### In scope

The three parts below, their tests, `docs/KNOWN_ISSUES.md`/`DECISIONS.md`/
`DEV_LOG.md` updates, and optionally the benchmark as `tools/cbr_bench/`.

### Out of scope

- Solid archives (C1 decode-ahead), libarchive update, other review items.
- Version change, tag, release (a separate task).
- Any change to the render path (`CLAUDE.md` ▸ INVIOLABLE): these parts
  touch the overlay (`AccessoryView`) and the decode side only.

### Parts

1. **Page-number auto-hide fix.** One commit.
2. **Resolution preferences section.** One commit.
3. **B1 + B2 non-solid RAR direct positioning.** One commit (plus the
   benchmark tool, if committed, in its own commit).

## Implementation notes

### Part 1 — page number never reappears with auto-hide on

- Find the cause before fixing. Start from `Sources/AccessoryView.m`: the
  page string is un-hidden only in `-mouseMoved:` (around `:302-326`), and
  only when `controller && [controller indicator] && imageView &&
  ![imageView loupeIsVisible]`. Hypotheses to check: the window not
  receiving mouse-moved events (`acceptsMouseMovedEvents`, tracking areas
  after window/fullscreen changes or restoration), `[controller indicator]`
  or `loupeIsVisible` stuck in a wrong state, `autoHidedPageString` set by
  `-hideAccessory` (`:840-860`) while the timer fires after a page or window
  change, a stale `accessoryTimer`, or the per-window state from MW-7 not
  being reset when a window is reused (Finder replace, ⌘N, restoration).
- Also check whether any other action (keyboard page turn, page-number
  input, opening a book) should un-hide it, and whether the separate
  resolution bar shares the problem.
- Add `os_log` diagnostics at the hide/un-hide points if needed to reproduce
  (no file names), and describe the reproduction. If it cannot be reproduced,
  fix the defects found by reading and say so.
- Verify on device: auto-hide on, page number appears on mouse move in a new
  window, a restored window, after ⌘N, after a Finder replace, after
  fullscreen in/out, after the loupe, after a sheet (bookmark/password).

### Part 2 — Resolution preferences section

- Preferences: a new **Resolution** section, separate from Page Number:
  - a checkbox to show the resolution;
  - on its right, an **In page number** checkbox. Checked: the resolution is
    appended to the page-number bar as today (In page number). Unchecked:
    it is drawn in its own bar.
  - for its own bar: its own **position** (set the same way the page number's
    position is set, via the accessory setting view) and its own **size**
    (font size, or font, matching how the page number's font is chosen).
    Disable these controls while "In page number" is checked or the
    resolution is hidden.
  - colors, margin and auto-hide follow the page number's settings unless the
    layout makes a separate setting natural; say which in the report.
- Keys: keep `ResolutionDisplay` (0 Off / 1 In page number / 2 Separate bar)
  as the stored state so existing profiles keep working, or migrate it once
  to new keys; either way an existing profile shows exactly what it showed
  before. New keys for the bar's position and font with defaults that match
  the current Separate bar placement.
- Drawing in `AccessoryView`: the separate bar uses its own position and font;
  it no longer has to sit next to the page number. Keep hide/auto-hide
  behavior consistent with Part 1.
- XIB: edit `Resources/Base.lproj` (and localizations) for the new section;
  English and Japanese labels.
- Verify on device: upgrade from each `ResolutionDisplay` value; each
  combination of the two checkboxes; moving the bar to each position; a
  larger font; single page and spread; auto-hide on and off.

### Part 3 — B1 + B2

- **B1:** record each entry's header offset in `CORarHeaderIndex`. For a
  non-solid archive, read a page by opening a fresh libarchive stream whose
  read callback presents the signature and main header and then continues at
  that entry's header, so the cursor never walks from the start. Solid
  archives keep the forward cursor. Encrypted-header and multi-volume
  archives, and archives that fell back from the header index, keep the
  current path.
- **B2:** prefetch the next page in page order (a hint from `COImageLoader`),
  not the next stored entry.
- Keep the RAR5 trailing-error recovery (`5335880`, KNOWN_ISSUES #37) working
  on the new path, with its size+CRC gate; add tests on RAR4 and RAR5,
  out-of-order non-solid fixtures, and the recovery fixture.
- **Measure** before and after with the method of
  `docs/cbr-performance-20261003.md` (same machine, warm cache, median of 3):
  read-through and page-turn latency on an out-of-order non-solid RAR4 and
  RAR5 and a 2000-small-page book, reopen count, peak memory. The target is
  read-through no slower than v1.3.7. Use generated fixtures only (the owner
  chose this; the 511-page owner book of the earlier report is not
  available). Do not search the owner's folders. Commit the harness as
  `tools/cbr_bench/` only if it is self-contained and documented.

## Verification

- Each part: `CLAUDE.md` build command (getconf in its own call; `xcodebuild`
  alone), `tests/engine/run_tests.sh` ALL PASS, then commit.
- On device after all parts, main app only (`CLAUDE.md` procedure including
  step 4 `lsregister -u`). Before any screen operation ask the owner to stand
  by. Launch by path; confirm the frontmost app and window before every
  keystroke or click (global CLAUDE.md). Save and restore preferences with
  `defaults export DOMAIN -` and an out-of-sandbox import, then read back.
- Before every push: `git fetch`, merge `origin/main` if it moved (never
  rebase or amend). Push with the owner's approval in chat.
- Permission / Sandbox counted from `~/Library/Logs/claude-permission-requests.log`.

## Progress

- Last completed step: all parts committed, device verification done,
  preferences restored (byte-identical export), LaunchServices unregistered.
- Current partial state: none.
- Exact next step: none (task complete).

## Implementation Result

**Status:** Completed

### Changes

- **Part 1 — auto-hide fix** (`c8d16ad`). Three causes found by reading
  (KNOWN_ISSUES #42): `-[AccessoryView mouseMoved:]` was gated on
  `[controller indicator]` (= `ShowPageBar`), so with the page bar off the
  page number never came back; it was fed only by the key window's
  mouse-moved events; and `-windowWillClose:` detached the overlay's
  outlets even for the kept last window, which the next open reuses. Fix:
  only the page bar part is gated on the page bar; an `NSTrackingArea`
  (`MouseMoved | ActiveAlways | InVisibleRect`) on the content view, owned by
  the `AccessoryView`, is now its only mouse-moved source; the detach (and
  the tracking area's removal) happens only when the registry retires the
  controller. `Sources/AccessoryView.m`, `CustomImageView.{h,m}`,
  `BookWindowController.m`. The separate resolution bar shares the
  page number's auto-hide flag and is fixed with it. Keyboard page turns,
  page-number input and opening a book still do not un-hide (existing
  design). No `os_log` diagnostics were added.
- **Part 2 — Resolution section** (`b43828d`, layout `efb5dc6`). A
  Resolution box below Page Number: Show, In page number (to its right),
  Set position…, font field + Select…, and a note that colors and auto-hide
  follow Page Number. `ResolutionDisplay` stays the stored state; new keys
  `ResolutionInPageNumber` (remembers the second checkbox while Show is
  off), `ResolutionPosition`, `Margin_Resolution`, `ResolutionTextFont`,
  each falling back to the page number's when unset; in the page number's
  corner the bar stays beside the page number, so existing profiles look the
  same. The bar is placed in the existing position panel (drag, snaps to a
  corner). Font/Select/Set position are disabled unless the separate bar is
  in use; In page number is disabled while Show is off. Colors and auto-hide
  are shared with the page number (one label style, one auto-hide switch).
  English and Japanese strings. **Deviation:** the first version put the box
  to the right of Page Number in a 76 pt wider nib; on device the window
  turned out to be sized per tab in code (484 pt), and the owner asked in
  chat for the box below Page Number — `efb5dc6` restores the nib width and
  makes only the Appearance tab 82 pt taller.
- **Part 3 — B1 + B2** (`06bd64c`). `CORarHeaderIndex` records header
  offsets, the signature+main-header prefix length and solidness (archive
  flag or any per-file flag). `CORarArchive` reads an entry of a non-solid,
  header-indexed archive through `archive_read_open2` with a read callback
  that presents the prefix and then the file from that entry's header;
  solid and fallback-indexed archives keep the rewinding cursor. The RAR5
  recovery (#37) runs unchanged on the new path. B2:
  `-[COArchive setPrefetchPageOrder:]` (named so after
  `-setPageOrder:` collided with an SDK selector), called by
  `COImageLoader`; `CORarArchive` prefetches the next page. Counters
  `-rewindCount` / `-positionedOpenCount` for tests.
- **Benchmark** (`acf9207`): `tools/cbr_bench/` (README, harness, corpus
  generator, runner, summary), self-contained, writes outside the repo;
  optional v1.3.7 build documented. Results appended to
  `docs/cbr-performance-20261003.md`.
- Docs: KNOWN_ISSUES #42 (new, fixed) and #37 note; DECISIONS ×3; DEV_LOG;
  `tests/fixtures/README.md`.

### Verification

- Build: `CLAUDE.md` command after each part, no new warnings; `build/`
  holds only `cooViewer.app`. One transient Xcode error during the Part 3
  build ("Copy cooViewerPreview.appex … failed with exit code 0"); the
  immediate rebuild was clean.
- Automated verification: `tests/engine/run_tests.sh` ALL PASS after each
  part (246 → 302 checks). New: direct positioning on out-of-order RAR4
  (STORE) and RAR5 (forward, backward, jumps; no rewinds), B2 prefetch hit,
  solid and fallback archives not positioned, #37 recovery read twice on the
  positioned path. Benchmark (median of 3, warm cache): read-through
  current ≤ v1.3.7 on all five generated archives; 2000 pages RAR5
  7.29 s → 1.50 s (v1.3.7 1.96 s); paced page turns 0 ms median.
- Manual verification (main app, `build/cooViewer.app` launched by path,
  prefs exported before and restored after, export byte-identical,
  `lsregister -u` done): auto-hide reappearance in a restored window, with
  another app frontmost, with the page bar off, in the kept last window
  after a refused open, after ⌘N, after a Finder open replacing the book,
  full screen in/out, loupe, bookmark sheet; hides after 2 s. Preferences:
  upgrade from `ResolutionDisplay` 2 (owner profile) shows the same bar;
  checkbox enabling; moving the bar to the bottom-right; 24 pt font; In page
  number appends to the page number; spread and single page; Input tab size
  unchanged. Reading the shuffled RAR5/RAR4 books: correct pages in order.
- Not performed: upgrade from `ResolutionDisplay` 0 and 1 on device
  (mapping verified by reading only); page-number auto-hide *off* with the
  separate bar; the pre-fix build was not run to reproduce the causes;
  QuickLook/Thumbnail (not touched by this task); a compressed RAR4 corpus
  (`rar` 6.x not available, RAR4 measured with STORE).

### Remaining Issues

- The Resolution font field shows a large font clipped (same as the page
  number's field).
- MainMenu.xib places the controls below the Resolution box at negative y in
  the Appearance tab (they appear when the tab grows by 82 pt at runtime);
  Interface Builder shows them clipped.

### Follow-up Suggestions

- In a non-solid book every page now opens its own positioned stream
  (2000 opens for 2000 pages, measured cheap); continuing on the cursor when
  the next page is also the next stored entry would remove most of them.
- Jumps wait behind a running prefetch on the serial read queue (r5n jump
  ~27 ms vs 16 ms in v1.3.7); a cancellable prefetch would remove that.
- Peak memory on 2000-page books rose to ~150–175 MB (still below v1.3.7 in
  the harness); consider C3 (cache limit by RAM) if it matters.
