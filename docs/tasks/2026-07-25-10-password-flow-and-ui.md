# TASK: Restore password flow and add password-entry UI for encrypted ZIP

## Scope

Restore end-to-end password handling for encrypted ZIP archives, building on
the crypto-enabled libzip (task 08) and the COZipArchive password support
(task 09). Two connected parts:

- Part A: thread the password through COArchive / COImageLoader so the
  reader's `setPassword:` / `cryptoStatus` are reachable from the open flow.
- Part B: prompt the user for a password with a modal dialog when an
  encrypted archive is opened, re-prompting on a wrong password.

ZIP only. Encrypted RAR remains out of scope and must still fail cleanly
with the existing "not supported" behaviour.

## Part A: Password flow

1. Raise `setPassword:` and a crypto-status accessor from `COZipArchive` to
   the `COArchive` surface so the open path can supply a password and read
   back whether one is needed / wrong / accepted. Keep RAR's path returning
   its existing unsupported state.
2. In `COImageLoader`, at the existing `crypted` detection point in
   `checkArchiveContainer:` (currently sets `mode=-1; return NO`), branch
   instead into a password-request path when the archive is an encrypted
   ZIP. Preserve the old fail-closed behaviour for encrypted RAR and for the
   case where the user cancels.
3. Reuse the old design as a template where useful (a `password` ivar, a
   check/loop analogous to the old `checkPassword`), but implemented against
   the current COArchive/COZipArchive, not XADMaster.

## Part B: Password-entry UI

1. Add a controller method analogous to the old `askInArchivePassword:` that
   presents a modal password prompt. Implement it in code with `NSAlert`
   plus an `NSSecureTextField` accessory view — do not add a NIB/XIB panel.
2. Behaviour:
   - modal, blocking the open of that document until answered
   - OK submits the password; Cancel aborts opening the archive
   - on a wrong password (COZipArchive reports WrongPassword), re-present
     the prompt, optionally indicating the previous attempt was incorrect
   - on no password / Cancel, fall back to the existing closed behaviour
     (document does not open its contents; no crash)
3. Use `NSSecureTextField` (masked), not a plain text field.
4. Localize the prompt strings through the existing localization mechanism
   (there are already 23 "should use localized string" analyzer notes;
   follow the project's existing approach for user-facing text — do not
   introduce hardcoded English if the project localizes elsewhere).

## QuickLook / Thumbnail extensions

- The Preview and Thumbnail extensions must not prompt for a password (they
  run in a non-interactive sandbox). For an encrypted archive, they should
  not attempt to read contents: detect `crypted` and return no
  preview/thumbnail, letting Finder show the default document icon.
- If the extensions share the archive-reading code, confirm the encrypted
  case returns cleanly there without requiring a password. Report whether
  the detection is shared or needs a guard added on the extension side.

## Verification

- Build all targets.
- Manual, main app:
  - open an encrypted ZIP fixture → prompt appears → correct password opens
    and displays pages
  - wrong password → re-prompt; repeated wrong → still no crash; Cancel →
    archive does not open, app stable
  - open a non-encrypted archive → no prompt, opens as before
  - open an encrypted RAR → existing unsupported behaviour, no prompt, no
    crash
- Non-ASCII password: test at least one Japanese-password encrypted ZIP
  created with UTF-8, and report whether it opens. This is the case the
  original could not handle; record the result either way.
- Extensions: confirm an encrypted archive yields the default icon with no
  hang or crash in Finder/QuickLook, following `CLAUDE.md` on registration.
- Report the analyzer count; no regression.

## Documentation

- Update `docs/KNOWN_ISSUES.md` #16: correct the earlier G4 note. Record
  that `GlobalKeyboardDevice` is unused (never instantiated) while
  `AppleRemote` is a live, UI-exposed feature (Preferences ▸ Input ▸
  Keyboard & AppleRemote), and that removing the RemoteControlWrapper
  library as a whole is declined on settings-compatibility grounds. This
  supersedes the "optional tidy-up" framing.
- Update `docs/DEV_LOG.md`: password-protected ZIP support restored is a
  meaningful user-visible milestone; record it once this task completes.
- Note in the implementation result whether the Japanese-password case
  works, so the original's known limitation can be revisited in the README
  rewrite later.
- Do not update `README.md` in this task.

## Notes

- Cancelling the prompt must never leave a half-open document or a crash.
- Do not weaken the encrypted-RAR path; it must still fail closed.
- Re-prompting must have a clear exit (Cancel), not an infinite loop with no
  escape.
- Follow `CLAUDE.md` on installing/registering builds when exercising the
  extensions; a single launch for verification is fine, avoid repeated
  install/register cycles (KNOWN_ISSUES #15).
## Implementation Result

**Status:** Completed

### Changes

**Part A — password flow**

- `Sources/COArchive.h/.m`: raised the crypto API to the base class. Added
  `COArchiveCryptoStatus` (`None` / `NeedsPassword` / `WrongPassword` /
  `OK` / **`Unsupported`**) and `-setPassword:` / `-cryptoStatus`. The base
  (libarchive) implementation cannot decrypt: `-setPassword:` is a no-op
  and `-cryptoStatus` returns `Unsupported` whenever `crypted` is set.
  **CORarArchive inherits this deliberately**, so encrypted RAR keeps its
  existing fail-closed behaviour.
- `Sources/COZipArchive.h/.m`: the reader-local `COZipCryptoStatus` enum was
  replaced by the shared `COArchiveCryptoStatus` (same case semantics);
  `-setPassword:` / `-cryptoStatus` are now overrides of the COArchive
  declarations. Reader logic itself is unchanged from task 09.
- `Sources/COImageLoader.h/.m`: added a `password` ivar (+ `-password`
  accessor, released in `-dealloc`) and a private `-unlockEncryptedArchive`.
  At the existing detection point in `-checkArchiveContainer:` the loader no
  longer fails immediately: it calls `-unlockEncryptedArchive`, and only
  sets `mode = -1; return NO` when that returns NO. Unlocking returns NO for
  a non-`NeedsPassword` status (encrypted RAR → `Unsupported`), for a host
  with no prompt available, and on Cancel — i.e. every previously-closed
  case stays closed. It first retries any password already accepted for the
  loader, then loops on the prompt, passing `wrongPassword:YES` after a
  rejection; the loop exits on Cancel (nil) or on any status other than
  `WrongPassword`.

**Part B — password-entry UI**

- `Sources/Controller.h/.m`: added
  `-askArchivePassword:wrongPassword:`, built in code with `NSAlert` plus an
  `NSSecureTextField` accessory view (**no NIB/XIB**), first responder set to
  the field. Message text switches between "Password required" and
  "Incorrect password"; informative text names the document. Returns the
  entered password, or nil for Cancel — and also for an empty entry, so
  pressing OK on a blank field cannot spin the caller's retry loop.
- Localization: strings go through the project's existing
  `NSLocalizedString` mechanism. Added "Password required", "Incorrect
  password", and `Enter the password for "%@".` to
  `Resources/en.lproj/Localizable.strings` (UTF-16LE, encoding preserved)
  and `Resources/ja.lproj/Localizable.strings` (UTF-8) with Japanese
  translations. Both files still pass `plutil -lint`.

**QuickLook / Thumbnail extensions — no guard needed (shared detection)**

Confirmed from `project.pbxproj`: both extension targets compile
`COArchive.m`, `COZipArchive.m`, `CORarArchive.m`, `CORarHeaderIndex.m`,
`COCoverExtractor.m`, `NSString_Compare.m` — **neither links `COImageLoader`
nor `Controller`**, so the prompt path does not exist in the extensions by
construction. `COCoverExtractor` never calls `-setPassword:`, so an
encrypted archive keeps `NeedsPassword` (or `Unsupported`), reports
`lastError` with zero entries, and `COExtractCoverImageData` returns nil at
its existing `lastError || itemCount == 0` check — the providers then fall
back to the default icon. Detection is shared; **no extension-side guard was
added**.

### Verification

- Build: all targets, `xcodebuild -scheme cooViewer_deploy -configuration
  Deployment` → `** BUILD SUCCEEDED **` (and `ANALYZE SUCCEEDED` for the
  analyzer run).
- Analyzer: **no regression** — dead-store 15, potential-leak 0,
  uninitialized-receiver 3, null-deref 1, localized-text 23, identical to
  the pre-change baseline. No new compiler warnings in the touched files.
- Test gates, both re-run after the change: COZipArchive password gate
  (`tests/engine/run_password_test.sh`) **PASSED (0 failures)**; engine gate
  (`tests/engine/run_tests.sh`) **ALL PASS** (non-encrypted zip/cbz/tar/7z/
  cbr, UTF-8/CP932 names, corrupt handling, backward navigation).
- Headless flow check against real fixtures (COArchive API + the QuickLook
  cover path), all as expected:
  | fixture | status before | after correct pw | cover path |
  |---|---|---|---|
  | `enc_aes.cbz` (AES-256) | NeedsPassword, 0 items | OK, 4 items, image data | nil |
  | `enc_aes.cbz` + wrong pw | — | WrongPassword, 0 items | nil |
  | `enc_trad.cbz` (`zip -e`) | NeedsPassword | OK, 4 items | nil |
  | `enc_aes_jp.cbz` (Japanese pw) | NeedsPassword | **OK, 4 items** | nil |
  | `enc_jp.cbz` (Japanese pw, traditional) | NeedsPassword | **OK, 4 items** | nil |
  | `enc.cbr` (encrypted RAR) | **Unsupported** | still Unsupported (setPassword no-op) | nil |
  | `test.cbz` (plain) | None, 4 items | — | 127364 bytes |
- Manual, main app (staged `build/cooViewer.app`, single launch):
  - encrypted `.cbz` → prompt appears ("Password required", masked field)
  - **wrong password → re-prompt titled "Incorrect password"** with the field
    cleared; no crash
  - correct password → document opens, title becomes `enc_aes.cbz`, pages
    render
  - **Cancel → prompt dismissed, no half-open document, app stable**
  - **Japanese password (`ぱすわーど日本語`) → opens and displays pages**
  - encrypted RAR → **no prompt**, existing unsupported behaviour, no crash
  - plain archive (`test_utf8.zip`) → **no prompt**, opens as before

### Non-ASCII password result (recorded for the README rewrite)

**Japanese passwords work.** Both AES-256 and traditional ZipCrypto archives
whose password is UTF-8 Japanese open correctly, verified headlessly and in
the GUI. The password crosses the libzip boundary as NUL-terminated UTF-8
(`-UTF8String` → `zip_set_default_password`), so it matches archives written
with UTF-8 passwords byte-for-byte. This is the case the original XADMaster-
based implementation was known not to handle.

### Could not verify at runtime

**Live QuickLook/Finder rendering of an encrypted archive was not
exercised.** The registered extension on this machine is
`/Applications/cooViewer.app`'s (v1.5.0, 2026-07-15) — the *old* build,
without these changes or the crypto-enabled libzip — and `qlmanage -t` hangs
in this environment **even for a plain, non-encrypted archive**, so it
reports nothing about encryption either way. Installing and registering the
new build to test would risk the LaunchServices/QuickLook breakage recorded
in KNOWN_ISSUES #15 (previously only resolved by an OS restart), which
`CLAUDE.md` tells us to avoid. The extension behaviour is instead established
at the code-path level, which is precise here: the providers cannot prompt
(neither `COImageLoader` nor `Controller` is linked into them) and
`COExtractCoverImageData` returns nil for every encrypted fixture — verified
directly, see the table above.

### Documentation

- `docs/KNOWN_ISSUES.md` #16: corrected the G4 note (the "optional tidy-up"
  framing is superseded — leave `COImageLoader.m:82` alone) and added a
  RemoteControlWrapper subsection recording that `GlobalKeyboardDevice` is
  never instantiated while `AppleRemote` is live and exposed in
  Preferences ▸ Input as assignable keys, and that removing the library as a
  whole is **declined** on settings-compatibility grounds.
- `docs/DEV_LOG.md`: added the milestone entry for restored
  password-protected ZIP support, including the working non-ASCII password
  result and the unchanged encrypted-RAR limitation.
- `README.md`: not modified (per scope).

### Remaining Issues

None for ZIP. Encrypted RAR stays unsupported by design (libarchive cannot
decrypt it); revisiting it means choosing another library, which is a
separate decision.

### Follow-up Suggestions

- The README rewrite can now state that password-protected ZIP works,
  including non-ASCII (Japanese) passwords, and that RAR does not.
- Optional: remember an accepted password per document (or offer Keychain
  storage) so reopening a recently-read encrypted archive does not prompt
  again. Deliberately out of scope here.
