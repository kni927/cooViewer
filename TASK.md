# TASK: Add Finder “Open With → cooViewer (New Window)” and release v1.6.3

## Owner intent and authorization

The owner wants the next user-facing change to be a Finder context-menu
**Open With** entry that opens a selected book in a new cooViewer window, and
then wants the accumulated changes released as **v1.6.3**.

This task therefore intentionally includes both implementation and release.
Normal commits, pushes to `origin/main`, the v1.6.3 version bump, the v1.6.3
tag push, the GitHub Release, and the Homebrew tap update are all within the
requested scope once their verification gates pass. Do not stop merely to ask
again for routine permission that is already expressed by this task.

The non-idempotent-operation rules in `docs/task-workflow.md` still apply:
before every commit/tag/push/release/update that could duplicate an existing
result, inspect the current repository and external state first. If the
release scope or user-facing release notes materially differ from this task by
the time the release gate is reached, report the discrepancy before
publishing rather than silently broadening the release.

## Background

cooViewer v1.6.2 deliberately changed ordinary Finder-open handling so that a
new file normally replaces the book in the existing front window instead of
creating another window (`d393955`,
`docs/tasks/2026-07-31-06-finder-open-reuses-window.md`). Existing dedup still
wins: opening a file already shown in another window focuses that window.

The desired new behavior is **not** to undo that policy. The owner wants an
additional Finder-native way to request a new window from the right-click
**Open With** submenu while retaining the ordinary `cooViewer` entry and its
current reuse behavior.

This exact entry-point problem has already been investigated:

- `docs/tasks/2026-08-02-01-investigate-finder-new-window-entry.md` established
  that Finder/Open With enumerates registered application bundles, while the
  main app receives only the file URLs in `-application:openFiles:`. A single
  bundle therefore cannot expose two differently named Open With actions or
  distinguish “default open” from “the other Open With action” after delivery.
- `docs/tasks/2026-08-02-05-retest-nsservices.md` established that `NSServices`
  is a much smaller implementation and works end-to-end, but appears under the
  Finder **Services** submenu and requires one-time per-user enablement. That
  is not the menu placement requested for this task.

Therefore this task chooses the previously investigated **second application
bundle / helper** design specifically to obtain a true second Open With entry.
Do not substitute NSServices or a Quick Action merely because it is smaller.

The RAR trailing-error compatibility fallback is already completed and pushed:

- `5335880` — recover a payload after a trailing libarchive error only when
  declared uncompressed size and RAR CRC32 both validate.
- `d8ad6db` — document the fallback and upstream follow-up.
- Upstream remains tracked at `libarchive/libarchive#3352` and `#3361`.

Do not reopen or redesign that work in this task.

## Release baseline at task creation

At creation time, `main` is `d8ad6dbc0b20eb536ea40ad6b22712fc1f9c9c58`
and is 9 commits ahead of tag `v1.6.2`. Re-check this at execution time with
`git fetch origin --tags` and `git log --oneline v1.6.2..origin/main`; this
snapshot is context, not an excuse to ignore later commits.

User-facing changes already accumulated since v1.6.2 include at least:

- `6aa27f8` — fix the empty-window / load-in-flight race with
  `bookLoadInFlight`.
- `5335880` — strict RAR payload recovery after a trailing libarchive error.
- The Open With new-window feature implemented by this task.

Other commits in the range are investigation/documentation unless the fresh
pre-release comparison proves otherwise.

## Goal

After implementation, Finder should offer two clearly distinct handlers for
cooViewer-supported documents:

1. **cooViewer** — existing behavior remains unchanged.
   - Ordinary Finder double-click / normal Open With delivery keeps the v1.6.2
     front-window-replace policy when applicable.
   - Existing dedup, empty-window handling, and `bookLoadInFlight` protection
     remain unchanged.
2. **cooViewer (New Window)** — new Open With entry.
   - For a file not already open, route to the same semantic path as the app's
     existing **File ▸ Open in New Window…** action, i.e.
     `-openBookInNewWindow:`.
   - Do not pass through `-application:openFiles:` and do not invoke the
     front-window-replace gate.
   - Preserve the existing `-openBookInNewWindow:` dedup behavior: if the
     exact file is already open, focus its existing window rather than opening
     a duplicate copy. “New Window” here means the same behavior as the app's
     existing new-window action for a not-already-open book.
   - If the main app is not running, invoking this Open With entry must launch
     it and open the file correctly.
   - The helper itself must not show a normal window, Dock icon, or persistent
     UI and must terminate after forwarding its request.

The existing app menu command **Open in New Window… (⌥⌘O)** must remain
unchanged.

## Required design

### 1. Dedicated helper application bundle

Add a minimal helper app target with a permanent identity distinct from the
main app. Unless implementation finds a concrete naming conflict, use:

- Product/bundle display name: `cooViewer (New Window)`
- Stable bundle identifier: `jp.coo.cooViewer.NewWindowHelper`
- `LSUIElement = YES`

The helper exists only to receive Finder document-open requests and forward
them to the main app. It must contain no book viewer, render path, archive
engine, preferences UI, or duplicated application logic.

The helper should claim the same user-openable document types that make sense
for the main cooViewer Open With entry. Avoid silently drifting into a
hand-maintained incompatible list. If the declarations must be duplicated in
two plists, add a lightweight verification step/test that compares the two
sets so future format changes do not update only one handler.

### 2. Ship as part of one cooViewer installation

The preferred packaging is one installed `cooViewer.app` containing the helper
bundle, so uninstall/update remains atomic and Homebrew still installs one main
application.

Do **not** assume that an arbitrary nested `.app` location is enumerated by
LaunchServices. Determine and use a bundle location/embedding arrangement that
is proven, on a clean test registration, to make Finder list
`cooViewer (New Window)` as a separate Open With handler.

This is a hard gate:

- If a correctly signed/structured embedded helper cannot be made to appear
  reliably after a clean install/registration without a second top-level app
  installation, stop before release and report the result.
- Do not silently change the distribution model to install a second standalone
  app into `/Applications` or `~/Applications` merely to make the test pass.
  That would be a material product/distribution decision outside this task.

### 3. Forwarding mechanism

Use the small private-IPC design already recommended by the prior
investigation unless implementation proves a simpler equally robust mechanism:

- Register a private URL scheme on the main app, e.g.
  `cooviewer-new-window:`.
- The helper receives file URLs via its app delegate and asks `NSWorkspace` to
  open a carefully encoded private URL handled by the main app.
- The main app handles that scheme in a dedicated URL-open delegate/handler,
  validates and decodes the file URL/path, and then calls
  `-openBookInNewWindow:` directly.

Requirements for the handoff:

- Never construct a shell command from the filename.
- Correctly preserve spaces, Unicode, `#`, `?`, `%`, and other URL-sensitive
  characters.
- Accept only the private scheme/expected action and a valid local file URL;
  reject malformed or unrelated URLs without trying to open arbitrary paths.
- Handle multi-file Finder opens deterministically. Each not-already-open file
  should reach the normal new-window path exactly once; existing dedup may
  collapse an already-open file to its existing window.
- If rapid helper requests arrive while the main app is launching, none may be
  silently lost or accidentally routed through ordinary Finder-open behavior.

If the chosen implementation differs from the investigated private-URL design,
record why in `TASK.md` before completion and verify the same behavior/security
properties.

### 4. Build and signing integration

Add the helper target and embedding/build dependencies cleanly to the Xcode
project.

The release workflow currently signs nested code bottom-up before signing the
main app. Extend `.github/workflows/xcode-build-and-release.yml` as needed so
the helper executable/bundle is signed before the outer `cooViewer.app`, while
preserving the QuickLook/Preview extension entitlements and the existing
bottom-up signing rationale.

Do not use a blanket re-sign that strips extension entitlements.
`codesign --verify --deep --strict` must pass on the final app.

The helper must use the same release version as the parent app. v1.6.3 must not
ship with a helper reporting a stale 1.6.2 or development version.

## Explicitly out of scope

- Reverting the v1.6.2 ordinary Finder-open/front-window-replace policy.
- Changing `-openBookInNewWindow:` semantics or removing its existing dedup.
- Implementing NSServices, Finder Quick Actions, Automator workflows, or
  Shortcuts as a substitute for the requested Open With entry.
- RAR fallback changes, libarchive vendoring/upgrades, or changes related to
  upstream issues #3352/#3361.
- Render-path, image scaling, page-layout, cache, or archive-format behavior.
- Broad cleanup of the previously observed stale LaunchServices registrations.
  Registration hygiene for this helper is in scope; unrelated historical
  cleanup is not.
- Unrelated refactors or dependency upgrades.

## Registration and test-safety constraints

The prior Open With investigation found many stale registrations for scratch
copies of the real `jp.coo.cooViewer` bundle identifier. Avoid adding more.

- Read `AGENTS.md`, `CLAUDE.md`, `docs/task-workflow.md`, and the two
  2026-08-02 investigation tasks before implementation.
- Never use the production main-app or production helper bundle identifier for
  disposable scratch builds.
- Disposable helper/main test copies must use unmistakably distinct scratch
  identifiers and executable/process names.
- Do not repeatedly register ad-hoc copies in different temporary directories.
  Prefer a single controlled registration pass in a scanned test location,
  inspect it fully, then unregister and remove it.
- Do not script UI by the generic process name `cooViewer` while the owner's
  real app may be running. Use the repository's documented isolated-test
  naming discipline.
- Do not modify the user's real `/Applications/cooViewer.app` during feature
  development. The real installed app is touched only at the release-artifact
  verification phase after CI publication.
- After isolated testing, prove the scratch helper registration and files are
  removed. Do not leave a test Open With entry behind.

## Feature verification before version bump

Do not bump to 1.6.3 until the feature itself is implemented, committed as a
coherent change, and passes the gates below.

### Automated / static verification

- Run the full archive engine suite and record the exact result/check count.
- Build the normal Development/Deployment product using the repository's
  documented final-product procedure; `build/` must retain only the intended
  final `cooViewer.app` product.
- Verify the helper is embedded exactly once in the intended location.
- Verify main and helper bundle identifiers/display names/document claims.
- Verify the main/helper document-type declarations do not unexpectedly diverge.
- Verify the private URL encode/decode path with filenames containing spaces,
  Japanese/Unicode text, and URL-reserved characters.
- Verify `codesign --verify --deep --strict` on an appropriately signed test
  product where applicable.
- `git diff --check` must pass.

### Manual isolated verification

Use controlled test fixtures only; do not use the owner's real books.

1. **Two Open With entries:** Finder's Open With submenu for a representative
   `.cbz` and `.cbr` shows one ordinary `cooViewer` entry and one clearly named
   `cooViewer (New Window)` entry, with no duplicate stale test entries.
2. **Ordinary entry unchanged:** with book A open in the front window, choose
   ordinary `Open With ▸ cooViewer` for different book B. Confirm the v1.6.2
   behavior still replaces the front window rather than creating another one.
3. **New-window entry:** with book A open, choose
   `Open With ▸ cooViewer (New Window)` for different book B. Confirm book A
   remains open and unchanged and book B opens in a genuinely separate window.
4. **No windows / app stopped:** quit the main app fully, then invoke the helper
   Open With entry. Confirm the main app launches and the selected book opens
   normally.
5. **Dedup:** with book B already open in another window, invoke the helper on
   book B again. Confirm the existing B window is focused and no duplicate B
   window is created, matching `-openBookInNewWindow:` semantics.
6. **Multiple files:** invoke the helper for 2+ selected files in one Finder
   action. Confirm each distinct not-already-open book appears exactly once and
   no request is lost during launch/forwarding.
7. **Path encoding:** repeat with a fixture whose path contains Japanese text,
   spaces, and URL-reserved characters; confirm the exact intended file opens.
8. **Helper UX:** helper produces no Dock icon/window and exits promptly after
   forwarding.
9. **Existing app action:** ⌥⌘O still opens via the same new-window path and
   behaves as before.
10. **Regression boundary:** ordinary double-click/Finder open, window
    restoration, QuickLook/Thumbnail extensions, and a representative CBZ/CBR
    remain functional.

If Finder cannot reliably present the embedded helper after a clean
registration, do not proceed to the version bump or release.

## Documentation after feature implementation

This feature creates a lasting architectural rule (a second bundled
application exists solely as a Finder Open With action), so update:

- `docs/DECISIONS.md` — record why a helper bundle is used instead of trying to
  distinguish ordinary Finder opens inside the main app, and why NSServices
  was not chosen despite being smaller.
- `docs/DEV_LOG.md` — record the implemented milestone.
- `docs/KNOWN_ISSUES.md` only if implementation leaves a real unresolved,
  actionable registration/signing/LaunchServices issue. Do not create a
  transient issue just to close it in the same task.

## Version bump to 1.6.3

Only after all feature gates above pass:

- Confirm the current version is still 1.6.2 and identify every build setting
  or plist that owns `CFBundleShortVersionString` / `CFBundleVersion` for the
  main app, QuickLook extensions, and new helper.
- Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` (and any explicit helper
  version declarations, if present) so all shipped executable bundles report
  **1.6.3**.
- Do not blindly replace historical references in archived documentation.
- Build again and inspect the resulting Info.plists to prove the main app,
  helper, Thumbnail extension, and Preview extension report the expected
  version.
- Commit the version bump separately from the feature when practical, following
  the precedent used by v1.6.2.
- Push all intended release commits to `origin/main` before tagging.

## v1.6.3 release pre-flight

Immediately before the tag:

1. `git fetch origin --tags`.
2. Working tree clean; `HEAD` matches the intended `origin/main` release commit.
3. `git log --oneline v1.6.2..origin/main` reviewed in full.
4. Confirm no local commit intended for the release is unpushed.
5. `git tag -l "v1.6.3"` must be empty.
6. `gh release view v1.6.3` must be not-found.
7. Confirm the Homebrew tap does not already claim 1.6.3.
8. Re-run the final engine suite / Deployment build if the release commit
   changed anything after the feature verification.

If a tag, release, or partial publication already exists, inspect and resume
from the first incomplete step per `docs/task-workflow.md`; never overwrite or
create a duplicate blindly.

## Draft user-facing release notes

Use these as the intended substance, adjusted only for accuracy after the
fresh commit-range review:

```markdown
## v1.6.3

- Added a separate “cooViewer (New Window)” entry to Finder’s Open With menu,
  so a book can be opened in another window without replacing the book in the
  current cooViewer window. The normal cooViewer Open With/default-open
  behavior is unchanged.
- Fixed a race where a window that was still loading a book could be mistaken
  for an empty reusable window and overwritten by another open request.
- Improved compatibility with a RAR5/libarchive edge case: when libarchive
  reports a trailing decoder error after returning the complete payload,
  cooViewer now accepts it only when both the declared size and RAR CRC32 prove
  the data is complete and valid.
```

Do not mention investigation-only commits as user-facing features. If the fresh
range contains another real user-facing change, add it explicitly rather than
letting generated GitHub notes obscure it.

## Tag, CI, notarization, and GitHub Release

Follow the current `CLAUDE.md` Releasing section and the existing
`.github/workflows/xcode-build-and-release.yml` tag-triggered flow.

- Create and push annotated tag `v1.6.3` only after all pre-flight gates pass.
- Watch the triggered Xcode Build and Release workflow through completion.
- The workflow must:
  - run archive engine tests;
  - build the Deployment app including the helper;
  - sign nested libraries/extensions/helper bottom-up without stripping
    entitlements;
  - notarize successfully;
  - staple and validate the app;
  - create the GitHub Release and upload the normal release zip, dSYM zip, and
    test-book asset.
- If signing/notarization fails, stop and diagnose. Do not bypass Gatekeeper,
  clear quarantine, ad-hoc sign the release artifact, or weaken verification.
- Inspect the resulting GitHub Release and ensure the user-facing notes reflect
  the intended v1.6.3 substance rather than leaving an opaque autogenerated
  commit dump if the workflow's generated notes are inadequate.

Notarization/signing secrets are already repository-managed. Never request,
print, rotate, or expose credential material as part of this task.

## Homebrew tap and released-artifact verification

After a successful GitHub Release, update `kni927/homebrew-tap` following the
established release procedure:

- Compute SHA-256 from the actual published `cooViewer-v1.6.3.zip`.
- Update the cask version/URL/SHA as required.
- Commit and push the tap update.
- `brew update`, then confirm the tap resolves cooViewer 1.6.3.

Then verify the real published artifact, not a local dev build:

- Uninstall/reinstall through the tap in the safe order established by the
  v1.6.2 release task (tap update must precede a fresh install that is expected
  to resolve the new version).
- Confirm main app version is 1.6.3 and the embedded helper also reports 1.6.3.
- `spctl` must report Notarized Developer ID acceptance with quarantine intact;
  do not use `xattr -cr`.
- Verify `codesign --verify --deep --strict` on `/Applications/cooViewer.app`.
- Confirm QuickLook and Thumbnail extensions resolve to the released
  `/Applications/cooViewer.app` and still function.
- Confirm Finder Open With on the released installation presents the two
  intended entries with no unexpected duplicate production/helper entries.
- Spot-check both released behaviors using project test fixtures only:
  - ordinary `cooViewer` Finder open keeps the existing front-window-replace
    behavior;
  - `cooViewer (New Window)` leaves the existing front book intact and opens
    the different test book in another window.
- Also spot-check the RAR synthetic regression fixture through the released app
  if practical, or at minimum confirm the release CI engine suite exercised the
  committed fallback fixture and passed.

Be especially careful not to replace or disturb an already-restored real user
book during released-build spot checks. Use the isolated/test-book procedure
from `CLAUDE.md`; do not drive the user's live content merely because the
release app is installed in `/Applications`.

## Completion and archiving

Follow `docs/task-workflow.md` exactly.

Append:

```markdown
## Implementation Result

**Status:** Completed / Completed with follow-up issues / Partially completed / Not completed

### Changes

### Verification

- Build:
- Automated verification:
- Manual verification:
- Release verification:
- Not performed:

### Remaining Issues

### Follow-up Suggestions
```

The result must record at least:

- helper target/bundle name, identifier, embedded location, and forwarding
  mechanism;
- whether Finder reliably enumerated the embedded helper and the exact clean
  registration procedure used;
- default Open With vs new-window Open With manual results;
- multi-file and special-character path results;
- archive-engine test count and build commands;
- signing/notarization verification including the helper;
- feature commit(s), version-bump commit, final release commit SHA;
- v1.6.3 tag and GitHub Actions run ID/result;
- GitHub Release URL/assets;
- Homebrew tap commit and released-artifact verification;
- any remaining LaunchServices or helper-distribution issue.

Archive this task as:

`docs/tasks/2026-08-22-01-open-with-new-window-release-v1.6.3.md`

Remove `TASK.md` from the repository root when reporting completion, update
`docs/DEV_LOG.md` and `docs/DECISIONS.md` as required above, push the archival
documentation commit, and provide the standard self-contained chat Completion
Report with exact commit hashes, test counts, tag/release status, and remaining
issues.

## Work Progress

- Feature implementation and the pre-version-bump gate are complete. A
  Deployment build succeeded; the helper URL tests passed 13/13 and the bundle
  verifier confirmed one helper with all 20 document declarations.
- Recursive disposable-bundle registration (`lsregister -f -R`) exposed both
  `.cbz` and `.cbr` Finder entries. Manual testing passed ordinary replacement,
  new-window forwarding, stopped-main launch, multi-file delivery,
  special-character paths, in-flight deduplication, helper exit/no UI, ⌥⌘O,
  Quick Look, and Finder thumbnails. All disposable registrations and the
  `~/Applications` scratch copy were removed afterward.
- Next step: commit the feature, then bump every shipped target to 1.6.3 and run
  the final build/release verification sequence.
