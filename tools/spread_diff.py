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
    python3 tools/spread_diff.py reference.png candidate.png \
        [--max-channel-diff 24] [--edge-margin 2] [--report report.png]

Exit codes:
    0  PASS (identical, or all diffs explained as edge AA noise)
    1  FAIL (a diff that is not edge-adjacent AA noise was found)
    2  usage / input error (e.g. size mismatch, unreadable file)

Dependencies: Pillow, NumPy (pip3 install pillow numpy).
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
