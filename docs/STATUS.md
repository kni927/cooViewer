# Status

The current state of this repository, for the next session and for the owner:
what comes next, what is on hold, and what waits on the owner. Rewrite it
rather than append; keep it under about 40 lines. Rules are in `AGENTS.md`,
decisions in `docs/DECISIONS.md`, and history in `docs/tasks/` and Git.

Updated: 2026-10-17

## Summary

cooViewer: macOS image and comic viewer, a maintained fork of coo-ona's original.
Latest release v1.6.9 (2026-10-15), notarized and in the Homebrew tap: page
bar size and Page Number settings, Fill title bar, status bar opacity, and
the #47 fixes (`docs/tasks/2026-10-15-03-release-v1.6.9.md`).

## Next

- None set; ask the owner.

## On hold

- Solid RAR next-page prefetch in page order can restart the cursor (speed
  only); left unchanged on 2026-10-15, reasons in
  `docs/tasks/2026-10-15-01-page-bar-settings.md`.

The next five were put on hold as minor (owner, 2026-10-08); details are in
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
  test copy's extension ran (`ql-check` skill).
- 2026-10-17: the step lists of Releasing, On-Device Verification and Spread
  Capture moved from `CLAUDE.md` to skills in `.agents/skills/` (`AGENTS.md`,
  Skills). The HQ went on stand-by (`docs/sessions.md`, Stand-by).
- 2026-10-12: computer use cannot type into save-panel accessory fields or
  secure input; run screen-operating subagents in the foreground
  (`device-check` skill).
- 2026-10-15: run `open -a Claude` right before a computer-use approval
  request so the owner sees the dialog (`device-check` skill).
