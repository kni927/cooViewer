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
