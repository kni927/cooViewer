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
- Image layout (from `returnComposeImage:secondImage and:firstImage`):
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

**Two-page image composition:**
```
composeImage → returnComposeImage(secondImage, firstImage)
  RTL: secondImage=LEFT, firstImage=RIGHT
  LTR: firstImage=LEFT, secondImage=RIGHT
```
