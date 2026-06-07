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
- IBOutlet/IBAction changes require editing `Base.lproj/MainMenu.xib` as well

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
signing alone does not help (see `docs/known-issues.md`).

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
git push origin master
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
| Preferences UI layout | `Base.lproj/MainMenu.xib` |

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
