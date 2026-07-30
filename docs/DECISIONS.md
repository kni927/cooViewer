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

**Update (2026-07-29, `docs/tasks/2026-07-29-05-mw3-visual-verification.md`):**
a screen-sharing session made the whole checklist checkable. `System Events`
UI scripting (unlike the two prior sessions) worked correctly, so dock menu
(both states), the bookmark add→persist-on-close→reopen→menu-restore
round-trip, `OpenLastFolder`-at-launch, and `Recent Books`/Open Recent were
all verified with real UI actions against real app state — all **passed**,
no defects found. Screen Recording was initially still missing (a separate
grant from Accessibility), but once granted to the correct process (found
via the OS's own consent-prompt naming it, not the visible terminal app —
see `docs/KNOWN_ISSUES.md` #22), `screencapture` started working and **PDF
pixel rendering was confirmed correct**: text, diagrams, and colour all
sharp and matching macOS Preview.app's rendering of the same file,
byte-for-byte the same content. (One screenshot along the way briefly
showed a solid-black page and was almost misreported as a rendering defect
— it was a first-paint timing artifact of the screenshot, not the app; see
the same KNOWN_ISSUES entry.) Only Apple Remote remains unverified, for
lack of hardware, as in every session across the whole multi-window
refactor — an accepted, permanent gap, not a new problem. **With that as
the sole remaining caveat, MW-3 is now fully closed; MW-4 can proceed.**

---

## MW-4 `validateMenuItem:` split: extract one branch to an accessor, don't duplicate or convert to selector dispatch (2026-07-29)

**Decision:** now that the 18 book/view menu actions target First Responder
(resolving to `Controller` via the window's delegate) and only
`open:`/`openTheLastPage:`/`preferences:`/`clearRecent:` stay explicitly
targeted at `AppController`, `-[AppController validateMenuItem:]` no longer
needs to forward every call to `-[Controller validateMenuItem:]` — it is now
only ever invoked for its own 4 items. Rather than leaving the wholesale
forward in place (correct but pointless: `Controller`'s title-switch would
run for titles it can no longer receive from anywhere else) or converting
either method to selector-based dispatch (explicitly out of scope per
`docs/multiwindow-plan.md`), the single title branch that actually belonged
to an `AppController` item — "Open the last page" — was extracted verbatim
into a new `-[Controller validateOpenTheLastPageMenuItem]` accessor. Its
body is byte-for-byte the original branch; only its container changed.
`-[AppController validateMenuItem:]` now checks that one title and calls the
accessor, defaulting to `YES` for its other items — the same result
`Controller`'s old default `contextMenu` fallthrough produced for them.

**Why an accessor and not exposing the underlying ivars:** the branch reads
`window`/`currentBookPath`/`defaults`, all private to `Controller`. Adding
public accessors for each would leak window-side state for a single call
site; a single-purpose accessor matches the existing pattern already used
for `AppController`↔`Controller` communication (`hasBookOpen`,
`sheetParentWindow`, `thumController`, `pathFromAliasData:`).

**Why this doesn't touch the other 34 branches:** every other title belongs
to an item still explicitly targeted at `Controller` (the 8 `RightMenu`
`contextAction:` items, `sheetOk:`/`sheetCancel:`) or resolves to
`Controller` via First-Responder chain search (the 18 retargeted actions) —
in both cases AppKit calls `-validateMenuItem:` directly on `Controller`,
so those branches must stay there unchanged.

**Verified on-device** (`docs/tasks/2026-07-29-06-mw4-menu-actions-responder-chain.md`):
with a book open, all 18 retargeted items show `enabled=true` via `System
Events`, respond correctly when invoked (`rotateRight:` visibly rotated the
page, `fitToScreenWidth:` moved the View-menu checkmark), and
`editBookmark:` opened its sheet correctly. With the window closed, all 18
show `enabled=false` — First-Responder resolution fails over to "no
target found" and AppKit auto-disables, without `Controller`'s
`validateMenuItem:` branches ever running, reproducing (and in one case —
`editBookmark:`'s previously-always-`YES` dead-code path — correcting) the
old `[window isVisible]` checks without any code duplicating that check per
retargeted item. `Open the last page` correctly stayed enabled with no
window open (real `RecentItems` was non-empty) and invoking it correctly
reopened the last book, confirming the extracted accessor behaves
identically to the original inline branch.

---

## MW-5 nib split: `BookmarkController` must be split *before* the nib, and `-windowDidLoad` replaces `-awakeFromNib` (2026-07-29)

Three decisions taken while splitting `MainMenu.xib` into `MainMenu.xib` +
`BookWindow.xib`. See
`docs/tasks/2026-07-29-07-mw5-bookwindow-controller.md`.

**1. The class split precedes the nib split, not the other way round.**
`docs/multiwindow-plan.md`'s MW-5 lists the `BookmarkController` split as
item 5 and TASK.md's suggested commit order put it after the nib work
("Land B before D/E"). That ordering is not possible. `BookmarkController`
was one nib object owning *two* panels: the per-book Bookmark sheet, which
belongs to a book window, and the app-wide All Bookmark browser, which does
not. A single object cannot be a top-level object's owner in two nibs, so the
class had to be split into `BookmarkController` + `AllBookmarkController`
*first*, and only then could the per-book half move into `BookWindow.xib`.
The general rule for the rest of the arc: **an object that owns UI with two
different lifetimes is a prerequisite for, not a consequence of, splitting the
nib that holds that UI.**

**2. `-awakeFromNib` → `-windowDidLoad` for the window controller.**
`NSWindowController` gives the class a documented once-only hook that runs
after the whole nib is instantiated and connected. `-awakeFromNib` does not:
AppKit leaves the order between nib objects' `-awakeFromNib` undefined, the
same hazard recorded as `docs/KNOWN_ISSUES.md` #19 and the reason MW-3 moved
`registerDefaults:` into `+initialize`. The body pushes settings into
`imageView`, `thumController` and `fullImagePanel`, so it genuinely depended
on that undefined order. `AppController` must therefore assign itself with
`-setAppController:` between `-initWithWindowNibName:` and the first `-window`
call, because `-windowDidLoad` reads it — the nib load is lazy and that
window is the trigger.

**3. Cross-nib connections go through `AppController`, never through a
second outlet into the other nib.** Seven connections crossed the new
boundary. `PreferenceController` (app-wide, stays in `MainMenu.xib`) lost its
`controller` and `window` outlets and gained an `appController` outlet;
`AllBookmarkController` did the same in the previous commit.
`-sheetOk:`/`-sheetCancel:` moved to `AppController` because their only
callers are the Preferences panel's buttons, which stay in `MainMenu.xib`.
The Filter menu item, whose controller moved *into* `BookWindow.xib`, now
targets First Responder and resolves to a one-line forwarder on
`BookWindowController` — the same mechanism MW-4 established for book/view
actions, extended to a panel that is now genuinely per-window.

**Image quality.** The plan rated MW-5 the highest-risk task in the arc for
rendering, on the grounds that `CustomImageView`'s external configuration
(`setUseCalayer:`, `setInterpolation:`, `setIgnoreImageDpi:`, autoresizing)
and its bounds handling had to survive being recreated in another nib.
Verified by pixel comparison rather than inspection: a per-window
`screencapture -l` of the book window, taken at the same size and
`fitScreenMode` before and after the move, is **byte-identical (same
SHA-256)** for both a single page and a two-page spread. Mean absolute
difference is therefore exactly 0 and the sharpness measure is trivially
unchanged. Moving the view between nibs is safe **when the whole `<customView>`
element is moved verbatim**, which is what makes the guarantee hold — a
hand-rebuilt view in Interface Builder would not have.

---

## MRC setters build the new value before releasing the old one (2026-07-29)

**Decision:** in this MRC codebase, an object setter must allocate/retain its
new value **before** releasing the old one, even when the argument looks
unrelated to it. Established while fixing `docs/KNOWN_ISSUES.md` #25.

The crash there was not a missing `retain` at some distant call site. It was
`-[AccessoryView setPageString:]` doing

```objc
[pageString release];
pageString = [[NSAttributedString alloc] initWithString:string ...];
```

where `string` was `[pageString string]` — an object *owned by* the value
being released. `-[AccessoryView setPreferences]` passes exactly that, because
re-rendering the current page string with new attributes is what it is for.
Reordering to build-then-release makes the setter correct for every caller,
including the self-referential one, and is why the fix needed no change on
the calling side.

**Consequence:** `if (!ivar) { ivar = alloc… } else { [ivar release]; ivar = alloc… }`
is an anti-pattern here, not just verbose — the `else` branch is the unsafe
ordering. `[nil release]` is a no-op, so the guard buys nothing. The same
shape still exists in `-[AccessoryView setInfoString:]`; it is unreachable
today and is recorded in #25 rather than changed, since that task was scoped
to the actual over-release.

---

## MW-6: per-window identity is a registry slot, and shared menu rebuilds stay lazy (2026-07-29)

Four decisions taken while removing the last "there is only one window"
assumptions. See `docs/tasks/2026-07-29-10-mw6-per-window-behaviour.md`.

**1. One per-window identity, assigned by the registry, used for every
autosave name.** The plan lists the main window's frame (item 1) and the
panels' frames (item 2) as independent, and they are not: both need to know
*which* window they belong to. `BookWindowController` therefore carries a
`windowIndex` — its slot in `AppController`'s window registry — assigned
before the nib loads, because the panel controllers in `BookWindow.xib` read
it from their own `-awakeFromNib`. All names go through
`-[BookWindowController frameAutosaveName:]`.

**Slot 0 keeps the historical, unsuffixed names** (`"NormalWindow"`,
`"Bookmark"`, `"FilterPanel"`). This is not cosmetic: it is what makes every
frame a user has already saved keep restoring, and it is why the
single-window case is bit-for-bit unchanged. The general rule for the rest of
the arc: **when a shared resource becomes per-window, the first window keeps
the old key.** A slot, rather than a monotonic counter, is also what keeps the
set of `NSWindow Frame …` defaults keys bounded once windows open and close —
MW-7 hands out the first free slot.

**2. The window controller owns window placement, not the window class.**
`setFrameAutosaveName:` moved out of `-[CustomWindow awakeFromNib]`. Whether a
window restores a saved frame or cascades off the previous one is a decision
about the window's *place in a set of windows*, which the `NSWindow` subclass
cannot know. Cascading is done by hand with `-cascadeTopLeftFromPoint:` seeded
from `NSZeroPoint`, which leaves the first window's restored frame untouched
and still produces the offset for the second;
`NSWindowController`'s own `-shouldCascadeWindows` is switched **off**
explicitly, because it acts only from `-showWindow:` and this app shows the
book window with `-makeKeyAndOrderFront:` — it would never have run, and two
cascade mechanisms must not silently coexist in MW-7.

**3. Rebuilding shared menu state on `-windowDidBecomeMain:` must not become
eager I/O.** The bookmark menu and the read/sort check-marks are pure
functions of the front window's ivars and are rebuilt outright. The "Open from
same folder" submenu is not: building it enumerates the book's parent folder,
and making that happen on every window activation is exactly the
folder-access-prompt problem the lazy `-menuNeedsUpdate:` build was
introduced to avoid. So activation only re-points the submenu's *delegate* and
sets a flag; the next `-menuNeedsUpdate:` turns that flag into a forced
rebuild. The forced part is required — `-setSameFolderMenu:` keeps the
existing items when the folder has not changed, and those items carry the
previous window's `target`. The delegate check also makes the whole method a
no-op when the front window has not actually changed.

**4. Read and sort check-marks are rebuilt by re-running
`-validateMenuItem:`, not by a second copy of its title dispatch.** They are
per-book overrides on a global default, so they follow the front *book*; the
logic that computes that from `readMode`/`sortMode` already exists in eight
localized-title branches of `-validateMenuItem:`. The rebuild walks the main
menu for items whose action is `changeReadModeMenu:` or `changeSortModeMenu:`
and calls that method on them. This is the same reasoning as MW-4's decision
not to duplicate or convert the title dispatch: one copy of a fragile
mechanism is better than two consistent copies that can drift.

---

## MW-7: the window registry keeps the last window, and de-duplication is keyed on the resolved book path (2026-07-29)

Decisions taken while enabling multiple windows. See
`docs/tasks/2026-07-29-11-mw7-open-in-new-window.md`.

**1. Step-0 decision 4 — "the last window closed quits the app" — is
deliberately not implemented yet, and MW-7 ships without it.** MW-7's scope
is Open in New Window and the cleanup needed to close windows safely;
quitting on the last close is a user-visible behaviour change with a
concrete hazard the task did not budget for. `-openPage:last:` closes the
window it has just ordered front when a *first* open fails, so with
`applicationShouldTerminateAfterLastWindowClosed:` returning YES, opening a
corrupt file as the first action of a session would quit the app. Instead,
`-[AppController retireWindowController:]` retires every closing window
*except the last*: that controller stays, bookless and hidden, and is what
File ▸ Open, Open the last page and the dock menu reuse — which is exactly
what the app did before MW-7, so nothing about the one-window experience
changes. Whoever implements decision 4 owns that failed-first-open path;
until then there is no empty-window state to design, because the surviving
window is never shown without a book.

Two consequences worth knowing: the surviving controller is whichever one
closed last, so it may not be slot 0 and may therefore be using suffixed
autosave names; and because it is never deallocated, its own teardown is
the one path the per-window `-dealloc`s do not exercise.

**2. "The book at this path" has exactly one definition.**
`+[BookWindowController resolvedBookPath:]` — a single image file resolves
to its parent folder, a PDF does not. It is what `-openPage:last:` already
did inline, lifted out so the de-duplication check (Step-0 decision 2) uses
the identical rule. This is the concrete form of the argument in the
multi-window decision above for why `NSDocumentController`'s `fileURL`-keyed
"already open" test would have been wrong: book identity is not file-URL
identity, and the one place that knows the difference must not be
duplicated.

**3. Open in New Window… targets AppController, not First Responder.**
MW-4 retargeted the render-path and book actions at First Responder so they
resolve to the front window. This one goes the other way on purpose:
creating a window is not something a window does, and the command has to
stay available when the front window has no book — or, once decision 4
lands, when there is no key window at all. The same split explains why
File ▸ Open keeps replacing the front window's book: only ⌥⌘O opens a
window, and a book handed over by the Finder or the Dock still replaces,
as it always has.

**4. A retired window's panels are closed with it.** The thumbnail,
bookmark, full-image and filter panels are separate windows in the same nib
as the book window, so closing the book window does not close them and
`NSWindowController` releases them when the controller is deallocated.
Left on screen they would outlive their window and then be deallocated
under AppKit's feet. `-closeAuxiliaryPanels` runs only for a window that is
actually being retired, so the last window — which is not — keeps the
pre-MW-7 behaviour of leaving its panels up.

---

## Quit-on-last-close is gated on "a book was read this session"; the Finder opens windows, File ▸ Open still replaces (2026-07-30)

The MW-7 follow-up task. See
`docs/tasks/2026-07-30-01-mw7-followups.md`.

**1. Step-0 decision 4 is implemented, guarded by session state rather
than by classifying the close.** `-applicationShouldTerminateAfterLastWindowClosed:`
returns YES only once some window has shown a book
(`didShowBook`, set from `-openPage:last:`). The alternative the task
offered — routing `-openPage:last:`'s failure close through a separate,
non-counted teardown — was rejected: it would need a second close path
whose only job is to be invisible to AppKit, and AppKit decides when to
ask the delegate, so the flag would still have to exist somewhere. Asking
"has this session read anything yet" answers the question directly, and
the state it appears to leave undefined — app alive, a book already read,
no window open — is unreachable, because reaching it is what terminates.

**The failure path is narrower than MW-7 assumed, and worth recording so
it is not re-derived.** A corrupt or empty book does *not* reach it:
`-[COImageLoader initWithPath:displayPath:readSubFolder:controller:]`
appends the bundled `empty.png` whenever a load yields no items, so
`-openPage:last:`'s `[newImageLoader itemCount] < 1` test can never fire
and a garbage `.cbz` opens as a one-page book. The reachable trigger is
`mode = -1`: a **cancelled archive read**, or a **cancelled password
prompt** on an encrypted archive. The second is one click away from a
cold launch and did quit the app before the guard.

**2. Panels are closed on every window close, not only on retirement.**
MW-7 restricted `-closeAuxiliaryPanels` to retired windows so the last
window would behave exactly as before. Decision 4 makes that impossible:
a panel left on screen is a visible window, so AppKit never asks the
delegate whether to terminate. This supersedes MW-7's decision 4 in that
record.

**3. The Finder opens windows; File ▸ Open still replaces.** MW-7 kept
`-application:openFile:` forwarding to the front window, so a book opened
from the Finder replaced that window's book. It is now the plural
`-application:openFiles:`, and each file goes through the same path ⌥⌘O
uses — de-duplicate on the resolved book path, reuse an empty window,
otherwise open a new one — so a multiple selection opens one window per
file. Step-0 decision 3 is unchanged and unaffected: File ▸ Open is a
different command and still replaces the front window's book.

**4. The Window menu was already correct and no code was written for
it.** `MainMenu.xib`'s Window menu carries `systemMenu="window"`, so
AppKit maintains the window list itself: titles, a check-mark on the
front window, selection brings a window forward, titles follow a window's
book, and the panels are excluded because `NSPanel` is excluded by
default. Building a second list from `AppController`'s registry would
have duplicated AppKit's tracking rather than avoided duplicating our
own, which is what the task's guidance was protecting against.

**5. The lookahead is per-window, and `threadCount` is not a join
counter.** It is incremented *after* the lookahead takes `lock`, so it
counts threads already inside the body; a thread detached a moment
earlier and still blocked on that lock is invisible to it, which is why
`-windowWillClose:`'s `[lock lock]`/`[lock unlock]` pair was not a join.
`pendingLookaheadCount` is incremented before the detach instead.
`-joinLookaheadThreads` runs at **both** points that destroy the state a
lookahead writes — `-windowWillClose:` and `-openPage:last:`'s
replacement of the previous book — and its wait is bounded at 2 s,
because `-loadImage:` can reach an archive read whose progress path is
driven from the main thread; a timeout degrades to the pre-existing
behaviour, which is safe only because
`+detachNewThreadSelector:toTarget:` retains the target for the thread's
duration.

---

## MW-8 window restoration: the delegate pair is the live hook, and `OpenLastFolder` is gated on the *request* count (2026-07-30)

Step-0 decision 5 — restore every window that was open at quit — is
implemented with `NSWindowRestoration`: `AppController` is the restoration
class, and `BookWindowController` carries the book. Four things about how
were settled by measurement rather than by the API's shape, and are
recorded so they are not re-derived.

**1. AppKit does not call the window controller's own restorable-state
methods.** `NSWindowRestoration.h` says the coder holds "the combined
restorable state of the window, its delegate, the window controller, and
any document". Instrumenting all four hooks on macOS 26 showed only the
`NSWindowDelegate` pair — `-window:willEncodeRestorableState:` and
`-window:didDecodeRestorableState:` — firing; the `NSResponder` methods
`-encodeRestorableStateWithCoder:` / `-restoreStateWithCoder:` are never
sent to a plain, document-less `NSWindowController`. Those two methods are
still where the work lives (the plan names them), and the delegate pair —
which `BookWindowController` also is — forwards into them. Decoding is
idempotent so that a future AppKit calling both changes nothing.

**2. `OpenLastFolder` is gated on how many windows the system *asked* to
restore, not on how many books came back.** The restoration requests all
arrive before `-applicationDidFinishLaunching:`, but the windows' state is
decoded *after* it (measured: ~200 ms later), and the books are opened a
run-loop pass later still. So at the only moment the gate can be evaluated,
neither `-hasBookOpen` nor a count of successfully decoded books exists.
"Did the system restore any windows" is also exactly the question the plan
gates the preference on. Consequence, accepted: a restored window whose
book has since been deleted suppresses `OpenLastFolder` and is left empty
— usable, never shown, and reused by the next open.

*Superseded in part (2026-07-30, KNOWN_ISSUES #32 — see "Launch-time Finder
opens wait for restoration…" below).* Two things in this paragraph have since
been corrected by re-measurement: the windows' state is decoded **before**
`-applicationDidFinishLaunching:`, not after it (what comes after is the book
open), and the gate is no longer evaluated in that method at all — it moved
to `-[AppController settleLaunch]`, where the restoration outcome *and*
whether a Finder request arrived are both known. The gate's question and the
accepted consequence above are unchanged.

**3. The book is opened one run-loop pass after the restoration pass.**
`-openPage:last:` is long, orders its window front, and can run modal (the
archive progress sheet, a password prompt, the "go to the last page?"
alert). Running that inside AppKit's restoration pass — before the app has
finished launching, before the window has its restored frame, and before
it has been put back into full screen — is asking for trouble. Deferring
by `-performSelector:withObject:afterDelay:0.0` means the book opens
exactly as any other book does, and the full-screen transition that
follows drives the existing `-windowDidEnterFullScreen:` →
`-recomposeForCurrentSize`. Restoration therefore adds **no** resampling
step: verified with a spread capture off a restored window, whose softness
measure was no higher than a plain re-open's.

**4. The book is stored as a security-scoped `NSURL` bookmark — the one
carve-out from "Alias Manager → `NSURL` bookmarks is out of scope for the
MW arc".** It is what the plan asked for, and it earns its keep: a book
renamed between quit and relaunch came back on its new path, which a stored
path could not do. cooViewer is not sandboxed, so the security scope is
inert today; requesting it costs nothing (creation succeeds unsandboxed)
and keeps the stored data valid if the app is ever sandboxed. The bookmark
is built once per book open, not per encode — encoding runs again after
every page turn.

**A window that is mid-restoration is neither empty nor open.** The window
registry's `-emptyWindowController` would otherwise hand the same window to
two restoration requests, since a restored window has no book until its
deferred open runs. `-beginRestoration` / `-endRestoration` bracket it,
with `NSApplicationDidFinishRestoringWindowsNotification` as the backstop
for a window AppKit never decodes state into.

## Apple Remote (IR) support is suspended, not removed (2026-07-30)

Apple Remote (IR) support is suspended, not removed: no current Mac has a
built-in IR receiver (the last was the 2014 Mac mini), so the feature is
inert on any modern hardware regardless of what the code does.
`RemoteControlWrapper` is kept only for Preferences ▸ Input
settings compatibility — the "AppleRemote …" entries are persisted in user
key bindings, so dropping the library would invalidate them (the earlier,
narrower "keep the library" reasoning is in `docs/KNOWN_ISSUES.md` §16 and
is not repeated here). On-hardware verification remains impossible, which
is the long-standing verification gap every MW task reported as "not
performed". Removal is deliberately not being done now: the only benefit —
minor license cleanup — does not justify the Preferences-UI change it would
require. Revisit only if a concrete cost appears, such as an actual
licensing conflict.

## Launch-time Finder opens wait for restoration, and take precedence over `OpenLastFolder` (2026-07-30)

Fixing `docs/KNOWN_ISSUES.md` #32 — a Finder open of a book that window
restoration was bringing back produced two windows on it.

**1. The measured launch order, which everything below rests on.** Every hook
was instrumented on macOS 26, with three windows to restore plus a Finder
open:

```
applicationWillFinishLaunching:
+restoreWindowWithIdentifier:   x3
-restoreStateWithCoder:         x3     <- which book each window gets is known here
NSApplicationDidFinishRestoringWindows
-application:openFiles:
applicationDidFinishLaunching:
-openRestoredBook               x3     <- ~0.3 s later; the books actually open here
```

This **corrects the comment MW-8 left** on `-applicationDidFinishLaunching:`,
which said the restored windows' state is decoded after that method. It is
decoded before it. What happens after it is the *book open*, which
`-restoreStateWithCoder:` defers by one run-loop pass (deliberately — the
window has not been given its restored frame or put back into full screen
yet). `NSApplicationDidFinishRestoringWindows` also fires when there is
nothing to restore, so it is a reliable "restoration is over" signal, but it
is not a "the restored books are open" signal — AppKit has none.

**2. A Finder request that arrives during launch is held, not acted on.**
De-duplication asks which window is *showing* a book (Step-0 decision 2, on
the resolved book path), and at the moment the request arrives no restored
window has opened its book yet. So `-application:openFiles:` queues the paths
and `-[AppController settleLaunch]` drains them through the same
`-openBookInNewWindow:` once no window has restoration work left. The
alternative — teaching de-duplication to also match a window's *pending*
restored path — was rejected: it would work only while the decode keeps
happening before the open request, which is an ordering AppKit does not
promise, and it would put a second notion of "which book is this window's"
next to the one every other caller uses.

**3. The restored window wins; it keeps its saved page.** Decided by the
project owner. The request brings that window forward and does not reset it
to page 1, which is what the de-duplication MW-7 built already does — so the
fix is a timing change, not a behaviour change.

**4. The wait is a bounded poll, not a notification.** There is no
notification for "the restored books are open" (see 1), and
`-openPage:last:` spins the run loop (MW-1's modal session), so a drain
scheduled with `-performSelector:afterDelay:` can land in the middle of a
restored book's open. `-isRestoredBookUnfinished` therefore covers all three
stages — AppKit deciding, decoded but not opened, and mid-open — and is
polled until it is clear everywhere or a 3 s deadline passes. On the deadline
the queue is drained anyway: a restoration that fails or never completes must
not silently swallow a file the user double-clicked. Verified both ways by
stalling `-openRestoredBook` by 2 s in a probe build: with the real deadline
the poll waits and de-duplication still wins (one window); with the deadline
forced to zero the file still opens, degrading to the old duplicate rather
than to a lost file.

**5. An explicit Finder request outranks `OpenLastFolder`.** The fallback used
to run in `-applicationDidFinishLaunching:`, gated on "did the system restore
any windows". That gate is now evaluated in `-settleLaunch` alongside the
drain, because at `-applicationDidFinishLaunching:` time it is not yet known
whether anything is going to open a book. It stands down for a restored
window (as before) **and** for a serviced Finder request, since opening the
last folder *and* the requested book is the same duplicate-window outcome
from the other direction. With no restoration and no request it behaves
exactly as it did.

## The archive password prompt is window-modal, and cancelling it empties the window rather than closing it (2026-07-30)

`KNOWN_ISSUES` #33's password half and #30, settled together because they are
the same code path.

**1. The prompt is a sheet with no modal loop.** MW-1 had already attached it to
the right window, but ran `[NSApp runModalForWindow:]` around it so the caller
could have the password as a return value — application-modal in everything but
appearance. `-[BookWindowController askPasswordForLoader:page:last:fromFileName:wrongPassword:]`
now uses `beginSheetModalForWindow:completionHandler:` alone. Measured: with a
sheet up on one window, the other window can be raised, becomes main, has an
enabled View/Setting menu and turns pages. Before, the whole menu bar was
disabled.

**2. The open is continuation-passing, split at one seam.** `COImageLoader`
gained an opt-in `deferPasswordPrompt`: instead of blocking to ask, it reports
`-needsPassword`, and each attempt goes back in through `-tryPassword:`, which
on success finishes exactly the work `-content` would have done. `-openPage:last:`
was split after the loader is constructed — `-openPageWithLoader:page:last:fromFileName:`
is the rest of it — so the sheet's completion handler can resume the open. Only
the loader, the page request and `fromFileName` cross the seam; everything else
was already ivars, which is why the split is three parameters rather than a
rewrite.

**3. The prompt for a *nested* archive stays synchronous.** `deferPasswordPrompt`
is per loader and only the book this window is opening asks for it. An encrypted
archive inside another archive is opened by `COImageLoader` from inside the outer
archive's entry list, where the enclosing load already runs inline, and it keeps
the old app-modal prompt. Verified with an encrypted ZIP nested in a plain one:
still prompts, still opens, menu bar disabled as before. Making that path
asynchronous too would mean suspending an open in the middle of enumerating
another archive's entries, for a case the retry loop already handles.

**4. Cancel: decision 1 of the task.** A window that already had a book keeps
showing it — nothing has been torn down at the point the prompt appears, which
is what the old code's "restore the old identity strings" branch already did. A
window with no book is left **bookless and ordered out, not closed**. That is
the state MW-8 established for a restore whose book has gone: not shown,
registered, reused by the next open — and, unlike a close, it cannot trip
quit-on-last-close, which is exactly the surprise #30 was about. Verified: after
cancelling, the next Finder open reuses the slot instead of creating a window.

**5. Wrong password: decision 2.** The sheet is re-presented in place with
"Incorrect password", with no attempt limit. Cancel is the exit that already
exists; a limit would only add a second way to fail, and it buys nothing for a
local file. Re-presented from the next run-loop pass, not from inside the
completion handler, because AppKit is still dismissing the old sheet.

**6. #30's session guard stays: decision 3, and it is still load-bearing.**
`-applicationShouldTerminateAfterLastWindowClosed:` answering `didShowBook`
looked like it might become dead weight once cancelling stopped closing
windows. It does not: the *other* live route into that failure branch is a
**cancelled archive read**, which still closes a fresh window. Reproduced on a
104 MB 7z — progress sheet, Esc, the window closed, and the app stayed alive
because of the guard. Removing it would quit the app when someone cancels the
first read of a session.

**7. A window waiting on a password is not an empty window.** `-[AppController
emptyWindowController]` skipped a window mid-restoration (MW-8); it now also
skips one whose open is waiting on a password. Without this, a second Finder
open landed on the window that already had a sheet up — a second book dropped
on top of an open in flight, with AppKit queueing the second sheet behind the
first on the same window. Found by testing "two encrypted archives at once",
which now gives two windows with two independent sheets.

**8. The launch drain deadline is not spent on human input** — scope item 4, the
one place this collides with #32. That work drains a queued Finder open once no
window has restoration work outstanding, bounded by a 3 s deadline. A restored
*encrypted* book waits on a person, so `-isRestoredBookUnfinished` now includes
"waiting on a password sheet" **and** `-settleLaunch` pushes the deadline
forward for as long as any window is in that state; the deadline still bounds
machine work that may never finish. Measured in both directions with the sheet
held for 12 s: with the pause, one window; with the pause removed in a probe
build, two — the duplicate #32 removed. Also measured on the pre-change build:
the collision did **not** exist there, because the app-modal loop stopped the
poll from running at all. It is created by making the sheet non-blocking, which
is why it is fixed here rather than reported.

**Not changed, and not a regression:** the application cannot be quit while the
password prompt is up — Cmd+Q, the Quit menu item and an AppleEvent quit are all
dropped rather than deferred. Measured identically on the pre-change build, so
the modality change neither caused nor cured it. Cancel is the way out.

*Fixed the same day, in its own task — see "Quitting with a password prompt up
needs an NSApplication subclass" below.*

## The All Bookmark browser gets its own app-targeted menu item (2026-07-30)

Fixing `KNOWN_ISSUES` #24. Which of the two possible causes was true had to be
established first, and it is the second one: the menu item was **never removed
from the nib**. `Bookmark ▸ Edit Bookmark…` exists, targets First Responder
since MW-4, and dispatches on whether the front window has a book — the sheet
if it does, the app-wide browser if it does not. With no book window there is
no responder implementing the action, so AppKit disables the item before
`-validateMenuItem:` is consulted, and the browser's branch became unreachable.
Confirmed on device before touching anything: with zero book windows the item
reports `enabled = false`.

**The browser gets its own item, `Bookmark ▸ All Bookmarks…`, targeted at
`AppController` — a deliberate exception to MW-4's First-Responder sweep.**
There is one browser for the whole application (MW-5 item 5, which is also why
MW-6 left its frame autosave name unsuffixed while every per-window panel got a
per-window one), it holds no per-window state, and it has to be reachable in
exactly the state that has no responder — no window with a book. Targeting it at
First Responder would reproduce #24. A future responder-chain sweep should leave
this item alone; `Edit Bookmark…` next to it stays on the responder chain and is
unchanged.

**The Bookmark menu's fixed head is now three items, and named.** `-setBookmarkMenu`
and `-windowWillClose:` both rebuilt the menu from index 2, silently encoding
"Edit Bookmark… + separator". Adding a second fixed item would have made both
loops delete it. They go through `kBookmarkMenuFixedItemCount` now.

**The browser's "Open" button did not work at all.** It sent
`-application:openFile:` to the book window controller — a method MW-7 deleted
when Finder opens moved to `AppController` — so it would have raised an
unrecognized selector for anyone who reached the browser. It now does what the
task settled: a book already open in some window brings that window forward
(the window is *not* re-opened — verified byte-identically, so the page is
kept), and a book that is not open replaces the front window's book, which is
what this button did when there was only ever one window. Both halves go
through `+resolvedBookPath:` and the existing registry lookup rather than a
second implementation.

**Reported, not implemented: there is no "go to this bookmark" gesture.** The
task assumed activating a bookmark navigates to its page. The panel has no such
affordance and never did: the left table lists books, the right table lists that
book's bookmarks as editable name/page rows, and the only open affordance —
the "Open" button — acts on the *book* selection and carries no page. The
per-book Bookmark panel is the same; bookmark *navigation* lives in the Bookmark
menu, which lists the front window's bookmarks and jumps to them. Adding a
page-navigating gesture to the browser would be new UI, so it is left for the
project owner to sanction rather than invented here.

**Two properties of the browser worth knowing, both pre-existing.** It runs
application-modal (`-runModalForWindow:`), so book windows cannot be operated
while it is up, and a quit request during it is dropped exactly as it is during
the password prompt. And it lists what has been *persisted* to `BookSettings`,
so a book whose window is still open — its bookmarks not yet written back —
does not appear until that window closes.

## Quitting with a password prompt up needs an NSApplication subclass (2026-07-30)

The application discarded every quit request while an archive password prompt
was showing. The fix proposed when that was first observed — dismiss the sheets
from `-applicationShouldTerminate:` — **does not work, and this was measured
rather than reasoned about.** Instrumenting the delegate method showed it firing
for an ordinary quit and not firing at all for a quit attempted with a prompt
up: AppKit's `-terminate:` refuses while a sheet is attached, before it consults
the delegate.

**So the prompts have to come down inside `-terminate:`, which means
`COApplication`, a two-method `NSApplication` subclass** (`NSPrincipalClass`,
plus the nib's File's Owner). It asks the delegate to cancel any prompt and,
when there was one, re-enters `-terminate:` one run-loop pass later — `-endSheet:`
only *starts* AppKit's dismissal, and terminating in the same pass meets the
refusal again. With no prompt up nothing is deferred and an ordinary quit
behaves exactly as before.

**Retargeting the Quit menu item at the delegate was tried first and rejected.**
It works for Cmd+Q and the menu, but a menu item bound to anything other than
`-terminate:` loses the **"Quit and Close All Windows"** alternate item AppKit
generates — a real affordance in an application with window restoration.
Verified both ways: with the custom action the app menu offers one Quit item,
with `-terminate:` restored it offers both again.

**The AppleEvent quit needs its own hook even so.** Measured: with a prompt up,
Cmd+Q and the menu item reach `-terminate:` (and so are fixed by the override),
while `osascript -e 'quit app "cooViewer"'` does not — AppKit's own handler for
`kAEQuitApplication` declines earlier. `AppController` therefore installs its own
handler for that event, from `-applicationDidFinishLaunching:` because
`NSApplication` registers its own during launch and the last registration wins.
All three routes verified with a prompt up, and with two prompts on two windows.

**A dismissed prompt is a cancel, and leaves nothing behind.** `RecentItems`,
`LastPages` and the restorable state are all written by the *second* half of the
open, which a cancelled prompt never reaches, so an archive whose password was
never entered cannot come back as a half-open window or a Recent Books entry.
Verified by quitting with two prompts up and relaunching: one restored window
for the real book, no sheets, and neither archive anywhere in the defaults.

**The two adjacent modal paths, reported rather than forced** (both were checked
because the task asked what they do):

- The **nested-archive prompt** is synchronous and app-modal by decision 3 of
  the window-modal-prompt task. Quit requests during it are blocked but
  *deferred* — answering the prompt lets the quit fire. Fixing it would mean
  undoing that decision, so it is left alone.
- The **archive-load progress sheet** runs an `NSApp` modal session (#33's
  loading half, still pending). Cmd+Q is swallowed by that session; the
  AppleEvent quit works immediately, because the handler above runs inside the
  modal run loop. The rest belongs with the deferred background-loading work.

## Unretained back-references are dropped in `-windowWillClose:`, and never with KVC (2026-07-30)

From the v1.6.0 field crash (`docs/KNOWN_ISSUES.md` #36): closing one of
several windows crashed in `-[AccessoryView drawRect:]`, because the view's
unretained `controller` outlet was left pointing at a freed
`BookWindowController`.

Two rules come out of it, and they apply to every per-window class in
`BookWindow.xib`, not just `AccessoryView`.

**1. The teardown point for an unretained back-reference is
`-windowWillClose:`, not a `-dealloc`.** By #26 the window/view group
(`CustomWindow`, `CustomImageView`, `AccessoryWindow`, `AccessoryView`) is
released *one close behind*, because AppKit holds the most recently closed
window. So every `-dealloc` in that group runs after the controller it
points at is already gone — one close too late to be useful. The window
controller is still alive in `-windowWillClose:`, which makes it the only
hook inside the interval where the dangling pointer can still be reached.

**2. Never nil an ivar with `-setValue:nil forKey:` in this project.**
cooViewer is MRC. KVC's ivar setter releases the previous value, so using it
to clear a reference to an already-deallocated object sends `-release` to
freed memory — it converts a read-after-free into an over-release, which is
strictly worse than the bug being fixed. Assign the ivar directly from a
method on the owning class.

Corollary for reviewers: **a nil check is not a fix for a use-after-free.**
An unretained outlet whose target has been deallocated is a dangling
pointer, not nil, so `if (controller && ...)` is still true and still
crashes. Guards are worth keeping as insurance once the pointer is actually
nil'd, but the fix is always the assignment.

## Deployment configuration now generates a dSYM; `build/`'s "app only" rule is unaffected (2026-07-31)

The v1.6.0 field crash (`docs/KNOWN_ISSUES.md` #36) could not be
symbolicated: `atos` against the shipped, stripped binary failed, and CI
did not archive a `.dSYM`. Root cause of the *project setting*, found by
inspection then confirmed empirically: the `cooViewer` target's
`Deployment` configuration had `GCC_GENERATE_DEBUGGING_SYMBOLS = NO` — no
`DEBUG_INFORMATION_FORMAT` was set anywhere in the project (this is a
legacy-style `.pbxproj` that predates that setting), so the only knob
actually in effect was the old one, and it was off. Setting
`DEBUG_INFORMATION_FORMAT = dwarf-with-dsym` alone would **not** have been
sufficient; both had to change together. Verified with a real build: with
only `GCC_GENERATE_DEBUGGING_SYMBOLS = NO` (the pre-existing state), no
`.dSYM` bundle was produced at all. With both settings changed, a build
produced `cooViewer.app.dSYM`, whose UUID matched the app binary's, and
`atos` resolved a real symbol to a correct file:line
(`-[AccessoryView drawRect:]` → `AccessoryView.m:636`).

Scope: only the `cooViewer` target's `Deployment` configuration was
changed. `Deployment2` (unused — see the `BufferingMode` history) and the
two QuickLook/Thumbnail extension targets keep
`GCC_GENERATE_DEBUGGING_SYMBOLS = NO`; they were not part of the crash and
changing them is out of scope for this hotfix.

**Where the dSYM lands, and why `build/`'s "only the final app" rule is not
broken by this:**

- **CI** does not use the local dev SYMROOT-redirect convention at all — it
  runs a plain `xcodebuild -configuration Deployment` with no path
  overrides, so *all* of Xcode's output, including intermediates, already
  lands directly under the repo's `build/` on the runner (pre-existing,
  not introduced by this change; that `build/` is the CI runner's own
  ephemeral workspace and is never committed). `cooViewer.app.dSYM` now
  appears there too, next to `cooViewer.app`. The release workflow zips it
  from that path (`build/Deployment/cooViewer.app.dSYM`) into
  `cooViewer-<tag>.dSYM.zip`, uploaded as a second release asset alongside
  the app zip. It is never stapled — notarization and stapling apply to
  the executable bundle, not to debug symbols.
- **Local dev builds** use the `CLAUDE.md`-documented command, which
  redirects `SYMROOT`/`OBJROOT` outside the repo and copies only
  `cooViewer.app` into the local `build/`. That copy step is unchanged, so
  the dSYM this setting now produces lands in the redirected `SYMROOT`
  (outside the repo) and is never copied into local `build/`. Confirmed by
  a real build: local `build/` still contains exactly one entry,
  `cooViewer.app`.

So both build paths keep their existing behaviour with respect to `build/`
contents; only CI gained a new artifact to pick up and ship.
