# CLAUDE.md
@AGENTS.md

## Project-specific (cooViewer)
- Vendored libs (one-time): `vendor/build-libs.sh` (needs cmake).
  libarchive/uchardet/libzip are built as universal dylibs, bundled in
  Frameworks/.
- Build so intermediates stay outside the repository and only the final
  app lands in `build/`:
  ```bash
  BUILD_TMP="${TMPDIR%/}/cooViewer-build"
  xcodebuild -project cooViewer.xcodeproj -scheme cooViewer_deploy \
    -configuration Deployment \
    SYMROOT="$BUILD_TMP/sym" OBJROOT="$BUILD_TMP/obj" \
    -derivedDataPath "$BUILD_TMP/dd" build
  rm -rf build && mkdir -p build
  cp -R "$BUILD_TMP/sym/Deployment/cooViewer.app" build/
  ```
  The overrides redirect all Xcode output (products, intermediates,
  index, DerivedData) under `$BUILD_TMP`, outside the repository; only
  the final `cooViewer.app` is copied into `build/`. The QuickLook
  extensions (`cooViewerThumbnail`, `cooViewerPreview`) are embedded in
  `cooViewer.app/Contents/PlugIns/` — do not copy the standalone `.appex`
  products into `build/`. The project no longer sets `SYMROOT`, so with a
  DerivedData build location a plain `xcodebuild` writes outside the repo
  too; still use the command above to place the final app under `build/`.
  Note: a stale per-user legacy build location
  (`xcuserdata/…/WorkspaceSettings.xcsettings` with
  `BuildLocationStyle = UseTargetSettings`) forces the old default of
  `SRCROOT/build`; switch Xcode ▸ Settings ▸ Locations to "Derived Data"
  if plain builds land in `build/`.
- Do not edit vendored library sources
- Do not install local/debug builds directly into `/Applications` for
  manual testing. Use a separate test location (e.g. `~/Applications`)
  and register it with `lsregister -f` / `pluginkit -a` instead.
  Repeatedly building, installing, and re-registering multiple
  cooViewer.app copies (including build output left under
  `build/Deployment/`) during a single dev session has previously left
  LaunchServices/QuickLook in an inconsistent state that only a full
  OS restart resolved — see `docs/KNOWN_ISSUES.md` #15.

## On-Device Verification Procedure

Use this procedure whenever a build needs to be exercised as a real user
would — main app launch, or QuickLook/Thumbnail extension behaviour. Follow
it exactly and in one pass; see `docs/KNOWN_ISSUES.md` #15 for why repeated
install/register cycles are risky.

### Main app only (no QuickLook/Thumbnail)

1. `open build/cooViewer.app`
2. Exercise the app.
3. Quit it (`Cmd+Q` or `kill`).

Do not touch `/Applications` (the Homebrew-managed install) or `~/Applications`
for this case. No LaunchServices registration occurs.

### QuickLook / Thumbnail extensions

Perform steps 1-6 in a single session, without repeating installs.

1. Copy `build/cooViewer.app` to `~/Applications/` (never `/Applications`).
2. `lsregister -f ~/Applications/cooViewer.app`
3. `pluginkit -a` to register the Preview and Thumbnail extensions
   explicitly.
3a. Confirm which bundle's extension Finder actually resolved — LaunchServices
    deduplicates by bundle ID, so if `/Applications` (the Homebrew build)
    is also registered, it may take priority over the `~/Applications` test
    build even after `lsregister -f`. Check with `pluginkit -m | grep
    coo.cooViewer` (or equivalent) before relying on the result. If the
    Homebrew build is being resolved instead, this step is not exercising
    the new binary — report it rather than treating the check as passed.
4. Verify via Finder directly — Icon/List view for thumbnails, Space bar for
   Quick Look preview. Prefer this over `qlmanage`; on this machine
   `qlmanage -t`/`-p` have hung even on non-encrypted files in past
   sessions. If `qlmanage` is used, one attempt only; on a hang, force-quit
   and switch to Finder rather than retrying.
5. Complete all checks needed before cleanup — do not do a partial check,
   clean up, then come back for more in the same session.
6. Clean up: `pluginkit -r` to unregister the extensions, then delete
   `~/Applications/cooViewer.app`.

### If something goes wrong

If Finder's thumbnail/preview behaviour becomes unresponsive or wrong
during or after this procedure, stop — do not attempt further
install/register cycles to fix it. Report it. A recurrence of #15 requires
a reboot, not more registration attempts.

## Repository Layout
- Repository root contains only dotfiles, top-level directories, `*.md`,
  `*.txt`, and the Xcode project bundle. Source, resources, and scripts
  live in subdirectories.
- Do not add new files to the repository root without explicit
  instruction.
- `build/` contains only the final `cooViewer.app`. Xcode intermediates
  (`DerivedData`, `.build`, indexes, test products) are kept outside the
  repository.
- Remove stale contents from `build/` before producing a new product, and
  verify afterwards that `build/` contains the app and nothing else.

## Dead Code
- Dead code removal is a task, not a side effect. Do it only when the
  active `TASK.md` requests it.
- Removal candidates must be verified before deletion:
  - not referenced from Objective-C/Swift sources, XIB/Storyboard
    outlets and actions, `Info.plist`, or build settings
  - not reachable via selectors, KVC/KVO key paths, notification
    names, or `NSClassFromString` / `performSelector`
  - not part of a public plug-in or QuickLook entry point
- Vendored sources under `vendor/` are out of scope.
- When a symbol looks dead but cannot be proven unreachable, record it
  in `docs/KNOWN_ISSUES.md` instead of deleting it.

## Plan Mode
- Use plan mode for multi-file changes or unfamiliar code paths.
- Skip it for single-line/obvious fixes.

## Compact Instructions
When compacting, preserve working state for continuation, not chat history.

Always keep:
- Current goal and acceptance criteria
- Exact files changed, created, deleted, or inspected — and why
- Important functions, classes, routes, settings, commands, config keys
- Architectural / business rule decisions
- Rejected approaches and why they were rejected
- Errors, failed tests, commands run, and fixes attempted
- Pending tasks and the exact next step

Summarize:
- Completed exploration
- Older discussion
- Repeated command output

Drop:
- Verbose logs unless they contain unresolved errors
- Duplicate explanations
- Abandoned ideas no longer relevant

After compaction, re-read TASK.md (or the active task file in docs/tasks/) before continuing.