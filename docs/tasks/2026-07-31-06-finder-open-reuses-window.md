# TASK: Finder-open reuses the front window instead of creating a new one

## Background

Currently, opening a file via Finder double-click
(`-application:openFiles:`) creates a new book window via
`-openBookInNewWindow:` — the same path used by "Open in New Window…"
(⌥⌘O), as established in the v1.6.2 investigation
(`docs/tasks/2026-07-31-02-investigate-new-window-size.md`).

The existing Finder-open dedup fix (#32, from the multi-window arc)
already handles the case where the incoming file is already open in
some window — that focuses the existing window. That behavior must
continue to take precedence over anything in this task.

I could not find a prior decision in this project's history that
already settled Finder-open reusing the front window — the multi-window
arc's Finder-open work was specifically the dedup fix (#32), not this.
If a decision on this specific behavior does exist somewhere this
task's author didn't check, raise it rather than silently proceeding.

## Goal

When a file is opened via Finder double-click / `-application:openFiles:`,
and the file is not already open in some window (dedup #32 resolves
that case first):

- If at least one book window exists, load the file into the current
  frontmost window, replacing its current content, instead of opening
  a new window.
- If no book window exists, behavior is unchanged — open a new window
  as today.

**"Open in New Window…" (⌥⌘O) is NOT affected.** It must always open a
new window regardless of how many windows already exist — it is the
explicit "give me another window" action and stays that way.

## Design assumptions — raise before implementing if any is wrong

- "Frontmost" = the key/main book window at the moment
  `-application:openFiles:` fires. If no book window is key for some
  reason, fall back to AppKit's most-recently-used registered book
  window; if that's ambiguous, fall back to opening a new window
  (safe default, matches current behavior).
- Multiple files opened/dropped at once via Finder: the first file
  replaces the front window's content; each additional file opens in
  its own new window (cascaded), since the front window is now
  occupied by the first. This is an assumption, not a confirmed
  requirement — verify what Finder actually sends for a multi-select
  open and report the actual behavior rather than just asserting it
  matches this.
- No new preference is added. This is unconditional behavior,
  consistent with this project's existing pattern of not gating
  window-management behavior behind a preference unless one already
  exists (none does here, per the v1.6.2 investigation's Q7).
- Unaffected by this task: window restoration, ⌥⌘O, Recent Books,
  All Bookmarks→Open (neither of the latter two creates windows today),
  and the dedup-focus behavior (#32).
- The v1.6.2 size-inheritance change in `-openBookInNewWindow:`
  becomes moot for the Finder-open path once this ships, since
  Finder-open will typically no longer call `-openBookInNewWindow:`
  when a window already exists. This is expected, not a regression —
  do not treat it as something to "fix."

## Scope

- Modify the per-file handling in `-[AppController application:openFiles:]`
  (or wherever the dispatch after the dedup check currently lives) to
  route to "replace front window's content" instead of
  `-openBookInNewWindow:`, whenever a book window exists and dedup
  didn't already resolve the file to an existing window.
- Look for whatever mechanism already exists for loading a different
  book into an existing window (e.g. if there's already a "replace
  current book" path used by drag-and-drop or some other entry point)
  and reuse it rather than writing a second book-loading path. If no
  such mechanism exists, say so in the completion report before adding
  one.
- Do not touch: `-openBookInNewWindow:` itself, autosave/restoration,
  the ⌥⌘O menu action, Recent Books, All Bookmarks→Open.

## Constraints

- **INVIOLABLE PRINCIPLE**: no extra resize/rescale step in the render
  path. Confirm that loading a new book into an existing window goes
  through the same single `drawInRect:` path as any other book display,
  and does not introduce a new compositing/resizing step.
- MRC project: swapping a window's book content must correctly release
  the old book's resources, cancel any in-flight loads/timers, and
  reset page state, without leaking or double-releasing. Check what
  already happens on normal book-close / `-windowWillClose:` for a
  pattern to reuse rather than inventing new cleanup logic.
- Preserve dedup (#32) exactly as-is: if the incoming file is already
  open in some window, that window must still be focused — do not let
  the new front-window-replace logic intercept that case.

## Verification

1. **Front-window replace**: one book window open, showing book A past
   page 1. Finder-open book B. Confirm: same window now shows book B
   (at whatever page a fresh open normally starts on), no new window
   created, window size/position unchanged.
2. **No windows open**: with zero book windows open, Finder-open a
   file — confirm unchanged behavior (opens a new window, as today).
3. **Dedup still wins**: two windows open (front: book A, background:
   book B). Finder-open book B — confirm existing dedup still focuses
   book B's window, and does NOT instead load book B into the front
   window in place of book A.
4. **⌥⌘O unaffected**: with a window open, ⌥⌘O — confirm it still opens
   a new window.
5. **Multiple files at once**: Finder-open 2+ files simultaneously with
   one window already open — observe and paste the actual resulting
   window layout; compare against the assumption above and flag any
   mismatch rather than asserting it matches.
6. **Leak check**: `leaks` before/after several replace-cycles (open A,
   Finder-open B into the same window, Finder-open C, …) — compare to
   the existing per-book-open leak baseline; no new growth.
7. **Render-path gate**: use `tools/spread_diff.py` (text/vector
   regions) or exact SHA-256 (solid-fill regions) to confirm a book
   loaded via front-window-replace renders identically to the same
   book opened fresh into a new window, captured in the same session.

## Deliverable

Standard completion/archiving procedure per `docs/task-workflow.md`:
append the Implementation Result to this `TASK.md`, archive as
`docs/tasks/YYYY-MM-DD-NN-finder-open-reuses-window.md`, and provide
the chat completion report.

## Implementation Result

**Status:** Completed

### Existing mechanism found and reused (per Scope)

`-[BookWindowController openBookAtPath:]` ([BookWindowController.m:889-898](../../Sources/BookWindowController.m#L889-L898))
already is "load a different book into this window," used today by
File ▸ Open (`-open:`, line 810-836, via
`-setCurrentBookPathAndOldBookPath:` + `-openPage:0 last:NO`) and by
`-openBookInNewWindow:` itself when it hands a book to a newly-created
or reused-empty window. It already does the correct MRC teardown of the
previous book (through the existing `-openPage:last:` /
`-openPageWithLoader:...` machinery — the same path a normal book
replacement in File ▸ Open exercises every day) and resets page state.
**No new book-loading or cleanup path was written** — the implementation
is a routing change only, calling this existing method on the front
controller instead of `-openBookInNewWindow:`.

### Changes

- **[Sources/AppController.m](../../Sources/AppController.m#L182-L246)**,
  `-application:openFiles:`: after the (unchanged) launch-queue early
  return, the per-file loop now tracks whether the front window's
  "replace" slot has been used yet this call (`frontWindowReplaced`,
  local to the method, reset every call — not stored state). For each
  filename: if the slot is still free, the front controller exists and
  has a book open, and the file is not already open anywhere (a
  read-only query via the existing `-windowControllerShowingBook:`,
  reused rather than duplicated), it calls
  `[front openBookAtPath:filename]` and marks the slot used. Otherwise
  it falls through to the unchanged `-openBookInNewWindow:`, which
  still runs its own dedup/empty-window/new-window logic exactly as
  before — this task adds no second copy of that logic, only a earlier
  gate in front of it for the one case being changed.
- `-openBookInNewWindow:` itself is untouched (confirmed by
  `git diff` touching only `AppController.m`'s
  `-application:openFiles:` and its preceding comment block).
- No new preference, no change to autosave/restoration/⌥⌘O/Recent
  Books/All Bookmarks→Open.

### A real safety issue found and fixed during verification (not a code defect — a test-methodology hazard)

While setting up the first isolated test copy, `System Events` resolved
`tell process "cooViewer"` to the **user's own real, already-running
`/Applications/cooViewer.app`** (PID 94692, started well before this
session and left running) instead of the test copy — the exact hazard
recorded in the prior implementation task's follow-up notes. One command
in this session (a window resize/reposition) was sent under that
ambiguous name; it errored harmlessly (`Can't get window "test.cbz"`,
since the real app didn't have a window by that name) before touching
anything, and was caught immediately by checking `ps aux` for the actual
running processes. **The user's real app, its window, and its book were
never modified** — confirmed by checking its process was still running
unchanged immediately after. All test copies for the remainder of this
session had their executable renamed (`cooViewerT1`/`T2`/`T3`) so
`System Events` could never resolve the ambiguity again. Recorded here
because it is a real, repeatable hazard for any future session that
runs a second copy of this app while the user's own copy might be open,
not merely a one-off mistake to shrug off.

### Verification

All manual verification used isolated, ad hoc-signed, renamed-executable
copies of a Development build, each with its own verified-empty
`NSUserDefaults` domain, cleaned up afterward along with all scratch
fixture copies (`test_copy_gate.cbz`, `test_copy_gate2.cbz`) and `/tmp`
scratch directories. No file under `/Applications` or `~/Applications`
was touched.

- **Build:** `xcodebuild -project cooViewer.xcodeproj -scheme cooViewer
  -configuration Development` — BUILD SUCCEEDED, both mid-implementation
  and as a final check after all testing.

- **1. Front-window replace.** One window open (`test.cbz`, resized to
  900×600 at (50,50)); Finder-open (`open -a`) `test_utf8.zip`:

  ```
  before: AccessoryWindow, test.cbz            pos=50,50 size=900x600
  after:  AccessoryWindow, test_utf8.zip       pos=50,50 size=900x600
  ```

  Same window (identical position and size), content replaced, no new
  window created.

- **2. No windows open.** Fresh bundle identifier, launched with no
  file argument — confirmed zero windows exist (`return name of
  windows` → empty). Finder-open (`open -a`) `test.7z` into that running,
  bookless instance:

  ```
  after: AccessoryWindow, test.7z
  ```

  Opens normally into the empty launch window — unchanged from today,
  since the front controller has no book open and the new gate falls
  through to `-openBookInNewWindow:`.

- **3. Dedup still wins.** Two windows open, front = `test_sjis.zip`,
  background = `test.7z`. Finder-open `test.7z` (already open):

  ```
  before: AccessoryWindow, test_sjis.zip, AccessoryWindow, test.7z
  after:  test.7z frontmost=true, test_sjis.zip frontmost=false
          (still exactly 2 windows, same 2 titles)
  ```

  `test.7z`'s window was brought forward; `test_sjis.zip`'s content was
  **not** replaced. Dedup resolved the file before the new front-replace
  gate ever saw it (the gate's own dedup check found it too, and
  `-openBookInNewWindow:`'s internal check is what actually performed
  the focus — this task's code never reached the replace branch for
  this file).

- **4. ⌥⌘O unaffected.** With `test.7z` front (2 windows existing),
  ⌥⌘O → opened `test_utf8.cbr`:

  ```
  before: AccessoryWindow, test_sjis.zip, AccessoryWindow, test.7z (2 windows)
  after:  AccessoryWindow, test_utf8.cbr, AccessoryWindow, test.7z,
          AccessoryWindow, test_sjis.zip (3 windows)
  ```

  A genuinely new window, not a replace of the front window's content
  (`test.7z`'s content was untouched — it's still `test.7z`, not
  overwritten).

- **5. Multiple files at once.** With 3 windows open (front:
  `test_utf8.cbr`, plus `test.7z`, `test_sjis.zip`), Finder-opened 3
  new files in a single `open -a` call
  (`test_solid.cbr test.tar test.cvbdl`):

  ```
  before (3 windows): test_utf8.cbr, test.7z, test_sjis.zip
  after  (5 windows): test.cvbdl, test.tar, test_solid.cbr, test.7z, test_sjis.zip
  ```

  Net +2 windows for 3 files — matches the assumption exactly (first
  file replaces the front window, the other two open their own
  cascaded windows). Position data confirms it: `test.7z`/`test_sjis.zip`
  kept their original cascade slots (positions 1–2 in creation order);
  `test_solid.cbr` landed in exactly the 3rd cascade slot that
  `test_utf8.cbr`'s window had occupied (same position), while
  `test.tar` and `test.cvbdl` took new 4th and 5th cascade slots. This
  confirms `test_solid.cbr` was the one file that replaced the front
  window (same window, same slot), and the other two are genuinely new
  windows — not merely inferred from the count. (Array order for a
  multi-path `open -a` matched command-line argument order in this
  trial; not asserted as a cross-platform guarantee, just what was
  observed.)

- **6. Leak check.** `leaks <pid>` (heuristic readonly-memory scan, not
  a full malloc-history trace — same caveat as the prior task) before
  six single-file front-window-replace cycles, all funneled through the
  one existing front window (since after the first replace, that window
  is always "the front window with a book open" again, so every
  subsequent Finder-open in the batch replaced it again rather than
  opening a new one — itself a natural exercise of exactly the "open A,
  Finder-open B into the same window, Finder-open C, …" scenario the
  task asked for):

  ```
  before: Process 9940: 292 leaks for 14528 total leaked bytes.
  after:  Process 9940: 292 leaks for 14528 total leaked bytes.
  ```

  Identical count and byte total.

- **7. Render-path gate.** Compared a book loaded via front-window-replace
  against the same, byte-identical file content opened fresh into a new
  window (two separately-named copies of `test.cbz` to avoid dedup
  interfering), both at 900×600, captured in the same session,
  non-overlapping.

  - **Solid-fill region** (a blank strip of the page, no text/vector
    content): **exact SHA-256 match** —
    `bd1b9fa7f8069eeaea0c1abd8a60b784c4765bbea3cf64420bb36c9da343f040`
    for both. No structural difference whatsoever.
  - **Text/vector region** (`tools/spread_diff.py`): reported FAIL
    (640/1,024,000 unexplained pixels) on the first pass. **Verified
    this is pre-existing environmental noise, not a defect introduced
    by this change**, with a decisive control: comparing two windows
    that both used the *unmodified* fresh-new-window path (neither
    involving front-window-replace at all), at the same two screen
    positions, produced a **larger** unexplained-pixel count (2622) than
    the front-replace-vs-fresh comparison (640). Since the code path
    that never changed shows equal-or-worse noise than the comparison
    involving this task's change, the noise cannot be attributed to the
    change — it is the same class of position-dependent anti-aliasing
    variance already documented in
    `docs/tasks/2026-07-31-04-investigate-byte-identity-gate.md`.
    Visually inspecting the diff-report overlay for the original
    comparison showed the flagged pixels concentrated at the thumbnail
    panel/content boundary (a long, high-contrast vertical edge) — the
    kind of edge the tool's own documented calibration caveat already
    anticipates ("overlapping edge-dilation at a corner can push a
    genuinely-AA pixel's ... delta above the flat threshold"), not a
    resampling artifact spread through the actual page content (which
    remained visually and structurally clean in every capture).
    **Practical note for future use of this gate:** the tool's raw
    PASS/FAIL alone is not sufficient when the two captures are at
    different screen positions or in different windows — a same-session
    fresh-vs-fresh control at the same positions is needed to separate
    real regressions from this known noise floor, exactly as done here.

### Remaining Issues

None.

### Follow-up Suggestions

- None new beyond what the byte-identity investigation task already
  recorded (the animated HUD overlay and the thumbnail-panel edge as
  uninvestigated variance sources for `tools/spread_diff.py`'s default
  thresholds) — this task's render-path gate result is consistent with,
  not additional to, those.
- Renaming a test copy's executable before running two app instances
  side by side is necessary, not optional, whenever the user's own real
  copy might also be running — worth turning into an explicit step in
  whatever future doc ends up covering multi-instance manual testing
  (CLAUDE.md's On-Device Verification Procedure covers single-instance
  testing only today).
