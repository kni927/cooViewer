---
name: spread-compare
description: Capture cooViewer spreads and compare them with a baseline, to show the render path is unchanged (or changed on purpose) - same-session captures, frontmost-window checks, SHA-256 for solid fills and tools/spread_diff.py for text or line art. Use whenever a change must be shown to render identically, or a rendering difference must be measured.
---

# Spread capture and comparison

`CLAUDE.md` ▸ Spread Capture & Comparison Methodology is the rule; this is
the procedure. Run the app with the `device-check` skill (or `CLAUDE.md` ▸
On-Device Verification Procedure) around it.

## Capture

1. **Both sides in the same session.** A spread region's exact bytes are not
   stable across sessions (window-corner anti-aliasing, compositor state).
   Build and capture the baseline, then the change, without a restart in
   between.
2. Wait for the first render; a capture right after launch can be black.
3. Place windows so they do not overlap, and **make the window under test
   frontmost right before each capture**: a region capture grabs whatever
   is in front, and a forced redraw (a page round trip) can bring another
   window, such as a Preview PDF, to the front
   (`docs/tasks/2026-07-31-04-investigate-byte-identity-gate.md`).
4. Prefer a fresh single draw to a redraw forced by paging; paging adds
   chances for the frontmost and anti-aliasing problems.
5. Capture with `tools/device_check.sh capture x,y,w,h`, which writes a new
   PNG outside the repository and prints its path. Screen Recording must be
   granted to the process that captures (for example `tmux`), not to the
   visible terminal.
6. A key press that should change nothing needs its own proof that it was
   delivered; an unchanged capture alone proves nothing.

## Compare

- **Solid-fill region:** exact SHA-256 match. It is reproducible byte for
  byte, so any difference is real.
- **Region with text or line art:** `tools/spread_diff.py` (bounded
  per-channel difference plus an edge-adjacency check). Anti-aliased edges
  are not bit-reproducible across redraws even with no code change (Apple's
  Preview.app does the same), so a hash mismatch there is not a failure,
  and "it looks the same" is not a pass.

Report the regions, the method used for each, and the result.
