# Decisions

Lasting architectural, technical, and product decisions for cooViewer.
See `docs/DEV_LOG.md` for narrative history and `docs/tasks/` for the
task documents these decisions were made in.

---

## RAR header parsing: reimplement from XADMaster's knowledge, not restore its code (2026-07-14)

**Decision:** `Sources/CORarHeaderIndex.h/.m` (phase 6,
`docs/tasks/2026-07-14-04-rar-header-parser.md`) reimplements RAR4/RAR5
header-only block parsing as new, small C/Foundation code matching
this project's existing style, informed by reading XADMaster's
`XADRARParser.m`/`XADRAR5Parser.m` — rather than restoring those files
(or XADMaster's supporting class hierarchy: `XADArchiveParser`,
`CSHandle`, `XADPath`, ~3500 lines) wholesale from before the v1.4.0
migration.

**Why:** XADMaster's RAR parser classes are built on its own
`CSHandle`/`XADArchiveParser`/`XADPath` abstractions (input handle
chaining, decryption handles, exception-based error flow) which this
project has no other use for and which don't match cooViewer's
existing flat, C-API-direct style (see `COArchive.m`/`COZipArchive.m`).
Pulling in that whole hierarchy to reach a handful of header-parsing
methods would have meant maintaining a second, foreign object model
alongside the libarchive/libzip-based one for no benefit beyond code
reuse. The header-format *knowledge* (block layouts, flag bits, RAR5
vint encoding) is what actually mattered and is what got reused, with
attribution.

**How to apply:** Any future RAR format work (e.g. porting RAR4's
`LHD_UNICODE` name decoding, still deferred — see Remaining Issues in
the phase 6 task doc) should continue this pattern: read XADMaster's
logic as a reference/spec, reimplement minimally in cooViewer's own
style, attribute clearly. Do not import XADMaster source files
directly into `Sources/` — if a future need turns out to require
XADMaster's fuller machinery (e.g. actual RAR decompression, which
this project still delegates entirely to libarchive), that is a
bigger decision requiring fresh review, not an extension of this one.

**Licensing consequence:** Because the reimplemented code is a
derivative of XADMaster's LGPL-2.1-or-later source, `CORarHeaderIndex.h`
carries an LGPL-2.1-or-later notice and
`docs/licenses/License_xadmaster.txt` was added. cooViewer statically
compiles this code into the app binary (no separate dylib) — the
phase 6 task doc flags this as unresolved by non-lawyer assessment
(compliance likely satisfied because the
whole project is already open source and buildable from this
repository) rather than guessed away; revisit before any
closed-source or object-only distribution change.

---

## QuickLook: two separate extension targets, and support both custom and pre-existing public UTIs (2026-07-14)

**Decision:** `docs/tasks/2026-07-14-05-quicklook-extension.md` (phase
7) adds **two** App Extension targets — `cooViewerPreview`
(`QLPreviewProvider`) and `cooViewerThumbnail`
(`QLThumbnailProvider`) — rather than one combined extension, and has
each extension's `QLSupportedContentTypes` list both cooViewer's own
exported UTIs (`jp.coo.cooViewer.cbz-archive`/`cbr-archive`) and the
pre-existing `public.cbz-archive`/`public.cbr-archive` UTIs, rather
than only the custom ones.

**Why:** Apple's current Xcode templates (checked directly, not
assumed from older docs) always generate preview and thumbnail
providers as separate targets bound to separate extension points
(`com.apple.quicklook.preview` vs `com.apple.quicklook.thumbnail|`) —
there is no supported combined form. On the UTI side, on-device
testing (`mdls -name kMDItemContentType` on real `.cbz`/`.cbr` files)
showed this dev Mac's `.cbz`/`.cbr` extensions already resolve to
`public.cbz-archive`/`public.cbr-archive`, publicly exported by other
installed comic readers (Yomu, EdgeView 2) — not to cooViewer's own
declared UTI. Since UTI-to-extension resolution is a per-machine,
install-order-dependent outcome that cooViewer's own
`UTExportedTypeDeclarations` cannot force, listing all four UTIs in
`QLSupportedContentTypes` is the only way to make the extensions work
regardless of which UTI actually wins on a given system, without
touching `public.zip-archive`/`public.data` (the system's default
zip/rar handlers) and without removing cooViewer's own UTI export
(still authoritative on a machine with no competing comic-reader
app installed).

**How to apply:** Any future QuickLook-adjacent UTI work (e.g. adding
7z/tar support) should check `mdls -name kMDItemContentType` /
`lsregister -dump` on a real file before assuming a custom UTI
declaration is authoritative — a same-named public UTI already
claimed by another installed app silently wins over a freshly declared
one, with no build-time or install-time warning.

---

## cb7 (7z) / cbt (tar) QuickLook support: not added (2026-07-15)

**Decision:** `docs/tasks/2026-07-15-01-verify-cb7cbt-release.md` (phase
8) evaluated extending the phase 7 QuickLook extensions to `.cb7`/`.cbt`
following the same four-UTI-per-format pattern used for cbz/cbr, and
decided **not** to add either, with measured evidence rather than
assumption.

**Why:** `.7z`/`.tar` files that don't match `COArchive`'s
`zip`/`cbz`/`rar`/`cbr` fast paths fall through to `COArchive`'s own
`readArchiveWithProgress:` (`Sources/COArchive.m:209`), which does a
single sequential libarchive pass that fully decompresses and buffers
**every** entry's payload into memory before the first page is
available — cost scales with total archive size/entry count
regardless of which single entry is actually wanted, unlike
`COZipArchive`'s true random access or `CORarArchive`'s
`CORarHeaderIndex`-based lazy seek. Measured against a realistic 1.4 GB
/ 679-entry archive (built from a real large `.cbz` fixture's own
pages, so representative of what this project's users actually open):
a `.tar` of that content took **~8s** to yield the first page through
this fallback path — uncompressed and therefore the *best case* for
this path, yet still ~60-80x slower than the ~0.1s the project's own
performance bar (phases 4/6) established for the equivalent solid-RAR
case, and uncomfortably close to typical QuickLook timeouts. A `.7z`
of the same content (default LZMA2, solid — libarchive/7-Zip's normal
default) was still compressing after 20+ minutes of heavy multi-core
CPU time when the encode itself was aborted, underscoring how far a
correct *decode-side* lazy-skip would be from meeting the time budget
for anything but small archives, since `archive_read_data_skip` on a
solid LZMA2 block must decompress from the start of that block
regardless of format — the exact problem `CORarHeaderIndex` was built
to solve for RAR (see `docs/tasks/2026-07-14-04-rar-header-parser.md`),
requiring bespoke per-format header/block-layout knowledge that does
not transfer.

Splitting the two formats: `.cbt` (tar, uncompressed, fixed-position
headers) is architecturally the easy case — a proper lazy reader would
only need `COZipArchive`-style skip-to-target, no RAR/7z-scale header
parser — but the *existing* fallback path still doesn't hit that, so
"trivial, UTI/dispatch-only" (the bar TASK.md set for adding either
format) does not hold today. `.cb7` (7z, typically solid LZMA2) would
need work comparable in scope to `CORarHeaderIndex` itself to be
genuinely lazy for the common case.

**How to apply:** If cbt support is revisited, the scoped work is a new
`COTarArchive` (mirroring `COZipArchive`'s interface, using tar's cheap
`archive_read_data_skip` to reach the target entry without
decompression) — a self-contained, low-risk addition given tar's
format simplicity. If cb7 is revisited, treat it as comparable in size
to the RAR lazy-reading project (phases 1–6 of this fork's own
history) — a from-scratch 7z header/folder parser — not a quick
follow-up.

## Vendored libzip built with CommonCrypto to support encrypted ZIP (2026-07-25)

**Decision:** Build the vendored libzip with `-DENABLE_COMMONCRYPTO=ON`
(the other crypto backends — GNUTLS / MBEDTLS / OPENSSL / WINDOWS_CRYPTO —
stay off, and `ENABLE_ZIPCRYPTO` is left at libzip's default ON). This gives
the vendored dylib WinZip AES-256 decryption plus traditional PKWARE
ZipCrypto, so encrypted ZIP archives can be reopened once the application
layer re-adds password handling.

**Why:** Password-protected archive support was a documented feature of the
original cooViewer, dropped in v1.4.0 when the archive layer moved from
XADMaster to libzip/libarchive (see
`docs/tasks/2026-07-25-07-investigate-password-archive.md`). The previous
vendored libzip had all crypto backends disabled, so encrypted entries were
only detected (`crypted`) and skipped. CommonCrypto is native to macOS: it
adds no extra runtime dependency (it lives in libSystem, so `otool -L` still
shows only system dylibs) and keeps the universal (arm64 + x86_64) link free
of arm64-only Homebrew codecs — the same constraint that governs the rest of
the vendored build. Verified with a standalone round-trip test
(`tests/engine/run_encryption_test.sh`): AES-256 and traditional ZipCrypto
both decrypt with the correct password and fail cleanly on a wrong one,
including a traditional fixture produced independently by the system `zip`
tool.

**RAR limitation (unchanged):** This covers ZIP only. libarchive cannot
decrypt encrypted RAR (it detects but does not decrypt), so restoring
password-protected RAR would require a different library (unrar/libunrar, or
bringing back XADMaster) and is a separate decision, not addressed here.

**How to apply:** The dylib now exports `zip_fopen_encrypted`,
`zip_fopen_index_encrypted`, `zip_set_default_password`, and
`zip_file_set_encryption`. The application layer (`COZipArchive` /
`COArchive` / `COImageLoader`) can call `zip_set_default_password` (or
`zip_fopen_index_encrypted`) at the point where `crypted` is currently
detected. Do not enable a heavier crypto backend (OpenSSL/mbedTLS) — they
would reintroduce external dependencies for no benefit on macOS.

## Encrypted RAR support: declined (2026-07-25)

**Decision:** cooViewer does **not** support password-protected RAR
archives, and this is settled — not pending work. **Both variants**
(data-only encryption, `rar a -p`, and header encryption, `rar a -hp`) fail
closed: the document does not open, Finder shows the default icon, and no
password prompt appears. Do not re-investigate without a new decision from
the project owner. Full analysis:
`docs/tasks/2026-07-25-11-investigate-encrypted-rar.md`.

**Expected, not a bug:** the two variants reach that same closed state by
different internal routes, so the state they leave behind differs. A
data-encrypted RAR reports `-crypted = YES` with `-cryptoStatus =
COArchiveCryptoUnsupported`, while a **header-encrypted RAR reports
`-crypted = NO`** — `CORarHeaderIndex` declines on header encryption and the
libarchive fallback fails before any entry exists, so
`archive_entry_is_encrypted()` is never reached and the archive is
internally indistinguishable from a corrupt one apart from its error string.
Do not "fix" that asymmetry; without a decoder there is nothing to unlock in
either case.

**Why:** The blocker is the decoder, not configuration. libarchive's RAR
readers contain **no decryption implementation at all** — they never consult
libarchive's own passphrase API (`archive_read_support_format_rar.c` and
`..._rar5.c` mention `passphrase` zero times, while the ZIP reader mentions
it 17 times and is exactly why encrypted ZIP works). No build flag changes
this; the readers detect encryption and stop
(`"RAR encryption support unavailable."` for RAR3/4,
`"Encryption is not supported"` / `"Reading encrypted data is not currently
supported"` for RAR5).

Every route to a decoder was rejected:

- **unrar (RARLAB)** — the only complete decoder (RAR3/RAR5, data-only and
  header encryption), but its licence is not OSI-approved and carries the
  restriction against using the source to re-create the RAR compression
  algorithm. Bundling it would put a non-MIT component into an otherwise MIT
  app and require a split licence statement.
- **An XADMaster subset** — legally viable (LGPL-2.1+), but its RAR
  decryption is inseparable from the `CSHandle` / `XADArchiveParser` /
  `XADPath` machinery (~3500 lines, chained decryption handles), so there is
  no bounded subset to lift. This is also the line drawn by the 2026-07-14
  decision above, which states that needing XADMaster's fuller machinery is
  a bigger decision requiring fresh review.
- **libunarr** — already spiked and rejected (2026-07-11, commit `4ae5d2f`):
  it refuses RAR5 outright, and every modern `.cbr` is RAR5.
- **7-Zip's RAR codec** — derives from unrar and inherits its licence terms,
  so it is not an independent option.

Weighed against that cost, the demand is small and shrinking: encrypted RAR
is a declining format, current `rar` (7.23) cannot even create RAR4 any
more, and **encrypted ZIP already restores the documented
"password-protected archive" feature in its most common form** (WinZip
AES-256 and traditional ZipCrypto, including non-ASCII/Japanese passwords —
see the libzip decision above and tasks 08-10). The present behaviour is
already safe, so the cost of leaving it is low.

This settles the "separate decision, not addressed here" note left by the
libzip/CommonCrypto entry above.

**Current behaviour, for reference** (measured, RAR5 fixtures):

- *data-only* encryption (`rar a -p`): entries are detected as encrypted and
  skipped — `-crypted` = YES, `-cryptoStatus` = `COArchiveCryptoUnsupported`,
  zero entries, `lastError` = "encrypted archives are not supported".
- *header* encryption (`rar a -hp`): libarchive fails before any entry
  exists, so the encrypted-entry check is never reached — `-crypted` is
  **NO**, `-cryptoStatus` = `COArchiveCryptoNone`, zero entries, and only
  libarchive's error string distinguishes it from a corrupt archive.
- Both end at `itemCount < 1`, so the open is aborted and the previous
  document is restored; the QuickLook/Thumbnail extensions return no cover
  and Finder falls back to the default icon.

**How to apply:** Treat encrypted RAR as out of scope. `CORarArchive`
inherits `COArchive`'s base `-setPassword:` (a no-op) and `-cryptoStatus`
(`Unsupported` when `crypted`) deliberately — do not wire a password path
into it. If the owner ever accepts unrar's licence terms, the work splits
as: vendor unrar (+ licence documentation and a README note about the
non-MIT component); add data-only decryption to `CORarArchive` mirroring the
ZIP shape; only then tackle header encryption, which needs an
open→ask→rebuild flow because the password is a precondition for listing
(the ZIP path must stay untouched); finally re-check that the extensions
still never prompt. Steps one and two carry most of the practical value.

## `.cvbdl` document type: keep as-is, origin documented (2026-07-25)

**Decision:** `Resources/Info.plist` registers `.cvbdl` ("ComicViewer
Comic") with `LSTypeIsPackage = true`, so Finder treats a folder with that
extension as a single document. There is no dedicated implementation for it
anywhere in this codebase or its known upstream history — the entry was
added in a single commit, `77b2275` ("1.2b24", 2020-01-13), part of the
initial fork import, and has never been touched since. It is kept as-is;
this is not a dead-code removal candidate. The origin was previously
unclear and is recorded here so it is not re-investigated.

**Why:** `.cvbdl` is a macOS bundle-folder variant of the "Comic Book
Format" naming convention (alongside `.cbz`/`.cbr`/`.cb7`/`.cbt`/`.cba`/
`.cbtc`), per the German Wikipedia article "Comic-Book-Format"
(https://de.wikipedia.org/wiki/Comic-Book-Format) — the only language
edition that lists it. This is **not a ratified standard**; no standards
body defines Comic Book Format. It is a de facto convention followed by a
handful of independent viewers/applications, such as
`HetimaZip.qlgenerator`. Because `LSTypeIsPackage` is set, `.cvbdl` folders
never reach `COImageLoader`'s archive dispatch (`+archiveTypes` explicitly
excludes `cvbdl`); they fall through to the generic directory-open path,
which happens to work because it's just a folder. Confirmed manually:
renaming a folder to `.cvbdl` opens it in cooViewer via that generic path.
QuickLook does not support it — `COCoverExtractor.m` explicitly excludes
`cvbdl` from the types it hands to `COImageLoader`'s fuller logic.

**How to apply:** Do not add a dedicated `.cvbdl` reader and do not remove
the Info.plist entry or the `archiveTypes` exclusion as unreachable/dead —
both are working exactly as intended for a package-type document handled by
the generic directory path. If `.cvbdl` support is ever revisited (e.g. to
read package-internal metadata `HetimaZip`-style), treat it as new work
scoped from this note, not as fixing an oversight.
