# cooViewer

A maintained fork of the original **cooViewer** by **coo-ona**.

This project continues development of cooViewer while preserving its lightweight design and usability. It includes bug fixes, macOS compatibility improvements, and a small number of practical enhancements.

## Original Project

The original application was created by **coo-ona**.

Repository:
https://github.com/coo-ona/cooViewer

This fork is based on the maintained fork by **tak758**, which incorporates improvements from several contributors.

Many thanks to everyone who has contributed to keeping cooViewer alive.

---

## Changes in This Fork

### Image Resolution Display

The page bar (bottom HUD) now shows the pixel dimensions of the current image alongside the page number and filename.

* Single page: `#5/42 (page005.jpg) 1600x1080`
* Spread (two pages): `#4-5/42 (page004.jpg 800x600 | page005.jpg 800x600)`

Resolution can be toggled independently under **Preferences → Appearance → Page Number → Resolution**.

<!-- Screenshot placeholder -->

### Right-Click → Save Image...

Right-clicking on the image opens a context menu with a **Save Image...** item.

* Saves the original file whenever possible (no re-encoding)
* Falls back to PNG/JPEG/TIFF when the image exists only in memory
* Correctly saves the page that was clicked in two-page spread mode

> **Setup:** Assign a mouse button to **Contextual Menu** in **Preferences → Input (Mouse)**.

<!-- Screenshot placeholder -->

### Reduced macOS Folder Permission Prompts

The "Open from same folder" menu is now built lazily instead of scanning the parent directory every time a book is opened. This significantly reduces unnecessary macOS folder permission prompts.

For downloaded binaries, Gatekeeper App Translocation may still cause repeated permission requests until the quarantine attribute is removed.

---

## Requirements

| Item         | Minimum                                  |
| ------------ | ---------------------------------------- |
| macOS        | 10.13 High Sierra                        |
| Architecture | Universal Binary (Intel & Apple Silicon) |

## Building

```bash
git clone https://github.com/kni927/cooViewer.git
cd cooViewer
vendor/build-libs.sh          # one-time: builds vendored libarchive + uchardet (needs cmake)
xcodebuild -configuration Deployment
open build/Deployment/cooViewer.app
```

`vendor/build-libs.sh` builds pinned releases of
[libarchive](https://github.com/libarchive/libarchive) and
[uchardet](https://www.freedesktop.org/wiki/Software/uchardet/) as
universal dylibs into `vendor/lib/` (gitignored). Re-run it only when
the script changes.

---

## Downloads

### Homebrew

```bash
brew install --cask kni927/tap/cooviewer
```

### GitHub Release

Download the latest release from GitHub Releases.

The application is **Developer ID signed and Apple notarized**.

After extracting the archive, move the application to `/Applications`:

```bash
mv cooViewer.app /Applications/
```

If macOS displays a security prompt the first time you open the application, simply choose **Open**. This should only be required once.

Installing the application in `/Applications` also avoids Gatekeeper App Translocation, preventing repeated folder permission prompts when using features such as **Open from same folder**.

---

### Test Book

A four-page CC0 test book is available for verifying page order,
mixed image dimensions, scaling, fine lines, halftones, crosshatching,
and Japanese and English text rendering.

[Download the cooViewer Test Book](https://github.com/kni927/cooViewer/releases/latest/download/cooViewer-test-book.cbz)

## Credits

This fork is based on:

* tak758/cooViewer
* plife18/cooViewer
* u39ueda/cooViewer

Original application by **coo-ona**.

---

## License

This project is distributed under the same licenses as the upstream project.

See:

* `Licence.txt`
* `Licence_RemoteControlWrapper.txt`
* `Licence_libarchive.txt` (bundled libarchive, BSD)
* `Licence_uchardet.txt` (bundled uchardet, MPL 1.1)
