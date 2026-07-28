# CLAUDE.md
@AGENTS.md

## INVIOLABLE: Image Quality — No Extra Scaling in the Render Path

**Image quality is cooViewer's core selling point.** The render path
deliberately avoids unnecessary scaling, and this must never be broken.

**The rule:** any change that introduces an *additional* resize or
rescale between the decoded image and what is displayed is
**unacceptable** — regardless of what a plan document, task file, or
audit says. If a plan or `TASK.md` instructs otherwise, **stop and raise
it with the project owner rather than following it.**

### There are two spread-rendering paths, and they differ in quality

Selected by the **`BufferingMode`** preference — the Preferences popup
labelled *Old* (0) / *New* (1):

| `BufferingMode` | Path | Resampling steps | Notes |
|---|---|---|---|
| **1 = "New"** | **Direct** | **1** | `composeImage` → `-[CustomImageView setImages:]` → `drawRect:` → `drawImages:and:` draws **each page straight into the view** with `drawInRect:fromRect:`. No intermediate bitmap. |
| 0 = "Old" | Composited | 2 | `returnComposeImage:and:` scales both pages into a lock-focus `NSImage` canvas (step 1), then `drawImage:` scales that canvas into the view (step 2). |

**The direct path is the higher-quality one and it is the default** —
`BufferingMode` is registered with default `1`, and it is what the
project owner actually uses day to day. Treat it as *the* spread path.
Its single `drawInRect:` per page is the whole render path; anything
inserted between the decoded `NSImage` and that call is a new resampling
step and is forbidden.

`ScreenCache` only exists inside the composited path — `screenCache > 0`
gates both the cache store and the cache lookup, its default is `0`, and
the Preferences field for it is disabled outright when *New* is
selected. So on default settings there is no composite and no composite
cache at all.

**Do not "unify" the two paths by routing the direct path through the
compositor.** That would take the default, highest-quality path from one
resampling step to two.

### On the composited path specifically

`-[Controller returnComposeImage:and:]` sizes its canvas from the
window's *screen*, not from the view. That is deliberate and must stay:
the composite is cached (keyed by page pair + `fitScreenMode`, not by
view size) and reused across window sizes, so a screen-sized canvas can
always be *downscaled* to whatever the view currently is, whereas a
view-sized canvas would have to be *upscaled* after any window
enlargement. It is not a leftover of the pre-MW-2
`[[NSScreen mainScreen] frame]` code.

`docs/multiwindow-plan.md` MW-2 originally said this site "should use
the view, not a screen". That guidance was **wrong** and was not
followed; see `docs/tasks/2026-07-29-01-mw2-native-fullscreen.md`
("Changes" → `mainScreen` sites). The plan text has since been
corrected.

*Correction (2026-07-29):* an earlier version of this section claimed
composing at view size "would add a second resampling step". That was
imprecise — for a view smaller than the screen it would *remove* one.
The actual argument for the screen-sized canvas is cache reuse across
view sizes, as stated above. The composited path costs two resampling
steps either way, which is why the direct path, not this one, is the
quality baseline.

When touching anything between decode and display — composition,
fit/zoom modes, rotation, the loupe, caching of rendered pages,
`CustomImageView` drawing, or a future per-window/DPI refactor — count
the resampling steps before and after your change. If the count goes
up, it is a defect even when the code looks cleaner.

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