# cooViewer Fork — Development Log

Fork base: [tak758/cooViewer](https://github.com/tak758/cooViewer)  
Fork repo: [kni927/cooViewer](https://github.com/kni927/cooViewer)  
Released as: `v1.3.3`

---

## Environment

- Language: Objective-C (MRC baseline, partial ARC in submodules)
- Build: `xcodebuild -configuration Deployment`
- macOS target: 10.13 High Sierra+
- Submodules: XADMaster, UniversalDetector (init with `git clone --recursive`)
- Preferences are stored in NSUserDefaults; new keys must be registered in `awakeFromNib`
- IBOutlet/IBAction changes require editing `Resources/Base.lproj/MainMenu.xib` as well

---

## Initial Setup Issues (solved once, record for next time)

### xcodebuild fails with exit 70 (plugin error)
```
A required plugin failed to load … DVTDownloads.framework
```
**Fix:**
```bash
sudo xcodebuild -runFirstLaunch
```

### Submodules empty after clone
```bash
git submodule update --init --recursive
```

---

## Features Added

### 1. Image Resolution Display in Page Bar

**What:** Shows pixel dimensions `(WxH)` next to page number in the bottom HUD.
- Single page: `#5/42 (page005.jpg) 1600x1080`
- Two-page spread: `#4-5/42 (page004.jpg 800x600 | page005.jpg 800x600)`

**Toggle:** Preferences → Appearance → Page Number → **Resolution** checkbox

**Files changed:**
- `Controller.h` — added `BOOL resolutionSwitch` ivar
- `Controller.m`
  - `awakeFromNib`: register default `ShowResolution = YES`
  - `setPreferences`: read `ShowResolution` into `resolutionSwitch`; refresh page string when either `numberSwitch` or `resolutionSwitch` changes
  - `pixelSizeStringForImage:` — new helper; reads pixel dimensions from `NSImageRep.pixelsWide/pixelsHigh` (not `NSImage.size` which is DPI-adjusted points)
  - `pageTextFieldString` — appends pixel size string
- `PreferenceController.h` — added `IBOutlet id showResolutionCheck`
- `PreferenceController.m` — read/write `ShowResolution` preference
- `Base.lproj/MainMenu.xib` — added Resolution checkbox (id=5001) in Page Number box; wired outlet

**Key note:** Use `NSImageRep pixelsWide/pixelsHigh` for accurate pixel dimensions. `NSImage size` returns points and is affected by DPI metadata embedded in the file.

---

### 2. Right-Click → Save Image...

**What:** Right-clicking on the image shows a context menu with **Save Image...** that saves the clicked page via NSSavePanel.

**How it works:**
- The existing mouse config system routes right-click through `mouseAction:` in `Controller_input.m`
- The "Contextual Menu" action (case 59) calls `[imageView menu]`, which is the NSView `-menu` property
- We override `-menu` in `CustomImageView` to return a menu containing Save Image...
- **Do NOT** override `menuForEvent:` or change `rightMouseDown:` to call super — that breaks the existing mouse action config

**Setup required by user:** In Preferences → Input (Mouse), assign a button to **Contextual Menu** action.

**Two-page spread: correct page detection**
- `Controller.m` `imageInfoForClickPoint:(NSPoint)windowPoint` determines which page was clicked
- Uses `[[window contentView] frame]` center X vs click X, combined with `readMode` to map geometric left/right to firstImage/secondImage
- Image layout (since 2026-07-29 from `-[CustomImageView drawImages:and:]`; was `returnComposeImage:secondImage and:firstImage` before the legacy composited path was removed):
  - readMode 0,2 (RTL): LEFT = secondImage, RIGHT = firstImage
  - readMode 1,3 (LTR): LEFT = firstImage, RIGHT = secondImage
- Returns `NSDictionary` with `@"path"` (for filename + direct file copy) and `@"image"` (NSImage for fallback encode)

**Save logic:**
1. If source file exists on disk → `NSFileManager copyItemAtPath:` (preserves original format — WebP stays WebP, etc.)
2. If in-memory / archive image → re-encode from individual page `NSImage` as PNG/JPEG/TIFF based on destination extension

**Files changed:**
- `Controller.h` — declared `currentImagePath`, `imageInfoForClickPoint:`
- `Controller.m` — implemented both methods
- `CustomImageView.m` — added `-menu` override and `saveCurrentImage:` action

---

### 3. Scroll Wheel Fix for Precision Scroll Devices

**Problem:** MX Anywhere 3S (and similar precision scroll mice) send small fractional `deltaY` values per notch (e.g. 0.1–0.5). The original code fired only when a single event's `deltaY` exceeded `wheelSensitivity`, so slow 1-notch scrolling never triggered page turns.

**Fix:** Accumulate `deltaY` across events; fire when the running total crosses the threshold, then reset.

**Also:** Reset accumulator on momentum-phase events (after user stops scrolling) to prevent unintended page turns from inertia.

**Files changed:**
- `Controller.h` — added `float wheelDeltaAccum` ivar
- `Controller_input.m` — rewrote `wheelAction:` threshold logic

**Default sensitivity:** Changed from `1.0` to `0.1` (= slider at max/High position). Most responsive out of the box.

---

## Bug Fixes

### Preferences Input Tab Renders Blank

**Cause:** `willSelectTabViewItem:` hides the current tab's view, animates the window resize, then unhides — but never forces a redraw of the incoming tab's content view.

**Fix:** Added `tabView:didSelectTabViewItem:` delegate method that calls `[[tabViewItem view] setNeedsDisplay:YES]` and `[tabView display]`.

**File:** `PreferenceController.m`

---

### `pageTextFieldString` Crash When No File Open (`nowPage == 0`)

**Cause:** Condition was `nowPage >= 0`, so `nowPage = 0` (no file loaded) passed through. `i = nowPage - 1 = -1` → `[completeMutableArray objectAtIndex:-1]` → NSRangeException crash.

**Fix:** Changed to `nowPage > 0`.

**File:** `Controller.m`

---

### `wheelDeltaAccum` Not Reset When Sensitivity = 0

**Cause:** `wheelSensitivity == 0.0` early-returned without clearing the accumulator. Re-enabling sensitivity later could fire an immediate spurious page turn.

**Fix:** Added `wheelDeltaAccum = 0.0` in the early-return path.

**File:** `Controller_input.m`

---

### `saveCurrentImage:` Nil Crash in Fallback Path

**Cause:** If `srcImage` was nil, calling `[srcImage TIFFRepresentation]` returned nil → nil `NSBitmapImageRep` → crash on `representationUsingType:`.

**Fix:** Added nil guard with an error alert before entering the encode path.

**File:** `CustomImageView.m`

---

### `imageInfoForClickPoint:` Returns Wrong Image in `iS < 0` Guard

**Cause:** Guard returned `firstImage` for `@"image"` key, but this code path is only reached when `secondImage` is non-nil, so `secondImage` is the correct image to use for index `i`.

**Fix:** Changed to `secondImage`.

**File:** `Controller.m`

---

### Repeated macOS Folder-Access Permission Prompts on `File > Open...`

**Symptom:** Opening a comic from a new folder via `File > Open...` (or
recent items / bookmarks) showed a macOS "would like to access files in
folder ..." permission dialog every single time — even though Full Disk
Access was already granted.

**Investigation:** The app is **not sandboxed** (no `.entitlements`, no
`com.apple.security.*` keys) and uses no `NSURL` security-scoped
bookmarks/resources — `currentBookPath` is stored as a plain path string
(plus a legacy Carbon `AliasHandle`/`FSRef`-based alias for "follow if
moved" support, see `pathFromAliasData:` / `aliasFromPath:`). So this isn't
an App Sandbox entitlement problem; it's the regular macOS TCC
"folder access" prompt for non-sandboxed apps (Catalina+).

The actual trigger turned out to be **eager parent-folder access right
after opening a book**:
- `setSameFolderMenu:` (builds the **Open from same folder** submenu) called
  `[[NSFileManager defaultManager] contentsOfDirectoryAtPath:superPath ...]`
  on the **parent directory** of the opened file, plus `fileExistsAtPath:`
  for every entry — and this ran immediately inside `openPage:last:`
  (i.e. on every single book open), not only when the user opened that menu.
- `checkCurrentFolderUpdated` additionally called
  `attributesOfItemAtPath:[superPath stringByResolvingSymlinksInPath]`
  on the same parent directory every time the app became active
  (`applicationDidBecomeActive:`).

Since `NSOpenPanel` only grants access to the item the user explicitly
picked (not its parent directory), this immediate "scope expansion" to the
parent folder is what macOS was prompting about — and it fired on a normal
open flow regardless of whether the user ever used the
"Open from same folder" feature.

**Fix — make parent-folder access lazy (on-demand only):**
- `Controller` now conforms to `NSMenuDelegate`; a single persistent `NSMenu`
  is created for `openSameFolderMenuItem`'s submenu in `awakeFromNib` (with
  `setDelegate:self`), instead of being recreated and swapped in via
  `setSubmenu:` on every refresh (which would have dropped the delegate).
- `setSameFolderMenu:` was rewritten to mutate that existing submenu in
  place (`removeAllItems` + rebuild) rather than allocating a new `NSMenu`.
- New `menuNeedsUpdate:` delegate method runs `checkCurrentFolderUpdated`
  and `setSameFolderMenu:NO` **only when the user is about to open the
  "Open from same folder" submenu** — i.e. right before it's displayed.
- Removed the eager `[self setSameFolderMenu]` calls from `openPage:last:`
  (fired on every book open) and the `checkCurrentFolderUpdated` call from
  `applicationDidBecomeActive:` (fired on every app activation).

**Result:** macOS now only asks for folder access when the user actually
opens **File → Open from same folder** for a given parent folder — not on
every `File > Open...`, recent-item open, or app focus change.

**Caveat:** If the binary was downloaded from GitHub Releases (unsigned /
ad-hoc signed) and launched from a quarantined location, **Gatekeeper App
Translocation** can still cause repeated prompts regardless of this fix —
because the app runs from a different randomized read-only path on each
launch, so macOS can't persist folder grants tied to it. Moving the app to
`/Applications` and/or `xattr -cr` on the `.app` works around this. Proper
Developer ID signing + notarization is the real long-term fix; ad-hoc
signing alone does not help (see `docs/KNOWN_ISSUES.md`).

**Files changed:**
- `Controller.h` — added `<NSMenuDelegate>` conformance
- `Controller.m`
  - `awakeFromNib` — create persistent submenu, set delegate
  - `setSameFolderMenu:` — mutate existing submenu instead of replacing it
  - new `menuNeedsUpdate:` — lazy trigger for folder access
  - `openPage:last:` — removed eager `setSameFolderMenu` calls (×2)
  - `applicationDidBecomeActive:` — removed eager `checkCurrentFolderUpdated` call

---

## Housekeeping

- Renamed `ﾇPRODUCTNAMEﾈ-Info.plist` → `$(PRODUCTNAME)-Info.plist` then deleted (unused artifact, not referenced in project, content outdated)
- Translated `CLAUDE.md` from Japanese to English
- Added `README.md` (English, with feature descriptions, build instructions, upstream credits)

### Multi-window refactor (MW-3): AppController persistence API (2026-07-29)

`AppController` (split out of `Controller` earlier in MW-3) gained a
single-writer API for the `RecentItems`/`LastPages`/`BookSettings` defaults
keys — `Controller` no longer reads or writes those keys directly at its
three highest-regression-risk call sites (`openPage:last:`,
`windowWillClose:`, `strongSetBookmark`). Verified end-to-end against the
real defaults domain via `open -a`/Apple Events rather than a mock; see
`docs/DECISIONS.md` ("MW-3 `AppController` extraction: implementation-time
refinements", 2026-07-29 update) and `docs/KNOWN_ISSUES.md` #22 for how.
A follow-up screen-sharing session (same day) then verified the whole
on-device checklist for real: dock menu (both states), the bookmark
add→persist-on-close→reopen→menu-restore round-trip, `OpenLastFolder`-at-
launch, Open Recent, and — once Screen Recording permission was tracked
down to the right process and granted — real pixel-level PDF rendering, all
passed with real evidence and no defects found. Only Apple Remote remains
unverified (no hardware, as in every session of this refactor) — an
accepted, permanent gap. **MW-3 is fully closed**; see
`docs/DECISIONS.md`'s 2026-07-29 update and
`docs/tasks/2026-07-29-05-mw3-visual-verification.md`. MW-4 can start next.

### Multi-window refactor (MW-4): menu actions onto the responder chain (2026-07-29)

The 18 book/view menu actions in `MainMenu.xib` (`slideshow:`,
`editBookmark:`, read-mode ×4, sort-mode ×4, `switchSingle:`,
`deleteSettings:`, fit-mode ×4, `rotateLeft:`/`rotateRight:`) now target
First Responder instead of a hardcoded `Controller` pointer; they resolve to
`Controller` via the window's delegate, since nothing overrides the default
responder chain. `open:`/`openTheLastPage:`/`preferences:`/`clearRecent:`
stay on `AppController` per MW-3. `-[Controller validateMenuItem:]` was
split along the same line: the "Open the last page" branch moved out to a
new `-[Controller validateOpenTheLastPageMenuItem]` accessor (body
unchanged), called from `-[AppController validateMenuItem:]`, which no
longer forwards wholesale. Render-path action bodies (`fitToScreen:` etc.)
were not touched — only their nib target, per the image-quality constraint
in `CLAUDE.md`. Verified on-device via `System Events` UI scripting: all 18
items enable/respond correctly with a book open and disable gracefully
with none, checkmarks track fit/read/sort-mode state, and invoking
`rotateRight:`/`fitToScreenWidth:` produced the correct visible effect. See
`docs/KNOWN_ISSUES.md` #23 for an `open`-invocation mistake hit during that
session (accidentally launched the Homebrew `/Applications` install instead
of the test build, which briefly touched real `RecentItems` — caught and
fully reverted, verified by diff). **MW-4 is closed**; see
`docs/tasks/2026-07-29-06-mw4-menu-actions-responder-chain.md`. MW-5 can
start next.

### Multi-window refactor (MW-5): `BookWindow.xib` + `BookWindowController` (2026-07-29)

The largest mechanical step in the arc. `MainMenu.xib` was split: the book
window, `CustomImageView`, the progress indicator, the accessory (page-bar)
window, `RightMenu`, the thumbnail panel and its controller/matrix/menu, the
per-book bookmark panel, the full-image panel and the filter panel now live
in a new `Resources/Base.lproj/BookWindow.xib`, with `ja`/`en`
`MainMenu.strings` split the same way. `Controller` became
`BookWindowController`, an `NSWindowController` and File's Owner of that nib;
`Controller_input.m` followed as `BookWindowController_input.m`. Its
`-awakeFromNib` became `-windowDidLoad`, which is ordered after every nib
object is connected — the body pushes settings into `imageView`,
`thumController` and `fullImagePanel`, so the old undefined ordering was the
same hazard as KNOWN_ISSUES #19. `AppController` now creates the single
window controller. `BookmarkController` had to be split first (per-book sheet
vs. app-wide All Bookmark browser) because one nib object cannot own
top-level objects in two nibs — a correction to the ordering TASK.md
proposed. The `window` ivar collision with `NSWindowController` was cleared
in its own commit ahead of the rename.

Image quality: per-window `screencapture` of a single page and of a two-page
spread are **byte-identical (same SHA-256) before and after**, so the arc's
highest-rated hazard — `CustomImageView`'s external configuration and bounds
handling changing as it moved nibs — did not materialise. Every panel was
exercised on device. Two pre-existing defects surfaced and were recorded, not
fixed: `docs/KNOWN_ISSUES.md` #24 (the All Bookmark browser has had no UI
entry point since MW-4) and #25 (Preferences ▸ OK crashes with a book open,
an over-released `NSString`; bisected to the last pushed commit). **MW-5 is
closed**; see
`docs/tasks/2026-07-29-07-mw5-bookwindow-controller.md`. Fixing #25 should
come before MW-6.

### Fixed the Preferences ▸ OK crash (KNOWN_ISSUES #25, 2026-07-29)

A crash that had been in the tree since before the multi-window work: with a
book open, Preferences ▸ OK killed the app with no crash dialog and no crash
report. Root cause was an aliasing bug in
`-[AccessoryView setPageString:]` — it released the old `pageString`
(an `NSAttributedString`) before building the new one, while
`-[AccessoryView setPreferences]` legitimately passes
`[pageString string]`, the old attributed string's own backing store, so the
argument was freed one line before it was read. Fixed with the standard MRC
create-then-release setter ordering; no `retain` added at the crash site, no
caller changed. Verified under `NSZombieEnabled` (crash gone *and* zombie
message gone, not just the crash window moved), plus Cancel, the no-book
case, a settings round-trip and a byte-identical render check. The identical
latent ordering in `-setInfoString:` is documented in #25 and deliberately
left alone — no caller can trigger it. Unblocks MW-6; see
`docs/tasks/2026-07-29-08-fix-preferences-ok-crash.md`.

### AccessoryView follow-ups from KNOWN_ISSUES #25 (2026-07-29)

Cleanup of the three items the #25 crash fix deliberately left out.
`-setInfoString:` got the same create-then-release setter ordering as
`-setPageString:` — prophylactic, since `infoString` still has no getter and
no caller can pass `[infoString string]`. The duplicated `-setPageString:`
call in `-setPreferences` was removed: the two calls were literally the same
expression (`-pageString` *is* `[pageString string]`), the `didFirst` guard on
the first one was dead (`didFirst` is set earlier in the same method), and the
only state changing between them affects a dirty rect that `[self display]`
supersedes. Both lines dated from the file's first commit, so there was no
intent to preserve.

The third item — a claimed `pageStringAttr` leak — **turned out not to exist**:
`-setPreferences` does release it (`AccessoryView.m:75`) before reassigning,
and `leaks` on a running build reported an unchanged 327 leaks / 25408 bytes
across three Preferences ▸ OK cycles. That follow-up note had been written
from the assignment sites without reading the release block above them; it is
retracted in the #25 archive so nobody acts on it. Two real, smaller findings
came out of the `leaks` run instead and are recorded as follow-ups:
a bounded 6-allocation leak under `-[AccessoryView setFrame:]`, and the fact
that `AccessoryView` has no `-dealloc` at all — harmless while it is a
lifetime-of-the-app nib object, but not once MW-7 gives every window its own.
Verified under `NSZombieEnabled` with a byte-identical render capture; see
`docs/tasks/2026-07-29-09-accessoryview-followups.md`. MW-6 unblocked.

### v1.5.2 released (2026-07-25)

First release actually distributed since v1.5.0 — v1.5.1 was tagged and
published as a GitHub Release but the Homebrew tap was never updated to
point at it, so it never reached users. v1.5.2 carries both the
password-protected ZIP restoration (below, originally landed as v1.5.1)
and `.cvbdl` QuickLook/Thumbnail support (below).

Built, signed, and notarized by the existing `.github/workflows/
xcode-build-and-release.yml` CI pipeline (triggered by the `v1.5.2` tag
push) rather than manually — the same tested path that shipped v1.4.0
through v1.5.1. Notarization: submission `27b37e69-ea17-443a-9db8-b94830a386ab`,
**Accepted**; stapled; `spctl` reports `source=Notarized Developer ID`.
Release: https://github.com/kni927/cooViewer/releases/tag/v1.5.2.

On-device verification against the actual notarized artifact (not a local
dev build) — the first time this was possible, since a pre-existing
`/Applications` install had blocked it in both the v1.5.1 and v1.5.2 dev
cycles (see KNOWN_ISSUES #18): `.cvbdl` now shows a real thumbnail and
Quick Look preview in Finder, confirming the QuickLook work end-to-end for
the first time; encrypted ZIP (traditional and AES-256) prompts, opens,
and re-prompts on a wrong password; ordinary CBZ/CBR unaffected. This
closes the "re-verify on real install" follow-up left by the `.cvbdl`
implementation task.

Homebrew tap (`kni927/homebrew-tap`, `Casks/cooviewer.rb`) updated to
1.5.2 and confirmed installing cleanly (`brew install --cask cooviewer`).

### QuickLook/Thumbnail support for `.cvbdl` bundles (v1.5.2, 2026-07-25)

Finder now shows real cover thumbnails and Quick Look previews for
`.cvbdl` comic bundles (the `LSTypeIsPackage` folder-based Comic Book
Format variant), instead of the generic folder icon. The main app was
already unaffected and stays that way — investigation
(`docs/tasks/2026-07-25-16-...`) found `.cvbdl` must keep going through
the generic directory-open path, since `COArchive`'s libarchive fallback
cannot open a directory as an archive stream; promoting it to a real
archive type would have broken it. Only the QuickLook/Thumbnail side
needed work: `.cvbdl` gained a real UTI
(`jp.coo.cooViewer.cvbdl-archive`, conforming to `com.apple.package`) wired
into both extensions' `QLSupportedContentTypes`, and
`COCoverExtractor.m` gained a `.cvbdl` branch that lists the bundle
directly with `NSFileManager` — bypassing `COArchive` entirely — filtering
and sorting exactly like the archive path (`imageFileTypes` +
`-finderCompareS:`) and reading the winning file's bytes straight off
disk. `tests/fixtures/make_fixtures.sh` gained a `test.cvbdl` fixture.
Verified: main app open of `.cvbdl` unaffected; a headless logic check
confirmed correct cover extraction plus clean `nil` (no crash) for an
empty bundle and a bundle with only non-image files. The on-device Finder/
QuickLook check itself could not be completed on this machine — a
pre-existing `/Applications` install (predating this feature, and the
Homebrew-managed copy `CLAUDE.md` says never to touch) keeps winning
LaunchServices' extension-identifier dedup over the freshly built
`~/Applications` copy even though the new build reports a higher version,
so Finder kept resolving to the old binary; recorded as unverified rather
than glossed over, per `docs/tasks/2026-07-25-17-...`.

### Password-protected ZIP support restored (v1.5.1, 2026-07-25)

Encrypted `.zip`/`.cbz` archives open again — the feature the original
cooViewer had and this fork lost in v1.4.0, when the archive layer moved
from XADMaster to libzip/libarchive. Rebuilt rather than ported, in three
steps: vendored libzip is now built with `-DENABLE_COMMONCRYPTO=ON`
(WinZip AES-256 plus traditional PKWARE ZipCrypto, no new runtime
dependency — CommonCrypto is in libSystem); `COZipArchive` gained
`-setPassword:` / `-cryptoStatus`, applying `zip_set_default_password` and
re-scanning the central directory, validating the password against the
first encrypted entry so a wrong one is distinguishable from a missing
one; `COImageLoader` asks the user through a new modal prompt
(`-[Controller askArchivePassword:wrongPassword:]`, NSAlert +
`NSSecureTextField`, no NIB) and re-prompts on a wrong password, with
Cancel leaving the archive closed exactly as before.

**Non-ASCII passwords work** — a Japanese-password archive (UTF-8) opens,
verified for both AES and traditional ZipCrypto. The password crosses the
libzip boundary as NUL-terminated UTF-8.

Encrypted RAR remains unsupported and still fails closed with no prompt:
libarchive detects but cannot decrypt RAR, which no build flag changes.
The QuickLook extensions never prompt — they use `COCoverExtractor`, which
links neither `COImageLoader` nor `Controller`, so an encrypted archive
simply yields no thumbnail/preview and Finder shows the default icon.
Details: `docs/tasks/2026-07-25-08-libzip-encryption-build.md`,
`…-09-cozip-password-support.md`, `…-10-password-flow-and-ui.md`.

### Double-click open-file investigation — phase 9 (2026-07-15)

Investigated a report that double-clicking a second `.cbz`/`.cbr` in
Finder while cooViewer already has a different file open activates the
app but doesn't load the new file. Confirmed via `git log -p` that
phase 7 made zero changes to `Controller.m`/`.h`, so this wasn't a
QuickLook-extension regression. Added temporary `NSLog` diagnostics to
`application:openFile:` (`Controller.m:645`) and `openPage:last:`, then
tested extensively via real Finder double-clicks and `open -a`: same-
format switching, cross-format switching, two installed copies sharing
the same bundle ID (a real, if incidental, artifact of this session's
own repeated dev-build installs — a plausible theoretical cause,
tested explicitly), and simultaneous multi-file open. **Could not
reproduce the symptom under any tested condition** — the window
correctly switched every time. Found and fixed one small, unrelated
bug along the way: `application:openFile:` always returned `NO` even
on success, violating `NSApplicationDelegate`'s documented contract;
changed to `YES`. Separately confirmed the reported Finder icon
staleness is pure caching (`qlmanage -r` resets `quicklookd`'s cache,
not Finder's separate Icon Services store) — the `coo_cbz.icns`/
`coo_cbr.icns` declarations and bundled resources are correct, verified
by direct visual comparison, not assumption. Root cause of the main
report remains undetermined; details and follow-up suggestions in
`docs/tasks/2026-07-15-02-doubleclick-open-investigation.md` and
`docs/KNOWN_ISSUES.md` #14.

### QuickLook display-order verification + cb7/cbt decision — phase 8 (2026-07-15)

Pre-release follow-up to phase 7, resolving two open questions before
shipping 1.5.0. **Display order:** built an adversarial `.cbz` fixture
where zip storage/insertion order (`page20.jpg, page10_cover.png,
page2.jpg, page1_actual_cover.png`) deliberately differs from
`finderCompareS:` natural-sort display order (`page1_actual_cover.png`
first). `COCoverExtractor` returned `page1_actual_cover.png`'s bytes
(confirmed by exact byte-length match) in 0.148s; opening the same
fixture in the main app showed the same file as page 1 (right side of
an RTL two-page spread, confirmed by reading the page-bar filename
string). Main app and QuickLook extension agree — no fix needed. This
also confirms the `finderCompareS:` sort observed earlier as
"provably equivalent" between the two code paths (same comparator,
same options, same pre-filtering for archives with only plain image
entries) holds in practice, not just in the code reading.

**cb7/cbt:** measured rather than assumed whether `.cb7`/`.cbt` are
cheap additions. Built a realistic 1.4 GB / 679-entry uncompressed
`.tar` from a real large `.cbz` fixture's own pages and timed
`COCoverExtractor` against it: **~8s** to first page via `COArchive`'s
non-lazy fallback path (the only path `.tar`/`.7z` currently have) —
far outside the ~0.1–1s bar phases 4–6 established for the equivalent
RAR case, and close enough to typical QuickLook timeouts to be risky.
A `.7z` (default solid LZMA2) built from the same content was still
compressing after 20+ minutes of heavy CPU time when aborted,
corroborating that a correct lazy decode path for solid 7z would need
work on the scale of `CORarHeaderIndex` (phase 6) — a bespoke 7z
header/folder parser — not a quick follow-up. Decision: don't add
either format this phase; `.cbt` is flagged as a reasonable
future addition (tar's simplicity means a proper lazy reader is a
much smaller lift than 7z's), `.cb7` is flagged as comparable in scope
to the whole RAR lazy-reading project. Details:
`docs/tasks/2026-07-15-01-verify-cb7cbt-release.md`,
`docs/DECISIONS.md`.

### Native QuickLook extensions for cbz/cbr — phase 7 (2026-07-14)

Replaced the Simple Comic dependency for Finder previews/thumbnails
with two native App Extension targets bundled in cooViewer.app:
`cooViewerPreview` (`QLPreviewProvider`, extension point
`com.apple.quicklook.preview`) and `cooViewerThumbnail`
(`QLThumbnailProvider`, `com.apple.quicklook.thumbnail`). Apple's own
current Xcode templates always split these into two targets/extension
points — never a single combined one — so that split was used here
too rather than attempting a merge. Both extensions share a new
`Sources/COCoverExtractor.h/.m` helper that opens the archive via the
unchanged `COArchive`/`COZipArchive`/`CORarArchive`/`CORarHeaderIndex`
readers from phases 1–6, sorts entries with the existing
`finderCompareS:` ordering (no reimplementation), and decodes only the
first page. Each extension target bundles its own copy of the vendored
dylibs (libarchive, uchardet, libzip) via a CopyFiles build phase,
mirroring the main app's pattern, since a sandboxed extension process
can't rely on the host app's loaded frameworks.

**UTI discovery (real, not assumed):** the task's premise — that
cbz/cbr "aren't standard system UTIs" — turned out to be
machine-dependent. This dev Mac has other installed comic readers
(Yomu, EdgeView 2) that already export `public.cbz-archive` /
`public.cbr-archive` as *public* UTIs, and LaunchServices resolves
`.cbz`/`.cbr` files to those rather than to cooViewer's own
newly-declared `jp.coo.cooViewer.cbz-archive`/`cbr-archive` (confirmed
via `mdls -name kMDItemContentType`, since `lsregister -dump` showed
both UTIs already claimed as `public`/`active` by other apps). Both
extensions' `QLSupportedContentTypes` list all four UTIs (the two
`jp.coo.*` ones plus the two `public.*` ones) so previews/thumbnails
work regardless of which UTI wins the resolution on a given machine.
`public.zip-archive`/`public.data` (the system's default zip/rar
handlers) are deliberately not touched.

**Sandbox (verified on-device, not assumed):** both extensions run
with `com.apple.security.app-sandbox` +
`com.apple.security.files.user-selected.read-only`, ad-hoc signed
(`CODE_SIGN_IDENTITY = "-"` — an empty identity silently drops
entitlements at build time even though the build "succeeds"). No
further entitlement was needed: QuickLook hands the extension process
a `QLFilePreviewRequest`/thumbnail request already scoped to the
specific file the user is looking at in Finder, so file access works
without a general filesystem entitlement. Verified via
`codesign -d --entitlements -` and real Finder testing (Space-preview
+ icon thumbnails) against small and large (1.9 GB `.cbz`, 1.4 GB
solid `.cbr`) fixtures — both rendered in ~1s, and a truncated/corrupt
`.cbr` fixture fell back to the generic file icon with no crash or
hang. `qlmanage -t`/`-p` were unreliable for testing App
Extension-based providers (hung / opened an interactive window) and
were abandoned in favor of driving real Finder. Details:
`docs/tasks/2026-07-14-05-quicklook-extension.md`.

Also fixed in the same phase: the main app's `Info.plist` had
`CFBundleVersion` but never wired `CFBundleShortVersionString`, so
Finder's Get Info panel showed a blank version. Added
`CFBundleShortVersionString = $(MARKETING_VERSION)` and bumped
`MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` to `1.5.0` across all 5
build configs × 3 targets.

### Fast solid RAR indexing via a revived XADMaster-derived header parser — phase 6 (2026-07-14)

Fixed the problem phase 5 diagnosed: `CORarArchive`'s open-time index
pass now tries a from-scratch, header-only RAR4/RAR5 block parser
(`Sources/CORarHeaderIndex.h/.m`) before falling back to the unchanged
phase 4 libarchive-based scan. The new parser walks the file via raw
`fseeko`/`fread` only — no decompression anywhere — reimplementing
just the block-header-walking *knowledge* from XADMaster's
`XADRARParser.m`/`XADRAR5Parser.m` (LGPL-2.1-or-later, MacPaw Inc.;
`docs/licenses/License_xadmaster.txt`) rather than restoring XADMaster's own
CSHandle/XADArchiveParser class hierarchy. Bails to the libarchive
fallback on anything it can't confidently handle: header encryption,
multi-volume archives, and (RAR4 only) `LHD_UNICODE`-flagged names,
which have a bespoke decode algorithm with no fixture available to
verify a port against.

Measured on the same 1.4 GB / 665-entry solid RAR5 fixture from phase
4/5: open 13.0s → **0.106s**; time-to-first-page (open + first-entry
decode) ~13.0s → **~0.13s**, beating even the v1.3.7/XADMaster
baseline (~0.5–1s) phase 5 measured. Non-solid open also improved
(0.19–0.21s → 0.10s). Full sequential read-through of a solid archive
still costs ~13s total (unchanged — the cursor/decode pass is exactly
phase 4's code), but that cost is now paid while reading pages
instead of blocking the initial open, matching how v1.3.7's own
background lookahead thread behaved. `docs/KNOWN_ISSUES.md` #13
(added in phase 5) is resolved and removed. No RAR4 archiver tool was
available to generate a test fixture, so
`tests/fixtures/make_rar4_fixture.py` hand-writes a minimal RAR4
(STORE method) archive from the spec, cross-checked against
libarchive's own RAR4 reader. Details:
`docs/tasks/2026-07-14-04-rar-header-parser.md`.

### Solid RAR open-time investigation — phase 5 (2026-07-14)

Diagnostic task, no code change: why does phase 4's solid RAR open
take ~13s (same order as v1.3.7's XADMaster) when v1.3.7 showed page
1 in under a second? Set up a `git worktree` at tag `v1.3.7` to
compare directly. Root cause, confirmed from both sides' source and
an instrumented progress trace: vendored libarchive's RAR5 reader
implements `archive_read_data_skip()` for solid archives by actually
calling its decompressor and discarding the output
(`archive_read_support_format_rar5.c` — `skip_mode` only disables
checksum verification, not the LZ decode); XADMaster's
`XADRAR5Parser.m` `-skipBlock:` instead does a raw
`seekToFileOffset:` based on the header's declared block size, never
touching a decompressor during enumeration, solid or not. This is a
genuine libarchive API/design limitation, not a bug or a missed flag
in `CORarArchive`. A real fix would mean writing a from-scratch
RAR4/RAR5 header-only block parser (mirroring XADMaster's strategy)
for the index pass alone — judged out of scope for this diagnostic
task per its own "stop and report back if more involved than
expected" instruction. No fix implemented; recommended as a phase 6
if wanted, plus a cheap interim idea (wire the existing byte-progress
callback into a determinate "Loading… NN%" indicator instead of an
indeterminate spinner). Details:
`docs/tasks/2026-07-14-03-solid-rar-investigation.md`.

### RAR partial lazy extraction — phase 4 (2026-07-14)

Extended the lazy-archive approach from zip (phase 2, libzip) to
rar/cbr, without adding a new dependency: `CORarArchive` does one
skip-only pass over the stream at open (`archive_read_data_skip`,
cheap — no entry data decoded) to index entries, then decodes a
requested entry on demand through a second "cursor" stream that
fast-forwards forward-only, reopening from the start on a backward
page turn. NSCache-bounded (256 MB), same policy as `COZipArchive`.

Measured on a 1.4 GB / 665-entry RAR5 fixture: non-solid open
2.060 s → 0.189 s, footprint after open 2676 MB → 2.6 MB. Solid
archives see no open-time improvement (13.8 s → 13.0 s — expected,
solid decode dominates skip cost too) but still a large memory win
(2714 MB → 34.5 MB after open). Cold backward jumps in solid
archives cost roughly proportional to distance from the start
(~6.2 s to jump halfway into the 1.4 GB solid file); verified this
doesn't affect normal forward reading of a real-world (uniform
extension) solid CBR, since RAR only reorders entries when file
types are mixed. A corrupt-archive fallback to the old
full-extraction path (mislabeled/unopenable files) turned out
trivial to add, mirroring zip's existing fallback. Details:
`docs/tasks/2026-07-14-02-rar-partial-lazy.md`.

### Source tree reorganization — phase 3: Sources/ (2026-07-14)

Pure reorg, no logic change: all 74 root-level `.h`/`.m` files moved
into `Sources/` (flat layout) via `git mv`; `project.pbxproj` path
references updated to match. `cooViewer_Prefix.pch` stays at root
(not in scope). Quote-includes (`#import "X.h"`) kept resolving
unchanged since every source moved together. Sequenced ahead of the
RAR lazy-extraction task so that diff stays clean against the new
paths. Details: `docs/tasks/2026-07-14-01-sources-reorg.md`.

### Lazy zip extraction — phase 2: libzip reader + dispatch (2026-07-13)

zip/cbz now open through COZipArchive (libzip): central directory
only at open, per-entry on-demand decode with a 256 MB NSCache, serial
read queue, next-entry prefetch. COArchive dispatches by extension and
falls back to libarchive when zip_open fails; other formats unchanged.
On a 1.9 GB / 200-entry CBZ: open 6.1 s → 0.004 s, footprint after
open 3772 MB → 2.2 MB, bounded ~400 MB during read-through. The
libzip path is locale-independent (CP932 verified under LC_ALL=C);
main.m's setlocale stays for the libarchive path. Corrupt zip entries
are now detected at read time (broken-image placeholder) instead of
being dropped at open. CI runs the engine tests now. Details:
`docs/tasks/2026-07-13-02-libzip-reader.md`.

### Lazy zip extraction — phase 1: vendored libzip (2026-07-13)

First phase of restoring per-entry lazy extraction for zip/cbz after
the v1.4.0 libarchive migration regressed open time / peak memory on
large archives. libzip v1.11.4 is now vendored via
`vendor/build-libs.sh` and bundled like libarchive/uchardet; the
reader path and on-demand cache follow in a separate task. Details:
`docs/tasks/2026-07-13-01-vendor-libzip.md`.

### v1.4.0 — libarchive + uchardet migration (2026-07-11)

Replaced the XADMaster/UniversalDetector submodules with vendored
libarchive v3.8.4 + uchardet universal dylibs (spike reports:
`docs/spike-libunarr-20260711.md` NO-GO, `docs/spike-libarchive-20260711.md`
GO). Phased work, one commit per phase:

1. **Vendoring** — `vendor/build-libs.sh` (pinned upstream commits,
   SDK-only deps, @rpath install names), Xcode link + Copy Files to
   Contents/Frameworks, CI builds the libs behind actions/cache keyed
   on the script hash.
2. **COArchive** — new engine, extract-all-to-memory (NSData per
   entry, matching how COImageLoader consumes pages), archive-wide
   uchardet name detection with pathname_utf8 fast path, corrupt
   entries skipped, progress + Esc cancel fed by
   archive_filter_bytes. Gate: `tests/engine/run_tests.sh` verifies
   names/order/SHA-256 for all fixtures — ALL PASS.
3. **Swap & removal** — COImageLoader wired to COArchive; submodules,
   XADWrapper/XADItem, password UI (PassPanel) and Licence_xad.txt
   removed; Info.plist document types pruned 65→20.
   CRITICAL detail: `main.m` calls `setlocale(LC_ALL, "en_US.UTF-8")`
   before NSApplicationMain — without it libarchive's zip reader
   corrupts CP932 filenames (0x5C trail bytes). Note that
   `sheetOk:`/`sheetCancel:` were kept: the Preferences window's
   OK/Cancel buttons share them.
4. **Release prep** — 1.4.0, release notes `docs/release-notes-v1.4.0.md`.

Dropped: LhA/LZH, StuffIt, password-protected and multi-volume
archives (v1.3.7 is the legacy option). Note: RAR5 is NOT new —
XADMaster already read it (the spike used XADMaster extraction as
the RAR5 byte-compare reference); the engine swap is for long-term
maintainability, with zip/rar5/7z/tar output verified byte-identical
to v1.3.7.

### v1.3.7 — audit quick wins (2026-07-11)

Pre-work before the libunarr migration (v1.4.0). **v1.3.7 is the last
version with LhA/LZH support** (see `docs/release-notes-v1.3.7.md`).
Based on the findings in `docs/audit-20260711.md`:

- **fix: XADWrapper/XADItem retain cycle** — items retained their
  wrapper while the wrapper's array retained the items, leaking the
  whole XADArchive graph on every archive open (verified with
  `leaks(1)`: 1267 leaks/762 KB → 0 XAD objects). Also removed a bogus
  `[archive init]` in `-dealloc` and autoreleased items on insert.
  XADItem now holds a non-retained back-reference; safe because items
  never outlive the wrapper's contentArray.
- **refactor: dead files removed** — `COImageLoader_temp.m`,
  `Controller.m_1.xcclassmodel/`, `Resources/version.plist`,
  `Resources/info copy.plist`, `Resources/icon2.icns`,
  `Resources/icon_orig.icns`. `ja.xliff` removed from the Resources
  build phase (was shipped inside the app bundle; file kept in
  `localize/`). `INFOPLIST_FILE` case fixed (`info.plist` →
  `Info.plist`) for case-sensitive file systems.
- **refactor: NSRunAlertPanel → NSAlert** (8 sites; OK stays the
  default first button). `NSBeginAlertSheet` and the Carbon Alias
  Manager deferred to their own tasks.

Earlier the same day (also in v1.3.7): resource consolidation into
`Assets.xcassets` + `Resources/` — AppIcon migrated from loose
`icon.icns` (asset catalogs reject TIFF, so UI TIFFs were converted
losslessly to PNG; `empty.png` must stay a loose file because
COImageLoader uses its file path as a page entry).

---

## Release / CI

**GitHub Actions** (`xcode-build-and-release.yml`):
- Trigger: push a tag matching `v*` (e.g. `v1.3.0`)
- Builds on `macos-latest` with default Xcode (removed hardcoded `Xcode_14.3.1`)
- Produces `cooViewer.app.zip`, uploads to GitHub Releases automatically
- Keeps only the latest 1 release (older ones auto-deleted)

**Release workflow:**
```bash
git add -A
git commit -m "feat: ..."

# Bump CURRENT_PROJECT_VERSION in cooViewer.xcodeproj/project.pbxproj
# (all 5 build configs) to match the new tag — e.g. 1.X.Y — so the
# About dialog / CFBundleVersion reflect the actual released version
# instead of going stale (it was stuck at the original 1.2b25 for a
# long time). Commit that change too, then:

git tag v1.X.Y
git push origin main
git push origin v1.X.Y
# GitHub Actions builds and publishes the release in ~10 min
```

**Versioning (semantic):**
- `v1.x.0` — new features
- `v1.x.y` — bug fixes only
- `v2.0.0` — breaking changes / major UI overhaul

**Signing gotcha (found in the 1.5.0 release, phase 8):** if any target
ships its own `.entitlements` file (as the QuickLook extensions do,
since phase 7), do **not** sign the whole app with a single
`codesign --deep --sign <identity>` pass — `codesign` does not carry
entitlements across a re-sign unless told to, so `--deep` silently
strips nested targets' entitlements even though the command "succeeds"
with no warning. Sign bottom-up instead: nested dylibs, then each
entitled target with its own `--entitlements <file>`, then the outer
app without `--deep`. See the "Sign app" step in
`xcode-build-and-release.yml` and
`docs/tasks/2026-07-15-01-verify-cb7cbt-release.md` for the verified
fix.

---

## Architecture Notes (for future reference)

| Concern | Where |
|---|---|
| Page navigation, preferences loading | `Controller.m` |
| Keyboard / mouse / wheel input routing | `Controller_input.m` |
| Image rendering, scroll, loupe | `CustomImageView.m` |
| Bottom HUD (page bar, page string) | `AccessoryView.m` |
| Image / archive loading | `COImageLoader.m` |
| Preferences UI logic | `PreferenceController.m` |
| Preferences UI layout | `Resources/Base.lproj/MainMenu.xib` |

**Mouse action flow:**
```
rightMouseDown: → mouseDown: → (on mouseUp:) mouseAction: → case 59 → [imageView menu]
```

**Page string flow:**
```
setPageTextField → pageTextFieldString → [imageView setPageString:]
```

**Two-page spread drawing** (single path since 2026-07-29 — the legacy
composited `BufferingMode = 0` path and `returnComposeImage:` were
removed; see `docs/DECISIONS.md`):
```
composeImage → [imageView setImages:secondImage]
  → drawRect: → drawImages:image1 and:image2   (each page drawn straight into the view)
  RTL: secondImage=LEFT, firstImage=RIGHT
  LTR: firstImage=LEFT, secondImage=RIGHT
```
