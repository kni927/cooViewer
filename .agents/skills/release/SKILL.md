---
name: release
description: Release a new cooViewer version - preflight, version bump, verified build, push main, hand the owner the tag block, then after the tag watch CI and notarization, replace the release body, update the Homebrew tap, verify the installed artifact (versions, Gatekeeper, launch, Quick Look only) and archive the task. Use for any release task.
---

# Release cooViewer

`CLAUDE.md` ▸ Releasing is the rule; this is the procedure. The owner
approves the version and the release notes in chat, and pushes the tag.
Before every non-idempotent step, check that its result does not already
exist (`docs/task-workflow.md`).

## Part 1: up to the tag

1. **Preflight:** `git fetch origin --tags`; `git tag -l vX.Y.Z` is empty;
   `gh release view vX.Y.Z` (or the GitHub API) finds nothing; `git status`
   is clean. If any part of the release exists, stop and report.
2. **Scope:** `git log --oneline v<previous>..origin/main`. If an
   app-changing commit appears that the task does not list, stop and report
   rather than widening the release.
3. **Registrations:** `tools/device_check.sh status`, and `pluginkit -mADv`
   for both extensions: nothing under the production bundle IDs except
   `/Applications`. Clear leftovers with `tools/device_check.sh unregister`.
4. **Version bump:** first confirm the old version string appears in
   `cooViewer.xcodeproj/project.pbxproj` only as `MARKETING_VERSION` and
   `CURRENT_PROJECT_VERSION`; then change every occurrence, in every
   configuration of every target.
5. **Build** with the `build-app` skill. The app,
   `cooViewer (New Window).app`, `cooViewerPreview.appex` and
   `cooViewerThumbnail.appex` all report the new version for both keys and
   `LSMinimumSystemVersion` 12.0 (`codesign -dvv` or the `Info.plist`s);
   engine tests ALL PASS (give the counts); then
   `tools/device_check.sh unregister`.
6. **Commit** "Prepare vX.Y.Z", staging files explicitly. `git fetch`; if
   `origin/main` moved, merge it (never rebase or amend), check, then push
   `main`.
7. **Stop and hand over the tag** as one ready-to-paste block:

   ```
   git tag -a vX.Y.Z -m "vX.Y.Z" <commit>
   git push origin vX.Y.Z
   ```

## Part 2: after the owner pushes the tag

1. **CI:** watch `.github/workflows/xcode-build-and-release.yml` to the end.
   From the log: notarytool `status: Accepted`, the staple and validate
   step passed, `spctl` reports `source=Notarized Developer ID`. If the
   build or notarization fails, stop and report; never work around
   Gatekeeper.
2. **Release body:** replace it with the approved notes, after the owner's
   OK in chat; keep the assets CI attached.
3. **Tap:** `tools/update_tap.sh X.Y.Z`, alone in its call. The diff must
   change only the version and sha256 (the sha256 equals the release
   asset's digest). Push the tap commit to `kni927/homebrew-tap`; that is
   part of the authorized release.
4. **Verify the artifact** (`CLAUDE.md` ▸ Verifying the release artifact),
   with the owner standing by for screen work:
   - `brew uninstall --cask cooviewer`, then
     `brew install --cask kni927/tap/cooviewer`: it resolves the new
     version, and all four bundles report it with minimum 12.0.
   - Gatekeeper-clean with the quarantine attribute present and no
     `xattr -cr`: `spctl` accepted, `codesign --verify --deep --strict`,
     `stapler validate`.
   - It launches and opens a book.
   - Quick Look and thumbnails: the `ql-check` skill, "Release artifact".
   - Nothing more. Features were verified on the development build of the
     same commit; re-check one only if app code changed after it was
     verified. If a release-note item was never verified, tell the owner
     before replacing the body.
5. **Records:** a `docs/DEV_LOG.md` entry; archive the task
   (`docs/task-workflow.md`); commit and push `main`.

Precedent: `docs/tasks/2026-10-15-03-release-v1.6.9.md`.
