# TASK: Verify the new device_check.sh subcommands on the Mac

## Background

The owner chose option (a) of the dotfiles TF's proposal to remove the
remaining permission dialogs from on-device checks. cooViewer HQ added to
`tools/device_check.sh` (07c2aac): `prefs-set <key> <value>`,
`prefs-delete <key>`, `ql-register`, `ql-unregister`, and updated
`CLAUDE.md` (Project-specific, QuickLook procedure), the `device-check`
skill and `docs/DECISIONS.md`. The script was written in a Linux cloud
container and only syntax-checked and run with stubs there. The global
dotfiles change (37f125a: `pluginkit -m`, `ps`, `top`, `sysctl`, `sample`
excluded) takes effect after `chezmoi apply`; ask the owner whether it has
been applied before relying on it.

## Goal

Each new subcommand works on the Mac, alone in its call, without a sandbox
bypass dialog, and the QuickLook / Thumbnail extensions of the current
main are checked once as a side effect.

## Scope

### In scope

- Run each new subcommand once on the Mac, following the `device-check`
  skill and `CLAUDE.md`, and fix any defect in `tools/device_check.sh`,
  the skill or `docs/DECISIONS.md` that the run reveals (small fixes, one
  commit).
- One QuickLook / Thumbnail pass with the current main build: thumbnails
  and Space-bar preview of a CBZ, a non-solid RAR5 and a solid RAR5 from
  the generated fixtures (the B3 and P2 changes touched the archive layer
  the extensions use).

### Out of scope

- Any change to `CLAUDE.md` or `.claude/settings.json` (if one is needed,
  put the exact text in the report for HQ).
- App code, version numbers, release.

## Verification

- Build with `build-app` (main as pulled).
- `tools/device_check.sh prefs-backup`, then `prefs-set` with a harmless
  key of an existing type (for example `ReadMode -int <its current value>`
  or a key used by a past test), `defaults read jp.coo.cooViewer <key>`,
  `prefs-delete` of a key that the test added, `prefs-restore` (must say
  "restored and verified"). Also confirm the refusals: `prefs-set` without
  a backup, an invalid key.
- `ql-register` once: the listed extension paths are under
  `~/Applications`; if `/Applications` wins, report it rather than passing
  the check. Finder checks as above, then `ql-unregister` once. Second
  `ql-register` in the same session: do not do it (one pass, KNOWN_ISSUES
  #15). If Finder misbehaves, stop and report.
- `unregister` at the end.
- Permission log: list this task's lines from
  `~/Library/Logs/claude-permission-requests.log`; the new subcommands must
  show no `"sandbox_bypass":true`.

## Progress

- Scope added by cooViewer HQ (owner approved 2026-10-06, e51c1af merged):
  `capture` and `capture x,y,w,h` once each; `tools/update_tap.sh` usage
  errors only; the new CLAUDE.md rules for excluded commands.
- Last completed step: all checks done; script fix and archive committed.
- Current partial state: none.
- Exact next step: owner approves the push.

## Implementation Result

**Status:** Completed with follow-up issues

### Changes

- `tools/device_check.sh`: `unregister` now covers every intermediate
  product under `$BUILD_TMP` (`*/Deployment/cooViewer.app`, so a repro build
  in `repro-sym/` is included) and also checks pluginkit's own list of the
  extensions before saying nothing is left; `ql-register` ends with
  `pluginkit -mADv` per extension, so duplicate registrations of the same
  version are visible. Found by this task's QuickLook pass: an intermediate
  product in `repro-sym/` (from the 2026-10-05 repro build) kept both
  extensions registered after `unregister`.
- No change to `CLAUDE.md`, `.claude/settings.json`, the skill or
  `docs/DECISIONS.md`.

### Verification

- Build: `build-app` on main as pulled (07c2aac), `build/` holds only
  `cooViewer.app`; engine tests 504 + 169 pass.
- Automated verification: `bash -n tools/device_check.sh`.
- Manual verification (each `tools/device_check.sh` call alone, no bypass):
  - `prefs-set` without a backup refused ("no preferences backup");
    `prefs-backup` (608 keys); `prefs-set ReadMode -int 0` (its current
    value) and read back; `prefs-set CooViewerDeviceCheckTest -int 1`, read
    back, `prefs-delete` it, gone; invalid keys (`'bad key'`, `../x`, `-g`)
    refused for set and delete, nothing written; `prefs-set` without a value
    refused; `prefs-restore` "restored and verified" (with the warning that
    another copy was running — the owner's Homebrew app was open then).
  - `capture`: a 3840×2160 PNG; `capture 0,0,400,300`: an 800×600 PNG; no
    dialog. Later captures during the QuickLook pass showed window content,
    so Screen Recording is granted.
  - `tools/update_tap.sh` with no argument and with `v1.6.x`: usage error,
    exit 1; not run for real.
  - QuickLook pass (one `ql-register`, Finder, `ql-unregister`): CBZ,
    non-solid RAR5 and solid RAR5 fixtures with distinct covers. Thumbnails
    showed the right covers, and the running Thumbnail extension (by `ps`)
    was `build/cooViewer.app`'s, byte-identical to the `~/Applications` copy,
    so the new binary was exercised. Quick Look previews showed the right
    covers, but the running Preview extension was the Homebrew
    `/Applications` copy, so the new Preview binary was not exercised.
    `ql-register`'s listing named `/Applications` for both; `pluginkit
    -mADv` showed four registrations of 1.6.6 for each (`/Applications`,
    `~/Applications`, `build/`, `$BUILD_TMP/repro-sym/`). Finder stayed
    responsive.
  - `ql-unregister`, then `unregister` (after the fix: unregistered
    `repro-sym`), leaves only the `/Applications` registration of each
    extension (`pluginkit -mADv`).
- Not performed: the Preview extension of the new build (resolution picked
  the Homebrew copy); a second `ql-register` (one pass only).
- Permission log (`~/Library/Logs/claude-permission-requests.log`, this
  session, 2026-10-06): no `tools/device_check.sh` line at all, so none with
  `"sandbox_bypass":true`; the only lines are the two `git pull --ff-only`
  runs outside the sandbox (they write `.claude/` files). Auto Mode refused
  `tools/device_check.sh unregister` and `git status --short` for a subagent
  once, before CLAUDE.md listed the subcommands as runnable without asking;
  not refused afterwards.

### Remaining Issues

- With several registrations of the same extension version, which copy
  Finder uses is not fixed (Thumbnail used `build/`, Preview used
  `/Applications`), so `ql-register` alone cannot guarantee the new binary
  is exercised while the Homebrew copy is registered. Options for the owner:
  temporarily unregister the Homebrew copy's extensions for the pass, or
  give the test copy a higher bundle version.

### Follow-up Suggestions

- `CLAUDE.md` QuickLook step 4 could mention the `pluginkit -mADv` listing
  that `ql-register` now prints (text for HQ in the report).
- `xcodebuild` keeps registering intermediate products; `build-app` already
  runs `unregister`, which now covers every SYMROOT under `$BUILD_TMP`.
