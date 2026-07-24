# TASK: Fix potential memory leaks reported by the analyzer

## Scope

Address the 7 `Potential leak` findings in `docs/KNOWN_ISSUES.md` #16.
Dead stores and the remaining false positives are out of scope.

## Steps

1. Re-run `xcodebuild analyze` and list the current potential-leak findings
   with file, line, and description. Report any drift from #16.
2. For each finding, determine before changing anything:
   - which call creates the owning reference
     (`alloc` / `new` / `copy` / `mutableCopy` / `retain`)
   - which code path leaves it unreleased (early return, exception path,
     conditional branch)
   - whether that path is actually reachable, as opposed to an infeasible
     branch the analyzer follows
   - whether the object is stored into an ivar, collection, or returned to
     the caller, in which case the ownership transfer may be intentional
     and the finding a false positive
3. Fix only the findings confirmed reachable and genuinely leaking. Prefer
   the minimal correct fix: add the missing `release` / `autorelease` on
   the leaking path, or restructure ownership only where a simple release
   would be wrong.
4. For any finding determined to be a false positive or an intentional
   ownership transfer, do not add defensive releases. Record the reasoning.
5. Do not touch `vendor/`.

## Verification

- Build all targets.
- Report the new potential-leak count and which findings remain, with
  reasons.
- Confirm no other analyzer category increased.
- Launch the built app, open a document, and exercise the code paths
  affected by the fixes. Over-release shows up as a crash, so each fixed
  path must be exercised. Report which paths were verified and which could
  not be reached from the UI.

## Documentation

- Update `docs/KNOWN_ISSUES.md` #16 with the resolved and remaining
  findings.
- Update `docs/DEV_LOG.md` if the result is meaningful project progress.

## Notes

- Over-release is worse than a leak. Where reachability or ownership is
  unclear, leave the code alone and record it rather than guessing.
- Record in the implementation result whether any fix could not be verified
  at runtime.
## Implementation Result

**Status:** Completed

### Changes

All 7 `Potential leak` findings were confirmed genuine, reachable MRC leaks
(no false positives) and fixed with the minimal correct change.

- `Sources/AccessoryView.m` `-setInfoString:` (was line 691) and
  `-setPageString:` (was 775): the `else` branch sent `-initWithString:`
  to an already-initialized **immutable** `NSAttributedString` and
  discarded the `+1` init result (leak; also a latent stale-text bug).
  Replaced with `[infoString release]; infoString = [[NSAttributedString
  alloc] initWithString:…]` (and the same for `pageString`), matching the
  `if` branch. Owning call: `-initWithString:`. Leaking path: every call
  after the first (before the ivar is cleared). Reachable.
- `Sources/Controller.m` (was 474) `multiTouchMouseArray`: `[[NSMutableArray
  alloc] initWithObjects:…]` was copied into `mouseArray` and stored in
  `NSUserDefaults`, but the array object itself was never released. Added
  `[multiTouchMouseArray release]` after the copy. Reachable only in the
  version-migration block (upgrade from < 1.2b23).
- `Sources/Controller.m` (was 2699/2735/2771; now 2698/2734/2770) `scroll`
  in `fitToScreenWidth:`, `fitToScreenWidthDivide:`, `noScale:`:
  `[[NSScrollView alloc] init]` is added to the view hierarchy via
  `replaceSubview:with:` (superview retains it) but the local `+1` was
  never released. Added `[scroll release]` after `setDocumentView:` in each
  of the three methods. Reachable via the View-menu fit modes.
- `Sources/ThumbnailController.m` (was 258) `image2` in
  `loadMangaImage:back:`: the `back` branch's `else` returned
  `[image autorelease]` without releasing the retained `image2`, unlike the
  symmetric `!back` branch which does. Added `[image2 release]` before the
  return. Reachable when rendering a small page beside a non-small one in
  bind mode.

No false positives among these seven; no defensive releases were added.
`vendor/` untouched.

### Verification

- Build: `xcodebuild -scheme cooViewer_deploy -configuration Deployment`
  (all targets) → `** BUILD SUCCEEDED **`.
- `xcodebuild analyze`: `Potential leak` **7 → 0**. No other category
  increased (dead-store 15, uninitialized-receiver 3, null-deref 1,
  localized 23 — all unchanged). No new over-release / use-after-free
  analyzer warnings.
- Runtime (staged `build/cooViewer.app`, `test.cbz`; over-release surfaces
  as a crash):
  - **scroll ×3 + infoString** — cycled the View-menu fit modes
    (`⌘1`/`⌘2`/`⌘3`/`⌘4`) six times; each switch runs a `fit*`/`noScale:`
    method (scroll create+release) and calls `-setInfoString:` (the fixed
    `else` after the first). No crash. **Verified.**
  - **pageString** — navigated pages (001 → 002–003 spread); the page
    overlay updated via `-setPageString:` (the fixed `else`). No crash.
    **Verified.**
  - **image2** (`ThumbnailController -loadMangaImage:back:` back-branch
    `else`) — **not exercised from the UI.** It needs the thumbnail panel to
    render a small page beside a non-small one in bind/back mode, which the
    test fixture and `isSmallImage:` heuristic do not let us force
    deterministically. Confidence is high regardless: the fix is a
    byte-for-byte match of the already-correct `!back` branch and the
    analyzer confirms no leak and no over-release.
  - **multiTouchMouseArray** — **not exercised from the UI.** It only runs
    in the one-time version-migration path (upgrade from < 1.2b23); a normal
    launch already has a current `Version` default. The fix is a plain
    `release` of a locally-alloced array; analyzer-confirmed.

### Could not verify at runtime

`image2` and `multiTouchMouseArray` paths (reasons above). Both are
analyzer-confirmed and, for `image2`, symmetric with existing correct code.

### Documentation

- `docs/KNOWN_ISSUES.md` #16: all 7 potential leaks marked RESOLVED with the
  owning call, leak path, and fix for each.
- `docs/DEV_LOG.md`: not updated — analyzer-driven leak fixes are code
  hygiene, not a major milestone per the DEV_LOG policy.

### Remaining Issues

None in this category. Remaining #16 items are dead stores (out of scope)
and the G2/G3/G4 false positives.

### Notes

Behaviour: the `AccessoryView` fix also corrects a latent bug — the `else`
branch previously failed to actually update the immutable attributed string,
so repeated info/page updates could show stale text in addition to leaking.
The fix makes the text update correctly. No over-release was observed in any
exercised path.
