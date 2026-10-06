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

### The spread render path (there is exactly one)

A two-page spread reaches the screen like this, and this is the whole
path:

```
decoded NSImage per page
  → -[Controller composeImage] → -[CustomImageView setImages:]
  → -drawRect: → -drawImages:and:
  → [page drawInRect:fromRect:]   ← ONE resampling step, straight into the view
```

There is **no intermediate composite** and **no cache of rendered
pages**. That single `drawInRect:` per page is the entire render path;
anything inserted between the decoded `NSImage` and that call is a new
resampling step and is forbidden.

**Do not reintroduce a compositor.** cooViewer used to have a second,
legacy path (`BufferingMode = 0`, the Preferences popup labelled *Old*)
that scaled both pages into a lock-focus `NSImage` canvas and then
scaled *that* into the view — two resampling steps instead of one. It
was deleted on 2026-07-29 along with `returnComposeImage:and:`,
`screenCacheArray`, the `ScreenCache` preference and the `BufferingMode`
popup; see `docs/DECISIONS.md`, "Legacy 'Old' composited render path
removed". The `BufferingMode` and `ScreenCache` keys may still exist in
old user profiles but nothing reads them.

Spread geometry now comes entirely from the view, via
`-[CustomImageView getDrawImagesInfo:and:]`. There is no compositor in
between to absorb a wrong bounds value, so anything that changes when or
how the view learns its bounds is a rendering concern.

When touching anything between decode and display — composition,
fit/zoom modes, rotation, the loupe, caching of rendered pages,
`CustomImageView` drawing, or a future per-window/DPI refactor — count
the resampling steps before and after your change. If the count goes
up, it is a defect even when the code looks cleaner.

## Releasing

Releases are built, signed, notarized, and published by CI — never locally.

- `.github/workflows/xcode-build-and-release.yml` is triggered by pushing a
  `v*` tag. It builds Deployment, signs bottom-up, notarizes with
  `xcrun notarytool`, staples, and creates the GitHub Release with
  `build/Deployment/cooViewer-<tag>.zip` in the CI workspace attached.
- This is the tested path that shipped v1.4.0 through v1.5.2. Do not
  substitute local notarization.

### Verifying the release artifact

This is a third case, distinct from the two in the On-Device Verification
Procedure. The artifact under test is the notarized build from the tagged
CI run, installed at `/Applications` via the tap — not a local build in
`~/Applications`.

1. `brew uninstall cooviewer`, then install the released version from the
   tap.
2. Confirm it launches and is Gatekeeper-clean without `xattr -cr`.
3. For QuickLook/Thumbnail checks, follow steps 3a-5 of the On-Device
   Verification Procedure, reading `/Applications` as the bundle under
   test. Step 3a matters more here, not less: this install is the one
   that should now win LaunchServices precedence.
4. Cleanup: none. This install is the intended end state.

### Credentials — never ask for these

Notarization uses three App Store Connect API secrets, already registered
in the repository (Settings ▸ Secrets and variables ▸ Actions):

- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_PRIVATE_KEY`

Never ask the owner for these values. Never ask for `.p8` file contents.
Never create, rotate, or register a credential yourself, and never print a
secret value. If a secret appears to be missing or expired, stop and
report — secret *names* are visible in Settings even though values are not.

### Rules

- A locally built and signed app is a **dry run for verification only**,
  never the release artifact. The artifact comes from the tagged CI run.
- **Pushing the tag is the irreversible publication step, and the owner
  does it.** Get explicit owner authorization for both the version number
  and the release notes, prepare everything up to the tag, then stop. Resume
  by watching the CI run once the owner has pushed the tag.
- If notarization fails, stop and report. Never work around Gatekeeper
  (ad-hoc signing, clearing quarantine, disabling checks) — none of these
  substitute for a passing notarization.
- After the release exists, update the Homebrew tap formula (`kni927/tap`,
  `cooviewer`): version, URL, sha256, with `tools/update_tap.sh <version>`
  (run alone; it downloads the release zip, rewrites the cask, shows the
  diff and commits locally, never pushes) — then confirm a fresh install
  resolves to the new version and launches. The tap update, including its
  push to `kni927/homebrew-tap`, is part of the authorized release and needs
  no separate approval.
- `brew uninstall cooviewer` is the only sanctioned reason to touch the
  Homebrew-managed `/Applications` install, and only to make room for
  verifying the real release artifact. This does not relax the rule
  against installing local/debug builds there (see Project-specific and
  the On-Device Verification Procedure). The tap update restores Homebrew
  management.

Before tagging, pushing, or creating a release — including when resuming
interrupted work — apply the non-idempotent operation rule in
`docs/task-workflow.md`: confirm the intended result does not already
exist (`git tag -l`, `gh release view`, uploaded assets).

Full procedural precedent: `docs/tasks/2026-07-26-02-release-v1.5.2.md`.

## Project-specific (cooViewer)
- Vendored libs (one-time): `vendor/build-libs.sh` (needs cmake).
  libarchive/uchardet/libzip are built as universal dylibs, bundled in
  Frameworks/.
- Build so intermediates stay outside the repository and only the final
  app lands in `build/`:
  ```bash
  BUILD_TMP="$(getconf DARWIN_USER_TEMP_DIR)cooViewer-build"
  xcodebuild -project cooViewer.xcodeproj -scheme cooViewer_deploy \
    -configuration Deployment \
    SYMROOT="$BUILD_TMP/sym" OBJROOT="$BUILD_TMP/obj" \
    -derivedDataPath "$BUILD_TMP/dd" build
  rm -rf build && mkdir -p build
  cp -R "$BUILD_TMP/sym/Deployment/cooViewer.app" build/
  ```
  The overrides redirect all Xcode output (products, intermediates,
  index, DerivedData) under `$BUILD_TMP`, outside the repository; only
  the final `cooViewer.app` is copied into `build/`.
  In a Claude Code session, do not derive `BUILD_TMP` from `$TMPDIR`:
  `xcodebuild` is a sandbox-excluded command and sees the per-user temp
  directory (`/var/folders/…/T/`), while sandboxed commands such as `cp`
  see the sandbox's own `$TMPDIR`, so the two halves of the build point
  at different directories. `getconf DARWIN_USER_TEMP_DIR` returns the
  same path inside and outside the sandbox. Run it in a call of its own
  and pass the literal path to `xcodebuild`, `cp` and `rm`; a command
  substitution in the same call as `xcodebuild` takes that call out of
  the sandbox exclusions. Copying into `build/` works inside the
  sandbox; removing `$BUILD_TMP` does not (the sandbox cannot write
  there). Registering or unregistering with `pluginkit` or `lsregister`
  does not work inside the sandbox either (use `tools/device_check.sh`
  below); listing with `pluginkit -m` (globally excluded) and
  `lsregister -dump` does. The QuickLook
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
- `cooViewer.xcodeproj/project.pbxproj` is this repository's own build
  configuration. Editing it — build settings, version numbers, targets,
  file references — when `TASK.md` calls for it is ordinary project work,
  not a change to shared infrastructure. The same applies to running the
  build command above, including build-setting overrides on the command
  line. This does not relax the Releasing rules: the owner pushes the tag.
- Do not edit vendored library sources
- Do not install local/debug builds directly into `/Applications` for
  manual testing. Use a separate test location (e.g. `~/Applications`)
  and register it with `lsregister -f` / `pluginkit -a` instead.
  Repeatedly building, installing, and re-registering multiple
  cooViewer.app copies (including build output left under
  `build/Deployment/`) during a single dev session has previously left
  LaunchServices/QuickLook in an inconsistent state that only a full
  OS restart resolved — see `docs/KNOWN_ISSUES.md` #15.
- When running an isolated test copy of cooViewer alongside your own
  real, already-running copy (e.g. for `System Events`/UI-scripting-
  driven tests), a plain process-name match (e.g. targeting
  "cooViewer") can resolve to your real running app instead of the
  test copy — they share the same executable name. Rename the test
  copy's executable/bundle to something distinct (e.g.
  `cooViewer-test`) before scripting against it by name, and verify
  which process you're actually driving before the first action that
  touches app state. See
  `docs/tasks/2026-07-31-06-finder-open-reuses-window.md` for a case
  where this was caught before any real window/book was affected.
- On-device checks use `tools/device_check.sh` (listed in
  `.claude/settings.json` under `sandbox.excludedCommands`), run from the
  repository root as `tools/device_check.sh <command>`, alone in its call
  (no pipe, redirect, `&&` or `$(...)`, which would keep it sandboxed):
  `status`, `prefs-backup` (saves the `jp.coo.cooViewer` preferences outside
  the repository), `launch` (opens `build/cooViewer.app` by path), `quit`
  (sends the quit Apple event to the build's pid only, never to the
  Homebrew copy), `prefs-restore` (restores and verifies against the
  backup), `unregister` (`lsregister -u` for the build and the
  intermediate product), `diag [secs]` (CPU, memory and state of the
  build, optionally a `sample`), `prefs-set <key> <value>` and
  `prefs-delete <key>` (change one `jp.coo.cooViewer` key for a test; the
  domain is fixed in the script and a backup must exist), and
  `ql-register` / `ql-unregister` (the QuickLook procedure below), and
  `capture [x,y,w,h]` (a screenshot into a new file outside the
  repository, for checks and the spread comparison below). Agents
  and their subagents may run these without asking each time. Use them
  instead of calling `defaults write`, `lsregister` or `pluginkit -a/-r`
  directly. The `device-check` and `build-app` skills give the
  order of steps.
- Commands that the global or project settings already run outside the
  sandbox (`tools/device_check.sh`, `tools/update_tap.sh`, `xcodebuild`,
  `pluginkit -m`, `codesign -dvv`, `ps`, `top`, `pgrep`, `sysctl`, `sample`, `log show`)
  are run alone in their call, as written: no pipe, `;`, `&&`,
  redirect or `$(...)`, and never with `dangerouslyDisableSandbox`. A
  pipe or chain keeps the whole call sandboxed and then fails; read the
  output instead of filtering it. Write `log show`, not `/usr/bin/log
  show`.
- Do not remove `$BUILD_TMP` (or anything under `/var/folders/`) after a
  build: it is outside the repository, the next build reuses it, and
  removing it needs a sandbox bypass.
- Do not launch a local build with computer use's `open_application`:
  it resolves the app by bundle ID and starts the Homebrew-managed
  `/Applications` copy instead. Launch the build by path
  (`open build/cooViewer.app`) and check which copy is running before
  acting on it. See `docs/tasks/2026-10-03-05-stability-fixes-and-rar-survey.md`.

## On-Device Verification Procedure

Use this procedure whenever a build needs to be exercised as a real user
would — main app launch, or QuickLook/Thumbnail extension behaviour. Follow
it exactly and in one pass; see `docs/KNOWN_ISSUES.md` #15 for why repeated
install/register cycles are risky.

### Main app only (no QuickLook/Thumbnail)

1. `tools/device_check.sh prefs-backup` if the check may change
   preferences, then `tools/device_check.sh launch` (or
   `open build/cooViewer.app`).
2. Exercise the app.
3. Quit it: `tools/device_check.sh quit`, `Cmd+Q`, or `kill`.
4. `tools/device_check.sh prefs-restore` if step 1 saved a backup.
5. `tools/device_check.sh unregister`, which runs `lsregister -u` for
   `build/cooViewer.app` and for the intermediate product under
   `$BUILD_TMP` if it still exists. Launching registers
   `build/cooViewer.app` with LaunchServices under the production bundle
   IDs, and `xcodebuild` registers the intermediate products too
   (`docs/KNOWN_ISSUES.md` #15).

Do not touch `/Applications` (the Homebrew-managed install) or `~/Applications`
for this case.

### QuickLook / Thumbnail extensions

Perform steps 1-6 in a single session, without repeating installs.

1-3. `tools/device_check.sh ql-register`: copies `build/cooViewer.app` to
   `~/Applications/` (never `/Applications`), runs
   `lsregister -f ~/Applications/cooViewer.app`, and `pluginkit -a` for the
   Preview and Thumbnail extensions. It refuses if the copy already exists.
4. Confirm which bundle's extension Finder actually resolved — LaunchServices
    deduplicates by bundle ID, so if `/Applications` (the Homebrew build)
    is also registered, it may take priority over the `~/Applications` test
    build even after `lsregister -f`. `ql-register` ends by listing each
    extension with `pluginkit -m -v -i <id>`; read the path there before
    relying on the result. If the
    Homebrew build is being resolved instead, this step is not exercising
    the new binary — report it rather than treating the check as passed.
    It also prints `pluginkit -mADv` for each extension: every registered
    copy, duplicates included. With several copies of the same version,
    Finder may use any of them; check which one actually ran (for example
    with `ps`), and report a check served by the `/Applications` copy as
    not verified — the release artifact verification covers it.
5. Verify via Finder directly — Icon/List view for thumbnails, Space bar for
   Quick Look preview. Prefer this over `qlmanage`; on this machine
   `qlmanage -t`/`-p` have hung even on non-encrypted files in past
   sessions. If `qlmanage` is used, one attempt only; on a hang, force-quit
   and switch to Finder rather than retrying.
6. Complete all checks needed before cleanup — do not do a partial check,
   clean up, then come back for more in the same session.
7. Clean up: `tools/device_check.sh ql-unregister` (`pluginkit -r` for the
   extensions, `lsregister -u`, then deletes `~/Applications/cooViewer.app`).
   Do **not** delete any `defaults` keys or
   `NSUserDefaults` entries — only remove the app bundle and QuickLook
   registrations.

### If something goes wrong

If Finder's thumbnail/preview behaviour becomes unresponsive or wrong
during or after this procedure, stop — do not attempt further
install/register cycles to fix it. Report it. A recurrence of #15 requires
a reboot, not more registration attempts.

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

## Sandbox
- The global Claude Code instructions define how to run commands so sandbox
  exclusions apply. Project-specific exclusions live in `.claude/settings.json`
  under `sandbox.excludedCommands`; list them under
  "Project-specific (cooViewer)".
- An operation that tasks need outside the sandbox again and again (saving and
  restoring preferences, unregistering an app, and the like) goes into a project
  script listed in `sandbox.excludedCommands`, with its step under
  "Project-specific (cooViewer)". The auto mode classifier then finds it in
  `CLAUDE.md`, also when a subagent runs it; a step written only in `TASK.md` or
  a task record is refused as a bypass.
- Commands that must always be confirmed, even in auto mode (for example a release
  or upload script), go under `permissions.ask` in `.claude/settings.json`. Do not
  add `allow` rules there; they bypass the auto mode classifier.
- The auto mode classifier reads the chat and `CLAUDE.md`, not `TASK.md`, so an
  approval written only in `TASK.md` does not count. It has refused edits to
  `CLAUDE.md` and `AGENTS.md` ("Self-Modification") that had no approval in chat,
  and creating a release tag ("Production Deploy"); see Workflow and Git Workflow
  in `AGENTS.md`.

## Plan Mode
- `TASK.md` is the approved plan. Do not enter plan mode because a task touches
  multiple files or unfamiliar code paths.
- Use plan mode only when `TASK.md` leaves an implementation choice to the project
  owner, or when you intend to deviate from `TASK.md`. Present the plan and wait
  for approval.
- The image-quality rule above is separate and always applies: a change that
  would add a resampling step stops work, whatever `TASK.md` says.

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

After compaction, re-read `TASK.md` (and the handover or recovery file in use, if any) before continuing.