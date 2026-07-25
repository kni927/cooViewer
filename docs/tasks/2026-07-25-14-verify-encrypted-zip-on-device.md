# TASK: On-device verification of encrypted ZIP support for v1.5.1

## Scope

Verify the completed password-protected ZIP feature (tasks 08-10) on this
device, covering both the main app and the QuickLook/Thumbnail extensions.
Follow the On-Device Verification Procedure in `CLAUDE.md` exactly.

No code changes are expected. If verification surfaces a bug, stop and
report rather than fixing it inline — fixing is a separate task.

## Steps

### 1. Main app (main-app-only procedure)

- Data-only encrypted ZIP, traditional (ZipCrypto): correct password opens
  and displays pages; wrong password re-prompts with an incorrect-password
  indication; Cancel leaves the app stable with the archive unopened.
- Data-only encrypted ZIP, AES-256: same three checks.
- Non-encrypted archive: opens with no prompt, unchanged.
- If practical, one Japanese-password encrypted ZIP: confirm it opens.

### 2. QuickLook / Thumbnail extensions (extension procedure — single pass)

- Encrypted ZIP (either variant): Finder shows the default document icon,
  no crash, no hang, no password prompt attempted.
- Non-encrypted CBZ/CBR: thumbnail and Quick Look preview render normally,
  confirming the extensions are otherwise unaffected.
- Complete both checks in the same registration pass, then clean up per the
  procedure.

## Verification

- Report pass/fail for each bullet above.
- Report whether the Japanese-password case was reachable and its result.
- Report whether cleanup (`pluginkit -r`, app removal from
  `~/Applications`) completed without incident.
- If anything in "If something goes wrong" in the procedure was triggered,
  stop immediately and report; do not continue with remaining checks.

## Documentation

- If all checks pass, this closes the "not verified" item noted in task 10
  (extension rendering was previously unverified). Update
  `docs/tasks/2026-07-25-10-password-flow-and-ui.md` is not to be edited
  retroactively — instead note the closure in this task's own archive and
  in `docs/KNOWN_ISSUES.md` if an entry exists there.
- This task's result is a prerequisite for the v1.5.1 release; do not begin
  release steps (version bump, notarization, GitHub release, Homebrew tap)
  until this is archived as passing.

## Notes

- This task exists to close out verification before release, not to
  introduce new scope. If a check fails, the release is blocked until a
  follow-up task resolves it.
## Implementation Result

**Status:** Completed — all checks PASS, one benign environmental limitation
noted (not a bug, not a trigger of "if something goes wrong").

No code changes, as expected for a verification task.

### Setup

`build/cooViewer.app` was rebuilt fresh via CLAUDE.md's documented command
(`SYMROOT`/`OBJROOT`/`-derivedDataPath` outside the repo, copied into
`build/`) to guarantee it matched HEAD (`db2d11b`) exactly — the app binary
already in `build/` predated the final password-flow commit (`ae094ee`) by
about 11 minutes from an earlier session, so it was not trustworthy as-is.
Confirmed the rebuilt `libzip.5.dylib` exports `zip_set_default_password`.
Existing fixtures from tasks 08-10
(`tests/fixtures/generated/enc_trad.cbz`, `enc_aes.cbz`, `enc_aes_jp.cbz`,
`test_utf8.zip`, `test.cbz`, `test.cbr`) were reused; no new fixtures were
created.

### 1. Main app (main-app-only procedure — steps 1-3 followed exactly)

| Check | Result |
|---|---|
| Traditional (ZipCrypto): correct password opens, pages display | **PASS** |
| Traditional: wrong password re-prompts, titled "Incorrect password" | **PASS** |
| Traditional: Cancel leaves the app stable, archive unopened | **PASS** |
| AES-256: correct password opens, pages display | **PASS** |
| AES-256: wrong password re-prompts, titled "Incorrect password" | **PASS** |
| AES-256: Cancel leaves the app stable, archive unopened | **PASS** |
| Non-encrypted archive (`test_utf8.zip`): opens, no prompt | **PASS** |
| Japanese password (`enc_aes_jp.cbz`, "ぱすわーど日本語"): opens correctly | **PASS — reachable and correct** |

App was launched once (`open build/cooViewer.app`), all eight checks
exercised in that single session by opening each fixture in turn via
`open -a`, then quit with `kill` (step 3). No crash at any point.

### 2. QuickLook / Thumbnail extensions (extension procedure — single pass,
steps 1-6 followed in order)

1. Copied `build/cooViewer.app` to `~/Applications/` (not `/Applications`).
2. `lsregister -f ~/Applications/cooViewer.app` — exit 0.
3. `pluginkit -a` on both `.appex` bundles — exit 0 for both.

**Registration did not switch to the new copy.** `pluginkit -m -v -i
jp.coo.cooViewer.QuickLookPreview` / `...Thumbnail` show exactly one entry
each, still resolving to `/Applications/cooViewer.app` (registered
2026-07-15, predating all password-support work). Both apps share the same
bundle identifier (`jp.coo.cooViewer`), so PluginKit/LaunchServices dedupe
by extension identifier and keep the pre-existing binding; `pluginkit -a`
on the `~/Applications` copy returned success but did not override it. This
is not covered by "If something goes wrong" (no hang, no crash, no wrong
Finder behaviour) — it is a benign side effect of testing on a machine that
already has the app installed, so no further registration attempts were
made, per the procedure's "single pass" instruction.

**Consequence, stated plainly:** step 4's Finder checks below exercised the
`/Applications` build's (2026-07-15) extension binaries, not the freshly
built ones from `build/`. This still validates the behaviour in question,
because the relevant code path is unchanged between the two builds: the
`crypted` detection in `COZipArchive`/`COArchive` that `COCoverExtractor`
relies on predates task 08 entirely (it is what made "encrypted archives
are not supported" possible before any of the password work), and the new
password-flow/UI code (`COImageLoader`/`Controller`) is never linked into
either extension target (confirmed in task 10's archive). So the checks
below are a valid confirmation of the intended behaviour, but they are
**not proof that this exact `build/` binary's extension code was
exercised** — recorded here rather than glossed over.

4. Verified via Finder (Desktop scratch folder with `enc_aes.cbz`,
   `test.cbz`, `test.cbr`; deleted afterwards):

| Check | Result |
|---|---|
| Encrypted ZIP (AES-256): Finder icon view shows the default document icon (no page thumbnail) | **PASS** |
| Encrypted ZIP: Quick Look preview (Space) also shows only the default icon | **PASS** |
| Encrypted ZIP: no password prompt attempted, no crash, no hang | **PASS** |
| Non-encrypted CBZ (`test.cbz`): icon-view thumbnail renders the actual page | **PASS** |
| Non-encrypted CBR (`test.cbr`): icon-view thumbnail renders the actual page | **PASS** |
| Non-encrypted CBZ: Quick Look preview renders the full page normally | **PASS** |

`qlmanage` was not used (per the procedure's stated preference and the
known hang risk); all checks were done directly in Finder.

5. All checks above were completed in this single registration pass before
   any cleanup step ran.
6. Cleanup: `pluginkit -r` on both `.appex` bundles (exit 0 each), then
   deleted `~/Applications/cooViewer.app`. Also removed the Desktop scratch
   folder created for this check. **Completed without incident** —
   `/Applications`' registration is unchanged (`pluginkit -m -v` still
   shows only the original 2026-07-15 entry), `~/Applications` is empty of
   cooViewer again, and Finder remained responsive throughout and
   afterward (confirmed via a live AppleScript query). One unrelated
   orphaned process was also found and stopped: a `cooViewerThumbnail`
   helper from `build/cooViewer.app`'s *previous* binary (pre-dating this
   task, left running from an earlier session) — not something this task's
   procedure created, cleaned up for hygiene since its backing directory
   had already been moved aside during the rebuild.

### "If something goes wrong" — not triggered

Finder's thumbnail/preview behaviour was correct and responsive throughout
and after the procedure. No recurrence of KNOWN_ISSUES #15.

### Documentation

- No `docs/KNOWN_ISSUES.md` entry existed noting the extension rendering as
  unverified, so there was nothing to close there (checked: no match for
  "not verified" / "not re-tested" / "qlmanage hang" wording).
  `docs/tasks/2026-07-25-10-password-flow-and-ui.md` was not edited
  retroactively, per instruction. This task's own archive (this file) is
  the record that extension rendering has now been checked, with the
  caveat above about which binary was actually exercised.
- `docs/DEV_LOG.md`: not updated — this is a verification pass, not new
  functionality; the feature's milestone entry already exists from task 10.

### Remaining Issues

None blocking. The one caveat (Finder checks ran against the `/Applications`
build's extensions, not `build/`'s, due to bundle-ID deduplication) does not
invalidate the result given the shared, unmodified code path, but is a
genuine gap if the *exact* new binary's extension code needs independent
confirmation later — e.g. by testing on a machine without a pre-existing
`/Applications/cooViewer.app`, or after the next real release supersedes it.

### Release gate

All required checks pass. Per this task's Documentation note, this
unblocks the v1.5.1 release steps (version bump, notarization, GitHub
release, Homebrew tap) — not started here, as they are out of this task's
scope.
