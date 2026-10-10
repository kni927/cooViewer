# Status

The current state of this repository, for the next session and for the owner:
what comes next, what is on hold, and what waits on the owner. Rewrite it
rather than append; keep it under about 40 lines. Rules are in `AGENTS.md`,
decisions in `docs/DECISIONS.md`, and history in `docs/tasks/` and Git.

Updated: 2026-10-10

## Summary

cooViewer: macOS image and comic viewer, a maintained fork of coo-ona's original.
Latest release v1.6.7 (2026-10-06), notarized and in the Homebrew tap. No task
is active and no TF is running.

## Next

- Nothing scheduled. The owner picks from On hold when work resumes.
- The next TF is named `cooViewer TF #NN <what>` (`docs/sessions.md`).

## On hold

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
