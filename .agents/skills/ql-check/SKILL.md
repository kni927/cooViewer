---
name: ql-check
description: Check cooViewer's Quick Look preview and Thumbnail extensions on the Mac in one pass - register the build in ~/Applications, confirm which copy Finder resolved, check in Finder, clean up - or check the released /Applications copy. Use for any Quick Look or thumbnail check, of a development build or of a release artifact.
---

# Quick Look / Thumbnail check

`CLAUDE.md` ▸ On-Device Verification Procedure is the rule; this is the
procedure. Repeated install and register cycles have left LaunchServices
and Quick Look broken until a reboot (`docs/KNOWN_ISSUES.md` #15), so do
every step once, in one session.

Run `tools/device_check.sh <command>` from the repository root, alone in
its call (no pipe, redirect, `&&` or `$(...)`).

## Development build

1. **Register once:** `tools/device_check.sh ql-register`. It copies
   `build/cooViewer.app` to `~/Applications/` (never `/Applications`), runs
   `lsregister -f` and `pluginkit -a` for both extensions, and refuses if
   the copy already exists.
2. **Confirm which copy Finder resolves.** LaunchServices deduplicates by
   bundle ID, so the Homebrew copy in `/Applications` may win even after
   `lsregister -f`.
   - `ql-register` ends with `pluginkit -m -v -i <id>` for each extension:
     the path must be under `~/Applications`.
   - It also prints `pluginkit -mADv`: every registered copy. With several
     copies of the same version Finder may use any of them.
   - After looking, check with `ps` which `.appex` actually ran.
   - A check served by `/Applications` is **not verified**; say so. The
     release artifact check covers that copy.
3. **Check in Finder:** Icon or List view for thumbnails, Space bar for the
   preview. Prefer Finder to `qlmanage`, which has hung here even on plain
   files; if you use it, one attempt only, and on a hang force-quit it and
   switch to Finder.
4. **Finish every check before cleaning up.** Do not check part, clean up,
   and come back in the same session.
5. **Clean up once:** `tools/device_check.sh ql-unregister` (`pluginkit -r`,
   `lsregister -u`, then deletes `~/Applications/cooViewer.app`). Do not
   delete any `defaults` keys; only the bundle and the registrations go.

## Release artifact

The bundle under test is the Homebrew install in `/Applications`; there is
nothing to register or clean up.

1. `pluginkit -mADv` for each extension lists exactly one copy, in
   `/Applications`, at the new version. If a development copy is still
   registered, run `tools/device_check.sh unregister` first.
2. Check in Finder as in step 3 above, for a CBZ, a non-solid RAR5 and a
   solid RAR5 book.
3. `ps` shows the Preview and Thumbnail processes that ran are the
   `/Applications` ones. A thumbnail Finder shows without a process may be
   cached; say so rather than counting it.

## If something goes wrong

If Finder's thumbnails or previews become unresponsive or wrong, stop. Do
not register or install again to fix it; report it. A recurrence of #15
needs a reboot.
