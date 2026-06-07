# cooViewer Fork — Development Log

Fork base: [tak758/cooViewer](https://github.com/tak758/cooViewer)  
Fork repo: [kni927/cooViewer](https://github.com/kni927/cooViewer)  
Released as: `v1.3.0`

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
