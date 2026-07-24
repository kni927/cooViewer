# TASK: Remove legacy tracked files and enable unused-code warnings

## Scope

Two independent parts, both without dead code deletion:

- Part A: remove fork-era legacy files from git tracking.
- Part B: enable unused-code warnings and re-measure.

Do not delete any source code, functions, or variables in this task.
Do not act on dead stores, potential leaks, or uninitialized-value
warnings; they are handled separately.

## Part A: Legacy tracked files

1. Remove the following from git tracking and from the working tree:
   - `cooViewer.xcodeproj/.svn/` (10 tracked files)
   - `cooViewer.xcodeproj/cookie.mode1`
   - `cooViewer.xcodeproj/cookie.mode2`
   - `cooViewer.xcodeproj/cookie.perspective`
2. Before removing, confirm none of them are referenced from
   `project.pbxproj`, build scripts, or sources. Report the result of that
   check.
3. Check whether any other Xcode 3 era files remain tracked under
   `cooViewer.xcodeproj/` (`*.pbxuser`, `*.mode1v3`, `*.perspectivev3`,
   `xcuserdata` committed by mistake). Report them; remove only those that
   are clearly unused legacy state.
4. Add appropriate `.gitignore` entries if the existing ones do not already
   cover these patterns.

## Part B: Unused-code warnings

1. Locate all targets and configurations where `GCC_WARN_UNUSED_VARIABLE`
   or `GCC_WARN_UNUSED_FUNCTION` is set to `NO` or left unset, and report
   the current state per target.
2. Set both to `YES` for all project targets. Do not change vendored
   library build settings.
3. Build and report:
   - total count of `-Wunused-variable` and `-Wunused-function` warnings
   - a breakdown by file, sorted by count
   - any target that fails to build as a result
4. Do not fix or remove anything the new warnings report. Recording the
   list is the deliverable.
5. If enabling these warnings produces an unmanageable volume of noise from
   a specific pattern (e.g. generated code), report it rather than
   suppressing it.

## Verification

- Build succeeds after both parts.
- `git status` clean after commit.
- The removed legacy files no longer appear in `git ls-files`.
- Warning counts from Part B are recorded in the implementation result.

## Notes

- Do not launch or register the built app in this task; a successful build
  is sufficient.
- Record the Part B warning list in the task archive so the next task can
  use it to define its scope.
- Record dead stores, potential leaks, and uninitialized-value warnings
  from the previous survey in `docs/KNOWN_ISSUES.md` if not already
  present. Do not fix them.
## Implementation Result

**Status:** Completed

### Changes

**Part A — legacy tracked files**

- Reference check (step 2): `cookie.mode1/mode2/perspective`, `.svn`, and
  `Seiki*` are **not referenced** from `project.pbxproj`, build scripts, or
  any tracked source. Verified via grep / git grep.
- Removed from git tracking and the working tree (step 1):
  - `cooViewer.xcodeproj/.svn/` (10 tracked files)
  - `cooViewer.xcodeproj/cookie.mode1`, `cookie.mode2`, `cookie.perspective`
- Other Xcode-3-era files (step 3): none remain tracked. No stray
  `*.pbxuser` / `*.mode1v3` / `*.perspectivev3` outside the now-removed
  `.svn/`, and no `xcuserdata` was committed. Remaining
  `cooViewer.xcodeproj/` tracked files are current (`project.pbxproj`,
  `project.xcworkspace/{contents.xcworkspacedata,xcshareddata/IDEWorkspaceChecks.plist}`,
  `xcshareddata/xcschemes/*.xcscheme`).
- `.gitignore` (step 4): existing entries covered `*.pbxuser` /
  `*.mode1v3` / `*.mode2v3` / `*.perspectivev3` but not the older
  no-`v3` names or SVN metadata. Added `*.mode1`, `*.mode2`,
  `*.perspective`, and `.svn/`.

**Part B — unused-code warnings**

- Current state before (step 1), per target/config:
  - `cooViewer` (project + app target): `GCC_WARN_UNUSED_VARIABLE` NO or
    unset across configs; `GCC_WARN_UNUSED_FUNCTION` mixed YES/NO/unset.
  - `cooViewerThumbnail`: both **unset** in all 5 configs.
  - `cooViewerPreview`: both **unset** in all 5 configs.
- Set both `GCC_WARN_UNUSED_VARIABLE = YES` and
  `GCC_WARN_UNUSED_FUNCTION = YES` in all 20 XCBuildConfiguration blocks
  (all belong to project targets; vendored cmake libs untouched).

### Verification

- Build: `xcodebuild -scheme cooViewer_deploy -configuration Deployment`
  (clean build, out-of-repo SYMROOT/OBJROOT/derivedDataPath) →
  `** BUILD SUCCEEDED **`. No target failed as a result.
- `git ls-files` no longer lists the removed `.svn/` or `cookie.*` files.

### Part B warning list (deliverable)

Totals (distinct source locations): **`-Wunused-variable` = 11**,
**`-Wunused-function` = 1**. (Raw occurrence counts are higher — 30 and 24 —
because the scheme compiles the app plus both extension dependencies and a
header-scope static function is re-warned per translation unit.)

`-Wunused-variable` by file:

- `Sources/Controller.m` (3): 1232 `heightValue`, 1232 `widthValue`,
  1232 `repi`
- `Sources/COImageLoader.m` (2): 500 `items`, 501 `data`
- `Sources/LoupeView.m` (2): 177 `sx`, 213 `sx`
- `Sources/NSString_Compare.m` (2): 47 `manager`, 60 `manager`
- `Sources/CustomImageView.m` (1): 1347 `fullscreenRect`
- `Sources/FilterPanelController.m` (1): 85 `docBounds`

`-Wunused-function` by file:

- `Sources/GlobalKeyboardDevice.h` (1): 47 `hotKeyEventHandler`

Noise pattern (step 5): the single `-Wunused-function` is a `static`
function defined in a **header** (`GlobalKeyboardDevice.h`), so it is warned
once per including translation unit (24 raw hits) despite being a single
source location. Reported, not suppressed.

### Remaining Issues

- None for this task. Dead stores / potential leaks / uninitialized-value
  findings from the earlier survey were recorded in
  `docs/KNOWN_ISSUES.md` #16 (not fixed, per scope).

### Follow-up Suggestions

- A future task may act on the 11 unused variables and 1 unused function
  listed above (out of scope here). The header-scope static function likely
  wants to move to a `.m` or be removed.
