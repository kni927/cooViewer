# TASK: Release v1.6.1 (multi-window close crash hotfix + dSYM in CI)

## Scope

Ship v1.6.1. **Two changes only:**

1. Already committed locally — the multi-window close crash fix (`e25feba`; archive
   `docs/tasks/2026-07-30-08-fix-multiwindow-close-crash.md`).
2. New in this task — add `.dSYM` upload to
   `.github/workflows/xcode-build-and-release.yml`.

Everything else is out of scope. In particular, do **not** touch the
"new window inherits the front window's size" behaviour — that is a separate
investigation task targeting v1.6.2. If you find another bug while working,
report it in the archive; do not fix it here.

Users currently on v1.6.0 are exposed to a reproducible crash, so this is a
hotfix: minimise surface area, do not refactor.

## Reporting rules (read before starting)

- **Never mark a step done without pasting the actual command output.** A
  procedure is not a result. If a step cannot be run, say so explicitly and
  say why.
- Where a claim is about behaviour, **measure it rather than reading the code
  and inferring**. The last three tasks on this project each had their stated
  premise overturned by measurement.
- If you make a mistake mid-task, report it rather than silently redoing it.

## Release path (do not improvise)

cooViewer **notarizes in CI, never locally.** Pushing a `v*` tag triggers
`.github/workflows/xcode-build-and-release.yml`, which builds, signs,
notarizes with `xcrun notarytool` using the three already-registered secrets
(`APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_KEY_ID`,
`APP_STORE_CONNECT_PRIVATE_KEY`), staples, and uploads the release asset via
`softprops/action-gh-release@v3`. A locally signed build is a dry run only,
never the artifact to ship.

The authoritative procedural precedent is
`docs/tasks/2026-07-26-02-release-v1.5.2.md` — follow its six-step sequence.
Read it before starting.

`brew uninstall` is the one sanctioned exception to the never-touch-
`/Applications` rule, and exists only to make room for the release artifact;
the tap update restores Homebrew management afterwards.

---

## Step 0 — Pre-flight

- Working tree clean, on `main`, `e25feba` present in history.
- `git tag -l` shows nothing above `v1.6.0`.
- No version bump has been made yet.
- Paste the output of `git log --oneline -5` and `git tag -l 'v1.6*'`.

## Step 1 — dSYM upload in CI

Why: the v1.6.0 field crash could not be symbolicated. `atos` against the
shipped, stripped binary fails and CI does not archive the `.dSYM`.

1. Confirm `DEBUG_INFORMATION_FORMAT` for the **Deployment** configuration is
   `dwarf-with-dsym`. If it is not, set it and report the change.
2. Determine where `xcodebuild` actually writes `cooViewer.app.dSYM` with the
   repo's `-derivedDataPath ./build` convention. Paste the path you found.
3. Zip it as `cooViewer-<tag>.dSYM.zip` and add it to the same
   `softprops/action-gh-release@v3` `files:` list as the app zip.
4. **Decision to record:** the repo convention is that `build/` holds only the
   final app. If the `.dSYM` now lands in `build/`, either zip it from
   elsewhere or amend the convention explicitly in `docs/DECISIONS.md`. Do not
   leave the contradiction unrecorded.
5. Confirm the Homebrew formula references only `cooViewer-<tag>.zip`, so an
   additional release asset cannot break it. Paste the relevant formula lines.
6. Paste the workflow diff.

## Step 2 — Version bump

- Find **every** place the version string appears (`Info.plist`
  `CFBundleShortVersionString` / `CFBundleVersion`, any `MARKETING_VERSION` /
  `CURRENT_PROJECT_VERSION` in the Xcode project, extension `Info.plist`s).
  List them all before editing.
- Bump to `1.6.1`. Paste the diff.

## Step 3 — Local dry-run build (gate)

Same-session clean build. Report:

- `** BUILD SUCCEEDED **`
- Warning count against the established baseline of **312** (310 source + 2
  "not stripping binary"). If it differs, diff the warning sets with the build
  path normalised out, and explain every line of difference before proceeding.
- `build/` contents (see the Step 1 decision).

## Step 4 — Tag and let CI release

- Push tag `v1.6.1`.
- Watch the run. Paste the run URL, duration, and per-step status.
- Confirm notarization was **accepted** and the artifact **stapled**.
- Confirm the GitHub Release exists with **both** assets. Record the SHA-256 of
  `cooViewer-v1.6.1.zip`.
- There has been a harmless, non-blocking error appearing in past workflow
  runs. Check whether the `action-gh-release@v3` bump already cleared it. If it
  is gone, say so with evidence from the v1.6.1 run log. If it is still there,
  diagnose it and report — do not fix it in this task unless it blocks the
  release.

## Step 5 — On-device verification against the real artifact

The fix task explicitly left this undone; it is required here, **before** the
tap update.

1. Download the release zip. Verify its SHA-256 matches the recorded value.
2. Gatekeeper/notarization checks on the downloaded artifact:
   `spctl -a -vv` and `stapler validate`. Paste both outputs.
3. **dSYM correctness check (the real test that the dSYM is usable):** compare
   the UUID of the shipped app binary against the UUID in the shipped dSYM.
   ```
   dwarfdump --uuid cooViewer.app/Contents/MacOS/cooViewer
   dwarfdump --uuid cooViewer.app.dSYM
   ```
   They must match. Then confirm `atos -o <dSYM>/Contents/Resources/DWARF/cooViewer`
   resolves a known symbol. Paste both.
4. **Reproduce the original crash scenario on the notarized artifact.** With
   `PageBarAutoHide` and `PageNumAutoHide` on (both are `1` in the owner's
   profile), open two books, hover the front window, then Cmd+W within the 2 s
   `accessoryTimer` window. Run 3 cycles. Expected: no crash, and **no new
   entries in `~/Library/Logs/DiagnosticReports`**. Paste the directory listing
   before and after.
   Note: `NSZombieEnabled` is not usable here — this launch is the real
   hardened-runtime artifact via Finder/LaunchServices. Absence of a crash
   report is the check at this stage; the zombie evidence already exists from
   the fix task.
5. Sanity: version string correct, a book opens, QuickLook/Thumbnail
   extensions resolve to the v1.6.1 bundle.

## Step 6 — Homebrew tap

Per the v1.5.2 precedent: update version, URL and sha256 in the tap formula,
then confirm a **fresh install** resolves, launches, is Gatekeeper-clean,
reports the correct version, and that the extensions resolve to the v1.6.1
bundle. Paste each confirmation.

## Step 7 — Docs and archive

- Update `docs/KNOWN_ISSUES.md` if the release changes any entry's status.
- Record the Step 1 `build/` decision in `docs/DECISIONS.md`.
- Archive this task to `docs/tasks/YYYY-MM-DD-NN-release-v1.6.1.md` **with the
  raw command output**, not a summary of it.

## Release notes

Single line, user-facing:

> Fixed a crash when closing one of several open windows.

(Japanese, if the release notes carry both: 複数ウィンドウを開いた状態で1つを閉じるとクラッシュする問題を修正しました。)

## Not in scope / carry-over

- New window size inheritance → separate v1.6.2 investigation task.
- `CustomImageView`'s `target` ivar — same unretained back-reference shape,
  recorded in KNOWN_ISSUES #36 as *not verified safe*. Leave it.
- The wider audit of per-window classes for the same shape, now that the rule
  is in `DECISIONS.md`.
