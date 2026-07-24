# TASK: Rebuild vendored libzip with encryption support

## Scope

Rebuild the vendored libzip with AES decryption enabled, so encrypted ZIP
archives can be opened later by the application layer. This task changes the
vendored build configuration and the resulting dylib only. No application
code changes.

Encrypted RAR is explicitly out of scope (a libarchive limitation, handled
separately if ever). This task concerns ZIP only.

## Steps

1. In `vendor/build-libs.sh`, enable a crypto backend for libzip. Prefer
   `-DENABLE_COMMONCRYPTO=ON` (native to macOS, no extra dependency). Leave
   the other backends (GNUTLS / MBEDTLS / OPENSSL / WINDOWS_CRYPTO) off.
2. Confirm `ENABLE_ZIPCRYPTO` remains on (libzip default) so traditional
   PKWARE ZipCrypto also works. Do not disable it.
3. Rebuild libzip as the universal dylib per the existing vendored build
   process. Do not change how libarchive or uchardet are built.
4. Verify the rebuilt dylib:
   - it is still a universal binary (`lipo -info`, x86_64 + arm64)
   - it exports the encryption entry points the application layer will need
     (`zip_fopen_encrypted` / `zip_fopen_index_encrypted` and the
     `zip_set_default_password` symbol). Report which symbols are present.
5. Create a minimal decryption check outside the app:
   - prepare small encrypted ZIP fixtures under `tests/fixtures/` (one AES,
     one traditional ZipCrypto if practical), each containing a known file
   - write or extend a small standalone C test (consistent with the
     existing `tests/` harness, e.g. alongside `tests/engine/`) that opens
     each fixture with the correct password, reads the entry, and compares
     it to the expected content
   - run it and report pass/fail per fixture, including the wrong-password
     case returning an error rather than garbage
6. Update the bundled dylib in `Frameworks/` so a normal build picks up the
   new libzip, following the existing bundling process.

## Verification

- `vendor/build-libs.sh` completes successfully.
- libzip dylib is universal and exports the required symbols (report them).
- The standalone test decrypts the AES fixture and (if built) the ZipCrypto
  fixture with the correct password.
- Wrong password returns a clean error, not a crash or garbage.
- A normal application build (`xcodebuild -configuration Deployment`) still
  succeeds and links against the rebuilt libzip. The app need only build and
  launch; no in-app encrypted-archive handling exists yet.

## Documentation

- Record in `docs/DECISIONS.md` that vendored libzip is built with
  CommonCrypto enabled to support encrypted ZIP, with the reason (feature
  restoration lost in v1.4.0) and the RAR limitation noted.
- If any fixtures are added, note their origin and license under
  `tests/fixtures/` consistent with the existing `tests/fixtures/src/`
  licensing.

## Notes

- ZIP only. Do not attempt encrypted RAR or reintroduce XADMaster.
- If CommonCrypto cannot be enabled cleanly (e.g. libzip's CMake does not
  detect it on this toolchain), report the exact failure and stop rather
  than switching to a heavier backend without confirmation.
- The vendored library sources under `vendor/` must not be edited; only the
  build configuration in `build-libs.sh`.
- This task builds vendored libraries, which requires cmake per `CLAUDE.md`.
  It does not install or register the app; a successful build and launch is
  sufficient.
## Implementation Result

**Status:** Completed

### Changes

- `vendor/build-libs.sh`: libzip crypto backend enabled —
  `-DENABLE_COMMONCRYPTO=ON` (was OFF). Other backends
  (GNUTLS/MBEDTLS/OPENSSL/WINDOWS_CRYPTO) left OFF; `ENABLE_ZIPCRYPTO` left
  at libzip's default (ON) so traditional PKWARE ZipCrypto also works. The
  libzip comment block was updated. libarchive and uchardet build config
  unchanged. No `vendor/` sources edited.
- `tests/engine/test_zip_encryption.c` (new): standalone libzip round-trip
  check — creates an AES-256 and a traditional-PKWARE archive, reads each
  back with the correct password and compares bytes, and confirms a wrong
  password fails cleanly. Also verifies an externally-created traditional
  fixture if given.
- `tests/engine/run_encryption_test.sh` (new): builds/links the test against
  `vendor/lib/libzip.5.dylib` (same pattern as `run_tests.sh`), creates an
  independent traditional fixture with the system `zip -e`, and runs it.
- `docs/DECISIONS.md`: recorded the CommonCrypto decision, reason (feature
  restoration lost in v1.4.0), and the RAR limitation.
- `tests/fixtures/README.md`: documented the encrypted fixtures (synthetic
  payload, no extra licensing; test password noted). Fixtures are generated
  into `tests/fixtures/generated/` and not committed.

### Verification

- `vendor/build-libs.sh` completed successfully (offline; the pinned
  upstream checkouts were already present, so `git fetch … || true` was a
  no-op and the pinned commits checked out cleanly). The libzip build
  compiled `zip_crypto_commoncrypto.c`, `zip_winzip_aes*.c`, and
  `zip_source_pkware_encode.c`.
- Rebuilt dylib: universal (`lipo -info` → `x86_64 arm64`), install_name
  `@rpath/libzip.5.dylib`, runtime deps only system libs (libbz2, libz,
  libSystem — CommonCrypto lives in libSystem). Exported symbols present:
  **`zip_fopen_encrypted`, `zip_fopen_index_encrypted`,
  `zip_set_default_password`, `zip_file_set_encryption`**.
- Standalone test (`run_encryption_test.sh`): **PASSED (0 failures)** —
  AES-256 correct-pw decrypt + wrong-pw rejected; TRAD_PKWARE correct-pw
  decrypt + wrong-pw rejected; external `zip -e` traditional fixture
  decrypt + wrong-pw rejected. Wrong passwords returned a clean error (AES
  fails HMAC at read; traditional rejected at open), no crash or garbage.
- App build: `xcodebuild -scheme cooViewer_deploy -configuration Deployment`
  → `** BUILD SUCCEEDED **`; the bundled
  `Contents/Frameworks/libzip.5.dylib` is the crypto-enabled build (283 KB,
  encryption symbols present). App launched and opened a document normally
  (no in-app encrypted-archive handling exists yet, as expected).

### Remaining Issues

None. ZIP-only per scope; encrypted RAR remains unsupported (libarchive
limitation), a separate decision.

### Follow-up Suggestions

- Next: application-layer plumbing — `COZipArchive` password parameter
  (`zip_set_default_password` / `zip_fopen_index_encrypted`), password flow
  in `COImageLoader`/`COArchive`, and a password-entry UI, triggered where
  `crypted` is currently detected.
