# cooViewer (kni927 fork)

A simple macOS comic/manga viewer, forked from [tak758/cooViewer](https://github.com/tak758/cooViewer).

## Added in This Fork

### Image Resolution Display
The page bar (bottom HUD) now shows the pixel dimensions of the current image alongside the page number and filename.

- Single page: `#5/42 (page005.jpg) 1600x1080`
- Spread (two pages): `#4-5/42 (page004.jpg 800x600 | page005.jpg 800x600)`

Resolution can be toggled independently under **Preferences → Appearance → Page Number → Resolution**.

<!-- Screenshot placeholder -->
<!-- ![Resolution display](docs/screenshots/resolution.png) -->

### Right-Click → Save Image...
Right-clicking on the image opens a context menu with a **Save Image...** item.

- Saves the file as-is when the source exists on disk (no re-encoding — WebP stays WebP, JPEG stays JPEG, etc.)
- Falls back to PNG/JPEG/TIFF re-encoding when the image lives only in memory (e.g. direct archive read)
- In two-page spread mode, saves the page that was actually clicked — not always the same page

> **Setup required:** In **Preferences → Input (Mouse)**, assign a mouse button action to **Contextual Menu**. Right-clicking will then show the Save Image... menu item.

<!-- Screenshot placeholder -->
<!-- ![Right-click save](docs/screenshots/save-menu.png) -->

---

## Requirements

| Item | Minimum |
|---|---|
| macOS | 10.13 High Sierra |
| Architecture | x86\_64, Apple Silicon (Universal Binary) |

## Building

```bash
git clone --recursive https://github.com/kni927/cooViewer.git
cd cooViewer
xcodebuild -configuration Deployment
open build/Deployment/cooViewer.app
```

Submodules ([XADMaster](https://github.com/tak758/XADMaster), UniversalDetector) are required — make sure to clone with `--recursive` or run `git submodule update --init --recursive` after cloning.

## Pre-built Binary

Download the latest universal binary from [Releases](https://github.com/kni927/cooViewer/releases/latest).

Built via GitHub Actions using Xcode with `-sdk macosx` flag.

> The binary is **unsigned**. macOS Gatekeeper will block the first launch — right-click the app and choose **Open** to bypass the warning.

## Upstream / Credits

This fork is based on [tak758/cooViewer](https://github.com/tak758/cooViewer), which itself merges improvements from:

- [plife18/cooViewer:custom](https://github.com/plife18/cooViewer/tree/custom) — Monterey/arm64 support, XADMaster submodule, Big Sur icon, fullscreen margin fix
- [u39ueda:fix/pagebar_minus_index_exception](https://github.com/u39ueda/cooViewer/tree/fix/pagebar_minus_index_exception) — page bar crash fix
- [u39ueda:feature/image_dpi](https://github.com/u39ueda/cooViewer/tree/feature/image_dpi) — ignore DPI setting

Original application by [coo-ona/cooViewer](https://github.com/coo-ona/cooViewer).

## License

See [Licence.txt](Licence.txt), [Licence_RemoteControlWrapper.txt](Licence_RemoteControlWrapper.txt), and [Licence_xad.txt](Licence_xad.txt).
