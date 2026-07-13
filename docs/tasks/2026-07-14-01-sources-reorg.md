# TASK: Source tree reorganization — phase 3 (move sources into Sources/)

## Background

Repo root currently holds a large number of Objective-C source files
(Controller.h/.m and friends) directly at the top level, inherited from
the original tak758/cooViewer fork style. This makes the root hard to
scan. This task is a pure reorganization: no logic changes.

This is intentionally sequenced before the next RAR performance task
(archive_read_data_skip-based partial lazy extraction) so that task's
diff stays clean against the new file locations rather than colliding
with file moves.

## Goal

- All Objective-C/C/C++ source and header files live under `Sources/`.
- Root contains only project-level files: README, LICENSE, CLAUDE.md,
  AGENTS.md, the .xcodeproj, vendor/, docs/, Frameworks/, and similar
  top-level directories — no loose .h/.m/.mm files.
- Project builds and runs identically to before the move. Zero behavior
  change.

## Scope

### In scope

- Move all root-level `.h` / `.m` / `.mm` / `.c` / `.cpp` source files
  into `Sources/` using `git mv` (preserve history; do not
  delete-and-recreate).
- A flat `Sources/` layout is acceptable for this pass; do not invent
  subfolder categorization (e.g. Views/, Controllers/, Models/) unless
  it is trivial and obvious — if grouping is non-obvious, leave it flat
  and note it as a follow-up suggestion instead of guessing.
- Update `project.pbxproj` file references to match new paths (Xcode
  will mostly handle this if files are moved via Xcode's "New Group
  from Selection" / drag, but if editing pbxproj by hand, verify no
  dangling or duplicate references remain).
- Update any `#import "X.h"` paths, build script paths, or CI workflow
  paths that assumed root-level source locations.
- Update README/CLAUDE.md/AGENTS.md if they reference specific source
  file paths.

### Out of scope

- Any logic, behavior, or API change to the moved files.
- Grouping into semantic subfolders beyond flat `Sources/` (leave as a
  follow-up suggestion if warranted).
- The RAR archive_read_data_skip lazy-extraction work (next task, after
  this one).
- Vendored library files (`vendor/`, `Frameworks/`) — not in scope,
  already organized.

## Verification

- Build: `xcodebuild -configuration Deployment` succeeds with no new
  warnings related to missing files.
- pbxproj sanity: no dangling file references (Xcode shows no red/
  missing-file entries when opened).
- Diff review: `git diff --stat` shows only renames (`R` status) for
  source files, no unintended content changes.
- Manual smoke test: app launches, opens a zip and a rar archive,
  displays pages — confirms nothing broke silently.
- CI: workflow runs green after the move (paths in
  `.github/workflows/*.yml`, if any reference source paths directly).

## Implementation Result

**Status:** Completed

### Changes

- Moved all 74 root-level `.h`/`.m` files into `Sources/` via `git mv`
  (37 headers + 37 implementation files, including `main.m`); history
  preserved as pure renames. `cooViewer_Prefix.pch` stays at root — it
  is a prefix header, not a `.h`/`.m`/`.mm`/`.c`/`.cpp` source file,
  and the task scope's extension list doesn't cover it.
  `Sources/` uses a flat layout as instructed; no subfolder
  categorization was attempted (see Follow-up Suggestions).
- `cooViewer.xcodeproj/project.pbxproj`: updated the `path =` field of
  all 74 moved `PBXFileReference` entries to `Sources/<file>`; no
  other project settings needed changes because every `#import "X.h"`
  in the codebase is a bare-filename quote-include, which Xcode/clang
  resolves relative to the including file's own directory — since all
  sources moved together, this kept working unchanged.
  `HEADER_SEARCH_PATHS` (vendor/include only) and `GCC_PREFIX_HEADER`
  (root-relative, file didn't move) were untouched.
- `tests/engine/run_tests.sh`: updated the two hardcoded paths
  (`$REPO_ROOT/COArchive.m` -> `$REPO_ROOT/Sources/COArchive.m`, same
  for `COZipArchive.m`) and the `-I` flag (`$REPO_ROOT` ->
  `$REPO_ROOT/Sources`) so `test_coarchive.m`'s `#import "COArchive.h"`
  still resolves. No other script or CI workflow referenced root
  source paths directly.
- README.md/CLAUDE.md/AGENTS.md: no changes needed — none of them
  reference a source file by path (only bare filenames appear in
  `docs/DEV_LOG.md`/`docs/KNOWN_ISSUES.md` prose, which stayed
  accurate since the files were not renamed, only relocated).

### Verification

- Build: `xcodebuild -configuration Deployment clean build` succeeds
  (only the pre-existing `imageFileTypes` deprecation warnings, no new
  ones, no missing-file errors).
- pbxproj sanity: `plutil -lint` passes; `xcodebuild -list` shows the
  same targets/schemes as before; `grep` confirms 0 remaining bare
  `path = <file>.h/.m;` references and exactly 74 `Sources/`-prefixed
  ones.
- Diff review: `git diff --cached --stat` shows only `R` renames for
  the 74 source files (0 insertions/deletions each); the only content
  diffs are `project.pbxproj` (path fields) and
  `tests/engine/run_tests.sh` (path flags).
- Tests: `tests/engine/run_tests.sh` (rebuilt against the new
  `Sources/` paths) — ALL PASS.
- Manual verification: launched the rebuilt app, opened
  `tests/fixtures/generated/test.cbz` (libzip path) and `test.cbr`
  (libarchive/rar path) — both display the 4-page test book
  correctly.

### Remaining Issues

- None.

### Follow-up Suggestions

- Semantic subfolders under `Sources/` (e.g. `Views/`, `Controllers/`,
  `RemoteControl/`, `Categories/`) were deliberately not attempted —
  the existing Xcode group structure (`main`, `filter`, `preference`,
  `bookmark`, `thumbnail`, `item`, `Remote Controll Wrapper`,
  `Category`, `archive`) already hints at a grouping, but turning that
  into physical subfolders is a separate, reviewable decision, not
  a trivial/obvious one for this pass.
- The RAR `archive_read_data_skip`-based partial lazy extraction task
  can now proceed against clean `Sources/` paths as intended.
