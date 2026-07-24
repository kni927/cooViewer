# TASK: Clean up repository root (stage 1)

## Scope

Remove build artifacts and OS metadata from the repository root, update
`.gitignore`, and correct the Repository Layout wording in `CLAUDE.md`.

Do not move or delete `Info.plist`, `cooViewer_Prefix.pch`, or
`MainMenu~.nib` in this task. They are handled separately in stage 2a-2.

## Steps

1. Remove `cooViewer.app.zip` from the repository. If it is tracked,
   remove it with `git rm`; if untracked, delete it.
2. Remove `.DS_Store` from the repository root. Check whether other
   `.DS_Store` files are tracked elsewhere (`git ls-files | grep DS_Store`)
   and remove those as well.
3. Update `.gitignore` so that both are excluded going forward:
   - `.DS_Store` (all directories)
   - `*.app.zip` or an equivalent pattern covering distributable archives
   Preserve existing entries and ordering style.
4. Replace the Repository Layout section in `CLAUDE.md` with:

```md
   ## Repository Layout
   - Repository root contains only dotfiles, top-level directories, `*.md`,
     `*.txt`, and the Xcode project bundle. Source, resources, and scripts
     live in subdirectories.
   - Do not add new files to the repository root without explicit
     instruction.
   - `build/` contains only the final `cooViewer.app`. Xcode intermediates
     (`DerivedData`, `.build`, indexes, test products) are kept outside the
     repository.
   - Remove stale contents from `build/` before producing a new product, and
     verify afterwards that `build/` contains the app and nothing else.
```

## Verification

- `ls -a` at the repository root shows no `cooViewer.app.zip` and no
  `.DS_Store`.
- `git status` is clean after committing.
- No Xcode build is required for this task.

## Notes

- Do not modify `README.md`.
- Report whether `cooViewer.app.zip` was tracked or untracked.
## Implementation Result

**Status:** Completed

### Changes

- Deleted `cooViewer.app.zip` (3.3M) from the repository root.
- Deleted `.DS_Store` from the repository root.
- `.gitignore` already excluded both patterns (`*.app.zip` line 73,
  `.DS_Store` line 79); no change was required. Existing entries and
  ordering preserved.
- Replaced the Repository Layout section in `CLAUDE.md` with the wording
  specified in this task (root allows dotfiles, top-level directories,
  `*.md`, `*.txt`, and the Xcode project bundle).
- Did not touch `Info.plist`, `cooViewer_Prefix.pch`, or `MainMenu~.nib`
  (reserved for stage 2a-2). `README.md` not modified.

### Verification

- Build: Not required (documentation/cleanup only).
- Automated verification: `ls -a` root shows no `cooViewer.app.zip` and no
  `.DS_Store`; `git ls-files | grep DS_Store` returns nothing.
- Manual verification: `.gitignore` confirmed to contain `*.app.zip` and
  `.DS_Store`; CLAUDE.md Repository Layout matches the requested text.
- Not performed: application launch (not applicable).

### Remaining Issues

- None.

### Follow-up Suggestions

- Stage 2a-2: handle `Info.plist`, `cooViewer_Prefix.pch`, and
  `MainMenu~.nib` at the repository root (out of scope here).

### Notes

- `cooViewer.app.zip` was **untracked** (never committed); removed by file
  deletion, not `git rm`.
