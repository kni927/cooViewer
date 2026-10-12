# Status

The current state of this repository, for the next session and for the owner:
what comes next, what is on hold, and what waits on the owner. Rewrite it
rather than append; keep it under about 40 lines. Rules are in `AGENTS.md`,
decisions in `docs/DECISIONS.md`, and history in `docs/tasks/` and Git.

Updated: 2026-10-12

## Summary

cooViewer: macOS image and comic viewer, a maintained fork of coo-ona's original.
Latest release v1.6.8 (2026-10-12), notarized and in the Homebrew tap: page
position on the page bar / title bar, file-name HUD or status bar, File >
Export... (`docs/tasks/2026-10-12-02-release-v1.6.8.md`).

## Next

- Nothing scheduled. The owner picks from On hold when work resumes.

## On hold

Held until the next binary change (owner, 2026-10-12: no binary changes right
after a release). Small follow-ups from the page bar and export task, details
in `docs/tasks/2026-10-12-01-page-bar-and-export.md`: an unused pages-prompt
string in `Localizable.strings`; Finder/drop routing can replace a window that
is exporting; exported entries get the current mtime; solid RAR prefetch in
page order can restart the cursor (speed only); the bottom HUD offset ignores
`Margin_PageBar`.

Also for the next binary change (owner, 2026-10-12):
- Page bar in the title bar: fill the title bar's background with a light grey
  up to the reading position (right to left for RTL), behind the title and
  position; display only, no click or drag; nothing in full screen. Image
  layout unchanged.
- Page bar size can no longer be changed in Preferences (reported after
  v1.6.8; cause not yet investigated). Fix it then, not as a hotfix.
- Decided: the bar height is the user's setting again, and the in-bar number's
  font size follows it automatically. The page number gets its own
  Preferences section (location: in bar / above bar / title bar / off; font
  for above bar and title bar); Page Bar keeps position, size, colours and
  the title-bar fill.

The first five were put on hold as minor (owner, 2026-10-08); details are in
the files named.

- Thumbnail panel and page-bar bubble still decode on the main thread; can
  stall on large solid RAR books (`docs/KNOWN_ISSUES.md` #46).
- An in-flight page decode cannot be cancelled (#46).
- Solid RAR5 decode-ahead files are left behind after a crash
  (`docs/DECISIONS.md`, per-book disk cache).
- Unused `Resources/empty.png` (`docs/KNOWN_ISSUES.md`, unused resources).
- Archives nested in archives, or in folder books, still load through the
  modal path (`docs/KNOWN_ISSUES.md`, async loading).
- Undecided (owner, moved here 2026-10-10): whether to support OPDS catalogues
  from a self-hosted server; Komga is favoured over Kavita.
- Not implemented: EPUB to PDF to CBZ conversion. Chosen toolchain is LuaLaTeX
  with jlreq for vertical Japanese text, on BasicTeX rather than MacTeX; Typst
  was rejected for lacking vertical writing. BasicTeX is not yet in the Mac
  setup's Brewfile.

## Waiting on owner

- None.

## Notes

Short-lived notes, dated. A note is a hint: check it before relying on it, and
delete it when it is done or out of date.

- 2026-10-06: QuickLook checks of a dev build count only when `ps` shows the
  test copy's extension ran (`CLAUDE.md`, QuickLook step 4).
- 2026-10-12: computer use cannot type into save-panel accessory fields or
  secure input; run screen-operating subagents in the foreground
  (`device-check` skill).
