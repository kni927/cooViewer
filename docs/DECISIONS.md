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

**How to apply:** Do not add a dedicated `.cvbdl` reader and do not remove
the Info.plist entry or the `archiveTypes` exclusion as unreachable/dead —
both are working exactly as intended for a package-type document handled by
the generic directory path. If `.cvbdl` support in the main app is ever
revisited (e.g. to read package-internal metadata `HetimaZip`-style), treat
it as new work scoped from this note, not as fixing an oversight.

**Update (v1.5.2, 2026-07-25):** QuickLook/Thumbnail support for `.cvbdl`
was added, per the investigation in
`docs/tasks/2026-07-25-16-investigate-cvbdl-support-scope.md` and
implemented in `docs/tasks/2026-07-25-17-implement-cvbdl-quicklook.md`.
This did **not** change anything described above — `archiveTypes` still
excludes `cvbdl` and the main app still uses the generic directory path
unchanged. What changed: `Resources/Info.plist` gained a
`UTExportedTypeDeclarations` entry (`jp.coo.cooViewer.cvbdl-archive`,
conforming to `com.apple.package`) and an `LSItemContentTypes` array on the
`.cvbdl` document type referencing it; both extensions' `Info.plist` gained
that UTI in `QLSupportedContentTypes`; `COCoverExtractor.m` gained a
`.cvbdl` branch that lists the bundle directly with `NSFileManager`
(bypassing `COArchive`, which cannot open a directory) rather than the
"explicitly excludes cvbdl" behaviour described above, which is now
superseded.

---

## Multi-window: AppController + NSWindowController, not NSDocument (2026-07-28)

**Decision:** cooViewer gains multi-window support by splitting the
single `Controller` into an application-level `AppController` and a
per-window `BookWindowController : NSWindowController` loaded from a
new `BookWindow.xib`. **`NSDocument` / `NSDocumentController` is not
adopted.** Multi-window is reached through a sequence of
single-window-preserving refactors (`docs/multiwindow-plan.md`,
tasks MW-1 … MW-9), not in one change.

**Why:** Three independent investigations reached the same
architecture — `docs/audit-20260711.md` §2a, `docs/codex-audit-20260728.md`,
and `docs/multiwindow-pass1.md`; the reconciliation is
`docs/multiwindow-pass2.md`. Beyond the cost of disabling
`NSDocument`'s save/revert/duplicate machinery for a read-only viewer,
two facts make it actively wrong here:

- **Book identity is not file-URL identity.** Opening a single image
  re-points the book at its parent folder
  (`Sources/Controller.m:741-749`), and `public.directory` is itself a
  declared document type (as is the `.cvbdl` package). So
  `NSDocumentController`'s `fileURL`-keyed "already open" check would
  be wrong in exactly the case where de-duplication matters.
- **The custom Open Recent carries a page number**
  (`{alias, page, temppath}`), which `NSDocumentController`'s recent
  list cannot store — so the hand-rolled list survives a migration and
  the app would maintain two.

The original 2026-07-11 reason for deferring multi-window — the
XADWrapper retain cycle leaking a whole archive object graph per open,
which every additional window would have multiplied — was fixed
directly in v1.3.7 and then removed outright when v1.4.0 migrated the
archive layer to libarchive/libzip. What replaces it is a
bounded list of specific defects (app-wide event pump during archive
load, app-modal password prompt, lookahead thread teardown, legacy
fullscreen), which is why the direction is now "proceed".

**Step 0 behaviour decisions (settled by the project owner, 2026-07-28):**

1. **Fullscreen:** drop the legacy custom implementation in
   `CustomWindow` and migrate to native AppKit `toggleFullScreen:` /
   `NSWindowCollectionBehaviorFullScreenPrimary`. Nothing about the
   current behaviour (no Spaces, process-wide `setMenuBarVisible:`,
   forced `mainScreen` frame) is worth preserving. This also retires
   the `DontHideMenuBar` and `Fullscreen` preferences.

   *Correction (2026-07-28, `docs/tasks/2026-07-28-02-fullscreen-default-investigation.md`):*
   this decision was originally justified in part by the claim that the
   `Fullscreen` preference "defaults to YES, so the app launches
   fullscreen out of the box". The registration is real
   (`Controller.m:70, 74, 90`) but the conclusion was wrong: the main
   window is `visibleAtLaunch="NO"` (`MainMenu.xib:15`), so no window
   is shown at launch at all — it appears only when a book opens, and
   at launch only under `OpenLastFolder`. The registered default is
   also effectively one-shot, because `Controller.m:273` writes the
   value back into the persistent domain on every launch. On the
   owner's machine the stored value is `0`, set by a prior
   Window ▸ Fullscreen toggle (`Controller.m:2864-2874` is the only
   writer of NO), so **current on-device behaviour is already
   non-fullscreen**. The decision is unchanged — the corrected facts
   only make retiring the preference lower-risk than assumed, since for
   any profile that has toggled the menu item it is a no-op.

   A related hazard was found and is resolved by this decision rather
   than separately: on a genuinely fresh profile,
   `CustomWindow -awakeFromNib` reads the key (`CustomWindow.m:12`)
   while `Controller -awakeFromNib` registers the default
   (`Controller.m:90`), and AppKit does not define `awakeFromNib`
   ordering across nib objects, so the first launch may read NO
   regardless (unverified at runtime). Removing the legacy fullscreen
   state in MW-2 removes the key, both readers and the ordering
   dependency — do not patch it in place beforehand.

   **Implemented 2026-07-29** (`docs/tasks/2026-07-29-01-mw2-native-fullscreen.md`).
   Two points the plan left to be decided and recorded:

   - **Orphaned defaults keys.** The stored `Fullscreen` and
     `DontHideMenuBar` values are **left in place, not deleted.** Nothing
     reads them any more, so they are inert; deleting them would mean
     writing a migration that touches every user's domain for no
     behavioural gain, and keeping them costs two unused keys. If a
     future task ever does a defaults cleanup sweep, these belong in it.
   - **Frame persistence.** The manual
     `saveFrameUsingName:`/`setFrameUsingName:@"NormalWindow"` pair was
     replaced by `-[NSWindow setFrameAutosaveName:@"NormalWindow"]`,
     keeping the **same key name** so existing users keep their saved
     window frame. AppKit then persists and restores it, and correctly
     ignores frames taken while full screen — which is what the manual
     pair, guarded by `if (![window isFullScreen])`, was doing by hand.
     MW-6 revisits the name itself when there is more than one window.

   Two behaviour changes worth noting beyond the fullscreen mechanism
   itself, both consequences of removing the legacy implementation:
   `ThumbnailPanel -constrainFrameRect:toScreen:` now returns the
   `-visibleFrame` of the screen it is on, instead of branching on the
   process-wide `[NSMenu menuBarVisible]` flag and forcing
   `[[NSScreen mainScreen] frame]` with hand-tuned -6/+16 fudges; and the
   nine `[[NSScreen mainScreen] frame]` sites outside `CustomWindow` now
   use the owning window's own screen, so a window on a secondary display
   is no longer measured against the main one.
2. **Same book reopened:** bring the existing window to the front —
   keyed on the **resolved book path**, not the URL passed in (see
   above).
3. **File ▸ Open:** replaces the current window's book.
4. **Last window closed:** the application quits
   (`applicationShouldTerminateAfterLastWindowClosed:` → YES).
   Consequently no empty-window state is needed.
5. **Startup restore:** macOS standard — `NSWindowRestoration` restores
   every window that was open at quit, not just one. `OpenLastFolder`
   is demoted to a fallback for when the system restored nothing.

**Follow-on decision (2026-07-28): how a second window is created.**
Add **Open in New Window… (⌥⌘O)** to the File menu, implemented in
**MW-7**. Decisions 3 and 4 above otherwise leave no in-app route to a
second window — File ▸ Open replaces the current book, and there is no
empty-window state — so a second window could only ever come from
Finder, the Dock, or a drag while a book was already open.

Before the shortcut is finalised, MW-7 must verify ⌥⌘O against the
user-configurable input mappings `KeyArray` / `KeyArrayMode2` /
`KeyArrayMode3` (loaded at `Controller.m:95-100`; defaults from
`+[PreferenceController setDefaultKeyArray]` and siblings). Entries pair
a `key` string with a `modifier` bitmask — option 1, control 2,
command 4 (`CustomWindow.m:119-126`) — so the case to look for is
`key == "o"` with `modifier == 5`. A menu key equivalent takes
precedence over the app's own key handling, so a collision would
silently disable a user's mapping instead of surfacing a conflict; if
⌥⌘O turns out to be taken, choose a different shortcut rather than
overriding the mapping. A check on the shipped defaults and the owner's
live profile found no collision (`o` is bound with `modifier = 0`, and
the Mode2/Mode3 arrays bind no `o`), but these arrays are per-profile
and user-editable, so the check must be repeated at implementation time.

**How to apply:** Work through `docs/multiwindow-plan.md` one MW task
at a time; MW-1 … MW-6 must leave the app single-window with no
user-visible change, and multiple windows are enabled only in MW-7.
Do not fold the listed out-of-scope cleanups (Alias Manager → `NSURL`
bookmarks, `imageFileTypes` → `imageTypes`, the remaining
`NSRunAlertPanel` sites, `validateMenuItem:`'s 44 localized-title
branches) into these tasks — they are independent follow-ups.

---

## Legacy "Old" composited render path removed; direct draw is unconditional (2026-07-29)

**Decision:** the `BufferingMode = 0` ("Old") spread-rendering path is
**deleted**. Every spread is now drawn by `-[CustomImageView
drawImages:and:]`, which draws each page straight into the view. Removed
with it: `-[Controller returnComposeImage:and:]`, `screenCacheArray` and
its plumbing, `-imageDisplayIfHasScreenCache`, the `composedImage` /
`useComposedImage` ivars, the `ScreenCache` preference and its UI field,
the `BufferingMode` popup in Preferences, and the
`respondsToSelector:@selector(finalize)` gate that registered the
`BufferingMode` default. Task:
`docs/tasks/2026-07-29-02-remove-legacy-composited-path.md`.

**Why:** the composited path cost **two** resampling steps (pages →
lock-focus canvas → view) against direct draw's **one**, so it was
strictly lower quality on the metric the project treats as inviolable
(see the top of `CLAUDE.md`). It was not the default —
`BufferingMode` registered as `1` — and its screen cache was off by
default as well (`ScreenCache` = 0 gates both store and lookup). Keeping
it meant carrying a second, lower-quality, rarely-exercised render path
through the whole multi-window refactor.

Removing it also closed, by deletion rather than by fixing:

- `KNOWN_ISSUES` #21 — the composed-spread cache was keyed by page pair
  and `fitScreenMode` but not by screen, and nothing invalidated it on a
  screen change.
- the MW-6 concern that per-window controllers would multiply a
  screen-resolution image cache.
- the MW-7 cache-key omission.
- the `finalize` gate, whose fragility was noted during the MW-2
  fullscreen investigation.

**Accepted trade-off:** users who had explicitly selected "Old" change
path. Image quality improves and page alignment becomes consistent, but
the composite cache is gone. Measured on the test fixture: page turns
cost more CPU (~0.50 s vs ~0.21 s over 24 turns, i.e. roughly 21 ms vs
9 ms per turn — not perceptible), while resizing was unchanged (~0.19 s
vs ~0.22 s over 20 resizes) and total session CPU was actually *lower*
on the new build, because the up-front compose work is gone. The owner
accepted this trade-off before the work started.

**Stored values:** `BufferingMode` and `ScreenCache` are **left in
place, unread, with no migration** — consistent with the `Fullscreen` /
`DontHideMenuBar` decision above. Nothing reads them; deleting them
would mean touching every user's domain for no behavioural gain.

**A rendering difference worth knowing about:** the two paths did not
lay spreads out identically. `returnComposeImage:and:` scaled each page
*independently* to fit its half of the canvas, so a spread of two pages
with different aspect ratios came out with mismatched heights. Direct
draw normalises them. So a former "Old" user sees a *better-aligned*
spread, not merely a sharper one — verified by capture during the
removal task. This is not a regression; it is what every default-settings
user has always seen.

**How to apply:** there is now exactly one spread path. Do not
reintroduce an intermediate composite — see the two-path table and the
inviolable constraint at the top of `CLAUDE.md`, which has been updated
to describe the single remaining path.

---

## MW-3 `AppController` extraction: implementation-time refinements (2026-07-29)

**Decision:** two narrow deviations from `docs/multiwindow-plan.md`'s MW-3
scope text, both discovered while implementing and both required for
correctness or to keep the task safely committable in slices.

1. **Only `registerDefaults:` and the KeyArray/MouseArray "set default if
   absent" calls moved to `+[Controller initialize]`** — not the whole
   "defaults bootstrap and version-migration block" as the scope bullet's
   wording suggests. The skip-page substitution and the four
   `#pragma mark only under 1.2bNN` version-migration blocks stay in
   `-awakeFromNib`, unchanged. Reason: those blocks share one `oldVersion`
   snapshot with the final `Version` write-back; splitting them across two
   run times (`+initialize` before any instance exists, `-awakeFromNib`
   after) would make a genuinely-fresh-install run see a `Version` key
   already written by the time the 1.2b10 alias-migration check runs,
   silently skipping migration for a real upgrade-from-ancient-version
   profile. The 1.2b10 block also calls the instance-only
   `-pathFromAliasData:` (Alias Manager helpers), which cannot run from a
   class method without turning those helpers into class methods too — out
   of MW-3's scope. This still fully closes the ordering hazard
   `KNOWN_ISSUES` #19 is about (registration itself can no longer race
   another nib object's `awakeFromNib`); see the update there.
2. **The single-writer persistence API (`RecentItems`/`LastPages`/
   `BookSettings`) was not implemented in this pass.** `AppController` and
   the app-delegate/menu-outlet/remote-control split were completed and
   verified as their own commits; the persistence-API refactor touches the
   three highest-line-count, highest-regression-risk call sites
   (`openPage:last:`, `windowWillClose:`, `strongSetBookmark`) against real
   user data and was deferred to keep it from being rushed. See the MW-3
   task archive in `docs/tasks/` for the exact remaining call sites.

**How to apply:** a future task picking up the persistence-API piece
should read the MW-3 task archive first — it records exactly which
`openRecentMenuItem`/`bookmarkMenuItem`/`openSameFolderMenuItem` accessor
plumbing already exists on `AppController` (reusable) versus what's still
inline in `Controller.m`.

**Update (2026-07-29, `docs/tasks/2026-07-29-04-mw3-persistence-api.md`):**
the persistence API landed. `AppController` gained the single-writer methods
`-recordClosingBookSettings:...` (the `openPage:last:` "close the old book"
path), `-recordBookSettingsOnWindowClose:...` (the `windowWillClose:` path),
and the four `searchFrom*` read helpers (moved bodily from `Controller`);
`Controller` now calls `[appController ...]` at every site that used to touch
`RecentItems`/`LastPages`/`BookSettings` directly, except the ones this task
was explicitly not scoped to touch (`setOpenRecentMenu`'s self-healing
RecentItems write, the `preferencesDidChange:` RecentItems-limit truncation,
the 1.2b10 version-migration block, and `PreferenceController`'s/
`BookmarkController`'s own writes to these keys — a fully single-writer API
would need to cover those too, left as a follow-up). The two write methods
were kept deliberately un-unified: `-recordBookSettingsOnWindowClose:...`
still removes a stale `RecentItems`/`LastPages` entry by a plain
`-pathFromAliasData:` comparison where `-recordClosingBookSettings:...` uses
`-searchFromRecentItems:`/`-searchFromLastPages:`, a pre-existing divergence
between `openPage:last:` and `windowWillClose:` that predates this refactor
and was preserved rather than reconciled. Verified end-to-end against the
real defaults domain (not a mock): opening a second test fixture while a
first was open exercised `-recordClosingBookSettings:...` (confirmed via
`defaults read` — the closed book gained a `page` entry in `RecentItems`),
and quitting the app with a book open exercised `-recordBookSettingsOnWindowClose:...`
the same way (`windowWillClose:` fires during `NSApplication`'s normal
terminate sequence). MW-3's on-device visual checklist (dock menu, bookmark
round-trip via the UI, `OpenLastFolder`-at-launch, PDF pixel rendering, Apple
Remote) is still not verified — this session had a working process launcher
and Apple Event dispatch but no working accessibility/screen-capture session,
so nothing pixel- or UI-tree-based could be checked; see
`docs/KNOWN_ISSUES.md` #22. MW-3 is not yet fully closed on that basis.
