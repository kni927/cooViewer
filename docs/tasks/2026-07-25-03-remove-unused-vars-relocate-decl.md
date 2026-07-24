# TASK: Remove unused variables and relocate hotKeyEventHandler declaration

## Scope

Apply the dispositions determined in
`docs/tasks/2026-07-25-02-classify-unused-code.md`.

- Part A: delete the 11 unused variables classified as safe to delete.
- Part B: move the `hotKeyEventHandler` declaration out of the header.

Do not touch dead stores, potential leaks, or uninitialized-value warnings
(`docs/KNOWN_ISSUES.md` #16). Do not change behaviour.

## Part A: Unused variables

1. Delete each of the 11 variables listed in the archived classification
   table. All were classified as non-owning or scalar with no side effects.
2. Re-verify ownership at each site before deleting. If any site differs
   from the archived classification, leave it in place and report the
   discrepancy rather than deleting it.
3. For `Controller.m:1232`, the consuming code is commented out. Delete the
   declarations; leave the commented-out block untouched.
4. For `COImageLoader.m:501` (`NSData* data;`), confirm no later assignment
   or use exists before deleting.
5. Do not reformat, reindent, or otherwise modify surrounding lines.

## Part B: hotKeyEventHandler

1. Remove the `static` declaration at `GlobalKeyboardDevice.h:47`.
2. Add a forward declaration in `GlobalKeyboardDevice.m` above its first use
   (line ~145), or move the definition above the use site.
3. This file originates from a third-party library
   (RemoteControlWrapper, MIT). Keep the change minimal and preserve the
   existing copyright header and style. Record the modification in the
   implementation result.
4. Do not remove or rewire `GlobalKeyboardDevice` itself. Whether the class
   should be used or dropped is a separate decision.

## Verification

- Build all targets.
- Confirm `-Wunused-variable` and `-Wunused-function` counts are now zero,
  or report any remaining ones with reasons.
- Confirm the total warning count did not increase in other categories.
- Launch the built app once and confirm it opens a document normally.
  Follow `CLAUDE.md` regarding installation and registration.

## Notes

- Behaviour must be unchanged. This is hygiene only.
- Record in the implementation result that `GlobalKeyboardDevice` is
  instantiated nowhere in the project, as a follow-up suggestion rather
  than acting on it.
## Implementation Result

**Status:** Completed

### Changes

Hygiene only; behaviour unchanged. Applied the dispositions from
`docs/tasks/2026-07-25-02-classify-unused-code.md`.

**Part A — deleted 11 unused variable declarations (9 source lines):**

- `Sources/COImageLoader.m:500` `NSArray* items` and `:501` `NSData* data`
  (confirmed `data` had no later assignment/use before deleting)
- `Sources/Controller.m:1232` `int heightValue = 0,widthValue = 0,repi = 0;`
  (whole line; the consuming code remains commented out and was left
  untouched)
- `Sources/CustomImageView.m:1347` `NSRect fullscreenRect`
- `Sources/FilterPanelController.m:85` `NSRect docBounds`
- `Sources/LoupeView.m:177` and `:213` `float sx`
- `Sources/NSString_Compare.m:47` and `:60` `NSFileManager *manager`

Each site was re-verified before deletion; all matched the archived
classification (scalar / value type / non-owning), so none was left in
place. Only declaration lines were removed — no surrounding lines were
reformatted or reindented (diff = 9 deletions, 0 insertions).

**Part B — relocated `hotKeyEventHandler` declaration:**

- Removed the `static OSStatus hotKeyEventHandler(...)` declaration from
  `Sources/GlobalKeyboardDevice.h:47`.
- Added the same forward declaration in `Sources/GlobalKeyboardDevice.m`
  immediately after `#import "GlobalKeyboardDevice.h"` (above the first use
  at the `InstallEventHandler` call), with a short comment explaining the
  relocation. The definition at the bottom of the `.m` is unchanged.
- The file is third-party (RemoteControlWrapper, MIT). The copyright header
  and existing style were preserved; the change is minimal.
- `GlobalKeyboardDevice` itself was not removed or rewired.

### Verification

- Build: `xcodebuild -scheme cooViewer_deploy -configuration Deployment`
  (clean build, all targets) → `** BUILD SUCCEEDED **`.
- `-Wunused-variable` = **0**, `-Wunused-function` = **0** (both previously
  11 and 1).
- No new warnings in any other category: normalized (line-number-independent)
  comparison against the pre-change build shows **0 genuinely new warnings**;
  the only delta is the removal of the 12 unused warnings. Distinct compiler
  warnings 168 → 156 (−12). (The raw file:line diff shows shifted line
  numbers for existing `-Wdeprecated-declarations` hits, not new warnings.)
- Launch: staged `build/cooViewer.app` and opened
  `tests/fixtures/generated/test.cbz` — the cover page rendered normally and
  the full main menu was present. The launched build instance was then
  quit; no copy was installed to `/Applications` or registered
  (per CLAUDE.md).

### Remaining Issues

None.

### Follow-up Suggestions

- `GlobalKeyboardDevice` is **instantiated nowhere in the project**
  (`Controller.m` creates only `AppleRemote`); its keyboard-shortcut remote
  feature is latent/unwired. Whether to keep or drop the class is a separate
  decision and was not acted on here.
