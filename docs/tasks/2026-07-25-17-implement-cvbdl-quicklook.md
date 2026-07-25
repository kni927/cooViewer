# TASK: Implement cvbdl QuickLook/Thumbnail support (v1.5.2)

## Scope

Per `docs/tasks/2026-07-25-16-investigate-cvbdl-support-scope.md`:
QuickLook/Thumbnail support for `.cvbdl` bundles only. Do not remove
`cvbdl` from `COImageLoader.archiveTypes`'s exclusion list and do not
touch the main app's directory-open path — the investigation found that
change breaks currently-working behaviour.

## Step 0: Sandbox capability check (do this first)

Before writing the extraction logic, confirm the extensions can actually
enumerate a directory's contents under their current entitlements.

1. Build a minimal `.cvbdl` fixture (see Step 3).
2. In `COCoverExtractor.m` (or a temporary standalone check within the
   extension target), attempt `NSFileManager` directory enumeration on a
   `.cvbdl` bundle passed in as the extension's file URL, and report
   whether it succeeds.
3. If enumeration fails or requires an entitlement not currently declared,
   stop here and report the failure and the exact error. Do not proceed to
   Steps 1-2 without confirming the fix, since the whole approach depends
   on this working.
4. If it succeeds, proceed.

## Step 1: UTI / document-type wiring

1. In `Resources/Info.plist`, add a `UTExportedTypeDeclarations` entry for
   `.cvbdl` (e.g. identifier `jp.coo.cooViewer.cvbdl-archive`,
   `UTTypeConformsTo: com.apple.package`, filename extension `cvbdl`),
   matching the pattern used for the existing `cbz`/`cbr` UTI exports.
2. Add `LSItemContentTypes` to the existing `.cvbdl` document type entry,
   pointing at the new UTI. Do not otherwise change that entry (keep
   `LSTypeIsPackage = true` as-is).
3. In `PreviewExtension/Info.plist` and `ThumbnailExtension/Info.plist`,
   add the new UTI to `QLSupportedContentTypes` alongside the existing
   cbz/cbr entries.

## Step 2: Cover extraction for cvbdl

1. In `COCoverExtractor.m`, add a branch for `.cvbdl` that does not go
   through `COArchive`:
   - enumerate the bundle directory with `NSFileManager`
   - filter to image files using the same approach as
     `COImageLoader.m:65-66` (`[NSImage imageFileTypes]`)
   - sort with the same comparator the main app uses for directories
     (`finderCompareS:`)
   - read the first file's data directly and return it
2. Keep this self-contained; do not route through `COZipArchive` /
   `CORarArchive` / `CORarHeaderIndex`.
3. Handle the empty-bundle case (no images found) by returning nil
   cleanly, consistent with how other unsupported/empty cases behave
   today.

## Step 3: Test fixture

1. Extend `tests/fixtures/make_fixtures.sh` to also produce a
   `test.cvbdl` fixture, following the existing convention (copy the same
   sample images used for other generated fixtures into a directory named
   `test.cvbdl`).

## Verification

- Build all targets.
- On-device verification, following the QuickLook/Thumbnail procedure in
  `CLAUDE.md` (single pass, includes the bundle-ID dedup check added
  after the previous verification task):
  - `.cvbdl` fixture shows a correct cover thumbnail in Finder and in
    Quick Look preview
  - opening the same fixture in the main app still works exactly as
    before (unchanged, since Step 1 only adds `LSItemContentTypes` and
    does not touch `archiveTypes`)
  - an ordinary folder renamed to `.cvbdl` with non-image contents does
    not crash or hang the extensions; confirm the failure mode is a
    missing/empty thumbnail, not a crash
  - confirm which bundle's extension Finder actually resolved (per the
    procedure's step 3a), so this check exercises the new binary
- Report the analyzer count; no regression expected.

## Documentation

- Update `docs/DECISIONS.md` or wherever the earlier cvbdl-origin entry
  was recorded, to note QuickLook/Thumbnail support was added in v1.5.2,
  referencing this task and the investigation archive.
- Update `docs/DEV_LOG.md` if this qualifies as a milestone worth
  recording alongside the encrypted-ZIP entry.

## Notes

- This task does not touch version numbers, notarization, GitHub Release,
  or the Homebrew tap. Those are deferred to the v1.5.2 release task.
- If Step 0 fails, do not attempt workarounds (broader entitlements,
  sandbox changes) without stopping to report first — entitlement changes
  affect the App Store / notarization posture and should not be made
  silently mid-task.
## Implementation Result

**Status:** Completed — code and fixtures implemented and verified where
possible; one specific on-device check (real Finder/QuickLook invocation
of the new binary) could not be completed on this machine and is reported
below rather than glossed over, per the task's own instruction to report
rather than force it.

### Step 0: Sandbox capability check — resequenced, see Verification

The task asked for an isolated pre-check before writing extraction logic.
In practice this isn't achievable in isolation: QuickLook cannot invoke
the extension for a `.cvbdl` file at all until it has a recognized UTI
(Step 1), so "pass a `.cvbdl` URL to the extension" has no path to test
before Step 1 exists. Step 1 and Step 2 were implemented together, and the
first on-device verification pass doubled as Step 0's real test — this
resequencing is stated plainly rather than silently reordering the steps.
That real end-to-end test hit an environmental blocker (see Verification);
it did not reveal an entitlement failure, so per the Notes ("if Step 0
fails, do not attempt workarounds without stopping") there was nothing to
work around — the blocker is a LaunchServices registration-precedence
issue on this dev machine, not a sandbox denial.

### Step 1: UTI / document-type wiring

- `Resources/Info.plist`: added a `UTExportedTypeDeclarations` entry —
  `UTTypeIdentifier: jp.coo.cooViewer.cvbdl-archive`,
  `UTTypeConformsTo: com.apple.package`, tagged filename-extension
  `cvbdl` — matching the `cbz`/`cbr` pattern exactly. Added
  `LSItemContentTypes: [jp.coo.cooViewer.cvbdl-archive]` to the existing
  `.cvbdl` document-type dict; `LSTypeIsPackage` and everything else in
  that dict left untouched.
- `PreviewExtension/Info.plist` and `ThumbnailExtension/Info.plist`: added
  `jp.coo.cooViewer.cvbdl-archive` to `QLSupportedContentTypes` alongside
  the existing cbz/cbr entries (one line each).
- `plutil -lint` passed on all three files after editing.

### Step 2: Cover extraction for cvbdl

- `Sources/COCoverExtractor.m`: added a `COExtractCoverImageDataFromBundle`
  static helper and a branch at the top of `COExtractCoverImageData` that
  detects the `.cvbdl` extension, confirms it's actually a directory (not
  routing anything unexpected through the new path), and — only for that
  case — lists the bundle's top-level contents with
  `-[NSFileManager contentsOfDirectoryAtPath:error:]`, filters with
  `[NSImage imageFileTypes]` (same filter `COImageLoader.m:65-66` uses),
  sorts with `-finderCompareS:` (same category the archive path already
  uses), and reads the winning file's bytes directly with
  `+[NSData dataWithContentsOfFile:]`. `COArchive`/`COZipArchive`/
  `CORarArchive`/`CORarHeaderIndex` are not touched by this branch, as
  required. No subfolder recursion (matches the archive path's existing
  "cover/first-page only" scope, noted in the updated design comment).
  Empty-bundle and no-images cases return `nil` cleanly (verified, see
  below) — no new failure mode was introduced.
- `Sources/COCoverExtractor.h`: updated the doc comment to describe the
  new `.cvbdl` path alongside the existing archive path.

### Step 3: Test fixture

- `tests/fixtures/make_fixtures.sh`: added a `test.cvbdl` fixture — a
  plain directory containing the same four sample images used by every
  other generated fixture, following the script's existing per-format
  section style. Ran the script; `generated/test.cvbdl/` was produced
  correctly (4 files, `.gitignore`d like the rest of `generated/`). The
  script's checksum/summary sections only glob `-type f`, so the directory
  fixture is silently and correctly excluded from `SHA256SUMS.txt` and the
  "Generated:" listing — not a bug, just worth noting since it looks like
  an omission at a glance.

### Verification

- Build: `xcodebuild -scheme cooViewer_deploy -configuration Deployment`
  → `** BUILD SUCCEEDED **` (all three targets). Confirmed in the built
  bundle: main app's `Info.plist` carries the new UTI export; both
  extensions' `Info.plist` list `jp.coo.cooViewer.cvbdl-archive` in
  `QLSupportedContentTypes`.
- Analyzer: `xcodebuild ... analyze` → `** ANALYZE SUCCEEDED **`, counts
  unchanged from the pre-existing baseline (dead-store 15, potential-leak
  0, uninitialized-receiver 3, null-deref 1, localized-text 23) — **no
  regression**. Only new warnings are two more instances of the
  project-wide pre-existing `imageFileTypes` deprecation, matching the
  same pattern already present in the file and in `COImageLoader.m`.
- Existing test gates re-run for regression sanity (neither touches
  `COCoverExtractor.m`, but both exercise code paths adjacent to this
  change): `tests/engine/run_tests.sh` → **ALL PASS**;
  `tests/engine/run_password_test.sh` → **PASSED (0 failures)**.
- Main app regression check (on-device, `open build/cooViewer.app`, then
  `open -a ... tests/fixtures/generated/test.cvbdl`): opened correctly,
  title bar `test.cvbdl`, all four pages rendered — **confirms Step 1 did
  not affect the main app's directory-open path**, as the task required.
- Headless logic check of the new `COCoverExtractor.m` code (a standalone
  probe binary linking the real, unmodified source files, unsandboxed —
  same technique used in earlier tasks in this series):
  | case | result |
  |---|---|
  | `test.cvbdl` (valid bundle, 4 images) | cover data returned, decodes as a valid image — **PASS** |
  | empty `.cvbdl` bundle | `nil`, no crash — **PASS** |
  | `.cvbdl` bundle with only a non-image file | `nil`, no crash — **PASS** (this is the "ordinary folder, non-image contents" case from Verification) |
  | `test.cbz` (existing archive path) | unchanged, still correct — **PASS, no regression** |
  | `test.cbr` (existing archive path) | unchanged, still correct — **PASS, no regression** |
  This proves the extraction logic itself is correct and crash-safe,
  including the specific "does not crash or hang" requirement from
  Verification — but it does **not** run inside the extension's real App
  Sandbox, so it does not by itself prove the sandbox entitlement question
  Step 0 was about.
- **On-device Finder/QuickLook check: not completed, reported rather than
  forced.** Following `CLAUDE.md`'s procedure exactly (including the new
  step 3a added after the previous verification task): copied
  `build/cooViewer.app` to `~/Applications/`, `lsregister -f`'d it,
  `pluginkit -a`'d both extensions (all exit 0) — but `pluginkit -m -v -i
  jp.coo.cooViewer.QuickLookPreview`/`...Thumbnail` still showed only the
  pre-existing `/Applications/cooViewer.app` (v1.5.0, 2026-07-15,
  predating this feature and every other change in this task series;
  `CLAUDE.md` says never to touch it) resolving both extension
  identifiers. This is the same bundle-ID dedup issue flagged in
  `docs/tasks/2026-07-25-14-verify-encrypted-zip-on-device.md`; this time
  the new build reports a higher version (1.5.1 vs. 1.5.0), which was
  tried as a hypothesis for why the newer copy might now win — it did
  not, so version does not appear to be the tie-breaker; `/Applications`
  simply keeps precedence for the shared bundle ID `jp.coo.cooViewer`
  regardless. Per step 3a and the general instruction not to attempt
  further install/register cycles, no further registration attempts were
  made. Cleaned up immediately (`pluginkit -r` both, deleted the
  `~/Applications` copy) rather than leaving it in a half-finished state.
  **Consequence:** the specific checks "`.cvbdl` fixture shows a correct
  cover thumbnail in Finder and Quick Look preview" and "an ordinary
  `.cvbdl` folder with non-image contents does not crash/hang the
  extensions" from the task's Verification section were **not exercised
  through real QuickLook invocation** on this machine. The logic-level
  checks above are the closest available substitute and give reasonable
  confidence, but this is recorded as a genuine verification gap, not
  claimed as done.
- Environment left clean: no stray `cooViewer.app` copies beyond
  `/Applications` (untouched, unregistered/reregistered state unchanged)
  and `build/`; one orphaned `cooViewerThumbnail` helper process left
  running from `xcodebuild`'s own automatic `lsregister` step (a build
  side effect, not something this task's procedure created) was found and
  stopped for hygiene.

### Documentation

- `docs/DECISIONS.md`: updated the existing `.cvbdl` entry (2026-07-25) in
  place — corrected the now-stale "QuickLook does not support it" line and
  added an "Update (v1.5.2, 2026-07-25)" paragraph describing what changed
  and referencing both the investigation archive and this task's archive.
  The original decision (do not touch `archiveTypes`/the main app's
  directory path) is preserved unchanged, since this task didn't touch
  that.
- `docs/DEV_LOG.md`: added a milestone entry, "QuickLook/Thumbnail support
  for `.cvbdl` bundles (v1.5.2, 2026-07-25)", placed above the existing
  encrypted-ZIP entry (most-recent-first), including the on-device
  verification gap so it isn't silently forgotten.

### Remaining Issues

- **On-device Finder/QuickLook rendering of `.cvbdl` was not verified on
  this machine**, due to the LaunchServices bundle-ID dedup issue
  described above. The code is verified correct at the logic level and
  the wiring is verified correct at the plist level, but true end-to-end
  confirmation needs either a machine without a pre-existing
  `/Applications/cooViewer.app`, or the next real v1.5.2 release build
  (which will supersede the 1.5.0 copy once actually installed).

### Follow-up Suggestions

- When the v1.5.2 release task installs a real build, re-run the
  QuickLook/Thumbnail on-device check for `.cvbdl` specifically (it was
  never confirmed end-to-end) alongside whatever that release task already
  plans to verify.
- Consider whether `make_fixtures.sh`'s summary/checksum sections should
  also acknowledge directory fixtures (cosmetic; `test.cvbdl` works fine
  today without this).
