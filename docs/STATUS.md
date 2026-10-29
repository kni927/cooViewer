# Status

The current state of this repository, for the next session and for the owner:
what comes next, what is on hold, and what waits on the owner. Rewrite it
rather than append; keep it under about 40 lines. Rules are in `AGENTS.md`,
decisions in `docs/DECISIONS.md`, and history in `docs/tasks/` and Git.

Updated: 2026-10-30

## Summary

cooViewer: macOS image and comic viewer, a maintained fork of coo-ona's original.
Latest release v1.6.9 (2026-10-15; `docs/tasks/2026-10-15-03-release-v1.6.9.md`).

## Next

- None set; ask the owner.

## On hold

- Solid RAR next-page prefetch in page order can restart the cursor (speed
  only); left unchanged on 2026-10-15, reasons in
  `docs/tasks/2026-10-15-01-page-bar-settings.md`.

- Minor, on hold (owner, 2026-10-08): main-thread decode in the thumbnail
  panel and page-bar bubble, and uncancellable page decodes (`docs/KNOWN_ISSUES.md`
  #46); RAR5 decode-ahead files left after a crash (`docs/DECISIONS.md`, per-book
  disk cache); unused `Resources/empty.png`; nested archives through the modal
  path (`docs/KNOWN_ISSUES.md`).
- Undecided (owner, moved here 2026-10-10): whether to support OPDS catalogues
  from a self-hosted server; Komga is favoured over Kavita.
- Not implemented: EPUB to PDF to CBZ conversion. Chosen toolchain is LuaLaTeX
  with jlreq for vertical Japanese text, on BasicTeX rather than MacTeX; Typst
  was rejected for lacking vertical writing. BasicTeX is not yet in the Mac
  setup's Brewfile.

## Waiting on owner

- None.

## Notes

- None. Device, Quick Look and computer-use quirks live in the `device-check`
  and `ql-check` skills.
