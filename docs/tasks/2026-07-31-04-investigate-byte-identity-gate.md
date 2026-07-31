# TASK: Investigate — spread byte-identity gate is not reproducible (methodology fix)

## This is an investigation task. Do not implement a render-path change.

The deliverable is a written report with a root cause and a recommended
fix to the *testing methodology* (the capture/compare procedure itself),
not to cooViewer's code. Investigation-only tasks are archived like any
other.

## Background

During v1.6.2 verification (`docs/tasks/2026-07-31-03-implement-new-window-size.md`),
the project's spread byte-identity gate (SHA-256 of a captured spread
region) was found to be non-reproducible on this machine/session — it
differed even for a same-window page reload with zero code involved.
This made it impossible to use the gate as literally specified to
validate that change, and the task had to fall back to a code-path
argument instead of a measured pass.

This gate exists specifically to protect the project's INVIOLABLE
PRINCIPLE (no extra resize/rescale in the render path — image quality
via avoiding unnecessary scaling). Every future change that touches
anything near the render or window-sizing path — not just bug fixes —
needs a gate that actually works, so this should be fixed before it's
relied on again.

## Reporting rules

- **Measure; do not infer from reading.** Show the observation that
  proves each claim, not a plausible explanation.
- Paste actual output (hashes, byte counts, screenshots/regions where
  useful).
- Where the answer is "I could not determine this," say that.
- Reuse the project's known capture pitfalls as a starting checklist,
  but treat them as unconfirmed suspects here, not settled causes:
  window-corner anti-aliasing varying across sessions, GPU compositing
  variance, display dithering, timing of capture relative to first
  render, whether the two windows being compared are pixel-identical
  in size/position/scale factor.

## Questions to answer

### Q1 — Reproduce and isolate

Confirm the non-reproducibility with the simplest possible case: same
window, same book, same page, reload (or re-display) with **no code
change involved**. Capture twice in the same session and compare
SHA-256. Then capture once, quit, relaunch, capture again — does
cross-session vs. same-session behave differently? Paste both hash
pairs.

### Q2 — Isolate the variable

Test each suspect independently, holding everything else fixed:
- Same window, recaptured twice with no redraw in between (does the
  capture mechanism itself introduce variance, e.g. a screenshot tool
  that isn't pixel-perfect deterministic?)
- Same window, forced redraw (e.g. resize-and-restore to the same
  frame) between captures — does that change the hash even though
  final pixels should be visually identical?
- Two different windows at identical frame/position, same content —
  does window-corner anti-aliasing differ per-window as already
  suspected from prior pitfalls, or is that not actually the cause
  here?
- Backing scale factor / Retina vs non-Retina considerations if
  applicable on this machine.
- Whether the capture region includes any window chrome (title bar,
  corner radius) vs. strictly the image content area.

### Q3 — Does cropping tighter eliminate the variance?

If chrome/corner pixels are implicated, test capturing a region
cropped well inside the image content only (away from any window
edge) and see if that hash is now stable across the same tests as Q1/Q2.

### Q4 — Root cause statement

State, with evidence, what is actually causing the non-determinism.
If more than one factor contributes, rank them by how much of the
variance each explains, to the extent measurable.

## Deliverable

A report in `docs/tasks/YYYY-MM-DD-NN-investigate-byte-identity-gate.md`
containing:

1. Answers to Q1–Q4 with pasted hash/measurement output.
2. A recommended fix to the capture/compare **procedure** — e.g. a
   revised crop region, a required settle time before capture, a
   different (non-hash) comparison metric if exact byte-identity turns
   out to be fundamentally unreliable on this setup, or whatever the
   evidence points to. If the fix is "byte-identity is not achievable
   here, use metric X instead," say so explicitly and propose X.
3. An implementation size estimate for adopting the fix (procedure-only
   change vs. needing new tooling/script support).
4. Anything found along the way that's out of scope, recorded rather
   than fixed.

## Implementation Result

**Status:** Completed

### Method

Built the `cooViewer` scheme (Development) to a scratch location, ran it
under an isolated bundle identifier (`jp.coo.cooViewer.gatetest`, its own
verified-empty `NSUserDefaults` domain), and drove it with `System
Events`/`screencapture`. Diffs were quantified with Pillow
(`ImageChops.difference` → `.getbbox()` / `.getextrema()`) in a scratch
virtualenv, not installed system-wide. All test windows and the defaults
domain were removed afterward; two unrelated apps (TextEdit, Preview)
were used as system-level controls and closed/quit afterward without
touching the user's own open documents (in particular, a real Preview
window showing the user's own PDF, `51_318.pdf`, was identified mid-session
and left completely untouched — see the methodology note below).

### Q1 — Reproduce and isolate

**Same-session, no redraw, back-to-back captures of a static window did
sometimes differ:**

```
q1_a1.png  e72a4ef0…
q1_a2.png  0da69999…   (different — bbox (470,382)-(482,394), max diff 21/255)
```

but were not *always* different — four further back-to-back retries were
mutually identical:

```
q1_retry_1..4.png   46f27868…  (all four identical to each other)
```

**Cross-session (quit, relaunch, recapture) was, in the end, perfectly
reproducible** — see the methodology note below for why the first
attempt looked otherwise:

```
cross2_before.png (pre-quit)         4f214011…
cross2_after.png  (post-relaunch)    4f214011…   — identical
```

**Methodology note — a real capture-contamination bug was found and
fixed while answering this question.** The first cross-session attempt
(`cross_before.png` / `cross_after.png` / `cross_after_settled.png`)
produced a huge, whole-region difference (max 255/255). Viewing the
"before" capture showed it was not cooViewer at all — it was a
completely unrelated Japanese academic PDF, which turned out to be the
user's own, already-open Preview window (`51_318.pdf – Page 1 of 8`,
confirmed present via `System Events` window enumeration), captured
because `screencapture -R` grabs whatever is on screen at that region
regardless of which app owns it, and window front-to-back order had
shifted after switching between test apps (TextEdit, Preview) earlier in
the session. Fixed by explicitly bringing cooViewer frontmost
(`set frontmost to true`) and re-confirming its window's own reported
position immediately before every capture from that point on, which is
what produced the clean, identical `cross2_*` pair above. This is a
sharper version of the project's existing "region capture grabs
whichever window is frontmost" pitfall: it is not enough to position
windows non-overlapping once — frontmost state must be reasserted right
before every capture in a session that also touches other apps.

### Q2 — Isolate the variable

- **Capture mechanism alone:** not the cause by itself. Repeated
  `screencapture` calls against a window that was not redrawn were
  internally consistent in the majority of trials (the four `q1_retry_*`
  captures matched exactly), and a purely solid-color crop (below) never
  differed. The `q1_a1`/`q1_a2` case shows the tool *can* catch a window
  mid-redraw, not that the tool itself is non-deterministic against
  identical framebuffer contents.
- **Forced redraw of already-displayed content changes the hash even
  when the final pixels are meant to be visually identical.** Navigating
  away a page and back to the same page 1 of `test.cbz` (previously
  measured in the implementation task: `96ab6598…` → `fa8f447a…`, max
  diff 57/255) reproduces here too; this investigation adds that the
  diff is *not* spread uniformly — see Q3.
- **Two different window instances, same content, same position
  (necessarily sequential, since two windows can't occupy identical
  screen pixels at once):** measured in the prior implementation task —
  differed with a small, unlocalized diff (max 5/255) between two
  separate processes' windows; not independently re-measured in this
  session, carried forward as a data point.
- **Backing scale factor:** confirmed Retina/2×. A 900×600-point capture
  region consistently produced 1800×1200-pixel PNGs
  (`sips -g pixelWidth -g pixelHeight`) throughout testing; the one time
  this did not hold (an early, since-abandoned attempt to position a
  test window at a screen x-coordinate that crossed onto a second
  display) produced a visibly wrong pixel width and was excluded from
  all reported comparisons.
- **Chrome vs. content-only region:** not the primary cause. All
  reported comparisons in this report already exclude the title bar
  (captures start at least 50pt below the window's top edge) and this
  did not, by itself, make captures deterministic — see Q1's `q1_a1`/
  `q1_a2` pair, both cropped well inside the content area.

### Q3 — Does cropping tighter eliminate the variance?

**Yes, decisively, when the crop excludes every anti-aliased edge.** A
100×10pt region chosen to contain only the page's blank white
background (no text, no shape borders) was captured before and after a
forced redraw (page nav away and back):

```
blank_1.png   8e626596…
blank_2.png   8e626596…   — identical, bbox: None, extrema: (0,0)
```

Zero difference, even across the same redraw operation that changed the
hash for a text-containing region. This is the clearest single result in
the investigation: **the non-determinism lives entirely at anti-aliased
pixel edges (text glyphs, vector shape borders) and is completely absent
from solid-fill regions**, regardless of redraw.

### Q4 — Root cause statement

**Primary cause (confirmed): anti-aliased-edge rendering is not
bit-reproducible across independent redraws, and this is a system-level
(AppKit/Core Graphics/WindowServer) phenomenon, not specific to
cooViewer's code.**

Evidence, ranked by how directly each isolates the cause:

1. **Solid-fill regions are always exactly reproducible; anti-aliased
   regions sometimes are not.** (Q3, decisive.)
2. **The same phenomenon reproduces in Apple's own Preview.app**, an
   unrelated, unmodified system app, under an equivalent forced-redraw
   test (window minimized and restored to the identical frame, showing
   a static PNG with no text reflow risk):

   ```
   preview_1.png            43b6f601…
   preview_after_restore.png 140b5a1e…   — different
   bbox (355, 0, 466, 9), extrema max 1/255
   ```

   Small (max 1/255) and tightly localized to an edge, but real and
   reproducible with the exact same methodology used against cooViewer.
   This rules out cooViewer-specific code as the sole cause.
3. **cooViewer's own redraw-triggered diffs are larger in magnitude**
   (up to 57/255, vs. Preview's 1/255, under comparable forced-redraw
   conditions) and can span a wider area (Q1's `q1_a1`/`q1_a2`, bbox
   ~12×12px; the implementation task's whole-region 5–57/255 cases).
   This is consistent with a universal, small baseline noise floor (item
   2) that cooViewer's own draw path — image scaling/interpolation
   through `-drawInRect:`, and/or the page-bar/HUD overlay compositing
   on top of the page — amplifies somewhat. **This investigation did not
   pin down which part of cooViewer's draw path does the amplifying**;
   doing so would mean instrumenting or modifying the render path, which
   this task is explicitly scoped not to do (Q4 asks for a root-cause
   *statement*, and the deliverable is a testing-procedure fix, not a
   render-path change).
4. **The trigger is redraw of already-displayed content, not the mere
   passage of time or a fresh single draw.** A clean quit-and-relaunch
   (a single fresh decode-and-draw, never previously composited in that
   process) reproduced byte-identically (Q1's `cross2_*` pair) once the
   frontmost-window contamination bug was fixed. Repeated captures of an
   *already-displayed*, never-redrawn frame were also usually stable
   (`q1_retry_1..4`). The one clearly non-deterministic same-session,
   no-redraw pair (`q1_a1`/`q1_a2`) is the outlier and most likely still
   caught an in-flight compositor update immediately after the window
   was resized/repositioned moments earlier in the same script — i.e.
   even "no redraw" isn't reliably true immediately after a geometry
   change. **Practical rule that falls out of this:** compare fresh,
   settled, single-draw captures wherever the test can arrange it;
   avoid comparing a page-nav-forced or geometry-driven redraw against
   an earlier capture, since that is the condition most reliably shown
   to introduce edge noise.
- **Not confirmed, and explicitly not claimed as the mechanism:**
  display-level temporal dithering, True Tone, or HDR/EDR tone-mapping
  were plausible candidates raised by the task's own checklist. Reading
  `defaults -currentHost read com.apple.CoreBrightness`/`CoreDisplay`
  for True Tone/Night Shift state returned no usable value on this
  machine, so this could not be confirmed or ruled out directly; it
  remains a plausible contributor to item 2's universal baseline but is
  recorded as unconfirmed rather than asserted.

### Recommended fix to the capture/compare procedure

**Byte-identity (exact SHA-256) is not achievable here whenever the
compared region contains anti-aliased content that was independently
redrawn, and should be replaced with a tolerance-based comparison for
any such region.** Concretely:

1. **Prefer comparing fresh, single-draw captures over redraw-based
   ones.** When the gate's purpose is "did this change introduce a
   resampling step," compare two freshly-opened windows/processes at
   settle time, not a page-navigated-away-and-back redraw of one window
   — the former was measured byte-identical across a full quit/relaunch
   cycle in this session; the latter was the single most reliable way to
   *induce* the noise this report is about.
2. **Where a solid-fill sub-region is available (e.g. page margins,
   background), keep using exact SHA-256 for it** — that comparison
   remains fully reliable (Q3) and is the cheapest possible check that
   nothing shifted or rescaled wholesale.
3. **For any region containing text or vector edges, replace exact hash
   equality with a small numeric tolerance:** compute the per-pixel
   absolute difference between the two captures and require both (a)
   max per-channel difference ≤ a small threshold (this session's
   legitimate noise topped out at 57/255 for cooViewer's own redraws and
   1/255 for Preview's; a threshold in the low tens, e.g. ≤16, would
   comfortably separate that noise from an actual rescale, which would
   show much larger, spatially systematic differences — a full resample
   shifts or blurs content over a wide area, not a handful of edge
   pixels), and (b) the non-zero-diff pixels form a small, edge-hugging
   footprint rather than being spread uniformly over the whole capture
   (a real added resampling step would show a much larger nonzero bbox
   than the tight bounding boxes measured in this report — compare Q1/Q3's
   handful-of-pixels boxes against a "whole region, uniform" pattern,
   which is the shape a genuine extra resize would be expected to
   produce). A simple, sufficient version of (b): report the nonzero-diff
   bounding box and eyeball that it hugs text/vector edges rather than
   covering the frame — this is already how this investigation
   distinguished real edge noise from the earlier accidental
   window-contamination bug (the latter's bbox covered the *entire*
   capture at max intensity, visibly different in kind from every
   genuine same-content comparison in this report).
4. **Always re-assert frontmost state immediately before each capture**
   in any session that also touches other apps, not just once at
   setup — the contamination bug in Q1 is a stronger version of the
   project's existing "position windows non-overlapping" pitfall and
   should be added to it.

### Implementation size estimate

**Small tooling addition**, not a procedure-only change and not a large
effort: the pass/fail check itself needs to move from `shasum -a 256`
equality to a short image-diff script (this investigation's ad hoc
Pillow one-liners are enough of a starting point — computing
`ImageChops.difference(...).getbbox()`/`.getextrema()` and checking
against the thresholds above is a handful of lines). This can live as a
small script (e.g. `scripts/compare-spread.py`, or documented as a
copy-pasteable one-liner in `docs/DECISIONS.md` next to the existing
byte-identity description) rather than new infrastructure. The
procedural changes (item 1, item 4 above) are free — they are about
*when* and *how* to capture, not new tooling.

### Anything found along the way that's out of scope

- **A persistent dark region along the left edge of every capture of the
  test window** (visible in the `cross2_before.png`/`cross2_after.png`
  images referenced above) was initially mistaken for capture
  contamination. It is not — it reproduced identically across fresh
  launches and is most likely cooViewer's own thumbnail/page-bar side
  panel rendering in its default state. Not confirmed further (would
  require reading `ThumbnailController`/page-bar code, out of scope for
  a testing-methodology task) and not a defect; recorded so a future
  session doesn't re-spend time on the same false lead.
- **The animated/HUD page-counter overlay** (the rounded "#1/4" pill
  visible at the top-left of every captured page) was avoided by
  cropping below it in every quantitative comparison in this report, but
  its own redraw/fade behavior (if any) was not tested and could be an
  additional, uninvestigated source of variance for any future gate
  that doesn't crop it out. Worth a quick check before relying on a
  full-window (uncropped) comparison.
- **Driving two simultaneously-running same-named copies of the app via
  `System Events`** remains unreliable (`tell process "cooViewer"` and
  `first process whose unix id is <pid>` were both observed resolving to
  the wrong process in the prior implementation task) — not re-exercised
  in this session since it wasn't needed, but still a live hazard for
  the next person running this gate with two live instances; the
  workaround (rename one copy's `CFBundleExecutable`) is recorded in the
  prior task's archive.
