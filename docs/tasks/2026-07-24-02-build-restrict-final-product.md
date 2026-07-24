# TASK: Restrict build/ to the final product (stage 2b)

## Scope

Ensure `build/` contains only the final `cooViewer.app`, and that Xcode
intermediates are written outside the repository.

## Steps

1. Inspect the current contents of `build/` and report what is present
   (e.g. `build/Deployment/`, `.build`, intermediates, extension products).
2. Determine how build output location is currently configured
   (`SYMROOT`, `OBJROOT`, `CONFIGURATION_BUILD_DIR`, `DerivedData`
   settings in `cooViewer.xcodeproj`, and any wrapper scripts).
3. Configure the build so that:
   - intermediate output (`OBJROOT`, index, test products, DerivedData)
     is written outside the repository
   - the final `cooViewer.app` is placed directly under `build/`
   Prefer passing explicit paths to `xcodebuild` in documented commands
   over committing absolute paths into the project file. If a project-level
   setting is unavoidable, use a relative path.
4. Remove stale contents from `build/` and confirm `.gitignore` covers
   `build/` appropriately.
5. Record the resulting build command in `CLAUDE.md` under
   `## Project-specific (cooViewer)`, replacing the existing build line if
   it no longer matches.

## Verification

- Run the documented build command.
- Confirm `build/` contains `cooViewer.app` and nothing else.
- Confirm no intermediates were created inside the repository
  (`git status` shows no unexpected untracked paths).
- Confirm the built app launches, if practical.

## Notes

- Follow `CLAUDE.md` regarding installation and registration of local
  builds. Do not install into `/Applications`.
- If the two extensions produce separate build products, decide whether
  they belong under `build/` or are embedded in the app bundle, and record
  the reasoning in the implementation result.
- This task precedes stage 2a-2. Do not begin 2a-2 in this task even if it
  appears related.
## Implementation Result

**Status:** Completed

### Changes

- No project file (`project.pbxproj`) change. The project keeps its
  existing `SYMROOT = build/` (5 project-level configs) as a fallback;
  build output location is controlled via explicit `xcodebuild` overrides
  per the task's stated preference (no absolute paths committed).
- Documented the canonical build in `CLAUDE.md` under
  `## Project-specific (cooViewer)`, replacing the old
  `xcodebuild -configuration Deployment` line. The command redirects
  `SYMROOT`, `OBJROOT`, and `-derivedDataPath` under
  `${TMPDIR}/cooViewer-build` (outside the repository) and copies only the
  final `cooViewer.app` into `build/`.
- Extension products decision: `cooViewerThumbnail` and `cooViewerPreview`
  build as `.appex` and are embedded in
  `cooViewer.app/Contents/PlugIns/`. The standalone `.appex` products are
  intentionally left in the out-of-repo products dir and NOT placed under
  `build/`, so `build/` holds only `cooViewer.app`.
- `.gitignore` already covers `build/` (line 15); no change required.

### Verification

- Build: `xcodebuild ... -scheme cooViewer_deploy -configuration Deployment`
  with out-of-repo `SYMROOT`/`OBJROOT`/`-derivedDataPath` → `** BUILD SUCCEEDED **`.
- Automated verification:
  - `build/` contains only `cooViewer.app` (no `.appex`, no intermediates).
  - `lipo -info` on the main binary: universal `x86_64 arm64`.
  - Embedded `Contents/PlugIns/`: `cooViewerPreview.appex`,
    `cooViewerThumbnail.appex`; `Contents/Frameworks/`: the 3 vendored dylibs.
  - No intermediates written into the repository; `git status` shows no
    unexpected untracked paths (only the archived task / build/ is gitignored).
- Manual verification: reviewed CLAUDE.md build block wording.
- Not performed: launching the app. The Deployment build is unsigned
  (`CODE_SIGN_IDENTITY = ""`, pre-existing) and CLAUDE.md #15 cautions
  against repeatedly registering local copies with LaunchServices/QuickLook;
  build success + bundle structure used as verification instead.

### Remaining Issues

- None for this task.

### Follow-up Suggestions

- Consider removing the baked-in `SYMROOT = build/` from the project so
  that plain `xcodebuild`/Xcode GUI builds also default to an out-of-repo
  DerivedData location. Deferred to avoid project-file churn in this task.
- Code signing of the Deployment build is out of scope here.
- stage 2a-2: relocate/handle root `Info.plist`, `cooViewer_Prefix.pch`,
  `MainMenu~.nib` (explicitly deferred by this task).
