# TASK: Record cvbdl exclusion guard and extension verification constraint

## Scope

Documentation only. No code changes. Do this before starting the v1.5.2
release task.

## Steps

1. Add an entry to `docs/KNOWN_ISSUES.md` (or wherever this project
   records this kind of guardrail):
   - `.cvbdl` is intentionally excluded from `COImageLoader.archiveTypes`
     (`COImageLoader.m:37-46`). This is not dead code to remove: `COArchive`
     falls back to `archive_read_open_filename` on unrecognized extensions,
     which cannot open a directory, so removing the exclusion breaks
     opening `.cvbdl` bundles entirely (confirmed in
     `docs/tasks/2026-07-25-16-investigate-cvbdl-support-scope.md`).
     `.cvbdl` is handled instead by the generic directory-open fallback,
     which already covers the full documented feature set.
2. Add a second entry recording the on-device verification constraint:
   - On this development machine, the Homebrew-managed copy in
     `/Applications` takes priority in LaunchServices' bundle-ID dedup
     regardless of version recency, which prevented on-device verification
     of new QuickLook/Thumbnail extension binaries in both the v1.5.1 and
     v1.5.2 development cycles (see
     `docs/tasks/2026-07-25-15-tag-v1.5.1.md` and
     `docs/tasks/2026-07-25-17-implement-cvbdl-quicklook.md`).
   - Note the only reliable workaround found so far: temporarily
     uninstalling the Homebrew copy to test the actual signed release
     artifact immediately before a release (as done in the v1.5.2 release
     task), then restoring Homebrew management via the tap update. This is
     not practical for routine development verification.
   - Note this as a standing constraint for any future task that changes
     extension code, not a one-off issue to close.
3. Commit.

## Notes

- Keep both entries factual and short; they exist to prevent future
  sessions from re-investigating settled findings or re-attempting a
  workaround that doesn't exist for routine dev-cycle verification.
## Implementation Result

**Status:** Completed

### Changes

Documentation only, as scoped. No code changed.

- `docs/KNOWN_ISSUES.md`: added two new entries, following the existing
  numbered-heading convention:
  - **#17** — records that `.cvbdl`'s exclusion from
    `COImageLoader.archiveTypes` (`Sources/COImageLoader.m:37-46`) is
    intentional, why removing it would break `.cvbdl` (libarchive cannot
    open a directory), and that the generic directory-open fallback
    already covers the documented feature set — cross-referencing the
    investigation archive and the `docs/DECISIONS.md` entries.
  - **#18** — records the LaunchServices bundle-ID dedup constraint: on
    this machine, `/Applications/cooViewer.app` always wins
    `pluginkit`/LaunchServices resolution over a freshly built
    `~/Applications` copy regardless of version recency, which blocked
    on-device QuickLook/Thumbnail verification in both the v1.5.1 and
    v1.5.2 cycles. Framed explicitly as a standing constraint for any
    future extension-touching task, not a one-off to fix, with the one
    known (impractical for routine use) workaround noted.

### Citation correction

Step 2 named `docs/tasks/2026-07-25-15-tag-v1.5.1.md` as where the dedup
issue was found during the v1.5.1 cycle. Checked before citing it: that
archive is the version-bump task and only has a passing note that no
LaunchServices registration was touched — it does not document the dedup
finding. The actual discovery is in
`docs/tasks/2026-07-25-14-verify-encrypted-zip-on-device.md` (the on-device
verification task run just before the version bump, same v1.5.1 cycle).
**Entry #18 cites `-14`, not `-15`,** for accuracy; noted here rather than
silently deviating from the task's wording.

### Verification

- Build: Not performed (documentation only; no code touched).
- Automated verification: confirmed via `git status`/`git diff --stat`
  that only `docs/KNOWN_ISSUES.md` changed (plus this archive) — no
  source, test, or plist files were touched.
- Manual verification: checked `docs/KNOWN_ISSUES.md` had no pre-existing
  entries covering either topic before adding (grepped for `cvbdl`,
  `dedup`, `bundle-id`, `pluginkit` — no hits), so nothing was duplicated.
  Cross-checked both cited investigation/task archives
  (`2026-07-25-16`, `2026-07-25-14`, `2026-07-25-17`) actually contain the
  claims being cited, rather than assuming the task's wording was correct
  (see the citation correction above).

### Remaining Issues

None.

### Follow-up Suggestions

None beyond what entry #18 itself already flags: the next task that
touches QuickLook/Thumbnail extension code should read #18 before assuming
on-device Finder verification is available on this machine.
