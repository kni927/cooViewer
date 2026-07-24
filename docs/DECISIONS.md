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
