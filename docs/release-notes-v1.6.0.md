# cooViewer v1.6.0 Release Notes

## Overview

v1.6.0 brings comprehensive multi-window support and QuickLook/Thumbnail integration to cooViewer — the project's largest feature update. You can now open multiple books simultaneously in separate windows, use native fullscreen per-window, and preview `.cbz`, `.cbr`, and `.cvbdl` files directly in Finder.

## New Features

### Multi-Window Support
- **Open in New Window** (`⌥⌘O`): Open the current book in a new window instead of replacing the active view
- **Per-Window State**: Each window maintains its own:
  - Current page and position
  - Reading direction and zoom/fit mode
  - Fullscreen state
  - Window position and size
- **Native Fullscreen**: Each window can enter macOS fullscreen independently
- **Window Restoration**: All open windows and their state are restored on next launch
- **Automatic Cleanup**: The app quits automatically when you close the last window

### QuickLook & Thumbnail Support
- **Finder Preview** (spacebar): View `.cbz`, `.cbr`, and `.cvbdl` files with quick preview
- **Finder Thumbnails** (icon view): See thumbnail images from the first page of archives
- **Supported formats**: 
  - Comic Book archives (`.cbz`, `.cbr`)
  - ComicViewer bundles (`.cvbdl`)
- Works seamlessly with Finder's native interface — no manual registration needed after install

### Menu Item for All Bookmarks Browser
- The All Bookmarks browser now has its own entry in the `File` menu for easier access
- Quickly browse and switch between bookmarks in your current book

## Improvements & Fixes

### Password-Protected Archives
- **Modal password prompt**: Password requests for nested archives (`.cbz` inside `.zip`, etc.) now appear as a window-modal sheet
- Quit deferral: The app defers quit requests while the password prompt is active, answering the prompt completes the quit

### Window Opening
- **No duplicate windows**: Opening a restored book from Finder no longer creates duplicate windows
- Seamless reintegration of Finder-opened documents with existing windows

### Quit Improvements
- Can now quit the app while a password prompt is displayed — the quit is deferred until you answer the prompt
- Improved quit handling across various modal scenarios

## Known Limitations

### Cannot Quit While Modals Are Displayed

Three scenarios remain where quit is blocked or deferred:

1. **All Bookmarks browser**: The All Bookmarks window is modal. Close it before quitting.
2. **Nested-archive password prompt**: Quit is **deferred** — answering the prompt will complete the quit (not discarded).
3. **Archive load progress sheet**: Cmd+Q is swallowed. Use an AppleEvent quit (`osascript -e 'tell app "cooViewer" to quit'`) to quit immediately, or wait for the progress to complete.

### All Bookmarks Browser Navigation

The All Bookmarks browser displays bookmarks from the current book, but does not support clicking a bookmark to jump to that page. The Open button switches to a different book in a different folder. This is a feature gap left to future consideration.

## System Requirements

- macOS 10.13 (High Sierra) or later
- Apple Silicon and Intel support

## Installation

### Homebrew
```bash
brew tap kni927/tap
brew install cooviewer
```

### Manual
Download `cooViewer-v1.6.0.zip` from the [GitHub Releases](https://github.com/kni927/cooViewer/releases) page, unzip, and drag into Applications.

## Verification

The released binary is **signed with a Developer ID certificate** and **notarized by Apple**, so you can run it directly without additional security warnings:

```bash
spctl -a -vvv /Applications/cooViewer.app
# Output should include: "valid on disk"
```

## Archive Format Support

cooViewer continues to support all previously supported formats, with QuickLook/Thumbnail support added for `.cbz`, `.cbr`, and `.cvbdl`:

- **ZIP archives** (`.zip`, `.cbz`)
- **RAR archives** (`.rar`, `.cbr`) — RAR tool not required for reading
- **7-Zip archives** (`.7z`)
- **Tar archives** (`.tar`, `.tgz`, `.tbz`, `.txz`)
- **Image files** (`.jpg`, `.png`, `.gif`, `.tiff`, `.bmp`, `.pdf`)
- **ComicViewer bundles** (`.cvbdl`) — including QuickLook support
- **Directories** (open folder as a book)

## Breaking Changes

None. All preferences and bookmarks from earlier versions are preserved.

## Credits

Multi-window support was driven by comprehensive testing against the native macOS multi-window contract, with validation across window state persistence, fullscreen behavior, and lifecycle edge cases.

---

**For detailed technical changes and bug fixes**, see the [commit history](https://github.com/kni927/cooViewer/commits/v1.6.0).
