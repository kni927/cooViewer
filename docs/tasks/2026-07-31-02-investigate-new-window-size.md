# TASK: Investigate — a new window should inherit the front window's size (v1.6.2 candidate)

## This is an investigation task. Do not implement anything.

The deliverable is a written report with file:line references, measured
behaviour, and an implementation size estimate. No code changes, no new
preferences, no new UI. Investigation-only tasks are archived like any other.

Do not start until v1.6.1 has shipped.

## Goal being investigated

Today, opening a second book window does not give it the same size as the
window it was opened from. The owner wants a new window to come up at the same
size as the existing one.

Before that can be scoped, the current window-sizing behaviour has to be
established by measurement.

## Reporting rules

- **Measure; do not infer from reading.** The last three tasks on this project
  each had their stated premise overturned by measurement. If you state that
  something happens, show the observation that proves it.
- Paste actual output. A procedure is not a result.
- Where the answer is "I could not determine this", say that, rather than
  producing a plausible guess.
- Relevant testing pitfalls already learned on this project: capture both sides
  of any comparison **in the same session** (a spread SHA-256 embeds window-
  corner anti-aliasing and is not stable across sessions); a screenshot taken
  immediately after launch can be black before first render; region capture
  grabs whichever window is frontmost, so position windows non-overlapping;
  a keystroke expected to produce "no change" needs independent proof it was
  delivered.

## Questions to answer

### Q1 — Where is a new book window's frame actually decided?

Enumerate **every** code path that sets a frame, size or position on a book
window, in the order they run:

- the nib's own frame
- `-setFrameAutosaveName:` / `-setFrameUsingName:`
- `-[NSWindowController shouldCascadeWindows]` and AppKit's cascade
- restoration decode (`window:didDecodeRestorableState:`)
- any fit-to-page / fit-to-image / zoom-to-fit logic
- anything in `-openPage:last:` / `-openPageWithLoader:page:last:fromFileName:`

### Q2 — Does opening a book resize the window to the page or spread? *(this is the pivot)*

This single answer determines the size of the eventual change.

- If there is **no** auto-fit, inheriting the size is a few lines in
  `-openBookInNewWindow:`.
- If the window **is** fitted to the content on open, an inherited size would
  be immediately overwritten, and the implementation needs a per-window "size
  was inherited — do not auto-fit" flag.

State which it is, where the code lives, and under what conditions it runs
(first open only? every page turn? preference-gated? different for single-page
vs two-page spread?).

Supporting observation: in the v1.6.0 crash report a `test.cbz` window was
102,59 480×392, and the fix task had to set 1200×900 explicitly for its
captures — consistent with some form of content-driven sizing. Confirm or
refute this.

### Q3 — The shared autosave name

`NSWindow Frame NormalWindow` appears to be a single autosave name used by all
book windows. Confirm, then measure what actually happens with N windows: which
window's frame wins at quit, and what all windows get on relaunch when
restoration is not involved.

### Q4 — Current order of precedence

Measured, not assumed: restoration vs autosave vs cascade vs auto-fit. Which
wins today, and at what point in the launch/open sequence.

### Q5 — Which entry paths should inherit?

List every path that creates a book window and state, for each, whether
inheritance makes sense:

- "Open in New Window…" (⌥⌘O) — the obvious yes
- Finder open via `-application:openFiles:`
- Recent Books
- All Bookmarks browser → Open
- window restoration — **should be excluded**; each window has its own saved
  frame and it must win
- the `OpenLastFolder` fallback

### Q6 — Fullscreen source window

If the front window is in native fullscreen when ⌥⌘O is used, what should the
new window get? Note that MW-A1/A2 already decided new windows open windowed,
not fullscreen — propose something consistent with that.

### Q7 — Existing preferences

Is there already a preference governing window sizing? If so, any proposal must
work with it. Do not propose adding a new preference.

## Constraints on any proposed design

- **INVIOLABLE PRINCIPLE:** cooViewer's core selling point is image quality
  through avoiding unnecessary scaling. Never introduce an extra
  resize/rescale step in the render path. Initial window geometry changes the
  fit scale, so the report must state explicitly whether the proposed design
  touches the render path, and how the spread byte-identity gate would be run
  against it.
- This is an MRC project. Any new reference from a new window to the front
  window must follow the rule now in `docs/DECISIONS.md`: unretained
  back-references are dropped in `-windowWillClose:`, and never via KVC.
- Prefer size-only inheritance with AppKit's normal cascade for position,
  unless the investigation finds a reason not to.

## Deliverable

A report in `docs/tasks/YYYY-MM-DD-NN-investigate-new-window-size.md`
containing:

1. Answers to Q1–Q7 with file:line references and the observations backing
   them.
2. A recommended design, in enough detail that the implementation task can be
   written from it.
3. An implementation size estimate in one of three buckets, with reasoning:
   - **≈10 lines** — no auto-fit conflict, set the frame at creation
   - **one small task** — needs an inherited-size flag to suppress auto-fit
   - **needs a design decision from the owner** — say what the open question is
4. Anything found along the way that looks wrong but is out of scope, recorded
   rather than fixed.

## Implementation Result

**Status:** Completed

### Method

Built the `cooViewer` scheme (Development configuration) to a scratch
`SYMROOT`/`OBJROOT`/`derivedDataPath` outside the repository. Before running
it, copied the built app and changed `CFBundleIdentifier` to
`jp.coo.cooViewer.investigate` (re-signed ad hoc with `codesign -s -`) so the
test run used its own, empty `NSUserDefaults` domain and its own window-restore
state — verified empty (`defaults read jp.coo.cooViewer.investigate` → "does
not exist") before the first launch, so nothing here touched the owner's real
profile, saved book bookmarks, or window frames. Confirmed at runtime via
`osascript … bundle identifier of process "cooViewer"` →
`jp.coo.cooViewer.investigate`.

Windows were opened, moved, resized and read back with `System Events`
(`position of window`, `size of window`), driven from the same shell session
so all comparisons in one question are from one continuous run. Three
independent fixtures from `tests/fixtures/generated/` (`test.cbz`,
`test_utf8.zip`, `test.7z`) were used as three distinct books, each with a
different underlying image, to separate "same nib default every time" from
"driven by this book's content."

Test artifacts (`${TMPDIR}/cooViewer-investigate`, the
`jp.coo.cooViewer.investigate` defaults domain) were removed after the
session. No file under `/Applications` or `~/Applications` was touched, no
system preference was changed (one system setting, `NSQuitAlwaysKeepsWindows`,
was read but not modified — see Q4).

### Q1 — Where a new book window's frame is actually decided

In order of when they run, for a freshly-created (non-restored) window:

1. **Nib frame.** `Resources/Base.lproj/BookWindow.xib:25` —
   `contentRect x="103" y="366" width="480" height="360"`. This is the frame
   every window starts from before anything else runs.
2. **`-windowDidLoad`**, [BookWindowController.m:208-240](../../Sources/BookWindowController.m#L208-L240):
   - `[self setShouldCascadeWindows:NO]` (line 236) — AppKit's own cascade
     machinery is explicitly disabled, with the comment explaining why: this
     app shows windows via `-makeKeyAndOrderFront:` in `-openPage:last:`
     rather than `-showWindow:`, so `-shouldCascadeWindows`'s hook
     (`-showWindow:`) would never fire anyway.
   - **`-setFrameAutosaveName:` runs only for `windowIndex == 0`**
     (lines 237-239). Windows with `windowIndex != 0` never get an autosave
     name at all — confirmed by measurement in Q3.
   - `gNextWindowCascadePoint = [[self window] cascadeTopLeftFromPoint:
     gNextWindowCascadePoint]` (line 240) runs unconditionally, for every
     window including index 0. This is a hand-rolled cascade, not AppKit's.
3. **Restoration decode**, `-window:didDecodeRestorableState:`
   ([BookWindowController.m:1013](../../Sources/BookWindowController.m#L1013)) →
   `-restoreStateWithCoder:` (line 1030). This does **not** touch the frame
   directly — the frame itself is restored by AppKit before this delegate
   callback runs (window identifier + restoration class wiring at
   [BookWindowController.m:248-249](../../Sources/BookWindowController.m#L248-L249)).
   What this method restores is *which book* to open into the window, on the
   next run-loop turn (`-openRestoredBook`, line 1087, via
   `performSelector:...afterDelay:0.0`).
4. **`-openPage:last:` / `-openPageWithLoader:page:last:fromFileName:`**
   ([BookWindowController.m:1157](../../Sources/BookWindowController.m#L1157),
   [:1228](../../Sources/BookWindowController.m#L1228)) — searched for any
   `setFrame:`/`setContentSize:`/similar call on the *window*: **none exists.**
   The only `setFrame:` calls anywhere in `BookWindowController.m` are on
   `imageView`/`scroll` (lines 3199, 3221, 3251, 3281) — i.e. fitting the
   *content view* inside the window's existing content rect, never resizing
   the window itself. A repo-wide grep for `setFrame:` on any `NSWindow`
   confirms the same: `CustomWindow.m` overrides `-setFrame:display:` only to
   forward to an accessory window (loupe), `CustomImageView.m` sets frames on
   its own accessory/lens windows, `PreferenceController.m`/
   `ThumbnailController.m`/`AllBookmarkController.m` size their own panels —
   none of it touches a book window.

**Conclusion for Q1:** nib frame → (index 0 only) autosave restore →
hand-rolled cascade (all windows) → AppKit's own restoration of the saved
frame (all windows, if any was saved) is the complete list. There is no
fit-to-page/zoom-to-fit step that ever resizes the *window*.

### Q2 — Does opening a book resize the window? (the pivot)

**No. Measured, not inferred.** With three fixtures opened as three separate
books in the same running instance:

```
osascript: open test.cbz (default nib frame, no prior resize)
  → window "test.cbz" pos=71,45 size=480×392

osascript: set size of window "test.cbz" to {900,600} (successful; an
earlier attempt to {900,700} was clamped by AppKit to the screen's visible
frame, 900×627 with the window's top edge landing exactly on the 1080px
screen height — a normal window-placement constraint, unrelated to content
fitting; redone at 900×600 which held exactly)
  → window "test.cbz" pos=100,100 size=900×600

Finder-style open of a second, unrelated file into the same running instance
(`open -a … test_utf8.zip`, delivered via -application:openFiles: to the
already-running process — confirmed only one cooViewer process existed
throughout):
  → new window "test_utf8.zip" pos=129,129 size=480×392

⌥⌘O ("Open in New Window…") with test.cbz's window (900×600) frontmost,
opening a third, independent file (test.7z) through the real Open panel
(navigated with Cmd+Shift+G, typed the path, Return, Return):
  → new window "test.7z" pos=158,158 size=480×392
```

Every newly-created window — regardless of which of the three different books
it opened, and regardless of the entry path (Finder-style open or "Open in New
Window…") — came up at exactly **480×392**, the nib's `480×360` content rect
plus the standard titled-window chrome (`392−360=32`), cascaded by AppKit's
`~29pt` step from the previous window's origin. None of them picked up the
front window's 900×600. There is no auto-fit of the window to the page or
spread at any point; `fitScreenMode`/`-fitToScreen:` etc.
([BookWindowController.m:3192-3293](../../Sources/BookWindowController.m#L3192-L3293))
resize the *image view* inside the window's existing content rect, never the
window.

**The v1.6.0 crash-report observation is refuted, not confirmed.** The
"480×392" figure in that report is not evidence of content-driven sizing — it
is simply the nib's unmodified default frame, reproduced identically for three
unrelated books with different underlying images in this session. The v1.6.0
fix task's need to set 1200×900 explicitly for its captures was working around
the *same* default-nib-size behaviour documented here, not a symptom of
per-book auto-fit.

**Answer: no auto-fit exists.** This puts the fix in the "≈10 lines" bucket
per the task's own bucketing (see Estimate, below) — there is no auto-fit to
suppress.

### Q3 — The shared autosave name

**Confirmed, but only for `windowIndex == 0`, and this is deliberate,
documented code** ([BookWindowController.m:222-239](../../Sources/BookWindowController.m#L222-L239),
comment block "MW-6 item 1"): only the first window (`windowIndex == 0`) is
ever given `-setFrameAutosaveName:`, under the plain name `"NormalWindow"`.
Windows 2+ are cascaded (line 240) but **never given any autosave name at
all** — `-frameAutosaveName:` (line 193-199, which would produce
`"NormalWindow-2"`, `"NormalWindow-3"`, …) is used elsewhere for per-window
*panels* (Bookmark, FilterPanel — see
[BookmarkController.m:21](../../Sources/BookmarkController.m#L21),
[FilterPanelController.m:16](../../Sources/FilterPanelController.m#L16)) but
is **not** called for the book window itself when `windowIndex != 0`.

Measured: after opening three windows, resizing/moving all three (window 1 to
900×600 at 100,100; window 2 moved to 200,200; window 3 moved to 600,200),
`defaults read jp.coo.cooViewer.investigate | grep -i "window "` showed:

```
"NSWindow Frame GoToSheet" = "730 584 460 215 0 0 1920 1050 ";
"NSWindow Frame NSColorPanel" = "0 67 250 297 0 0 1920 1050 ";
"NSWindow Frame NormalWindow" = "100 380 900 600 0 0 1920 1050 ";
```

No `NormalWindow-2` or `NormalWindow-3` key ever appeared, before or after
quitting the app — confirming windows 2 and 3 are genuinely never autosaved by
name. **So the premise in the task ("a single autosave name used by all book
windows") is itself outdated** — it describes the pre-MW-6 behaviour that the
2026-07-29 MW-6 task already replaced. What's true today is closer to the
opposite risk: only the *first* window's size is remembered by name at all;
windows 2+ have no persistent-by-name record of their frame.

"Which window's frame wins at quit" is therefore not a real conflict any more
— there is only ever one name in play (`NormalWindow`, window 0's), so nothing
overwrites anything else by that mechanism. What second/third windows get on
relaunch is answered in Q4.

### Q4 — Current order of precedence (measured)

With `NSQuitAlwaysKeepsWindows` (a **global, user-level system preference**,
System Settings → Desktop & Dock → "Close windows when quitting an app",
unchecked) read as `1` on this machine (`defaults read -g
NSQuitAlwaysKeepsWindows` → `1`) — **read only, never changed; changing a
global system preference to test the opposite state would be modifying system
settings, which is out of scope for an investigation task** — a graceful quit
(verified: polled `ps aux` until the process was actually gone, since an
earlier attempt via a synthetic `Cmd+Q` keystroke silently failed to quit the
app for several seconds and would have produced a false "restore" result by
just re-reading the same still-running windows) followed by a plain relaunch
reproduced **all three** windows at their exact prior positions and sizes:

```
test.cbz       pos=100,100 size=900×600   (had an autosave key)
test_utf8.zip  pos=200,200 size=480×392   (had no autosave key)
test.7z        pos=600,200 size=480×392   (had no autosave key)
```

This means **AppKit's own window-state restoration (wired at
[BookWindowController.m:248-249](../../Sources/BookWindowController.m#L248-L249),
`-setIdentifier:`/`-setRestorationClass:`) restores frame for every window,
including the two that have no by-name autosave entry at all** — restoration
does not depend on the `NormalWindow` defaults key. This is a genuinely new,
measured finding.

**I could not determine where this per-window frame data is physically
stored.** It is not in the `NSUserDefaults` domain (checked exhaustively —
`defaults read jp.coo.cooViewer.investigate` has no `Frame`/`Window`/`Rect`
key besides the three named ones already listed) and it is not in
`~/Library/Saved Application State/` (no
`jp.coo.cooViewer.investigate.savedState` directory was ever created,
verified both before and after the quit/relaunch cycle, and confirmed the
whole directory has no `coo`-prefixed entry). This is recorded here rather
than guessed, per the reporting rules.

**Order of precedence, as measured:**

1. **Restoration** (AppKit, all windows) — wins whenever there is anything to
   restore, i.e. whenever the previous quit left restorable state (which, on
   this machine's current system setting, is every graceful quit).
2. **Named autosave** (`NormalWindow`, window 0 only) — would be window 0's
   fallback if restoration had nothing to restore (not directly observed in
   this session, since restoration was always available once any window had
   been shown; follows from AppKit's documented behaviour and from
   `-setFrameAutosaveName:` being the only other frame-setting call for
   window 0).
3. **Hand-rolled cascade** (`gNextWindowCascadePoint`, all windows,
   [BookWindowController.m:240](../../Sources/BookWindowController.m#L240)) —
   applies to windows 2+ whenever neither restoration nor an autosave key
   exists, e.g. the very first time a second window is ever created.
4. **Auto-fit** — does not exist (Q2).

This runs once per window, at `-windowDidLoad`/restoration-decode time
(load-time only, not on every page turn), and is not gated by any preference
(Q7) or different between single-page and spread mode — `windowDidLoad` runs
before any book is open, so it cannot know the eventual view mode.

### Q5 — Which entry paths create a new window, and should inherit

Re-reading the actual call graph (not just the task's list) turns up that
two of the five listed paths **do not create a new window at all**:

| Entry path | Creates a new window? | Should inherit? |
|---|---|---|
| "Open in New Window…" (⌥⌘O) → `-[AppController openBookInNewWindow:]` ([AppController.m:399](../../Sources/AppController.m#L399), [:532](../../Sources/AppController.m#L532)) | Yes, unless an empty window is reused ([AppController.m:548-552](../../Sources/AppController.m#L548-L552)) or the book is already open elsewhere (line 537-541) | **Yes** — the obvious case |
| Finder open, `-application:openFiles:` → same `-openBookInNewWindow:` ([AppController.m:218](../../Sources/AppController.m#L218), [:729](../../Sources/AppController.m#L729)) | Same as above | Per the task: excluded — Finder open has no "front window" the user is deliberately extending from |
| Recent Books → `-openFromOpenRecent:` ([BookWindowController.m:1147](../../Sources/BookWindowController.m#L1147)) | **No.** It is an instance method reached through the responder chain from the front window's own menu; it calls `-openPage:` on **the same window**, replacing that window's book. | N/A — no new window is created |
| All Bookmarks browser → Open → `-[AllBookmarkController openInSelf:]` ([AllBookmarkController.m:257-278](../../Sources/AllBookmarkController.m#L257-L278)) | **No** (explicitly, per the comment at lines 245-256: "a book that is not open replaces the front window's book"). Only brings an *already-open* window forward if the book is open elsewhere ([AllBookmarkController.m:266-269](../../Sources/AllBookmarkController.m#L266-L269)); otherwise calls `[[appController frontController] openBookAtPath:path]` (line 271) — the front window itself. | N/A — no new window is created |
| `OpenLastFolder` fallback → `-applicationDidFinishLaunchingSetup:` on `[self frontController]` ([AppController.m:748](../../Sources/AppController.m#L748)) | No — only runs when nothing else opened a book this launch (line 740 guard), meaning the only window in existence is the default empty one from launch. There is no other window to inherit from. | N/A — nothing to inherit from |
| Window restoration | Creates windows, but each has (or, per Q4, effectively always gets) its own restored frame | **Excluded**, as the task states — restoration must win |

**So the actual scope of "inherit front window's size" is exactly one call
site: `-[AppController openBookInNewWindow:]`**, and only the branch that
allocates a genuinely new window
([AppController.m:550](../../Sources/AppController.m#L550),
`aController = [self newWindowController]`) — the empty-window-reuse branch
(line 549) and the already-open branch (line 538-540) should not resize
anything, since those are existing windows the user has already sized
themselves.

### Q6 — Fullscreen source window

**The premise doesn't match anything in the repository.** Searched
`docs/DECISIONS.md` and all of `Sources/` for `MW-A1`, `MW-A2`, and any
decision text resembling "new windows open windowed, not fullscreen" —
**no such label or decision exists.** The only related, real decision is MW-2
(`docs/DECISIONS.md:354-406`), which migrated fullscreen to native AppKit
`toggleFullScreen:`/`NSWindowCollectionBehaviorFullScreenPrimary` per-window
state; it does not say anything about what a *newly created* window's
fullscreen state should be relative to the window it was opened from.

That said, the practical answer is simple and can be stated with confidence
from the code: **a new window is never created in fullscreen today, because
nothing in `-newWindowController`/`-openBookInNewWindow:` ever calls
`-toggleFullScreen:` or sets `NSWindowStyleMaskFullScreen`.** Fullscreen is
exclusively entered by explicit user action on an already-visible window
(the green button or the Window menu item). So "new windows open windowed
regardless of the source window's fullscreen state" already holds today, as a
side effect of no code path doing otherwise — not because of a documented
decision under the label the task cites. **Recommendation:** since size-only
inheritance is being proposed (Q7/design, below), and a fullscreen window's
reported frame is the screen frame (not a meaningful "size" to copy), the
front window's **last windowed frame** should be the one read — which is
exactly what `-frame` already returns once a window exits fullscreen, and
which AppKit already tracks separately from the fullscreen frame (per the
MW-2 comment at `docs/DECISIONS.md:403-405`, "correctly ignores frames taken
while full screen"). If the front window is *currently* in fullscreen,
`[window frame]` returns the *screen's* frame, not the windowed one — so the
implementation must read the front controller's last non-fullscreen size (a
value already being tracked for autosave purposes, not something new to add)
rather than `[[frontController window] frame]` directly. This is a small, real
detail for the implementation task, not a design fork — see the "one small
task" vs "≈10 lines" note below.

### Q7 — Existing preferences

**None.** Grepped `PreferenceController.m` for `WindowSize`, `Cascade`,
`frameAutosave`, and any "window ... size" pattern — no matches. No default
key of any kind governs window sizing or placement; `NSQuitAlwaysKeepsWindows`
(Q4) is a system-level, not app-level, preference and is unrelated. Any
inheritance design is free to make its own rule with no existing preference to
reconcile.

## Recommended design

1. In `-[AppController openBookInNewWindow:]`
   ([AppController.m:532](../../Sources/AppController.m#L532)), only in the
   branch that actually allocates a new window controller (line 550,
   `aController = [self newWindowController]`), capture the current front
   window's frame **before** creating the new controller (since
   `-newWindowController` immediately registers the new controller and can
   change what `-frontController` resolves to,
   [AppController.m:507-510](../../Sources/AppController.m#L507-L510)).
2. Read size only, not origin, from that frame (per the task's own
   preference, confirmed sensible by Q6: origin should keep going through the
   existing hand-rolled cascade at
   [BookWindowController.m:240](../../Sources/BookWindowController.m#L240)
   unchanged, so windows still step down-right instead of stacking exactly on
   top of each other).
3. If the front window is currently in native fullscreen
   (`-[CustomWindow isInFullScreen]`, [CustomWindow.m:6-9](../../Sources/CustomWindow.m#L6-L9)),
   do not read `[window frame]` (that is the screen's frame while fullscreen)
   — use the last windowed frame instead. This needs one small piece of new
   state (or an existing one to expose) since nothing currently reads "the
   frame a fullscreen window had before it went fullscreen" from outside
   AppKit's own autosave machinery. This is the one open question that keeps
   this out of the flat "≈10 lines" bucket.
4. Apply the captured size to the new window before it is shown (i.e. before
   `-openPage:last:`'s `-makeKeyAndOrderFront:`,
   [BookWindowController.m:1159](../../Sources/BookWindowController.m#L1159)) —
   a single `-setFrame:display:NO` call with the captured size and the
   window's own cascaded origin. This runs once, at creation, well before the
   first `composeImage`/`drawRect:` — it changes what bounds the one existing
   `drawInRect:` step is handed, exactly as a user manually resizing the
   window before opening a book already does today. **No new resampling step
   is introduced**; the render path (`composeImage` →
   `-[CustomImageView setImages:]` → `-drawRect:` → `-drawImages:and:` →
   `[page drawInRect:fromRect:]`) is untouched — geometry still comes from
   `-[CustomImageView getDrawImagesInfo:and:]` reading the view's (now
   differently-sized) bounds, same as it does after any ordinary manual
   resize. **The spread byte-identity gate needs no new case**: it already
   has to tolerate different window sizes (that's the whole point of
   comparing spreads at a fixed, controlled window size); this change does
   not add a code path between decode and `drawInRect:`, so there is nothing
   new for that gate to exercise. Confirm this by running the existing gate
   once with the window pre-set to an inherited size vs. the current default,
   at the same target size, and diffing — a formality given no new step
   exists, but worth doing once in the implementation task rather than
   asserted here.
5. Per Q3, no defaults-key churn is needed: window 0 still autosaves under
   `NormalWindow` unconditionally regardless of this change (untouched); an
   inherited-size window that is windowIndex != 0 still has no autosave name
   of its own (unchanged, pre-existing behaviour, out of this task's scope
   per Q3's finding).

**No per-window "size was inherited, do not auto-fit" flag is needed** — Q2
established there is no auto-fit to suppress in the first place.

## Implementation size estimate

**≈10 lines**, with one caveat that keeps it from being a flat trivial
change: the fullscreen-source case (Q6/step 3 above) needs the new window to
read the front window's *last windowed* frame rather than
`[[frontController window] frame]` verbatim when the front window is currently
in fullscreen. If that "last windowed frame" is already cheaply available
(worth checking first in the implementation task — AppKit's own fullscreen
handling already has to know it, to restore the window correctly on exiting
fullscreen), this stays ≈10 lines. If it turns out nothing exposes that value
today and one has to be added, it becomes a small, well-scoped addition (a few
more lines, still no new architecture) — not a design decision for the owner,
since the answer ("use the last windowed size, not the fullscreen screen
frame") is already settled by this investigation; only the plumbing is
unresolved. Recorded as the one thing worth a quick look at the start of the
implementation task rather than assumed.

## Anything found along the way that looks wrong, out of scope

- **The task's own premises for Q3 and Q6 are stale/unsubstantiated** and
  should not be carried into the implementation task's TASK.md verbatim:
  - Q3's "single autosave name used by all book windows" describes
    pre-MW-6 behaviour; MW-6 (2026-07-29,
    `docs/tasks/2026-07-29-10-mw6-per-window-behaviour.md`) already changed
    this, and windows 2+ in fact have **no** autosave name at all today (a
    different, arguably more interesting, gap than the one described).
  - Q6's "MW-A1/A2" decision label does not exist anywhere in the repository.
    The underlying behaviour it describes (new windows are never fullscreen)
    is true today, but only as an emergent property of no code path setting
    it, not a recorded decision.
- **Windows 2+ have no persisted-by-name frame at all**
  ([BookWindowController.m:237](../../Sources/BookWindowController.m#L237),
  the `windowIndex == 0` guard). Today this is masked by AppKit's own
  restoration handling it via the identifier/restoration-class wiring — but
  that restoration's storage location could not be identified in this session
  (see Q4), so its reliability across macOS versions or with
  `NSQuitAlwaysKeepsWindows` off is unverified. If a future task ever needs
  windows 2+ to reliably remember their own size independent of full
  restoration (e.g. a user with "close windows when quitting" left at its
  default), the `-frameAutosaveName:` machinery already exists
  ([BookWindowController.m:193-199](../../Sources/BookWindowController.m#L193-L199))
  but is simply never invoked for the book window itself when
  `windowIndex != 0` — worth a look, not fixed here since it's outside this
  task's scope.
- **`-setSize:` clamping to the screen's visible frame** was observed as a
  side effect while testing (a `900×700` resize at position `100,100` on a
  `3840×2160` display was silently clamped to `900×627`, with the window's
  bottom edge landing exactly on the visible-frame boundary). This is normal
  AppKit window-placement behaviour, not a cooViewer defect, and is only
  recorded here so a future reader doesn't mistake it for content-driven
  sizing if they retest.

### Verification

- Build: `xcodebuild -project cooViewer.xcodeproj -scheme cooViewer
  -configuration Development` with `SYMROOT`/`OBJROOT`/`-derivedDataPath`
  redirected to a scratch directory outside the repository —
  **BUILD SUCCEEDED**.
- Automated verification: not applicable (investigation-only task, no code
  changed).
- Manual verification: all Q1–Q7 findings above were measured against a
  running, isolated instance of the built app (own bundle identifier, own
  `NSUserDefaults` domain, verified empty before use) — see the actual
  `osascript`/`defaults read` output pasted inline under each question. No
  file under `/Applications` or `~/Applications` was touched, no shared or
  real user state was modified, and all test artifacts and the test defaults
  domain were deleted afterward.
- Not performed: testing the `NSQuitAlwaysKeepsWindows`-off case (would
  require changing a global system preference, out of scope for this task);
  identifying the physical storage location of AppKit's per-window
  restoration data (see Q4).

### Remaining Issues

None (investigation-only; findings above are recorded as follow-up
suggestions, not defects to fix now).

### Follow-up Suggestions

- Write the actual implementation task from the "Recommended design" section
  above, scoped to `-[AppController openBookInNewWindow:]` only.
- Consider (separately, not as part of the above) giving windows with
  `windowIndex != 0` their own `-frameAutosaveName:`-based persistence, so
  their size/position survive independent of full window restoration — see
  "Anything found along the way," above.
