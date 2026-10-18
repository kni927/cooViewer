---
name: device-check
description: Run an on-device check of build/cooViewer.app (main app only) safely, before and after: owner stand-by, preferences backup and verified restore, launch by path, frontmost checks, quit of the build copy only, and LaunchServices clean-up. Use for any check that launches the local build, including from a subagent.
---

# On-device check of the main app

`CLAUDE.md` ("On-Device Verification Procedure", "Main app only") is the
rule; this is the procedure. QuickLook/Thumbnail checks use the
`ql-check` skill; steps 2, 7 and 8 here still apply to them.

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
   backup; restore that one first. To set up a test preference, use
   `tools/device_check.sh prefs-set <key> <value as defaults write takes it>`
   (for example `prefs-set ReadMode -int 1`) and
   `tools/device_check.sh prefs-delete <key>`, never `defaults write`
   directly: the script fixes the domain to `jp.coo.cooViewer` and needs
   the backup, so `prefs-restore` undoes it. Reading needs no script:
   `defaults read jp.coo.cooViewer <key>` works in the sandbox.
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
   - Screenshots: `tools/device_check.sh capture` (or `capture x,y,w,h`
     for a region) writes a new PNG outside the repository and prints its
     path; use it instead of calling `screencapture` directly.
   - Light and dark mode: `tools/device_check.sh appearance dark` (or `light`),
     and `tools/device_check.sh appearance restore` before quitting, so the
     owner's setting comes back. Never switch it with `osascript` directly.
   - "user interrupt" without any owner input means the parent session's
     turn is not running (found 2026-10-12 in the Claude desktop app
     code). Computer use treats an idle parent as aborted, so a background
     subagent (`run_in_background`) fails at once in `computer_batch`,
     `app_batch`, `teach_batch`, full-screen `key`/`type`/`wait`/
     `hold_key`, `app_menu` presses, and any input sent within 750 ms of
     the previous one. Run screen-operating subagents in the foreground
     (`run_in_background: false`). In the background, use only single
     `app_*` calls (`app_screenshot`, `app_click`, `app_key`, `app_zoom`),
     one at a time and about 1 s apart, and click the menu bar with
     `app_click` instead of using `app_menu`.
   - Approval dialogs (`request_access`, `request_full_control`) appear
     behind a frontmost build, where the owner cannot see them without
     switching apps; that approval can only be given at the Mac itself, not
     from a phone or Remote Control. Run `open -a Claude` alone, right
     before each request, then bring the build back to the front and
     confirm it before the next key or click (owner decision 2026-10-15).
     A subagent resumed with `SendMessage` runs in the background, so hand
     screen work to a new foreground `Agent` call or do it in the main
     session instead.
   - `app_menu` validates menu items while the app is in the background,
     so it can report an enabled item as disabled; use its key equivalent
     after bringing the build to the front with `open <build path>`.
   - The tool refuses to type into a save panel's accessory field or to
     type a path (⌘⇧G, `/`, `~`) there. A save panel opens in the book's
     folder, so copy test inputs into the output folder first, and leave
     accessory-field input to the owner.
   - When the app looks stuck or slow, `tools/device_check.sh diag` shows
     its CPU, memory and state, and `tools/device_check.sh diag 3` also
     samples it for 3 s and prints the main thread's call graph. Use these
     instead of `ps`, `top` or `sample`, which the sandbox refuses.

## After (always, even when a step failed)

7. `tools/device_check.sh quit`: sends the quit Apple event to the build's
   pid only (this is also the AppleEvent-quit test). If it reports the
   build still running, a sheet or modal holds it or its main thread is
   busy: run `diag 3` to see which, report it, then dismiss the sheet,
   wait, or `kill <pid>`.
8. `tools/device_check.sh prefs-restore`: waits for the last writes,
   restores and verifies against the backup. A difference is reported, not
   ignored.
9. `tools/device_check.sh unregister`: unregisters `build/cooViewer.app`
   and the intermediate product and confirms none is left registered.
10. Record in the task's Verification what passed, what could not be
    driven, and that preferences were restored and verified.

## QuickLook / Thumbnail extensions

Use the `ql-check` skill: register once, check everything in Finder,
unregister once.
