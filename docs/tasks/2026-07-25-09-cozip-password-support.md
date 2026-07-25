# TASK: Wire password support into COZipArchive

## Scope

Add password handling to `COZipArchive` so encrypted ZIP entries can be
decrypted, using the crypto-enabled libzip built in the previous task.

This task covers the ZIP reader layer only. The COImageLoader / COArchive
password flow and the password-entry UI are separate later tasks. Encrypted
RAR remains out of scope.

## Approach

Use `zip_set_default_password` on the open `zip_t` handle, then read entries
with the existing `zip_fopen_index` path. This keeps the change minimal:
encrypted and non-encrypted entries are read through the same code once the
password is set. Only fall back to per-entry `zip_fopen_index_encrypted` if
the default-password approach proves insufficient; if so, report why before
diverging.

## Steps

1. Add a way to supply a password to `COZipArchive` — a `setPassword:`
   method or an initializer parameter, consistent with how `COArchive`
   constructs its readers today. Do not yet change `COArchive`'s public
   signature beyond what is needed to pass a password through; keep the
   surface minimal and note what the next task will extend.
2. When a password is set, call `zip_set_default_password` on the `zip_t`
   handle after `zip_open`.
3. Keep the existing `crypted` detection
   (`st.encryption_method != ZIP_EM_NONE`). With a password set, encrypted
   entries should now open and read rather than being skipped. Without a
   password, preserve the current behaviour (report `crypted`, do not
   crash).
4. Distinguish the two failure modes explicitly and surface them via the
   existing error channel (`lastError`):
   - no password supplied for an encrypted archive
   - wrong password supplied (libzip returns a specific error;
     `ZIP_ER_WRONGPASSWD` / `ZIP_ER_NOPASSWD`)
   The next task and the UI depend on telling these apart, so they must be
   separable, not a single generic error.
5. Do not change how non-encrypted archives are read. Verify that path is
   byte-for-byte unaffected.

## Verification

- Build all targets.
- Extend the existing standalone test (or add one) at the COZipArchive
  level if it can be exercised without the full app; otherwise verify
  through a temporary test harness and report how.
- Confirm with encrypted fixtures:
  - correct password: entries read and content matches
  - wrong password: distinguishable error, no crash, no garbage
  - no password: existing crypted-skip behaviour, no crash
- Confirm non-encrypted archives (existing cbz fixtures) still open and read
  identically.
- Report the analyzer count; it must not regress.

## Documentation

- Update `docs/DEV_LOG.md` only if this is a meaningful milestone; the
  feature is not user-visible until the flow and UI land, so a DEV_LOG entry
  may be premature. Use judgement.
- Do not update `README.md`.

## Notes

- The password may contain non-ASCII bytes. Pass it to libzip as UTF-8
  bytes and report how the string is encoded at the boundary, since the old
  XADMaster path and libzip may differ here.
- This task does not add UI and does not read a password from the user. It
  only makes COZipArchive capable of using one that is passed in. Tests
  supply the password directly.
- Keep the change reviewable; encrypted-archive support should be additive
  to the reader, not a rewrite of it.
## Implementation Result

**Status:** Completed

### Changes

Additive password support in the ZIP reader; the non-encrypted path is
unchanged.

- `Sources/COZipArchive.h`: added the `COZipCryptoStatus` enum
  (`None` / `NeedsPassword` / `WrongPassword` / `OK`), a `password` /
  `cryptoStatus` / `firstEncIndex` / `firstEncSize` ivar set, and
  `-setPassword:` + `-cryptoStatus`. Updated the design comment.
- `Sources/COZipArchive.m`:
  - `readCentralDirectory` now, after `zip_open`, applies the password with
    `zip_set_default_password` (when set) and delegates entry collection to
    a new re-runnable `-scanEntriesAndClassify`.
  - `-scanEntriesAndClassify` collects usable entries with a per-entry
    encrypted flag. Encrypted entries set `crypted`; they are included only
    when a password is present AND validated. It then classifies:
    no encrypted → `None`; encrypted + no password → `NeedsPassword`;
    encrypted + password → validated result. `lastError` is set distinctly
    for the two password states ("password required for encrypted archive"
    vs "wrong password"), separate from the generic errors, so the flow/UI
    can tell them apart.
  - `-validatePasswordForIndex:size:` test-reads the first encrypted entry:
    traditional PKWARE is rejected at `zip_fopen_index`; WinZip AES fails its
    HMAC only at EOF, so the entry is read in full plus one byte. It maps
    `ZIP_ER_WRONGPASSWD`/`ZIP_ER_NOPASSWD` to `WrongPassword` and treats any
    other failure as OK (read-time handles corruption).
  - `-setPassword:` stores the password (`copy`, MRC), calls
    `zip_set_default_password`, and re-scans.
  - The existing `crypted` detection and lazy `zip_fopen_index` read path
    are unchanged; encrypted entries are read through the same path once the
    default password is set.
- `COArchive`'s public signature was not changed; the reader is reached via
  the existing dispatch (`initWithPath:` returns the COZipArchive), so the
  next task can lift `setPassword:`/`cryptoStatus` to the COArchive surface
  and wire the COImageLoader flow.

**Password encoding at the boundary:** the `NSString` password is passed to
libzip as NUL-terminated **UTF-8** bytes via `-UTF8String`
(`zip_set_default_password` takes a `const char *`). This is the correct and
only sensible encoding for a C-string API; non-ASCII passwords are therefore
matched byte-for-byte against archives whose password was also UTF-8 (the
common modern case). A password containing an embedded NUL cannot be
represented in this C-string API — an inherent libzip limitation, not
specific to this change.

### Verification

- Build: `xcodebuild -scheme cooViewer -configuration Deployment` →
  `** ANALYZE SUCCEEDED **` (full build). Analyzer counts unchanged
  (dead-store 15, potential-leak 0, uninitialized-receiver 3, null-deref 1,
  localized 23) — no regression; no new warnings in COZipArchive.m.
- New COZipArchive-level test (`tests/engine/test_zip_password.m` +
  `run_password_test.sh`): **PASSED (0 failures)** — for AES-256 and
  traditional PKWARE fixtures: no-password → `NeedsPassword` + no entries +
  lastError; wrong password → `WrongPassword` + no readable entries +
  lastError, no crash/garbage; correct password → `OK` + entry present +
  decrypted content matches. A non-encrypted `plain.zip` → `None`, entry
  read, content matches, lastError nil.
- Non-encrypted regression: existing engine gate
  (`tests/engine/run_tests.sh`) **ALL PASS** — zip/cbz/tar/7z/cbr, UTF-8 and
  CP932 names, corrupt/truncated handling, and backward navigation all read
  identically after the change.

### Remaining Issues

None. ZIP only; encrypted RAR remains out of scope (libarchive limitation).

### Follow-up Suggestions

- Next task: lift `setPassword:` / `cryptoStatus` to the `COArchive`
  surface (or a small protocol), reinstate the password flow in
  `COImageLoader`/`COArchive` (trigger where `crypted` is detected), and add
  the password-entry UI. The reader now distinguishes needs-password from
  wrong-password, which the UI depends on.

### Documentation

- `docs/DEV_LOG.md`: not updated — the reader gained a capability but the
  feature is not user-visible until the flow and UI land, so a milestone
  entry would be premature (per the task's guidance).
