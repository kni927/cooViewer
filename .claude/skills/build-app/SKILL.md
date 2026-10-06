---
name: build-app
description: Build cooViewer.app the way CLAUDE.md requires (intermediates outside the repository, only the app in build/), then run the engine tests. Use whenever a task says to build, before any on-device check, and before reporting a part as done.
---

# Build cooViewer

`CLAUDE.md` ("Project-specific (cooViewer)") is the rule; this is the
procedure. Hand it to a subagent when the build output would fill the
context.

1. **Temp path, in a call of its own:**

   ```bash
   getconf DARWIN_USER_TEMP_DIR
   ```

   Append `cooViewer-build` to the printed path; that is `BUILD_TMP`. Write
   it as a literal path in the next steps. Do not use `$TMPDIR` or a
   command substitution: `xcodebuild` runs outside the sandbox and sees a
   different temp directory, and a substitution in the same call takes
   `xcodebuild` out of the sandbox exclusions.
2. **Build**, with the literal path:

   ```bash
   xcodebuild -project cooViewer.xcodeproj -scheme cooViewer_deploy -configuration Deployment SYMROOT=<BUILD_TMP>/sym OBJROOT=<BUILD_TMP>/obj -derivedDataPath <BUILD_TMP>/dd build
   ```

   On failure, report the first error lines, not the whole log.
3. **Place the app**, one call each:

   ```bash
   rm -rf build
   mkdir -p build
   cp -R <BUILD_TMP>/sym/Deployment/cooViewer.app build/
   ```

   Never copy the standalone `.appex` products; the QuickLook extensions are
   already inside `cooViewer.app/Contents/PlugIns/`.
4. **Check `build/`:** `ls -A build` shows `cooViewer.app` and nothing else.
5. **Engine tests:** `tests/engine/run_tests.sh` (and
   `run_encryption_test.sh` / `run_password_test.sh` when archive or
   password code changed). Report the pass counts.
6. **LaunchServices:** `xcodebuild` registers the intermediate products.
   After the task's on-device checks (or at once if there are none), run
   `tools/device_check.sh unregister` (see the `device-check` skill).

Do not remove `<BUILD_TMP>`: it is outside the repository, the next build
reuses it, and removing it needs a sandbox bypass.
