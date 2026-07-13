# cooViewer — Known Issues / Things to Be Careful About

This document collects fragile areas, gotchas, and "do not touch lightly" spots
in the codebase. Read this before making non-trivial changes.

---

## 1. MRC (Manual Reference Counting) Project — Watch Out for ARC Mixing

cooViewer's own code is built with **MRC** (Manual Reference Counting) as the
baseline, while the submodules (XADMaster, UniversalDetector) may be built
with ARC (or a mix, depending on the file).

- Do **not** assume ARC semantics (no automatic `retain`/`release`/`autorelease`,
  no implicit `__strong`/`__weak`) when editing `.m` files in the main project.
- When passing objects across the MRC/ARC boundary (e.g. calling into
  XADMaster), be careful about ownership — bridging mistakes here cause subtle
  leaks or over-releases that are hard to reproduce.
- New files added to the project should match the memory-management model of
  the surrounding code unless there's a strong reason to change it (and if you
  do change it, set the `-fobjc-arc` / `-fno-objc-arc` compiler flag explicitly
  for that file in the Xcode build phase).

---

## 2. Nib Dependency — Interface Builder Must Stay in Sync

Several controllers (`Controller`, `PreferenceController`, etc.) are wired up
through `Base.lproj/MainMenu.xib`.

- Any change to an `IBOutlet` or `IBAction` in the `.h`/`.m` files **must** be
  mirrored in the `.xib` (rename, retype, rewire, or remove the connection).
  Forgetting this causes a crash at launch (`NSUnknownKeyException`,
  "this class is not key value coding-compliant for ...") or silently broken
  UI (outlet is nil).
- Conversely, if you delete or rename a control in Interface Builder, check
  that no outlet/action in code still references the old name.
- `MainMenu~.nib` is a **legacy** nib kept for reference only — do not edit it,
  and do not confuse it with the active `MainMenu.xib`.
- Xcode's nib editor can silently leave stale connections behind; after editing
  the xib, build and actually launch the app to confirm there's no
  KVC-compliance crash on startup.

---

## 3. Two-Page Spread Left/Right Detection Is Complex

The logic that decides which physical side (left/right on screen) corresponds
to which logical image (`firstImage`/`secondImage`) depends on **both**:

- the current `readMode` (RTL vs LTR — values `0,2` vs `1,3`), and
- the geometric composition produced by `returnComposeImage:secondImage and:firstImage`.

Mapping (from `composeImage`):
```
RTL (readMode 0,2): LEFT = secondImage, RIGHT = firstImage
LTR (readMode 1,3): LEFT = firstImage,  RIGHT = secondImage
```

This mapping is easy to get backwards, and a mistake won't crash — it will
just silently save/report/act on the *wrong page* of a spread. Any change that
touches page ordering, composition, or click-to-page mapping should be
re-tested in **all four** `readMode` values, with both single pages and
two-page spreads.

---

## 4. `imageInfoForClickPoint:` Is Fragile — Touch Carefully

`Controller.m`'s `imageInfoForClickPoint:(NSPoint)windowPoint` determines which
page of a spread was clicked by comparing the click X position against the
center X of `[[window contentView] frame]`, then re-mapping geometric
left/right to `firstImage`/`secondImage` using the `readMode` rules above.

- It returns an `NSDictionary` with `@"path"` (used for the filename and direct
  file copy) and `@"image"` (an `NSImage`, used as a re-encode fallback).
- There is a known-fixed edge case where the `iS < 0` guard previously returned
  the wrong image for the `@"image"` key (`firstImage` instead of
  `secondImage`) — a reminder that the guard branches here are easy to get
  wrong because they're only reachable in specific spread/index combinations
  that are rarely exercised manually.
- When modifying this method, manually test: single-page mode, two-page spread
  in both reading directions, and clicks very close to the page boundary
  (the geometric center line).

---

## 5. `mouseAction:` Case 59 — Special-Cased, Reason Unclear, Do Not Refactor Blindly

In `Controller_input.m`, the mouse action dispatcher's **case 59**
("Contextual Menu") is handled specially: it calls `[imageView menu]` (the
standard `NSView -menu` property) rather than going through the generic
mouse-action machinery used by other cases.

- The exact historical reason for this special case is **not documented** and
  not obvious from the surrounding code.
- `CustomImageView` overrides `-menu` (not `menuForEvent:`) specifically so
  that this path returns the Save Image... context menu — see Feature #2 in
  `docs/DEV_LOG.md`.
- **Do not** override `menuForEvent:`, change `rightMouseDown:` to call
  `super`, or "simplify" the case 59 branch to match the other cases without
  thorough manual testing — earlier attempts in this vein broke the existing
  mouse-action configuration (right-click stopped routing through
  `mouseAction:` at all).
- The flow to keep in mind:
  ```
  rightMouseDown: → mouseDown: → (on mouseUp:) mouseAction: → case 59 → [imageView menu]
  ```

---

## 5b. Parent-Folder Access Must Stay Lazy (Don't Reintroduce Eager Scans)

`setSameFolderMenu:` (builds the **Open from same folder** submenu) and
`checkCurrentFolderUpdated` (detects whether the current book's folder moved)
both call `NSFileManager` APIs (`contentsOfDirectoryAtPath:`,
`attributesOfItemAtPath:`, `fileExistsAtPath:`) on the **parent directory**
of the currently open book — a location the user did not explicitly pick via
`NSOpenPanel`.

- These are now triggered **only** from `menuNeedsUpdate:` (an
  `NSMenuDelegate` method), i.e. right before the "Open from same folder"
  submenu is actually displayed — see the `docs/DEV_LOG.md` entry "Repeated macOS
  Folder-Access Permission Prompts on `File > Open...`".
- **Do not** call `setSameFolderMenu:` / `checkCurrentFolderUpdated` eagerly
  again from `openPage:last:` or `applicationDidBecomeActive:` (or any other
  frequently-firing path) — doing so reintroduces a macOS folder-access
  permission dialog on every book open / app activation, regardless of
  whether the user ever uses the "same folder" feature.
- The submenu for `openSameFolderMenuItem` is created **once** in
  `awakeFromNib` and reused for the app's lifetime (`removeAllItems` +
  rebuild in place) specifically so its `NSMenuDelegate` stays attached.
  **Do not** go back to allocating a fresh `NSMenu` and swapping it in via
  `setSubmenu:` on every refresh — that drops the delegate and breaks the
  lazy-loading mechanism silently (no crash, the menu just never repopulates
  via `menuNeedsUpdate:` again).

---

## 6. NSImage Size vs. Pixel Dimensions

`NSImage.size` returns **point** dimensions, which can be affected by DPI
metadata embedded in the image file (e.g. a 300 DPI scan reports a smaller
"size" than its pixel dimensions). For anything that needs the actual pixel
resolution (HUD display, save/export, etc.), read
`NSImageRep.pixelsWide` / `pixelsHigh` instead — see `pixelSizeStringForImage:`
in `Controller.m`.

---

## 7. Scroll Wheel Handling — Precision Devices Need Accumulation

`wheelAction:` in `Controller_input.m` accumulates `deltaY` across events
(`wheelDeltaAccum` in `Controller.h`) rather than acting on a single event's
delta, because precision scroll devices (trackpads, MX-style precision mice)
emit many small fractional deltas per physical notch.

- The accumulator must be reset both when the threshold fires **and** when a
  momentum-phase (inertia) event arrives, and also when `wheelSensitivity == 0`
  (otherwise re-enabling sensitivity later can fire a spurious page turn).
- If you touch this code, test with both a traditional notched mouse wheel and
  a precision/trackpad-style device — behavior that looks correct on one can
  be broken on the other.

---

## 8. NSUserDefaults Keys Must Be Registered in `awakeFromNib`

New preference keys (e.g. `ShowResolution`) must have a default value
registered inside `Controller`'s `awakeFromNib`. Skipping this means the first
launch after an update reads `nil`/`0`/`NO` for the new key until the user
opens Preferences and the value happens to get written — leading to
inconsistent first-run behavior that's hard to reproduce once you've run the
app once locally.

---

## 9. Localized Strings

Any new user-facing string must be added to `Localizable.strings` in **both**
`en.lproj` and `ja.lproj`. Missing an entry doesn't crash — it just falls back
to the raw key string (or the other language's string, depending on lookup
order), which is easy to miss during a quick manual test in your own locale.

---

## 10. No Automated Tests — Manual Verification Required

There is no test suite. Every change — especially to the areas above — needs
to be verified by actually building (`xcodebuild -configuration Deployment`)
and running the app (`open build/Deployment/cooViewer.app`) against real
comic archives, in multiple `readMode` / preference combinations where
relevant.

---

## 11. Submodules Are Off-Limits

`XADMaster/` and `UniversalDetector/` are git submodules vendored for archive
extraction and encoding detection. Do not edit them directly in this repo —
any fix belongs upstream. If submodules appear empty after cloning, run:
```bash
git submodule update --init --recursive
```

---

## 12. Unsigned Build → Repeated Folder-Access Prompts / Gatekeeper Translocation

The project builds with `CODE_SIGN_IDENTITY = ""` (no Developer ID — at most
an implicit ad-hoc signature on Apple Silicon). This is **not** an App Sandbox
issue (the app isn't sandboxed at all — no `.entitlements`, no
`com.apple.security.*` keys), but it does interact badly with two separate
macOS subsystems:

**a) TCC folder-access permissions don't persist across rebuilds**
TCC ties "allow this app to access folder X" grants to the app's code
signature/identity. An ad-hoc signature is derived from the binary's content
hash, so it changes on every rebuild — macOS then treats each new build as a
"different app" and re-prompts for folders it already granted access to
before. (See the `docs/DEV_LOG.md` entry on lazy parent-folder access — that fix
reduces *how often* the app touches folders it wasn't explicitly granted, but
can't fix this identity-churn problem.)

**b) App Translocation for binaries downloaded via GitHub Releases**
A `.app` downloaded through a browser gets a `com.apple.quarantine` extended
attribute. If launched from a quarantined location without first being moved
(e.g. straight from `~/Downloads`), macOS runs it from a **randomized
read-only path** (`/private/var/folders/.../AppTranslocation/<uuid>/d/...`)
that changes on every launch — so, again, folder-access grants can't persist,
and the app may also misbehave if it ever assumes a stable bundle path.

**Workarounds (user-side, not a code fix):**
```bash
xattr -cr /Applications/cooViewer.app   # remove quarantine attribute
```
or simply move the `.app` fully into `/Applications` before first launch.

**Real fix (requires paid Apple Developer Program membership):** sign with a
Developer ID Application certificate (`DEVELOPMENT_TEAM` + proper
`CODE_SIGN_IDENTITY`) and notarize via `notarytool`. Switching to plain
ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`) does **not** meaningfully help —
the CDHash still changes every build and Translocation still applies to
quarantined ad-hoc-signed apps.
