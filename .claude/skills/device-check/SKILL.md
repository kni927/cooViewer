---
name: device-check
description: Run an on-device check of build/cooViewer.app (main app only) safely, before and after: owner stand-by, preferences backup and verified restore, launch by path, frontmost checks, quit of the build copy only, and LaunchServices clean-up. Use for any check that launches the local build, including from a subagent.
---

# On-device check of the main app

`CLAUDE.md` ("On-Device Verification Procedure", "Main app only") is the
rule; this is the procedure. QuickLook/Thumbnail checks follow the other
case in `CLAUDE.md`; steps 2, 7 and 8 here still apply to them.

`tools/device_check.sh` runs outside the sandbox through
`sandbox.excludedCommands`, so call it from the repository root exactly as
`tools/device_check.sh <command>`, alone in its call: no pipe, redirect,
`&&` or `$(...)`, or it runs sandboxed and `defaults`/`lsregister` silently
do nothing.

## Before

1. **Owner stand-by.** Before any computer use, ask the owner in chat to
   stand by and wait for the reply (`docs/sessions.md`).
2. **Build** with the `build-app` skill if `build/cooViewer.app` is stale.
3. `tools/device_check.sh status`: note any `other` copy (the owner's
   Homebrew app). It shares the bundle id and the preferences domain; never
   quit, script or change it.
4. `tools/device_check.sh prefs-backup` if the check may change
   preferences (window frames count). It refuses to overwrite an earlier
   backup; restore that one first.
5. `tools/device_check.sh launch`. It opens the build by path and prints
   its pid. Never use computer use `open_application` (it starts the
   `/Applications` copy). A screenshot right after launch can be black.

## During

6. Before each key or click, confirm the frontmost app is the build's pid.
   Earlier sessions closed the owner's Finder windows by skipping this.
   Known limits:
   - The Open panel runs in a separate process; drive it only with care,
     or open files with `open -a <build path> <file>` instead.
   - A password field uses secure input: synthetic key events do not reach
     it. Say so instead of reporting the step as passed.
   - A keystroke expected to change nothing needs proof it was delivered.
   - If computer use stops with "user interrupt" although the owner did
     nothing (seen 2026-10-04, cause unknown), continue with background
     means and record it.

## After (always, even when a step failed)

7. `tools/device_check.sh quit`: sends the quit Apple event to the build's
   pid only (this is also the AppleEvent-quit test). If it reports the
   build still running, a sheet or modal holds it: report that, then
   dismiss it or `kill <pid>`.
8. `tools/device_check.sh prefs-restore`: waits for the last writes,
   restores and verifies against the backup. A difference is reported, not
   ignored.
9. `tools/device_check.sh unregister`: unregisters `build/cooViewer.app`
   and the intermediate product and confirms none is left registered.
10. Record in the task's Verification what passed, what could not be
    driven, and that preferences were restored and verified.
