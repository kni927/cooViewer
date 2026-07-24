# TASK: Clean up repository root (stage 2a-2)

## Scope

Decide and apply the disposition of `Info.plist`,
`cooViewer_Prefix.pch`, and `MainMenu~.nib` at the repository root.

Investigate first, decide based on observable state, and record the
reasoning for each decision in the implementation result.

Additionally, remove the project-level `SYMROOT = build/` fallback so that
plain `xcodebuild` and Xcode GUI builds also write intermediates outside
the repository, consistent with the Repository Layout rule in `CLAUDE.md`.
Verify that the documented build command in `CLAUDE.md` still produces
`cooViewer.app` under `build/` afterwards.

## Steps

### 1. cooViewer_Prefix.pch

- Inspect its contents and `GCC_PREFIX_HEADER` /
  `GCC_PRECOMPILE_PREFIX_HEADER` in all targets.
- If the header only provides imports that sources already include
  individually, remove the prefix header: clear the build settings and
  delete the file. Add any imports that turn out to be required to the
  individual sources.
- If it is genuinely needed, move it to `Sources/` and update the build
  settings.
- Verify by building. A build failure after removal means sources depend
  on it; in that case prefer moving over removing.

### 2. Info.plist

- Report where the `PreviewExtension` and `ThumbnailExtension`
  Info.plist files live.
- If extension plists live inside their own target directories, move the
  main target's `Info.plist` to `Resources/` and update `INFOPLIST_FILE`.
- If the existing arrangement is already consistent, leave it in place and
  record why.
- Check for scripts or tooling referencing the plist path
  (`plutil`, `agvtool`, version bump scripts) and update them.

### 3. MainMenu~.nib

- Determine whether it is tracked and whether the Xcode project or any
  source references it.
- If it is an Interface Builder backup with no references, delete it.
- If it is referenced, move it to `Resources/` and update the project.

### 4. SYMROOT fallback

- Remove or redirect `SYMROOT = build/` in `cooViewer.xcodeproj`.
- Confirm that a build without explicit overrides does not write into the
  repository.
- Confirm the documented command in `CLAUDE.md` still places
  `cooViewer.app` under `build/`; update the command if the removal changes
  where the product lands.

## Verification

- Build succeeds after all changes.
- The built app launches and its main menu is present.
- Both extensions build and are embedded correctly.
- `ls -a` at the repository root matches the Repository Layout rule in
  `CLAUDE.md`.

## Notes

- Changes to `cooViewer.xcodeproj/project.pbxproj` are expected. Keep them
  minimal and reviewable.
- Follow `CLAUDE.md` regarding installation and registration of local
  builds.
- If any item cannot be safely resolved, leave it in place and record it as
  a follow-up suggestion rather than forcing a change.
## Implementation Result

**Status:** Completed

### Changes

- **cooViewer_Prefix.pch — removed.** The header only provided
  `#import <Cocoa/Cocoa.h>` (under `__OBJC__`). A test build with the
  prefix header disabled for all targets
  (`GCC_PREFIX_HEADER= GCC_PRECOMPILE_PREFIX_HEADER=NO`) succeeded, proving
  sources already include their own imports. Cleared `GCC_PREFIX_HEADER`
  (16 refs → `""`) and set `GCC_PRECOMPILE_PREFIX_HEADER = NO` (14 refs) in
  `project.pbxproj`, and deleted the file. No source edits were required.
- **Info.plist — moved to `Resources/Info.plist`.** The extension plists
  live in their own target directories
  (`PreviewExtension/Info.plist`, `ThumbnailExtension/Info.plist`), so the
  main target's plist was relocated and `INFOPLIST_FILE` updated in the 5
  main-target configs (`Info.plist` → `Resources/Info.plist`). No scripts,
  `agvtool`, `plutil`, or shell build phases reference the plist path.
- **MainMenu~.nib — deleted.** It was a tracked Interface Builder backup
  (legacy `classes.nib`/`info.nib`/`keyedobjects.nib`, plus stale `.svn`
  metadata) with no reference anywhere in `project.pbxproj`. The live menu
  is `Resources/Base.lproj/MainMenu.xib`, compiled into the app as
  `Contents/Resources/Base.lproj/MainMenu.nib`.
- **SYMROOT — removed.** Deleted the 5 project-level `SYMROOT = build/;`
  lines. CLAUDE.md build note updated accordingly.

### Root disposition summary

Repository root now contains only dotfiles, top-level directories, `*.md`,
`*.txt`, and `cooViewer.xcodeproj`, matching the Repository Layout rule.

### Verification

- Build: `xcodebuild ... -scheme cooViewer_deploy -configuration Deployment`
  with out-of-repo SYMROOT/OBJROOT/derivedDataPath → `** BUILD SUCCEEDED **`
  after all edits.
- Automated verification:
  - `build/` contains only `cooViewer.app`.
  - App bundle: `Contents/Info.plist` present with `NSMainNibFile = MainMenu`,
    `NSPrincipalClass = NSApplication`, `CFBundleExecutable = cooViewer`;
    compiled menu at `Contents/Resources/Base.lproj/MainMenu.nib`; both
    extensions embedded in `Contents/PlugIns/`; 3 vendored dylibs in
    `Contents/Frameworks/`; universal `x86_64 arm64`.
  - SYMROOT removal: a build with no SYMROOT override and no legacy per-user
    build-location writes products to the DerivedData path (outside the
    repository), verified by temporarily removing the local
    `xcuserdata/…/WorkspaceSettings.xcsettings`.
- Manual verification: reviewed pbxproj diff and CLAUDE.md wording.
- Not performed: launching the app. Structural checks above substitute for
  a live launch, to respect the CLAUDE.md #15 caution against repeated
  LaunchServices/QuickLook registration of local copies (several app copies
  were already produced this session). Menu presence is evidenced by the
  embedded compiled `MainMenu.nib` and the `NSMainNibFile` key.

### Remaining Issues

- On this machine, a per-user legacy build location survives in
  `cooViewer.xcodeproj/project.xcworkspace/xcuserdata/…/WorkspaceSettings.xcsettings`
  (`BuildLocationStyle = UseTargetSettings`). It is untracked (xcuserdata),
  so it is not part of the repo, but while set it forces plain `xcodebuild`
  / Xcode GUI builds on this machine to the built-in legacy default
  `SRCROOT/build`. It was restored to its original state (not modified by
  this task). Fresh clones without this file default to DerivedData and are
  unaffected.

### Follow-up Suggestions

- Optionally switch Xcode ▸ Settings ▸ Locations to "Derived Data" on this
  machine (or delete the local WorkspaceSettings.xcsettings) so plain builds
  here also avoid the repository. Documented in CLAUDE.md.
- Code signing of the Deployment build remains out of scope.
