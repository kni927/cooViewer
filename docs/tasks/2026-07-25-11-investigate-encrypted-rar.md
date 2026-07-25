# TASK: Investigate encrypted RAR support options

## Scope

Investigation only. Do not implement, vendor, build, or commit source
changes. Produce the material needed to decide whether to support encrypted
RAR archives, and if so, by what means.

Encrypted ZIP support is already complete (tasks 08-10). This task concerns
RAR only.

## Part A: Format variants and current behaviour

1. Report the encryption variants that matter for RAR, and how each is
   detected today by `CORarArchive` / libarchive:
   - RAR3 vs RAR5 encryption (algorithms and key derivation differ)
   - data-only encryption vs header encryption (in the latter, entry names
     are also encrypted)
2. State explicitly what libarchive can and cannot do for each variant —
   detection, listing, extraction — and confirm the limitation is inherent
   rather than a build-flag issue. Reference where in the current code the
   unsupported path is taken.
3. Report what a user currently sees for each variant when opening such an
   archive in cooViewer.

## Part B: Candidate libraries

For each candidate below, report capability, licence, size, and integration
cost. Do not fetch or vendor anything; report from source inspection where
already available locally, and from documentation otherwise. State clearly
which findings are from inspection and which are from documentation.

1. **unrar (RARLAB)** — the reference decoder.
   - which RAR versions and encryption variants it handles
   - licence terms, in particular the restriction on re-creating the RAR
     compression algorithm, and whether redistribution in an open-source
     app distributed via Homebrew is permitted
   - API surface needed to list and extract entries with a password
2. **XADMaster (LGPL)** — used by this project before v1.4.0.
   - whether RAR decryption can be extracted as a bounded subset, or is
     entangled with the parser, `CSHandle` streams, and checksum code
   - what LGPL obligations follow from including a derived subset in an
     otherwise MIT project, and how that interacts with the existing
     `docs/licenses/` arrangement
   - note that `docs/licenses/License_xadmaster.txt` is currently stale;
     report whether it should be removed or would become live again
3. **Any other viable option** — report only if genuinely applicable, with
   the same criteria. Note that 7-Zip's RAR codec derives from unrar and
   inherits its licence terms.

## Part C: Flow impact

1. The current password flow detects `crypted`, then prompts. Report
   whether that flow holds for each RAR variant.
2. For header-encrypted RAR specifically, the password is required before
   entries can be enumerated at all. Report what would have to change in
   `COImageLoader` / `COArchive` to request a password before listing, and
   whether that restructuring would also affect the working ZIP path.
3. Report whether the QuickLook / Thumbnail extensions remain unaffected
   (they should continue to yield the default icon without prompting).

## Part D: Build integration

1. Report how a new vendored library would fit `vendor/build-libs.sh`:
   universal build, dylib bundling into `Frameworks/`, and whether a C++
   library introduces linking considerations the current C libraries do not.
2. Estimate the change to build time and bundle size.

## Deliverable

A chat report covering:

- what is and is not possible with the current libraries, per RAR variant
- candidate comparison: capability, licence, integration cost
- flow impact, especially header encryption
- a recommendation: proceed with a named library, defer, or decline — with
  the reasoning stated plainly
- if proceeding is recommended, a proposed task split

## Notes

- Investigation only. Archive this `TASK.md` on completion per
  `docs/task-workflow.md`; do not leave it at the repository root.
- Do not fetch, clone, or vendor any library in this task. If a finding
  genuinely cannot be determined without network access, say so rather than
  guessing, and mark it as unverified.
- Licensing conclusions are informational, not legal advice. Report the
  terms and the open questions; the project owner decides.
- A recommendation to decline is a valid outcome. Encrypted RAR is a
  declining format, and the ZIP support already restores the documented
  feature in its most common form.
## Implementation Result

**Status:** Completed

### Changes

Investigation only; no code, vendoring, or build changes. Findings recorded
below so they survive outside the chat. Evidence is marked **[inspected]**
(local source/binary/fixture examined or executed here) or **[documented]**
(from documentation knowledge; this task used no network, so such points are
**unverified**).

**Part A — variants and current behaviour**

Decisive evidence [inspected], from the vendored libarchive sources: the RAR
readers never consult the passphrase API at all —
`archive_read_support_format_rar.c` and `..._rar5.c` contain **0** mentions
of `passphrase`, while `..._zip.c` contains **17**. libarchive does have a
generic `archive_read_add_passphrase()` which the ZIP reader uses; the RAR
readers simply do not implement decryption. **This is an implementation
absence, not a build-flag issue.**

| variant | detect | list | extract | source evidence |
|---|---|---|---|---|
| RAR3/4 data-only | yes | **yes** (deliberately not FATAL) | no | `rar.c:1469-1479` `FHD_PASSWORD` → "RAR encryption support unavailable."; comment keeps listing possible |
| RAR3/4 header-encrypted | yes | no | no | `rar.c:1000-1010` `MHD_PASSWORD` → "cannot read any file names" → `ARCHIVE_FATAL` |
| RAR5 data-only | yes | yes | no | `rar5.c:1668-1671` marks entry; `:4201-4204` "Reading encrypted data is not currently supported" |
| RAR5 header-encrypted | yes | no | no | `rar5.c:2381-2388` "Encryption is not supported" → `ARCHIVE_FATAL` |

Algorithms differ by generation (RAR3 AES-128-CBC with a custom KDF; RAR5
AES-256 with PBKDF2-HMAC-SHA256) [documented]; neither is implemented.

Measured behaviour in cooViewer, with real RAR5 fixtures built by `rar`
7.23 [inspected]:

```
data_enc.rar (rar a -p)   crypted=1 status=Unsupported items=0 err="encrypted archives are not supported"
hdr_enc.rar  (rar a -hp)  crypted=0 status=None        items=0 err="Encryption is not supported"
```

**Important asymmetry:** a header-encrypted RAR reports **`crypted = NO`**.
`CORarHeaderIndex` declines on header encryption
(`CORarHeaderIndex.m:156`, `outUnsupported`) and the libarchive fallback
takes `ARCHIVE_FATAL` before producing any entry, so
`archive_entry_is_encrypted()` is never reached. In cooViewer's own state
such an archive is indistinguishable from a corrupt one apart from the error
string. Both variants end at `itemCount < 1`, so `Controller.m:754` aborts
the open and restores the previous document — **no prompt appears** for
either (data-only because the status is `Unsupported`, header-encrypted
because `crypted` is NO and the branch is never entered).

**Part B — candidates**

1. **unrar (RARLAB)** [documented, unverified]: the reference decoder;
   handles RAR3/RAR5, data-only and header encryption — the only complete
   answer. Licence is **not free/OSI-approved** and carries the restriction
   against using the source to re-create the RAR compression algorithm
   (Debian ships it as non-free). Decryption-only use is generally read as
   permitted, but bundling it into an MIT app means a non-MIT component in
   the distributed binary and a split licence statement; Homebrew
   distribution is technically possible but the compliance call is the
   owner's. API needed is small: `RAROpenArchiveEx` / `RARSetPassword` /
   `RARReadHeaderEx` / `RARProcessFile`, with the password supplied right
   after open so even header-encrypted archives enumerate.
2. **XADMaster (LGPL-2.1+)** [inspected, local docs]: extracting RAR
   decryption as a bounded subset is **not practical** — `docs/DECISIONS.md`
   (2026-07-14) already analysed this: the RAR parsers sit on
   `CSHandle`/`XADArchiveParser`/`XADPath` (~3500 lines, exception-based
   flow, chained decryption handles), and decryption is entangled with that
   handle chain. That decision explicitly states that needing XADMaster's
   fuller machinery (e.g. actual RAR decompression) is "a bigger decision
   requiring fresh review, not an extension of this one". LGPL obligations:
   cooViewer statically compiles such code into the app binary; the phase-6
   task doc already flags static-link LGPL compliance as unresolved by
   non-lawyer assessment (likely satisfied because the whole project is open
   and buildable from this repo), to be revisited before any closed-source
   or object-only distribution.
   **Correction — `docs/licenses/License_xadmaster.txt` is NOT stale.**
   [inspected] Its own preamble states it covers `Sources/CORarHeaderIndex.h/.m`,
   whose RAR block-layout and flag-bit knowledge is *derived* from
   XADMaster's parsers; `CORarHeaderIndex.h` carries the matching
   LGPL-2.1-or-later notice and points at this file. It is a **live
   attribution and must not be removed**. This supersedes the "stale"
   description in this TASK and in
   `docs/tasks/2026-07-25-07-investigate-password-archive.md`, which was
   wrong.
3. **Others**: **libunarr — already spiked by this project (2026-07-11,
   commit `4ae5d2f`), verdict NO-GO** [inspected]: it rejects RAR5 outright
   (`rar.c:214: RAR 5 format isn't supported`) and every modern `.cbr` is
   RAR5. **7-Zip's RAR codec derives from unrar and inherits its licence
   terms**, so it is not an independent option [documented]. Note also that
   the installed `rar` 7.23 **cannot create RAR4 at all** [inspected], so
   the RAR3/4 variants are fading from the producer side.

**Part C — flow impact**

1. **Data-only encryption**: the current detect-`crypted`-then-prompt flow
   holds as-is; headers are plaintext, so the ZIP shape (`setPassword:` then
   re-scan) transfers directly.
2. **Header encryption**: the password is a **precondition for listing**.
   `COArchive`'s designated initializer calls `readArchiveWithProgress:`
   inside `-init`, so the entry list is fixed at construction. Supporting it
   needs either a password callback injected into the open path, or
   "open → detect → ask → **rebuild** the container". **The rebuild
   approach leaves the working ZIP path untouched** and is the one to
   prefer; adding a callback to the shared COArchive API would modify the
   live ZIP path for no benefit.
3. **QuickLook / Thumbnail extensions: unaffected** [inspected] —
   `COExtractCoverImageData` returned nil for both RAR variants, so Finder
   shows the default icon. The extensions link neither `COImageLoader` nor
   `Controller`, so no prompt path exists there even if RAR support were
   added later.

**Part D — build integration**

- Fits `vendor/build-libs.sh`'s existing shape (pinned checkout, cmake,
  `arm64;x86_64`, `@rpath` install_name, copy into `vendor/lib` and bundle
  into `Frameworks/`). unrar ships makefile-based [documented], so it would
  need a small cmake or direct-clang step rather than the plain `cmake -S`
  used today.
- **A C++ library introduces no new linking consideration** [inspected]:
  `libuchardet.0.dylib` is already C++ and links `/usr/lib/libc++.1.dylib`
  in the current universal build; the app itself links no C++ runtime
  directly but already ships one transitively.
- Size/time: app bundle is currently 12 MB with ~2.5 MB of vendored dylibs
  [inspected]. unrar would add roughly 400–600 KB universal
  (decoder-only estimate) [documented] — about +5% of bundle — and under a
  minute to the vendored build.

### Recommendation: **decline** (with data-only as the cheapest future option)

1. The only complete answer is unrar, whose licence does not sit comfortably
   in an MIT project (non-OSI, algorithm-re-creation restriction). XADMaster
   is legally viable but its decryption is inseparable from the CSHandle
   machinery this project deliberately declined to adopt in 2026-07-14.
2. Demand is structurally small: encrypted RAR is a declining format, RAR4
   can no longer even be created by current `rar`, and the documented
   "password-protected archive" feature is already restored in its most
   common form (ZIP, AES + traditional, including non-ASCII passwords).
3. The current behaviour already fails safely — no crash, default icon,
   extensions unaffected — so the cost of leaving it is low.

If the owner later accepts unrar's licence terms, a workable split is:
(1) vendor unrar + universal build + licence documentation and a README
licence note about the non-MIT component; (2) data-only decryption in
`CORarArchive` with `cryptoStatus` matching the ZIP shape; (3) the
open→ask→rebuild flow for header encryption, leaving the ZIP path unchanged;
(4) extension regression check (no prompt). Steps 1–2 alone deliver most of
the practical value; step 3 is the invasive one.

### Verification

- Build: Not performed (investigation only).
- Automated verification: Not performed (investigation only) — read-only
  inspection plus throwaway diagnostics in the scratchpad (a small probe
  linking the existing readers, and RAR fixtures built with `rar`), none of
  which touched the repository.
- Manual verification: read the vendored libarchive RAR/RAR5/ZIP readers,
  `CORarArchive`/`CORarHeaderIndex`/`COArchive`/`Controller`,
  `docs/DECISIONS.md`, `docs/licenses/License_xadmaster.txt`, the libunarr
  spike commit, and inspected the shipped dylibs for C++ linkage.

### Remaining Issues

None. Deliverable is the report above.

### Follow-up Suggestions

- **Correct the stale-licence claim**: `docs/tasks/2026-07-25-07-*.md`
  records `docs/licenses/License_xadmaster.txt` as stale. It is not — it is
  live attribution for `CORarHeaderIndex`. Worth a one-line correction if
  that archive is ever revised (not edited here, since archives are not
  retroactively rewritten).
- If encrypted RAR is ever revisited, start from the data-only variant; it
  needs no flow restructuring.
