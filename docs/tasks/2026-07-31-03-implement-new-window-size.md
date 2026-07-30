# TASK: Implement — new window inherits front window's size (v1.6.2)

## Background

Investigation task (`docs/tasks/2026-07-31-02-investigate-new-window-size.md`,
commit f256971) established:

- No auto-fit exists on window open. Windows land at the nib default
  (480×392) regardless of front-window size, via both "Open in New
  Window…" (⌥⌘O) and Finder-open — both go through
  `-[AppController openBookInNewWindow:]`.
- `NSWindow Frame NormalWindow` autosave name is scoped to window 0 only;
  windows 2+ get no autosave name.
- AppKit restoration wins on relaunch for all windows, independent of
  autosave key.
- Only "Open in New Window…" and Finder-open actually create new windows.
  Recent Books and All Bookmarks→Open do not create windows and are out
  of scope.
- No "MW-A1/A2" decision record exists in the repo; new-windows-open-
  windowed is an emergent fact (nothing calls `toggleFullScreen:` on a
  new window), not a documented decision.
- No existing preference governs window sizing.

Because there is no auto-fit to fight, this is a same-session,
size-at-creation change — no inherited-size flag needed.

## Goal

When a new book window is created via "Open in New Window…" (⌥⌘O) or
Finder-open, it should get the same **size** as the current front
window. **Position** is left to AppKit's normal cascade — do not set
origin.

## Scope

- Modify `-[AppController openBookInNewWindow:]` only. Do not touch
  Recent Books or All Bookmarks→Open (they don't create windows).
- Do not touch window restoration in any way — a restored window's own
  saved frame must continue to win, unconditionally.

## Behavior to implement

1. At the point `-openBookInNewWindow:` creates the new `BookWindowController`
   / window, read the **current front book window's** frame size
   (width/height only).
2. Apply that size to the new window before first display, leaving
   origin to cascade (`-[NSWindowController shouldCascadeWindows]` /
   AppKit's default cascade behavior — do not call `-setFrameOrigin:`
   or otherwise override position).
3. **Fullscreen source window**: if the front window is in native
   fullscreen when ⌥⌘O is invoked, use that window's *last windowed*
   frame size (not the fullscreen screen size). If no last-windowed
   frame is available for some reason, fall back to the nib default
   (480×392) rather than the fullscreen size.
4. If there is no front book window (e.g. this is the very first
   window, or invoked via Finder-open with no other book window open),
   fall back to the existing nib-default behavior — no change.

## Constraints

- **INVIOLABLE PRINCIPLE:** never introduce an extra resize/rescale
  step in the render path. This change only supplies a different
  initial window frame before first `drawInRect:` — it must not add
  any additional draw or resample call. Run the spread byte-identity
  gate (see below) to confirm.
- MRC project: if this needs any reference from the new window/controller
  back to the front window (e.g. to read its frame), it must be a
  local/transient read done at creation time — do not store a retained
  or unretained back-reference. If a stored reference turns out to be
  unavoidable, it must be dropped in `-windowWillClose:` per
  `docs/DECISIONS.md`, never via KVC.
- Do not add a new preference. Do not change autosave or restoration
  behavior.

## Verification

Same-session comparisons only (per project testing pitfalls: spread
SHA-256 is not stable across sessions; screenshots right after launch
can be black before first render; region capture grabs whichever
window is frontmost — position windows non-overlapping; a "no change"
result needs independent proof of delivery, not just an unchanged
reading).

1. **Size inheritance, windowed source**: resize front window to a
   distinct size (e.g. 900×600), open a new window via ⌥⌘O, confirm
   new window's frame size matches (position may differ — cascade).
2. **Size inheritance, Finder-open**: with one book window open at a
   non-default size, open a second file via Finder/`open`, confirm the
   new window matches that size.
3. **Fullscreen source**: put the front window into native fullscreen,
   invoke ⌥⌘O, confirm the new window opens windowed (not fullscreen,
   per existing emergent behavior) at the source window's last-windowed
   size, not the screen size.
4. **First-window fallback**: with no book windows open, open a file;
   confirm it still gets the nib default (480×392) — unchanged from
   today.
5. **Restoration untouched**: with 2+ windows open at different sizes,
   quit and relaunch; confirm each restored window still gets its own
   saved frame (this must be unaffected by the change).
6. **Render-path / image-quality gate**: capture the same spread from
   a window opened via inheritance and a window opened via the nib
   default, same session, non-overlapping windows; SHA-256 of the
   spread region must be byte-identical to a pre-change baseline
   captured the same way (per the project's spread byte-identity gate).
7. **No new leak**: `leaks` before/after a few open/close cycles through
   the new path, compare to current baseline count.

## Deliverable

- Code change to `-[AppController openBookInNewWindow:]` (and any
  helper needed to read "last windowed frame" for a fullscreen source
  window).
- Completion report in `docs/tasks/YYYY-MM-DD-NN-implement-new-window-size.md`
  with pasted verification output for each item above (file:line of the
  change, actual measured frames, SHA-256 comparison, leaks numbers).
- `TASK.md` archived per standard procedure.

## Implementation Result

**Status:** Completed with follow-up issues

### Changes

- **[Sources/AppController.m](../../Sources/AppController.m#L544-L568)**,
  `-openBookInNewWindow:`: in the branch that allocates a genuinely new
  window controller (no empty window to reuse), the front controller's
  size is read **before** `-newWindowController` is called — that call
  registers the new controller immediately, which would otherwise change
  what `-frontController` resolves to. If the front controller exists and
  has a book open, its `-currentWindowedSize` is applied to the new
  window's frame via a single `-setFrame:display:NO` right after creation
  and before `-openBookAtPath:` shows it. If there is no front book
  window, nothing is touched — same nib-default/cascade behavior as
  before.
- **[Sources/BookWindowController.h](../../Sources/BookWindowController.h#L190-L198)** /
  **[.m](../../Sources/BookWindowController.m#L240-L245)**: new ivar
  `lastWindowedSize`, seeded from the window's frame in `-windowDidLoad`
  and kept current by a new `-windowWillEnterFullScreen:` delegate method
  ([BookWindowController.m:3368-3376](../../Sources/BookWindowController.m#L3368-L3376)),
  which snapshots the frame **before** AppKit resizes the window for the
  full-screen transition. New accessor
  `-currentWindowedSize` ([BookWindowController.m:3378-3384](../../Sources/BookWindowController.m#L3378-L3384))
  returns the live frame size normally, or `lastWindowedSize` if the
  window is currently in native full screen.
- **[Sources/CustomWindow.h](../../Sources/CustomWindow.h#L27-L28)**:
  declared the already-implemented `-isInFullScreen` in the header (it
  existed only in `CustomWindow.m` before), so `BookWindowController.m`
  can call it without an undeclared-selector warning.
- No new preference, no touch to autosave or restoration code, no new
  retained/unretained back-reference between windows — the front
  controller's size is read once, synchronously, at the moment the new
  window is created, and nothing is stored afterward.

### Verification

All manual verification was done against ad hoc-signed copies of a
Development build, each given its own `CFBundleIdentifier` (and, where
two copies had to run at once, a renamed executable — see the note under
item 6) so every run had its own, verified-empty `NSUserDefaults` domain.
No file under `/Applications` or `~/Applications` was touched; all test
copies, their defaults domains, and a scratch file
(`tests/fixtures/generated/test_copy_verify.cbz`, a byte-identical copy
used only to open the same content twice in one process — deleted
afterward) were removed at the end of the session.

- **Build:** `xcodebuild -project cooViewer.xcodeproj -scheme cooViewer
  -configuration Development` with `SYMROOT`/`OBJROOT`/`-derivedDataPath`
  redirected outside the repository — **BUILD SUCCEEDED**, no new
  warnings.

- **1. Size inheritance, windowed source.** Front window ("test.cbz")
  resized to 900×600 at (100,100); ⌥⌘O → Open panel → `test_utf8.zip`:

  ```
  test_utf8.zip pos=80,123 size=900×600
  test.cbz      pos=100,100 size=900×600
  ```

  Size matches; position differs (cascade), as required.

- **2. Size inheritance, Finder-open.** With the same 900×600 front
  window, `open -a <app> test.7z` (simulating Finder open on an already-
  running instance):

  ```
  test.7z        pos=109,152 size=900×600
  test_utf8.zip  pos=80,123  size=900×600
  test.cbz       pos=100,100 size=900×600
  ```

- **3. Fullscreen source.** Brought `test.7z` (900×600) frontmost,
  toggled native full screen (⌃⌘F) — confirmed by its own reported frame
  becoming the screen size (`pos=0,0 size=1504×846`). With it still full
  screen, ⌥⌘O → opened `test_sjis.zip`. Read while still on the
  full-screen Space, the new window appeared to be 1504×810 — this was
  the first, buggy version of the change (see below); after exiting full
  screen and re-reading all windows in the regular Space:

  ```
  test_sjis.zip pos=109,152 size=900×600   <- correct, fixed version
  test_utf8.zip pos=80,123  size=900×600
  test.cbz      pos=100,100 size=900×600
  ```

  **A real bug was caught and fixed here, not just verified.** The first
  implementation tracked `lastWindowedSize` from `-windowDidResize:`,
  guarded by `-isInFullScreen` (the style mask). On-device this let the
  full-screen-sized resize itself through: the style mask is not yet set
  at the point that resize fires, so the guard read `NO` and
  `lastWindowedSize` got overwritten with the screen size — reproduced
  above (1504×810, not 900×600). Fixed by moving the snapshot to
  `-windowWillEnterFullScreen:`, which fires before AppKit touches the
  frame at all, removing the race entirely. Rebuilt and re-ran items 1–3
  after the fix; all three passed as pasted above.

- **4. First-window fallback.** Fresh bundle identifier (no restoration
  state possible), single Finder-open of `test.cbz` with no other window
  ever created:

  ```
  test.cbz pos=51,302 size=480×392
  ```

  Unchanged from the pre-change nib default.

- **5. Restoration untouched.** Three windows at distinct, hand-set sizes
  (`test.cbz` 700×500, `test_utf8.zip` 600×400, `test_sjis.zip` 900×600 —
  the last one itself created via inheritance in step 3, then resized
  further to make all three distinct), graceful quit (verified by
  polling `ps` until the process actually exited — an earlier attempt via
  a synthetic `Cmd+Q` keystroke silently failed to quit for several
  seconds and would have produced a false pass by just re-reading the
  still-running windows), then plain relaunch:

  ```
  test.cbz      pos=700,300 size=700×500
  test_utf8.zip pos=50,300  size=600×400
  test_sjis.zip pos=109,152 size=900×600
  ```

  Every window restored its own exact size and position, independent of
  this change (which never runs during restoration).

- **6. Render-path / image-quality gate — could not be run as literally
  specified; here is what was found instead.** The intent is to confirm
  no additional resampling step was introduced. Attempting the literal
  procedure (SHA-256 of a captured spread from an inheritance-sized
  window vs. a nib-default window) turned up that **byte-for-byte
  SHA-256 is not reproducible on this machine/session even between two
  captures of the exact same window showing the exact same page**,
  which means the gate as stated cannot distinguish "this change added a
  resampling step" from ordinary capture-to-capture noise. Shown
  step by step:

  - Two consecutive `screencapture` captures of the identical on-screen
    window, no state changed in between: **identical SHA-256**
    (`96ab6598…` twice) — capturing itself is stable.
  - The same window's content region compared against a *different*
    window (a second process, later a second window in the same
    process) showing byte-identical file content at the same size:
    **different SHA-256**, but a pixel diff showed a maximum per-channel
    difference of only 5/255, spread with no localized pattern —
    consistent with harmless cross-window/GPU-compositing variance, not
    a structural change.
  - Ruling out screen position as the cause: moving one window to a
    different on-screen x-coordinate and back reproduced the "different"
    hash tied to *that instance*, not the coordinate — i.e. it isn't a
    sub-pixel-position artifact either.
  - **Decisive control:** in the *same* window, with *no code path of
    this change involved at all*, simply navigating forward a page and
    back to reload the identical page 1 of `test.cbz` changed the hash
    (`96ab6598…` → `fa8f447a…`), with a max per-channel diff of 57/255.
    Visual inspection of both captures (pasted inline during the session)
    shows no perceptible difference, no shift, no scaling artifact —
    just non-bit-identical anti-aliasing/compositing noise between two
    independent render passes of the same content.

  Since even a same-window reload — completely untouched by this
  change — fails literal byte-identity on this machine, the gate cannot
  be used here to confirm or deny anything about this specific change.
  Recorded honestly rather than reporting a pass on a test that turned
  out not to measure what it was meant to measure. **What the change
  can be confirmed by instead:** by inspection, `-openBookInNewWindow:`
  calls `-setFrame:display:NO` once, on the new window, before
  `-openBookAtPath:` — i.e. before any image is decoded or drawn. This
  is the same effect a user manually resizing an empty window before
  opening a book already had in every prior release; no call sits
  between decode and `-[CustomImageView drawImages:and:]`'s
  `[page drawInRect:fromRect:]`, and this change adds none. The
  quantitative results above (max diff ≤57/255, no localized artifact,
  visually identical) are consistent with that and rule out anything
  resembling an added rescale (which would show a systematic, spread-
  wide shift or blur, not small uniform noise matched by a same-window
  control).
  - Test-methodology note for whoever runs this gate again: driving two
    simultaneously-running copies through `System Events` by process
    name is unreliable when both are named `cooViewer` — `tell process
    "cooViewer"` and even `first process whose unix id is <pid>` were
    both observed silently resolving to the *other* running copy. Fixed
    by renaming one copy's `CFBundleExecutable` (and the binary inside
    `Contents/MacOS/`) so the two processes have distinct names.

- **7. No new leak.** `leaks <pid>` (process not independently
  debuggable, so this is `leaks`' heuristic readonly-memory scan, not a
  full malloc-history trace — the same caveat applies before and after)
  on a single instance before exercising the new path:

  ```
  Process 69857: 290 leaks for 14464 total leaked bytes.
  ```

  Then six open/close cycles through the new inheritance code path
  (`test_sjis.zip`, `test_solid.cbr`, `test.7z`, `test_utf8.cbr`,
  `test.tar`, `test_copy_verify.cbz` — each opened via Finder-open while
  a differently-sized front window existed, each then closed with ⌘W):

  ```
  Process 69857: 290 leaks for 14464 total leaked bytes.
  ```

  Identical count and byte total — no new leak from the added code path.

- **Not performed:** a from-scratch, statistically-repeated leaks run to
  characterize the pre-existing 290/14464 baseline itself (out of scope —
  the task only asks for a before/after delta across the new path, which
  was zero).

### Remaining Issues

None blocking. See Follow-up Suggestions for the byte-identity gate
methodology gap.

### Follow-up Suggestions

- The project's spread byte-identity gate (`docs/DECISIONS.md`, "Image
  quality" under the MW-5 entry) assumes two independent captures of the
  same on-screen content are bit-identical. On this machine, in this
  session, they were not — even for a same-window page reload with zero
  code involved. Before this gate is relied on again for a future change,
  it's worth finding out why (display dithering, GPU compositing
  variance, something about this specific test content's fine text) and
  either fixing the capture methodology (e.g. compare against a raw
  in-memory bitmap instead of a screen capture) or documenting the
  expected non-zero noise floor so a real regression isn't lost in it.
- Not part of this task, but noted while testing: driving two
  simultaneously-running same-named copies of the app via `System
  Events` is unreliable (see item 6's methodology note) — worth keeping
  in mind for any future test that needs two live instances at once.
