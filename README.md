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

### Page Position, File Names and Image Resolution

The page bar shows the current position, centred and in reading order: `5/42` for a single page, `4-5/42` for a spread. Its settings are under **Preferences → Appearance → Page Number**. **Show in** puts it in the bar (In bar, default), just outside it (Above bar: on the side away from the window edge, so below a bar at the top of the window), in the title bar (Title bar: the book name stays left-aligned and the position is centred on the window; a long name is shortened in the middle so it ends before the position; hidden in full screen with the title bar), or turns it off (Off). In the bar the number's size follows the bar's height, a little smaller than the bar, so a taller bar shows a larger number; **Font** sets the font for Above bar and Title bar. The bar itself (position, size, colours, auto-hide) is under **Preferences → Appearance → Page Bar**: **Set position and size…** opens a preview where the bar is dragged into place and resized by its bottom-right corner. **Fill title bar** (off by default) also shows the reading position as a light grey fill of the title bar's background, behind the book name and any position shown there: from the left up to the position, or from the right for right-to-left books, across the title bar after the window buttons. It is display only (the title bar still moves and zooms the window as usual), fainter when the window is inactive, works with the page bar shown or hidden (**Show**), and is not shown in full screen, where the title bar is hidden. The bar's default height is 18 px; a profile that still had the old default (15 px) moves to it once, and any other height is kept.

The file-name HUD shows the file names of the shown pages, with each image's pixel dimensions:

* Single page: `page005.jpg (1600x1080)`
* Spread (two pages, in screen order): `page004.jpg (800x600) | page005.jpg (800x600)`

Its settings are under **Preferences → Appearance → File Name**. **Show in** puts the file names in the corner HUD (default) or in a status bar: a full-width bar along the bottom of the window, drawn over the image (which keeps its size and place) and shown and hidden with the page bar's auto-hide. Each name is centred under its page (in a spread, the left page's under the left page and the right page's under the right page); a name too long for its page is shortened in the middle, so the two never overlap. A bottom page bar sits just above the status bar, and the other HUDs keep clear of it. Show (and its keyboard/mouse action) shows or hides the file names in either place. Resolution can be toggled independently under **Preferences → Appearance → Resolution**: in the file-name HUD, in a bar of its own (the HUD then shows only `page004.jpg | page005.jpg`), or off. A resolution bar placed in the file-name HUD's row sits beside it; placed on another row, it stays where Preferences put it whatever the file names' length.

<!-- Screenshot placeholder -->

### Right-Click → Save Image...

Right-clicking on the image opens a context menu with a **Save Image...** item.

* Saves the original file whenever possible (no re-encoding)
* Falls back to PNG/JPEG/TIFF when the image exists only in memory
* Correctly saves the page that was clicked in two-page spread mode

> **Setup:** Assign a mouse button to **Contextual Menu** in **Preferences → Input (Mouse)**.

<!-- Screenshot placeholder -->

### File → Export...

**File → Export...** (⇧⌘E) writes the open book's pages into a new `.cbz`. It is available for archive and folder books (not PDF).

* A sheet first asks for the **Pages**, using the page numbers the page bar shows: empty for every page, or a list such as `20-30`, `5` or `1-3,7,10-12`. Invalid input is reported under the field as you type, and **Continue…** stays disabled until it is fixed. Return or Enter continues; Esc cancels.
* A save panel then asks where to save. Cancelling it ends the export.
* The suggested name is `<book name>-export.cbz`, or `<book name>-export-<pages>.cbz` with chosen pages (`1-3,7` becomes `1-3_7`).
* Each page is the original file, byte for byte: no decoding or re-encoding, and no rotation, filters or spread layout. Pages of a password-protected ZIP are written decrypted; pages from archives inside the book are included like any other.
* The `.cbz` is uncompressed (stored), in the book's page order. Entries keep their original file names; when two names collide or the names would not sort in page order, every entry gets a sequence prefix instead (`0001_page.jpg`).
* The export runs in the background with a progress sheet and **Cancel**. Cancelling, a failure, closing the window or quitting leaves no file behind.
* A folder book that contains a PDF cannot export the PDF's pages; choosing one is refused with a message.

### Reduced macOS Folder Permission Prompts

The "Open from same folder" menu is now built lazily instead of scanning the parent directory every time a book is opened. This significantly reduces unnecessary macOS folder permission prompts.

For downloaded binaries, Gatekeeper App Translocation may still cause repeated permission requests until the quarantine attribute is removed.

### Finder QuickLook Support

cooViewer now ships its own QuickLook extensions, showing the cover
page of `.cbz`/`.cbr` files as the Space-preview and Finder icon
thumbnail — no need to open cooViewer itself, and no third-party app
(e.g. Simple Comic) required for this anymore.

---

## Requirements

| Item         | Minimum                                  |
| ------------ | ---------------------------------------- |
| macOS        | 12 Monterey                              |
| Architecture | Universal Binary (Intel & Apple Silicon) |

## Building

```bash
git clone https://github.com/kni927/cooViewer.git
cd cooViewer
vendor/build-libs.sh          # one-time: builds vendored libarchive + uchardet + libzip (needs cmake)
xcodebuild -configuration Deployment
open build/Deployment/cooViewer.app
```

`vendor/build-libs.sh` builds pinned releases of
[libarchive](https://github.com/libarchive/libarchive),
[uchardet](https://www.freedesktop.org/wiki/Software/uchardet/), and
[libzip](https://libzip.org/) as
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

* `LICENSE.txt`
* `docs/licenses/License_RemoteControlWrapper.txt`
* `docs/licenses/License_libarchive.txt` (bundled libarchive, BSD)
* `docs/licenses/License_uchardet.txt` (bundled uchardet, MPL 1.1)
* `docs/licenses/License_libzip.txt` (bundled libzip, BSD-3-Clause)
* `docs/licenses/License_xadmaster.txt` (RAR header-parsing logic derived from
  XADMaster, LGPL 2.1-or-later — see `Sources/CORarHeaderIndex.h`)
