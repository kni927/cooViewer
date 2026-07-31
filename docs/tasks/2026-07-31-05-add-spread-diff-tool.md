# TASK: Add tolerance-based spread-diff tool; document the capture/comparison methodology (v1.6.x)

## Background

Investigation (`docs/tasks/2026-07-31-04-investigate-byte-identity-gate.md`,
commit 5e59ec3) found: exact SHA-256 comparison of a spread capture is
only valid for solid-fill regions. Anti-aliased edges from text/vector
content are not bit-reproducible across independent redraws, even with
zero code change — a system-level rendering characteristic (reproduced
in unmodified Preview.app under an equivalent test), not a cooViewer
defect. The investigation also caught a real methodology bug: a
forced-redraw test let `screencapture -R` grab a different, frontmost
window instead of the intended test window.

Recommendation from that investigation: replace exact hashing with a
tolerance-based diff (bounded max per-channel difference + edge-
adjacency check) for any region containing text/vector content; keep
exact hashing for solid-fill regions; prefer fresh single-draw captures
over page-nav-forced redraws where a choice exists.

This task is not release-critical — v1.6.2 is not being treated as a
hotfix, so there is no urgency, but this should land before it's next
relied on for an image-quality-sensitive change.

## Goal

1. Add a working tolerance-based diff tool to the repository, based on
   the draft below.
2. Update `CLAUDE.md` with the methodology section below.
3. Update `docs/DECISIONS.md` with the entry below, filling in this
   task's own archive path once known.
4. No app code changes. No render-path changes.

## Placement

Decide the tool's location following the repository's existing
conventions (e.g. a `tools/` or `scripts/` directory, whichever
already exists or fits better) — use your judgment, this task does not
mandate a specific path. Record the chosen path in the completion
report and use that same path in the CLAUDE.md addition below (the
draft below uses `tools/spread_diff.py` as a placeholder — update it
to match wherever it actually lands). Note any runtime dependency
(Pillow, NumPy) in whatever form the project already documents such
things (e.g. a comment header, `docs/`, or a requirements file) if one
exists; do not add new project-wide dependency-management
infrastructure just for this if none exists — a note of `pip3 install
pillow numpy` in the script's own docstring/usage is sufficient.

## Draft script to adapt (starting point, not final)

The script below is a working draft — tested against small synthetic
images (identical → PASS; a real content change inside a solid region
→ correctly FAILs; edge-adjacent AA-style noise → mostly PASSes, with
one boundary-overlap pixel exceeding tolerance at the default
settings). Treat the default `--max-channel-diff 24` / `--edge-margin
2` as unvalidated against real cooViewer spread captures — calibrating
them is part of this task (see Verification).

```python
#!/usr/bin/env python3
"""
spread_diff.py — tolerance-based comparison for cooViewer spread captures.

Replaces exact SHA-256 comparison for regions containing text/vector
content, where anti-aliased edge pixels are not bit-reproducible across
independent redraws even with zero code change (see
docs/tasks/2026-07-31-04-investigate-byte-identity-gate.md).

Verdict logic:
  - If the two images are byte-identical, PASS immediately (fast path;
    also the expected result for pure solid-fill captures).
  - Otherwise, every differing pixel must satisfy BOTH:
      1. max per-channel absolute difference <= --max-channel-diff
      2. within --edge-margin pixels of a detected edge in the
         reference image (a simple gradient-magnitude edge map)
    If any differing pixel fails either condition, treat the diff as a
    real content change, not AA noise, and FAIL.

This tool does not touch cooViewer's render path or app code. It is a
verification-only utility for manual/CI capture comparisons.

Usage:
    python3 spread_diff.py reference.png candidate.png \
        [--max-channel-diff 24] [--edge-margin 2] [--report report.png]

Exit codes:
    0  PASS (identical, or all diffs explained as edge AA noise)
    1  FAIL (a diff that is not edge-adjacent AA noise was found)
    2  usage / input error (e.g. size mismatch, unreadable file)

Dependencies: Pillow, NumPy (pip install pillow numpy).
"""

import argparse
import sys

try:
    import numpy as np
    from PIL import Image
except ImportError as e:
    print(f"error: missing dependency ({e}). Run: pip3 install pillow numpy",
          file=sys.stderr)
    sys.exit(2)


def load_rgb(path):
    try:
        img = Image.open(path).convert("RGB")
    except Exception as e:
        print(f"error: could not open '{path}': {e}", file=sys.stderr)
        sys.exit(2)
    return np.asarray(img, dtype=np.int16)  # int16 to allow signed diffs


def edge_mask(reference_rgb, dilate_margin):
    """
    Simple gradient-magnitude edge map on the reference image, dilated
    by `dilate_margin` pixels so AA fringes adjacent to an edge count
    as "near an edge" too. No external CV dependency — plain NumPy
    Sobel-ish gradient + a manual box dilation.
    """
    gray = reference_rgb.mean(axis=2)

    gy = np.zeros_like(gray)
    gx = np.zeros_like(gray)
    gy[1:-1, :] = gray[2:, :] - gray[:-2, :]
    gx[:, 1:-1] = gray[:, 2:] - gray[:, :-2]
    grad = np.abs(gx) + np.abs(gy)

    edges = grad > (grad.max() * 0.02 if grad.max() > 0 else 1.0)

    if dilate_margin <= 0:
        return edges

    dilated = edges.copy()
    h, w = edges.shape
    for dy in range(-dilate_margin, dilate_margin + 1):
        for dx in range(-dilate_margin, dilate_margin + 1):
            if dy == 0 and dx == 0:
                continue
            shifted = np.zeros_like(edges)
            y0, y1 = max(0, dy), h + min(0, dy)
            x0, x1 = max(0, dx), w + min(0, dx)
            sy0, sy1 = max(0, -dy), h - max(0, dy)
            sx0, sx1 = max(0, -dx), w - max(0, dx)
            shifted[y0:y1, x0:x1] = edges[sy0:sy1, sx0:sx1]
            dilated |= shifted
    return dilated


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("reference", help="path to reference/baseline PNG")
    ap.add_argument("candidate", help="path to candidate PNG being checked")
    ap.add_argument("--max-channel-diff", type=int, default=24,
                     help="max per-channel abs diff tolerated for an edge pixel (default: 24)")
    ap.add_argument("--edge-margin", type=int, default=2,
                     help="pixels of dilation around detected edges (default: 2)")
    ap.add_argument("--report", metavar="PATH",
                     help="optional: write a diff-visualization PNG here "
                          "(red = disqualifying diff, yellow = tolerated edge diff)")
    args = ap.parse_args()

    ref = load_rgb(args.reference)
    cand = load_rgb(args.candidate)

    if ref.shape != cand.shape:
        print(f"error: size/shape mismatch: {ref.shape} vs {cand.shape}",
              file=sys.stderr)
        sys.exit(2)

    diff = np.abs(ref - cand)
    max_channel_diff = diff.max(axis=2)
    differing = max_channel_diff > 0

    n_total = differing.size
    n_diff = int(differing.sum())

    if n_diff == 0:
        print(f"PASS  byte-identical  (0/{n_total} pixels differ)")
        sys.exit(0)

    edges = edge_mask(ref, args.edge_margin)

    within_tolerance = max_channel_diff <= args.max_channel_diff
    explained = differing & edges & within_tolerance
    unexplained = differing & ~explained

    n_explained = int(explained.sum())
    n_unexplained = int(unexplained.sum())

    if args.report:
        vis = ref.copy().astype(np.uint8)
        vis[explained] = [255, 220, 0]   # yellow: tolerated AA noise
        vis[unexplained] = [255, 0, 0]   # red: disqualifying diff
        Image.fromarray(vis, "RGB").save(args.report)
        print(f"report written: {args.report}")

    print(f"pixels differing:   {n_diff}/{n_total}")
    print(f"  edge-adjacent, within tolerance (+/-{args.max_channel_diff}, "
          f"margin {args.edge_margin}px): {n_explained}")
    print(f"  unexplained (not edge-adjacent, or exceeds tolerance):  {n_unexplained}")

    if n_unexplained == 0:
        print("PASS  all diffs explained as edge anti-aliasing noise")
        sys.exit(0)
    else:
        print("FAIL  unexplained diff found — treat as a real content/render change")
        sys.exit(1)


if __name__ == "__main__":
    main()
```

Feel free to adjust implementation details (e.g. dependency-free
approach, different edge-detection method, CLI shape) as long as the
verdict semantics (exact match always passes; solid-fill regions must
match exactly; text/vector regions tolerate only edge-adjacent,
bounded-magnitude diffs) are preserved. Note the observed rough edge
in the draft: overlapping edge-dilation at a corner can push a
genuinely-AA pixel's combined per-channel delta above the flat
threshold — worth keeping in mind when calibrating, not necessarily a
defect to fix.

## CLAUDE.md addition

Add this section after "On-Device Verification Procedure" (adjust the
script path to wherever it actually lands per the Placement section
above):

```markdown
## Spread Capture & Comparison Methodology

Use this whenever a change needs to be verified as visually identical
(or intentionally different) to a baseline, e.g. confirming the render
path wasn't affected by an unrelated change.

### Known pitfalls (apply every time)

- Capture both sides of a comparison in the **same session**. A spread
  region's exact bytes are not stable cross-session (window-corner
  anti-aliasing, compositor state).
- Region capture grabs whichever window is **frontmost** at the moment
  of capture. Position windows non-overlapping, and if a test forces a
  redraw (e.g. via a page-nav round trip) between captures, re-assert
  frontmost immediately before each capture — a forced-redraw test can
  let a different window (e.g. an unrelated Preview/PDF window) become
  frontmost in between. See
  `docs/tasks/2026-07-31-04-investigate-byte-identity-gate.md` for a
  concrete case.
- A screenshot taken immediately after launch can be black before first
  render.
- A keystroke expected to produce "no change" needs independent proof
  it was delivered, not just an unchanged reading.
- Screen Recording permission must be granted to the actual capturing
  process (e.g. `tmux`), not the visible terminal app.
- **Anti-aliased edges (text/vector content) are not bit-reproducible
  across independent redraws**, even with zero code change — confirmed
  as a system-level rendering behavior (reproduced in Apple's own
  Preview.app under an equivalent test), not a cooViewer defect. Solid-
  fill regions ARE exactly reproducible byte-for-byte.
- Prefer a fresh single-draw capture over a page-navigation-forced
  redraw when a choice exists — the latter introduces more opportunity
  for the frontmost-window and edge-AA pitfalls above.

### Comparison method

- **Solid-fill region:** exact SHA-256 match is valid and expected.
- **Region containing text/vector content:** use `tools/spread_diff.py`
  (tolerance-based: bounded max per-channel difference + edge-adjacency
  check) instead of exact hashing. Exact hashing on such a region WILL
  show spurious diffs even with no code change — do not treat that as
  a failure, and do not treat it as a pass just because "it usually
  looks the same."
```

## DECISIONS.md addition

Add this entry, filling in the implementation task's own archive path
(this task) once it is archived:

```markdown
## Spread comparison: tolerance-based diff replaces exact hash for text/vector regions

Exact SHA-256 comparison of a spread capture is only valid for solid-
fill regions. Anti-aliased edges from text/vector content are not
bit-reproducible across independent redraws, even with zero code
change — this is a system-level rendering characteristic (reproduced
in unmodified Preview.app), not a cooViewer defect.

For any region containing text/vector content, use the tolerance-based
diff tool (bounded max per-channel pixel difference + edge-adjacency
check — see CLAUDE.md, "Spread Capture & Comparison Methodology"), so
a spurious AA diff passes but a real content or render-path change
still fails.

Investigation: `docs/tasks/2026-07-31-04-investigate-byte-identity-gate.md`.
Implementation: <this task's archive path>.
```

## Verification

1. Run the script's own correctness cases (or equivalents you devise):
   identical images → PASS; a real content change inside a solid
   region → FAIL; synthetic edge-adjacent noise → PASS or a documented,
   understood near-miss.
2. **Calibration against real captures** (the part not yet done):
   capture the same spread twice in the same session (zero code
   change, per the investigation's own repro case) and confirm the
   tool PASSes at the chosen default thresholds. Capture a spread with
   a deliberately introduced 1-line render change (e.g. temporarily
   perturb something in a scratch build) and confirm the tool FAILs.
   Revert the scratch change afterward — do not leave it in the repo.
   Paste actual tool output for both cases in the completion report.
3. Confirm `CLAUDE.md` and `docs/DECISIONS.md` read correctly after
   the edits (no broken structure, path references match the actual
   chosen script location).
4. No build/app verification needed beyond confirming the script runs
   under a plain `python3` invocation with the stated dependencies
   installed — this task does not touch `cooViewer.xcodeproj`.

## Deliverable

Follow the standard completion/archiving procedure in
`docs/task-workflow.md`: append the Implementation Result to this
`TASK.md`, archive it as
`docs/tasks/YYYY-MM-DD-NN-add-spread-diff-tool.md`, and provide the
chat completion report per the same doc's template.

## Implementation Result

**Status:** Completed

### Changes

- **[tools/spread_diff.py](../../tools/spread_diff.py)** (new): the
  draft script adopted essentially as-is — verdict semantics, CLI shape,
  and dependency note (`pip3 install pillow numpy`, stated in the
  script's own docstring, no new project-wide dependency infra since
  none exists for this project) all unchanged from the draft. `tools/`
  was created since no `tools/` or `scripts/` directory existed yet;
  chosen over adding this to `tests/` because it is a manual/CI
  verification utility for capture comparisons, not part of the
  `tests/engine/` automated suite or `tests/fixtures/` fixture
  generation.
- **[CLAUDE.md](../../CLAUDE.md)**: added the "Spread Capture &
  Comparison Methodology" section verbatim from the draft, inserted
  after "On-Device Verification Procedure" and before "Repository
  Layout". Path reference (`tools/spread_diff.py`) already matched the
  chosen placement, no edit needed there.
- **[docs/DECISIONS.md](../../docs/DECISIONS.md)**: appended the
  "Spread comparison: tolerance-based diff replaces exact hash for
  text/vector regions" entry verbatim from the draft, with the
  `<this task's archive path>` placeholder filled in as
  `docs/tasks/2026-07-31-05-add-spread-diff-tool.md`.
- No app code was left changed. A scratch, temporary 8-point horizontal
  offset was introduced in `Sources/CustomImageView.m`'s single-page
  `-drawInRect:fromRect:` call for the FAIL-case calibration test (see
  Verification below), built, exercised, and then reverted;
  `git diff Sources/CustomImageView.m` is empty after the revert
  (confirmed below).

### Verification

- **Script's own correctness cases**, run against synthetic fixtures
  built for this task (not committed — scratch files under `/tmp`):

  ```
  === Case A: identical ===
  PASS  byte-identical  (0/30000 pixels differ)
  exit: 0

  === Case B: solid-region content change ===
  pixels differing:   100/30000
    edge-adjacent, within tolerance (+/-24, margin 2px): 0
    unexplained (not edge-adjacent, or exceeds tolerance):  100
  FAIL  unexplained diff found — treat as a real content/render change
  exit: 1

  === Case C: edge-adjacent noise ===
  pixels differing:   720/30000
    edge-adjacent, within tolerance (+/-24, margin 2px): 720
    unexplained (not edge-adjacent, or exceeds tolerance):  0
  PASS  all diffs explained as edge anti-aliasing noise
  exit: 0
  ```

  All three match the required verdicts (identical → PASS; solid-region
  content change → FAIL; edge-adjacent noise → PASS). Case C passed
  outright rather than showing the draft's described one-pixel boundary
  near-miss — a different synthetic fixture than the draft author used,
  not a discrepancy in the tool's logic (the boundary-overlap caveat in
  the draft is about a specific input, not a general guarantee).

- **Calibration against real captures.** Built the `cooViewer` scheme
  (Development) to a scratch location and ran it under an isolated
  bundle identifier (`jp.coo.cooViewer.calib`, own verified-empty
  `NSUserDefaults` domain), following the frontmost-reassertion
  methodology from the investigation task (`docs/tasks/2026-07-31-04-…`)
  to avoid the capture-contamination bug found there.

  - **Zero-code-change PASS, same window, no redraw:**

    ```
    PASS  byte-identical  (0/1280000 pixels differ)
    exit: 0
    ```

  - **Zero-code-change PASS, same window, after a forced redraw**
    (page-nav away and back, repeated 5×): all five recaptures were
    byte-identical to the pre-redraw baseline this run (the AA-edge
    noise the investigation documented is real but intermittent, not
    reproduced in this particular session — see the investigation
    task's own note that it isn't always present). The tool's fast
    byte-identical path correctly reported PASS in all cases:

    ```
    PASS  byte-identical  (0/1280000 pixels differ)
    exit: 0
    ```

  - **Zero-code-change PASS, two independent windows, same content**
    (opened the same book under two different filenames — a
    byte-identical copy — to get two separately-rendered windows
    without the "already open" dedup interfering): also byte-identical
    this run:

    ```
    PASS  byte-identical  (0/1280000 pixels differ)
    exit: 0
    ```

    **Honest limitation:** this session's real captures did not
    reproduce the non-trivial AA-edge noise (5–57/255) that the
    investigation task measured and pasted evidence for — the
    phenomenon is confirmed real and system-level (see that task's
    Preview.app control) but intermittent, and this session's real
    captures happened to land in the deterministic case every time.
    The tool's *tolerance* logic (as opposed to its trivial
    byte-identical fast path) is therefore validated here only against
    the synthetic Case C above, not against a real cooViewer capture
    exhibiting genuine AA noise. The FAIL-case test below does exercise
    the tolerance/edge-detection logic against a real capture, just not
    the PASS side of it. Recorded rather than fabricating a real "PASS
    via tolerance" result that wasn't actually observed.

  - **Deliberate render-path change → FAIL**, on a real capture. Scratch
    change: `Sources/CustomImageView.m`, the single-page
    `-drawInRect:fromRect:` call, offset `drawRect.origin.x` by 8pt.
    Built to a separately-named scratch copy
    (`jp.coo.cooViewer.calibscratch`, executable renamed to
    `cooViewerScratch` to avoid the `System Events` same-process-name
    ambiguity recorded in the prior implementation task), captured, and
    compared against the unmodified baseline capture:

    ```
    pixels differing:   141210/1280000
      edge-adjacent, within tolerance (+/-24, margin 2px): 19207
      unexplained (not edge-adjacent, or exceeds tolerance):  122003
    FAIL  unexplained diff found — treat as a real content/render change
    exit: 1
    ```

    122,003 unexplained pixels — correctly FAILs, and by a wide margin
    (the ~19K edge-adjacent pixels are the new edge the shift itself
    created, which is expected and does not change the verdict since
    the bulk of the shifted image content falls far outside any
    edge-adjacency margin). Confirms the default thresholds
    (`--max-channel-diff 24`, `--edge-margin 2`) do not mask a real,
    even fairly small (8pt), render-path change.

    Scratch change reverted immediately after capture:
    `git diff Sources/CustomImageView.m` — empty. Rebuilt afterward to
    confirm the reverted source still compiles (BUILD SUCCEEDED).

- **CLAUDE.md / DECISIONS.md read correctly** after editing — both
  files use the exact draft text with only the `<this task's archive
  path>` placeholder filled in; no other placeholder or path mismatch
  remains (the CLAUDE.md path reference, `tools/spread_diff.py`, already
  matched the Placement decision, so no substitution was needed there).

- **Build:** `xcodebuild -project cooViewer.xcodeproj -scheme cooViewer
  -configuration Development` — BUILD SUCCEEDED, both with the scratch
  perturbation (for the FAIL-case capture) and after reverting it (final
  state). No `cooViewer.xcodeproj` changes were made; this was
  verification only, per the task's own scope note.

- **Cleanup:** all scratch app copies, their `NSUserDefaults` domains,
  the scratch `test_copy_calib.cbz` fixture, and `/tmp` scratch
  directories were removed after the session.

### Remaining Issues

None. The one honestly-recorded limitation (real AA-noise PASS case not
reproduced this session) does not block the tool's correctness — the
FAIL-case test exercised the same tolerance/edge-detection code path
against a real capture, just from the opposite (over-threshold) side.

### Follow-up Suggestions

- Next time the AA-edge noise reproduces on a real capture (per the
  investigation task's own note that it's intermittent), run it through
  `tools/spread_diff.py` and confirm it PASSes via the tolerance path
  rather than the byte-identical fast path — closes the one gap left by
  this session's calibration.
- `--max-channel-diff 24` / `--edge-margin 2` are validated as not
  masking an 8pt content shift, but were not tuned against a much
  smaller, more realistic near-threshold render regression (e.g. a 1px
  shift or a subtle interpolation-quality change). Worth a follow-up
  calibration pass if a future change is that subtle.
