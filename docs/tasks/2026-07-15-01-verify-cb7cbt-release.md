# TASK: Verification + cb7/cbt check + 1.5.0 release — phase 8

## Background

Phase 7 (archived: `docs/tasks/2026-07-14-05-quicklook-extension.md`)
shipped the QuickLook preview/thumbnail extensions and fixed the missing
`CFBundleShortVersionString`, bumping to 1.5.0. Nothing was committed
yet, pending two open questions raised in chat:

1. Whether the QuickLook extensions actually select the first page by
   the same **display-order** logic the main app uses (filename natural
   sort etc.), or by raw archive/entry storage order — these can differ,
   and phase 4's note that "archive order matched display order" was
   confirmed only for one specific fixture (all-PNG, no mixed
   extensions), not as a general guarantee.
2. Whether `.cb7` (7z) and `.cbt` (tar) — out of scope in phase 7 —
   should be added now, following the same four-UTI-per-format pattern
   used for cbz/cbr, since they're low-cost to add if the plumbing
   already generalizes.

Once both are resolved, this task also covers committing the phase 7
work, pushing, and publishing the 1.5.0 release.

## Goal

- Confirm (or fix) that QuickLook always shows the same "first page" a
  user would see opening the archive in the main app, not an
  arbitrary/incidental one.
- Decide, with evidence rather than assumption, whether cb7/cbt support
  is worth adding now, and add it if trivial.
- Phase 7's work is committed, pushed, and released as cooViewer 1.5.0.

## Scope

### In scope

**1. Display-order verification**

- Build (or reuse if one already exists) an adversarial test fixture
  where filename natural-sort order and archive storage order
  deliberately differ (e.g. entries stored as `z_cover.jpg`,
  `a_page2.jpg` in that storage order, where correct display order
  puts `a_page2.jpg` first... or whatever the main app's actual sort
  rule dictates — first confirm what that rule is, e.g. filename
  natural sort vs. some other criterion, by reading the main app's
  existing sort code, not by assumption).
- Run this fixture through both the main app and the QuickLook
  extension; compare which "first page" each shows.
- If they match: done, document the confirmation.
- If they diverge: fix the QuickLook extension to call the same
  sort/ordering routine the main app uses (do not reimplement sorting
  logic independently — share it, consistent with this project's
  existing pattern of reusing `COZipArchive`/`CORarArchive` rather than
  duplicating).

**2. cb7/cbt support decision**

- Check whether the current QuickLook extension's format handling
  (COZipArchive / CORarArchive / libarchive fallback) already covers 7z
  and tar at the reader level (it should, in principle, since 7z/tar
  were never removed from the libarchive path).
- If adding `.cb7`/`.cbt` is a matter of extending the UTI declarations
  and format dispatch (mirroring the existing four-UTI-per-format
  pattern for cbz/cbr) with no new reader work required, add it.
- If it turns out to need non-trivial new work (e.g. 7z/tar don't
  already have a working single-entry decode path suitable for
  QuickLook's time budget), do not implement — report back with what
  was found instead, per this project's usual scope-control convention.
- Either way, record the decision and reasoning in the Implementation
  Result.

**3. Commit**

- Commit phase 7's work (QuickLook extensions, `CFBundleShortVersionString`
  fix, version bump to 1.5.0) as one coherent unit, plus this task's
  fixes/additions, following the project's commit conventions.

**4. Release 1.5.0**

- Tag the release (`v1.5.0` or the project's existing tag convention —
  check prior tags for the exact format).
- Push the tag and trigger/verify the existing GitHub Actions
  release workflow (`.github/workflows/xcode-build-and-release.yml`)
  produces the tag-named release zip.
- Update the Homebrew tap (`kni927/tap/cooviewer` referenced in
  README) if that's a separate repo Claude Code has access to; if not,
  note the exact version/sha256/URL values Master needs to update it
  manually.
- Update README/DEV_LOG with a 1.5.0 summary entry (QuickLook support,
  performance work across phases 1–6) if not already sufficiently
  covered by existing entries.

### Out of scope

- Any further performance work on zip/rar reading (phases 1–6 are
  done).
- Any new format support beyond cb7/cbt as scoped above.
- Marketing/announcement content beyond the GitHub release notes and
  README/DEV_LOG updates.

## Verification

- Display-order fixture: documented pass/fail and, if a fix was
  needed, confirmation that main app and QuickLook now agree.
- cb7/cbt: if added, confirm Finder preview/thumbnail works for sample
  .cb7 and .cbt files; if not added, the reasoning is documented.
- Release: tag pushed, GitHub Actions run green, release asset
  downloadable, and (if applicable) Homebrew tap updated or manual
  update values documented.
- Fresh install smoke test: download the released zip (not a local
  build), move to /Applications, launch, confirm QuickLook works and
  Get Info shows 1.5.0.

## Implementation Result

**Status:** Completed

### Changes

- **Display-order verification (confirmed, no fix needed):** built an
  adversarial `.cbz` fixture where zip storage/insertion order
  deliberately differs from `finderCompareS:` natural-sort display
  order. `COCoverExtractor` and the main app were both run against it
  and independently agreed on the same "page 1" (confirmed by exact
  byte-length match on the extractor side, and by reading the
  page-bar filename string in the main app's RTL two-page-spread
  view). No code change was needed — phase 7's reuse of
  `finderCompareS:` was already correct, this closes the open
  question with evidence rather than assumption.
- **cb7/cbt decision (not added, evidence-based):** measured real
  timing rather than assuming. `.tar`/`.7z` don't currently have a
  lazy single-entry path (`COArchive.m`'s `readArchiveWithProgress:`
  fallback fully decompresses/buffers every entry up front); a
  realistic 1.4 GB `.tar` built from a real large `.cbz` fixture's own
  pages took ~8s to first page through that path — far outside this
  project's own established performance bar (~0.1–1s, phases 4–6) —
  and a `.7z` of the same content was still compressing after 20+
  minutes of CPU time when aborted, corroborating that solid 7z would
  need `CORarHeaderIndex`-scale bespoke work to be genuinely lazy.
  Neither format was added. Reasoning recorded in `docs/DECISIONS.md`
  and `docs/DEV_LOG.md`, with `.cbt` flagged as a reasonable smaller
  future addition and `.cb7` as comparable in scope to the whole RAR
  lazy-reading project (phases 1–6).
- Committed phase 7 (QuickLook extensions, `CFBundleShortVersionString`
  fix, 1.5.0 version bump) together with this task's verification
  work as one coherent commit, per this task's own instruction.
- **CI signing bug found and fixed before release:** while preparing
  to tag, checked the release workflow's signing step rather than
  assuming it would carry the new extensions' entitlements correctly.
  `.github/workflows/xcode-build-and-release.yml`'s "Sign app" step
  ran a single `codesign --deep --sign "$SIGNING_IDENTITY" "$APP_PATH"`
  — confirmed by local testing (ad-hoc identity standing in for the
  real one) that this **silently strips** the sandbox entitlements
  from nested `.appex` bundles, because `codesign` does not carry
  entitlements across a re-sign unless told to. Fixed by signing
  bottom-up instead: each vendored dylib, then each extension with its
  own `.entitlements` file, then the outer app without `--deep` (since
  its nested content is already correctly signed). Committed
  separately (`fix(ci): preserve QuickLook extension entitlements
  during release signing`) before tagging.
- Sought and received explicit owner confirmation in chat before
  tagging/pushing, per `AGENTS.md`'s "Initial publication to GitHub
  and other significant push points are reviewed by the project
  owner" — the original TASK.md request alone was treated as scope,
  not as that confirmation.
- Tagged and released `v1.5.0`; updated the `kni927/homebrew-tap`
  cask (version + sha256).

### Verification

- **Display order:** documented pass above — main app and QuickLook
  extension agree.
- **cb7/cbt:** not added; reasoning and measurements documented in
  `docs/DECISIONS.md`.
- **Release:** tag `v1.5.0` pushed; GitHub Actions run
  [29346504162](https://github.com/kni927/cooViewer/actions/runs/29346504162)
  completed successfully in 5m50s; release
  [v1.5.0](https://github.com/kni927/cooViewer/releases/tag/v1.5.0)
  published with `cooViewer-v1.5.0.zip` and the test-book asset.
- **CI signing fix, verified against the actual release artifact (not
  just local ad-hoc testing):** downloaded the real
  `cooViewer-v1.5.0.zip`, extracted it, and confirmed — `codesign
  --verify --deep --strict` passes; `spctl --assess` reports
  "accepted, source=Notarized Developer ID"; `stapler validate`
  succeeds; `CFBundleShortVersionString`/`CFBundleVersion` are `1.5.0`
  (checked directly via `plutil`/`PlistBuddy` — `defaults read`
  misreported "does not exist" again, the same environment quirk
  already documented in `docs/KNOWN_ISSUES.md` #13, not a real
  problem); and — the actual point of the fix — both
  `cooViewerThumbnail.appex` and `cooViewerPreview.appex` retain
  `com.apple.security.app-sandbox` +
  `com.apple.security.files.user-selected.read-only` under the real
  `Developer ID Application: Kuniharu Nishimura (87B58V226A)`
  signature.
- **Fresh install smoke test:** installed the downloaded release
  build, registered it with LaunchServices/pluginkit, and confirmed
  in real Finder (Space-preview) that the QuickLook extension in the
  actual notarized release artifact works, not just a local dev
  build.
- **Homebrew tap:** updated `kni927/homebrew-tap`'s `Casks/cooviewer.rb`
  to `version "1.5.0"` + the release zip's sha256; verified end-to-end
  by actually running `brew update && brew upgrade --cask cooviewer`
  against the real published tap (not just `brew audit`/`brew style`
  on the file) — it correctly resolved and upgraded the on-disk
  `/Applications/cooViewer.app` from 1.4.0 to 1.5.0, which was then
  re-registered and re-verified the same way (entitlements intact,
  QuickLook working).
- **Build:** `xcodebuild -configuration Deployment` succeeds for all 3
  targets.

### Remaining Issues

None.

### Follow-up Suggestions

- Consider `.cbt` (tar) support as a future phase: needs a new
  `COTarArchive` lazy reader (tar's simplicity makes this a
  self-contained, low-risk addition, unlike `.cb7`).
- `.cb7` (7z) support would be a project on the scale of the RAR
  lazy-reading work (phases 1–6), not a quick follow-up — revisit only
  if there's real demand.
- The CI signing bug found here (`--deep` re-sign silently dropping
  nested entitlements) was specific to this project's new extension
  targets, but worth remembering for any future target that ships its
  own `.entitlements` file.
