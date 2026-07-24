# TASK: Investigate password-protected archive support for reimplementation

## Scope

Investigation only. Do not implement, modify code, or commit changes to
source. Produce the findings needed to scope a reimplementation of
password-protected archive support (a documented feature of the original
cooViewer, removed or lost at some point in this fork's history).

The goal is to determine whether reimplementation is a port of the old
code or a new implementation on the current archive layer, and what the
current vendored libraries support.

## Part A: Locate the old implementation

1. Identify how the original v1.3.7 (or nearest version that had
   password-protected archive support) can be accessed: a tag, release, or
   commit in this repository's history, or an upstream repository.
   - Check local tags and history first: `git tag -l`, `git log --all`.
   - If it is not in local history, identify the upstream GitHub repository
     and the specific tag/commit. Report the exact reference; do not fetch
     or merge anything.
2. Once located, identify the files and functions in the old version that
   implemented password handling and encrypted-archive extraction.
3. Report which library and method the old version used to open encrypted
   archives (e.g. a bundled unrar, an older libzip/libarchive, custom
   crypto), and how the password reached that layer.

## Part B: Current archive layer

1. Map the current archive-extraction path: how `COImageLoader` /
   `archiveContainer` open and read entries today, and which vendored
   library handles zip vs rar.
2. Report where in this path a password would need to be supplied, and
   whether the current code has any residual hooks for it (parameters,
   dead branches, commented-out code).

## Part C: Vendored library capability

1. Inspect `vendor/build-libs.sh` and the resulting libzip / libarchive
   build configuration.
2. Determine whether the current builds support encrypted archives:
   - libzip: is encryption (AES / traditional ZipCrypto) compiled in?
   - libarchive: what encrypted formats are supported by the current
     build, for both zip and rar?
3. Report what would need to change in the vendored build to support
   password-protected zip and rar, if anything.

## Part D: UI

1. Report whether the old version presented a password-entry UI, and how
   (sheet, dialog, Keychain).
2. Report whether the current Preferences or document-opening flow has any
   place this would attach.

## Deliverable

A chat report covering:

- exact reference (tag/commit/repo) for the old implementation
- old approach: library, method, password flow
- current archive layer: where a password attaches, residual hooks
- current vendored library capability for encrypted zip and rar
- assessment: is reimplementation a port or a new implementation, and does
  it require rebuilding vendored libraries
- proposed split of the implementation work into tasks

## Notes

- Investigation only. Archive this TASK.md on completion per
  `docs/task-workflow.md` (investigation tasks are archived like any other;
  do not leave it at the root).
- Do not fetch, clone, merge, or build in this task unless read-only
  inspection requires a shallow read of a specific upstream file, in which
  case report what was accessed.
- Architecture and design direction are decided in chat. Stop at the report;
  do not begin implementation.
## Implementation Result

**Status:** Completed

### Changes

Investigation only; no code modified. Findings (full report delivered in
chat) summarized below so they survive outside the chat.

**Part A — old implementation**

- Reference: tag **`v1.3.7`** (present in local history; nearest version
  with password support — `COArchive.h` notes "password support dropped in
  v1.4.0"). No upstream fetch needed.
- Library/method: **XADMaster** (`XADWrapper` / `XADItem`);
  `archiveContainer = [[XADWrapper alloc] initWithPath:filePath]`.
- Password flow (`COImageLoader.m` @v1.3.7): `NSString *password` ivar,
  `-setPassword:` → `[archiveContainer setPassword:password]`,
  `-checkPassword` / `-checkAndSetPassword:`; on open, if `checkPassword`
  fails it calls `[controller askInArchivePassword:self]`, then gives up
  with `return NO`. Sources lived at the repo root (pre-`Sources/`,
  pre-libarchive).

**Part B — current archive layer**

- `COImageLoader` (mode 2) → `COArchive` dispatcher:
  zip/cbz → `COZipArchive` (**libzip**: `zip_open`/`zip_stat_index`/…);
  rar/cbr → `CORarArchive` (**libarchive** + header parser);
  fallback → libarchive (`archive_read_open_filename`).
- Password attach point: `COArchive initWithPath:progress:` → the per-format
  reader. No password parameter today.
- Residual hooks: `crypted` BOOL + `-crypted`; encryption detection
  (`ZIP_EM_NONE` / `archive_entry_is_encrypted`) → skip + lastError
  "encrypted archives are not supported"; `COImageLoader
  -checkArchiveContainer:` rejects crypted+empty with `mode=-1` (comment:
  非対応 since v1.4.0). No password ivar/UI remain. XADMaster code removed;
  only `docs/licenses/License_xadmaster.txt` lingers.

**Part C — vendored capability (`vendor/build-libs.sh`)**

- libzip: all crypto backends OFF (`-DENABLE_COMMONCRYPTO=OFF`,
  MBEDTLS/GNUTLS/OPENSSL/WINDOWS_CRYPTO OFF) → **no WinZip AES**.
  `ENABLE_ZIPCRYPTO` unset ⇒ libzip default ON, so traditional PKWARE
  ZipCrypto is likely compiled (needs no backend), but COZipArchive treats
  all encryption as unsupported.
- libarchive: `-DENABLE_OPENSSL=OFF` etc. **libarchive's RAR reader cannot
  decrypt encrypted RAR (detection only) — a hard limitation, not a build
  flag.** Encrypted-zip read support is not wired in either.
- To support encrypted ZIP: rebuild libzip with `-DENABLE_COMMONCRYPTO=ON`
  (AES); traditional zipcrypto likely already works. To support encrypted
  RAR: libarchive cannot; a different library (unrar/libunrar, or bring back
  XADMaster) is required.

**Part D — UI**

- Old (v1.3.7): `Controller -askInArchivePassword:` shows a **modal**
  `passPanel` (NIB, `passTextField`) via `[NSApp runModalForWindow:]`,
  OK/Cancel = `sheetOk:`/`sheetCancel:`, recursive re-prompt on wrong
  password. **No Keychain.**
- Current: no password UI; nothing in Preferences/open flow. The
  `-checkArchiveContainer:` crypted-detection point is the natural place to
  trigger a prompt instead of failing.

### Assessment

- **New implementation** (not a port): the old code targets XADMaster, which
  is gone; the archive layer is now libzip/libarchive. Old design
  (password ivar, checkPassword loop, askInArchivePassword modal) is reusable
  as a template.
- **Rebuilding vendored libraries**: required for ZIP (libzip +
  CommonCrypto). RAR is impossible on libarchive — needs a separate library
  decision.

### Proposed task split

1. Rebuild vendored libzip with `-DENABLE_COMMONCRYPTO=ON`; verify with
   encrypted-zip fixtures.
2. COZipArchive password plumbing (`zip_set_default_password` /
   `zip_fopen_index_encrypted`, wrong-password error).
3. Reinstate password flow in COImageLoader/COArchive (password ivar,
   setPassword/checkPassword, forward to COZipArchive, trigger on `crypted`).
4. Password UI (modal panel vs sheet vs Keychain — design decision) wired to
   the open flow; add entry field to MainMenu.xib.
5. (Separate, larger) RAR password support — choose/vendorer a
   RAR-decrypting library; out of libarchive's reach.

ZIP-only (tasks 1–4) is the realistic first stage; RAR needs a separate
architectural decision.

### Verification

- Build: Not performed (investigation only).
- Automated verification: Not performed (investigation only) — read-only
  `git`/`grep` inspection of local history and current sources; no fetch,
  clone, merge, or build.
- Manual verification: inspected `v1.3.7` tree (`COImageLoader.m`,
  `Controller.m`), current `COArchive`/`COZipArchive`/`CORarArchive`/
  `COImageLoader`, and `vendor/build-libs.sh`.

### Remaining Issues

None. Deliverable is the report above.

### Follow-up Suggestions

- Decide ZIP-only vs ZIP+RAR scope before starting (RAR drives a large
  library decision).
- Stale `docs/licenses/License_xadmaster.txt` can be revisited depending on
  whether XADMaster is reintroduced for RAR.
