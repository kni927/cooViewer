# TASK: Document the cvbdl format origin and status

## Scope

Documentation only. No code changes.

## Steps

1. Add an entry to `docs/DECISIONS.md` (or `docs/KNOWN_ISSUES.md`, whichever
   fits the project's existing convention for this kind of note) recording:
   - `.cvbdl` is a macOS bundle-folder variant of the "Comic Book Format"
     naming convention (alongside .cbz/.cbr/.cb7/.cbt/.cba/.cbtc), per the
     German Wikipedia article "Comic-Book-Format"
     (https://de.wikipedia.org/wiki/Comic-Book-Format), which is the only
     language edition listing it. This is not a ratified standard — no
     standards body defines Comic Book Format; it is a de facto convention
     followed by several independent viewers or applications such as
     HetimaZip.qlgenerator.
   - No dedicated implementation exists in this codebase or its known
     upstream history (single commit `77b2275`, 2020-01-13, part of the
     initial fork import). It is currently handled only by the generic
     directory-open fallback in `COImageLoader`, since `LSTypeIsPackage`
     makes Finder treat the folder as a single document.
   - Confirmed manually: renaming a folder to `.cvbdl` makes it open in
     cooViewer via the generic path. QuickLook does not support it
     (`COCoverExtractor.m` explicitly excludes it).
   - Decision: kept as-is (not dead code to remove); origin was previously
     unclear and is now documented to avoid re-investigation.
2. Commit.

## Notes

- Keep this factual and short; it exists so a future session does not
  re-investigate the same question.
## Implementation Result

**Status:** Completed

### Changes

Documentation only; no code changes.

- `docs/DECISIONS.md`: added "`.cvbdl` document type: keep as-is, origin
  documented (2026-07-25)", following the project's existing convention of
  recording "kept deliberately, not dead code" calls in this file (same
  pattern as the RemoteControlWrapper and encrypted-RAR entries above it).
  Recorded: the Comic Book Format naming-convention origin (German
  Wikipedia, not a ratified standard, followed by third-party viewers like
  HetimaZip.qlgenerator); that no dedicated implementation exists in this
  codebase or its known history (single commit `77b2275`, 2020-01-13,
  initial fork import, untouched since); that `LSTypeIsPackage` routes
  `.cvbdl` folders around the archive dispatch into the generic
  directory-open fallback, confirmed manually by renaming a folder to
  `.cvbdl`; and that QuickLook does not support it
  (`COCoverExtractor.m` excludes it explicitly).
- `docs/KNOWN_ISSUES.md` was not used — this is a settled "why it's this way
  and why we're not changing it" call, matching DECISIONS.md's convention
  rather than KNOWN_ISSUES.md's "fragile area to be careful with" framing.

### Verification

- Build: Not performed (documentation only).
- Automated verification: confirmed no source, test, vendor, or resource
  files were touched (`git status` shows only `docs/DECISIONS.md`).
- Manual verification: re-read the new entry against the task's required
  content list — all five points present.

### Remaining Issues

None.

### Follow-up Suggestions

None. The entry exists so a future session does not re-investigate the same
question.
