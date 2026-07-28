# Task: Remove the legacy "Old" composited render path (BufferingMode=0)

Standalone task, to run **before MW-3**. Not part of the multi-window
plan, but sequenced ahead of it for the same reason MW-2 was pulled
forward: deleting a subsystem before the split makes every later task
smaller.

## Background

Owner has decided this path should go. It is not the default, it costs an
extra resampling step versus direct draw, and every open concern that
lives inside it disappears with it: `screenCacheArray`, the `ScreenCache`
preference, `KNOWN_ISSUES` #21, the MW-6 per-window memory concern, and
the MW-7 cache-key omission.

## Scope

- Delete `returnComposeImage:`, `screenCacheArray` and its plumbing, the
  `ScreenCache` preference and its UI field, and the `BufferingMode`
  popup in Preferences. Direct draw becomes unconditional.
- Remove the `respondsToSelector:@selector(finalize)` gate along with it
  — do not log it as a separate issue; it ceases to exist here.
- Stored `BufferingMode` / `ScreenCache` values: leave them in place, no
  migration — consistent with the `Fullscreen` / `DontHideMenuBar`
  decision.
- Verify nothing outside the compose path reads these. In particular
  check `useComposedImage`, `composedImage`, and any menu/validation
  that branches on buffering mode.

## Accepted trade-off

Users who explicitly selected `BufferingMode = 0` change path. Image
quality improves, but without the composite cache, resize/scroll CPU cost
may rise. **The owner has accepted this.**

## Verify

- Spreads and single pages render identically to the current build under
  the owner's settings (`BufferingMode = 1`) — pixel comparison, not a
  look.
- A profile that currently has `BufferingMode = 0` now renders via direct
  draw with no crash and no visual defect. Note any perceptible
  responsiveness change during resize/scroll, since the composite cache
  is gone.

## Then

- Update `docs/multiwindow-plan.md`: close out the MW-6 and MW-7 items
  this removes.
- Drop `KNOWN_ISSUES` #21 as resolved-by-deletion.
- Record the decision and its rationale in `docs/DECISIONS.md`.

Archive per `docs/task-workflow.md`. MW-3 follows in a fresh session.

---

## Implementation Result

**Status:** Completed

### Changes

**`Sources/Controller.{h,m}`** — deleted `returnComposeImage:and:` and
`-imageDisplayIfHasScreenCache` outright; removed the `screenCacheArray`,
`composedImage`, `useComposedImage`, `bufferingMode` and `screenCache`
ivars and every use; removed the `BufferingMode` / `ScreenCache` defaults
reads and write-backs and the `respondsToSelector:@selector(finalize)`
gate that registered `BufferingMode`. `-composeImage` is now three lines
(`[imageView setImages:secondImage]`). The compose/cache block in
`-lookaheadAndCompose` is gone, as is the
`useComposedImage`/`composedImage` selection in `-lockedImageDisplay`.
The four fit-mode actions and `-recomposeForCurrentSize` lost their
`bufferingMode` forks and now always take the direct branch.

**`Sources/Controller_input.m`** — removed 20 `useComposedImage`
assignments, 2 `composedImage` teardown pairs, and the 5
`if (bufferingMode == 0 && screenCache>0) [self imageDisplayIfHasScreenCache];`
fast-path calls.

**`Sources/PreferenceController.{h,m}`** — removed the
`bufferingModePopUpButton` and `screenCacheTextField` outlets, their
load/save halves, and the `changeBufferingMode:` action.

**`Resources/Base.lproj/MainMenu.xib`** — removed the Buffering mode
popup (and its Old/New menu items), the "Buffering mode:" label, the
screen-cache field (and its number formatter), the "Cache :" label, and
both outlets. Also removed an orphan the scope list did not mention: the
grey hint *"Old" does not work properly on retina display*, which only
made sense while the popup existed. Caught by screenshotting the
Advanced tab rather than by grep.

**`Resources/ja.lproj/MainMenu.strings`** — removed the six now-dangling
localization entries (494 → 488 keys).

**Docs** — `CLAUDE.md`'s two-path table replaced by a single-path
description; `docs/DECISIONS.md` entry added; `docs/multiwindow-plan.md`
MW-6 and MW-7 cross-cutting flags closed as no-longer-applicable, MW-5
hazard 2 rewritten (it referenced `returnComposeImage:`), the
cross-cutting intro corrected, MW-9 case 16 collapsed from three
sub-cases back to one; `KNOWN_ISSUES` #21 closed as resolved-by-deletion;
`docs/DEV_LOG.md` architecture notes updated (they still described the
compose flow as current).

### Scope check: nothing outside the compose path read these

Verified by grep after the removal: no occurrence of `bufferingMode`,
`screenCache`, `screenCacheArray`, `composedImage`, `useComposedImage`,
`returnComposeImage` or `imageDisplayIfHasScreenCache` remains anywhere
in `Sources/`, and none in the nib. `useComposedImage` turned out to be
write-only outside the one selection block in `-lockedImageDisplay` — 20
assignments, one reader — so removing the reader made all of them dead.
No menu item or `validateMenuItem:` branch referenced buffering mode.

### Verification

- **Build:** `BUILD SUCCEEDED`, Deployment. Zero non-deprecation
  warnings; the remaining warnings are pre-existing deprecations in
  untouched code.
- **Pixel comparison against the pre-removal build** (same fixture, same
  window geometry 1400×900 at {200,100}, display 1, cropped to the
  window):

  | Case | Result |
  |---|---|
  | Spread, `BufferingMode = 1` (owner's setting) | **identical** — meanAbsDiff `0.0000`, maxDiff `0` |
  | Single page, `BufferingMode = 1` | **identical** — meanAbsDiff `0.0000`, maxDiff `0` |
  | New build, `BufferingMode = 0` vs `= 1` | **identical** — confirms the paths are unified and the preference is now inert |

- **`BufferingMode = 0` profile** (`ScreenCache = 5`): opens, renders,
  no crash. Its rendering *does* differ from the old build
  (meanAbsDiff 46.0) — expected, the path changed. Inspected the
  captures to confirm it is not a defect: the old composited path scaled
  each page **independently** to fit its half of the canvas, so a spread
  of two differently-proportioned pages came out with mismatched heights;
  direct draw normalises them. Former "Old" users get a *better-aligned*
  spread, and the same output every default-settings user already had.
- **Responsiveness** (the accepted trade-off, measured on the test
  fixture, `BufferingMode = 0` profile):
  - Page turns, 24 alternating: CPU `0.21 s` (old, cached composites)
    vs `0.50 s` (new, direct) — roughly 9 ms vs 21 ms per turn. Higher,
    but not perceptible.
  - Resizes, 20: CPU `0.22 s` (old) vs `0.19 s` (new) — no regression.
  - Total session CPU was *lower* on the new build (`1.17 s` vs
    `1.32 s`), because the up-front compose work in
    `lookaheadAndCompose` is gone.
- **Preferences:** opens without a KVC-compliance crash (the risk from
  removing outlets), and the Advanced tab lays out cleanly with no hole
  where the two controls were — verified by screenshot, which is also
  how the orphaned retina hint was found.
- **Defaults safety:** the domain was exported before testing and
  restored after; verified `FULL DOMAIN IDENTICAL: True`, with
  `BufferingMode = 1` / `ScreenCache = 0` as before.
- **Not verified:** responsiveness on a large real book — the fixture is
  4 pages of 2000×1400. The per-turn cost scales with image size, so a
  book of much larger scans would show a larger absolute difference
  (still one `drawInRect:` per page, so it should stay proportional).
  Also not tested: PDF-backed books through the changed draw path.

### Remaining Issues

- Stored `BufferingMode` and `ScreenCache` values remain in existing
  profiles, now unread. Deliberate, recorded in `docs/DECISIONS.md`,
  consistent with `Fullscreen` / `DontHideMenuBar`.

### Follow-up Suggestions

- `-composeImage` is now a three-line wrapper around
  `[imageView setImages:secondImage]` and its name no longer describes
  what it does. Renaming it (and `-lookaheadAndCompose`, which no longer
  composes) would be a small clarity win, but it touches many call sites
  — better done as its own task, and ideally after MW-5, which renames
  the class anyway.
- MW-3 is unaffected by this removal; its inventory in
  `docs/multiwindow-plan.md` still stands.
