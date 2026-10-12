# TASK: Page number in the page bar, file-name HUD, and Export

Received from cooViewer HQ (2026-10-12). The design decisions are the owner's
(approved in the cooViewer HQ chat, 2026-10-12).

## Background

The owner decided both features in the cooViewer HQ chat (2026-10-12), after a
design discussion in a gateway session ("☁️ cooViewer page indicator layout
ideas"; read it with `list_events` only if something below is unclear).

Today the page number HUD shows `#9-10/20 (009.jpg 1400x2000 | 010.jpg
1400x2000)`, built by `-pageStringWithNumber:resolution:`
(`Sources/BookWindowController.m`) and drawn by `Sources/AccessoryView.m`.
Saving pages is limited to the page context menu's Save Image….

## Goal

1. The page position (`9-10/20`) lives on the page bar; the old page number
   HUD becomes a file-name HUD.
2. File ▸ Export… writes the book's original page files, all or chosen pages,
   into an uncompressed `.cbz`.

## Scope

### In scope

**Part 1: page bar number and file-name HUD**

- The page bar shows the position, `9-10/20` (single page `9/20`), centred.
  No `#`. Numbers are in reading order.
- A new setting chooses where the position goes: In bar (default) /
  Overlay / Off. Overlay draws it just outside the bar, centred on the side
  away from the window edge (above a bottom bar), and follows the bar's
  auto-hide like the bar text does.
- The bar's default height grows from 15 to about 18 px so the number fits;
  pick the font size to match. Existing profiles that still hold the old
  default height (15) move to the new default once; any other stored height
  is kept.
- The number gets a subtle shadow so it stays readable over both the read
  and unread parts of the bar (`PageBarReadedColor` defaults to 50 % white).
- The old page number HUD (`ShowNumber`) becomes the file-name HUD:
  `009.jpg (1400x2000) | 010.jpg (1400x2000)`. No `#`, no position, no outer
  parentheses; parentheses only around a resolution. Show both resolutions
  even when they are equal. Spread entries stay in screen order (left page
  first), as today (KNOWN_ISSUES #3).
- With the resolution in its own bar or off (`ResolutionDisplay`), the HUD
  shows only `009.jpg | 010.jpg`; the resolution bar is unchanged.
- Preferences: the "Page Number" section is renamed "File Name", and gets
  the new position setting (or the page bar section does; choose what reads
  best and say which). Keep the `ShowNumber` key and its keyboard/mouse
  action; rename only the visible labels. The bookmark title that
  `goBookmark:` shows briefly in this HUD stays as it is.

**Part 2: Export**

- File ▸ Export… (⇧⌘E unless taken), enabled when the front window shows an
  archive or folder book. Disabled for PDF books.
- A save panel with an accessory field "Pages": empty = all pages; otherwise
  a list of pages and ranges such as `20-30`, `5`, `1-3,7,10-12`. Numbers
  are the page numbers the page bar shows. Reject invalid input (out of
  range, reversed, empty result) with a message, and keep the panel open or
  reopen it.
- Default file name `<book name>-export.cbz` for all pages; with pages given,
  `<book name>-export-<pages>.cbz` using the typed list, with characters
  unsafe in file names replaced (for example `,` → `_`).
- Contents: the original bytes of each page file, unchanged (no decoding,
  rotation, filters or spread composition); pages from an encrypted ZIP are
  the decrypted bytes; pages from nested archives are included like any
  other page. Store-only ZIP (no compression). Order follows the book's page
  order. Entry names keep the original file names, flattened; when names
  collide or when the original names would not sort in page order, prefix a
  zero-padded sequence number (`0001_`) to every entry instead.
- Runs off the main thread with a progress sheet and Cancel (solid RAR books
  can be slow). Cancel or failure leaves no partial file behind.
- An existing file at the destination is replaced only through the save
  panel's own confirmation.

**Part 3 (addendum from cooViewer HQ, owner-approved in the HQ chat,
2026-10-12): title bar and status bar positions**

The page-position setting (In bar / Overlay / Off) gains two choices:

- Title bar: the position (`3-4/12`) is shown beside the book name in the
  title bar. The title stays centred; when the title is long, the number
  sits to its right and pushes right. Prefer a title-bar accessory or
  equivalent that keeps the window's own title (and the Window menu entry)
  as the plain book name; if that is not practical, say what you chose. In
  full screen the title bar is hidden, which is acceptable.
- Status bar: a full-width bar at the bottom of the window, auto-hiding
  like the page bar, drawn semi-transparent OVER the image. The image
  layout and size must not change (no reserved space; the render path and
  its single resampling step stay as they are, `CLAUDE.md`). It shows the
  position. Keep it from overlapping a bottom page bar (for example the
  page bar sits just above it while it is shown); choose and say.

Separate commits are fine. Reports to HQ stay short: HQ reads this
session's transcript, so a pointer (what, commit, what is needed) is
enough.

### Out of scope

- PDF export, image conversion or re-encoding, any other output format.
- The items under On hold in `docs/STATUS.md`.
- A release. v1.6.8 is a separate task after this one.

### Parts

1. Page bar number and file-name HUD (one or more commits).
2. Export (one or more commits).

Subagents may do either part. The parts touch different code and can be
done in either order.

## Implementation notes

- Image-quality rule (`CLAUDE.md`): neither part may touch the render path.
  The page bar and HUDs are drawn by `AccessoryView`; Export reads bytes and
  never draws. Say in the report that the resampling count is unchanged.
- The page bar's text is drawn with `drawAtPoint:`; keep the number within
  the bar's width and clip rather than overflow on a very short bar.
- Register the new position key's default in the same place as the other
  defaults (`BookWindowController.m` near `ShowNumber`).
- Export reads pages through the existing archive classes (`COArchive` and
  subclasses, the folder loader). Do not add a new archive library; the
  vendored libzip can write a store-only ZIP.
- Add engine tests where the code allows it (page-list parsing, entry
  naming, store-only output that `unzip -l` and a re-open by cooViewer's own
  loader read back in order).
- `README.md`: update what it says about the page number and add Export,
  per `AGENTS.md`.
- `git push` when a part is done and verified; the permission dialog is the
  owner's approval (`AGENTS.md`).
- Update `docs/STATUS.md` at completion (`docs/task-workflow.md` step 4).

## Verification

Build with the `build-app` skill (engine tests ALL PASS). On-device checks
follow the `device-check` skill (main app only; no QuickLook changes here).
Ask the owner to stand by before screen operations.

Part 1:
1. Default settings: the bar shows `9/20`, then `9-10/20` in a spread, in
   both reading directions; readable over read and unread parts.
2. Overlay and Off; auto-hide hides and shows the number with the bar.
3. File-name HUD in a spread with the resolution in the HUD, in its own bar,
   and off; RTL shows the right page's name on the right.
4. A profile with the old 15 px bar height gets the new height; a custom
   height (`prefs-set`) is kept.
5. Preferences labels read "File Name"; the toggle action still works.

Part 2:
6. Export all pages of a CBZ, a non-solid RAR5, a solid RAR5 and a folder
   book; `unzip -v` shows Stored entries, byte-identical to the originals
   (compare hashes), in page order; cooViewer opens the result.
7. Pages `2-3,5` and a single page; invalid inputs are refused.
8. Encrypted ZIP book exports decrypted pages. PDF book: menu item disabled.
9. Cancel during a slow solid RAR export leaves no file.

Restore preferences and unregister the build afterwards.

## Progress

- Parts 1 and 2 committed (32ecc57, f5f8951; Export 12f4f14).
- Design change (owner decisions in chat, 2026-10-12, after an on-device
  look at the first Part 3 build):
  - Title bar mode: the book name stays left-aligned (just after the
    window buttons) and only the position is centred on the title bar; a
    long name is shortened (middle) to end before the position, which is
    always visible.
  - "Status bar" is no longer a PageBarNumber choice (popup: In bar /
    Overlay / Title bar / Off; tags 0, 1, 3, 2; a stored 4 reads as In
    bar). The bottom status bar is instead a place for the file names:
    new key FileNameLocation (0 HUD, default; 1 Status bar), Preferences ▸
    Appearance ▸ File Name ▸ Show in. ShowNumber and its action still
    show or hide the names in either place. Each entry carries the
    resolution when ResolutionDisplay is "in file name".
  - Second on-device review (owner, 2026-10-12): each status-bar entry is
    centred under its own page (left page's name under the left page,
    right page's under the right page; a single page under the page),
    truncated to stay within its page with a gap so they never overlap,
    and inside the bar. Page spans come from the image view's own
    geometry, read only (-[CustomImageView shownPageRectsInView:]: the
    same -getDrawImagesInfo:and: / -getDrawImageInfo: and rotation as
    -drawRect:, nothing drawn, fRect/sRect restored); stacked pages
    (90/270 rotation) or no geometry (Preferences preview) fall back to
    the bar's halves. Redrawn on page turn, fit/zoom change
    (-drawAccessory), window resize (-setFrame:) and scrolling (clip view
    bounds notification).
- Last completed step: all three parts committed (Part 3: 3c0903f), built,
  tested and checked on device; Implementation Result filled in; task
  archived.
- Current partial state: none.
- Exact next step: none (task complete). v1.6.8 is a separate task.

## Implementation Result

**Status:** Completed with follow-up issues

### Changes

Commits: 32ecc57 (Part 1), f5f8951 (Part 1 follow-up), 12f4f14 (Part 2),
3c0903f (Part 3); merge 447ed03. Also 21488ea (device-check skill: the
cause of computer use's "user interrupt" and its tool limits) and 0839af7
(STATUS note on Part 3).

**Image quality:** the resampling count is unchanged in every part (one
`drawInRect:` per page). The page bar number, the HUDs, the status bar and
the title-bar label are overlay or window-chrome drawing; Export reads bytes
and never decodes or draws.

**Part 1: page bar number and file-name HUD** (32ecc57, f5f8951)

- The page bar shows `9/20` / `9-10/20`, centred, in reading order, with a
  subtle shadow; clipped to the bar's width. New key `PageBarNumber`
  (0 In bar, default; 1 Overlay; 2 Off; 3 Title bar from Part 3; an unknown
  value such as 4 reads as 0), registered with the other defaults. The
  setting is in **Preferences ▸ Appearance ▸ Page Bar ▸ Number**, since it
  describes the bar.
- Default bar height 15 → 18 px; `PageBarHeightMigrated` moves a stored 15
  to 18 once and keeps any other height. Bottom-corner HUDs are offset to
  clear the taller bar.
- The `ShowNumber` HUD is now the file-name HUD:
  `009.jpg (1400x2000) | 010.jpg (1400x2000)`, or `009.jpg | 010.jpg` when
  the resolution is in its own bar or off; spread entries in screen order
  (KNOWN_ISSUES #3). Formatting is in `Sources/COPageLabel.{h,m}` (engine
  tested). The "Page Number" Preferences box is "File Name"; the
  `ShowNumber` key and action are kept, their visible labels read
  "ShowFileName". The bookmark title shown by `goBookmark:` is unchanged.
- Follow-up (f5f8951, owner review): the number is drawn at the HUD text
  size (File Name font). A resolution bar in the file-name HUD's corner but
  on another row no longer moves with the names' width (pre-existing since
  b43828d / v1.6.7, made visible by the shorter Part 1 text: short single
  page names pushed it off the left edge); stored `Margin_Resolution`
  values are converted once (`ResolutionMarginMigrated`).

**Part 2: Export** (12f4f14)

- File ▸ Export… (⇧⌘E), enabled for archive and folder books, disabled for
  PDF. Pages: empty = all, or lists such as `2-3,5`; invalid input (out of
  range, reversed, empty) is refused live. Default names
  `<book>-export.cbz` / `<book>-export-<pages>.cbz` with unsafe characters
  replaced (`,` → `_`).
- Store-only ZIP via the vendored libzip; original bytes (decrypted for
  encrypted ZIP, nested archives included), in page order; original names
  flattened, or a `0001_` prefix on every entry when names collide or
  would sort out of page order. Background run with a progress sheet and
  Cancel; written to a staging file and moved into place only on success,
  so cancel, failure, window close or quit leave no file, and an existing
  destination is replaced only after the save panel's confirmation.
- New `Sources/COExport.{h,m}` (parsing, naming, writing; engine tested),
  `Sources/COExportSession.{h,m}` (sheet, progress, cancel), additions in
  `COArchive`, `COImageLoader`, `CORarArchive`, `BookWindowController`,
  `AppController`; `tests/engine/test_export.m`.
- **Deviation (owner-approved in chat):** pages are asked in an app-owned
  sheet before a plain save panel, not in a save-panel accessory field.
  On current macOS the save panel's UI is out of process (NSRemoteView;
  `defaultButtonCell` is nil), so Return/Enter in an accessory field could
  not be handled or validated reliably.
- Cancel fix: cancelling a 1.8 GB solid RAR5 export first took about 30 s,
  because export shared the viewer's forward-only solid cursor and waited
  behind prefetch. Export now opens its own reader per RAR archive and
  checks for cancel every 256 KB: 0.5-0.9 s on device, ≤ 0.25 s in the
  engine test.

**Part 3: title bar and status bar** (3c0903f; addendum from cooViewer HQ,
owner-approved in the HQ chat)

- **Design changed by the owner in chat** after on-device looks at the
  first Part 3 build:
  - Title bar (`PageBarNumber` = 3): a title-bar accessory
    (`Sources/COTitleBarLabelView.{h,m}`) shows the book name left-aligned
    and the position centred on the window; a long name is shortened in
    the middle to end before the position. `window.title` (and the Window
    menu) stays the plain book name. Hidden in full screen with the title
    bar.
  - "Status bar" is not a page-position choice (popup: In bar / Overlay /
    Title bar / Off). Instead the file names can be shown in a bottom
    status bar: new key `FileNameLocation` (0 HUD, default; 1 Status bar),
    **Preferences ▸ Appearance ▸ File Name ▸ Show in**. The bar is a
    full-width semi-transparent overlay that auto-hides with the page bar;
    each page's name is centred under its page, shortened to stay within
    it. Page spans come from a read-only
    `-[CustomImageView shownPageRectsInView:]` that uses the same geometry
    as `-drawRect:`, draws nothing and restores `fRect`/`sRect`; stacked
    pages (90/270 rotation) or no geometry fall back to the bar's halves.
    The image's layout and size do not change. A bottom page bar sits just
    above the status bar, and bottom-corner HUDs clear it.

### Verification

- Build: Deployment, BUILD SUCCEEDED for Part 1, Part 2 and Part 3 (only
  pre-existing deprecation warnings, including `setAllowedFileTypes:`).
  `build/` held only cooViewer.app. f5f8951 was not built on its own: it
  was split from a combined working tree that was built and tested.
- Automated verification: engine tests ALL PASS: test_coarchive 504,
  test_imageloader 169, test_pagelabel 81, test_export 511, plus an
  `unzip -v` Stored-entries check of the export output.
- Manual verification (device-check skill; preferences backed up, restored
  and verified each time; build unregistered afterwards):
  - Part 1, items 1-5 PASS (agent and owner): position in both reading
    directions, Overlay and Off with auto-hide re-show, file-name HUD with
    the resolution in the HUD / own bar / off and RTL order, 15 → 18 px
    migration with a custom height kept, "File Name" labels and the toggle
    action. The owner confirmed the number size and the resolution bar
    fix.
  - Item 6 PASS: CBZ, non-solid RAR5, solid RAR5 and folder books exported;
    `unzip -v` shows Stored entries in page order, sha256 identical to the
    originals; cooViewer reopened each result.
  - Item 7 PASS (owner, with the pages sheet): invalid inputs refused
    live, Return/Enter accepted, names such as `test-export-2-3.cbz`,
    contents checked with `unzip -v` CRCs.
  - Item 8 PASS: an encrypted ZIP book exported decrypted pages, sha256
    identical (the owner entered the password); the menu item is disabled
    for a PDF book.
  - Item 9 PASS after the cancel fix: cancel took 0.5-0.9 s and left no
    file; Replace then Cancel kept the old file; a full 600-entry export
    was intact.
  - Part 3 PASS (owner): title bar with the name on the left and the
    position centred; status bar names under their pages in both reading
    directions, through resize, zoom and scrolling.
- Not performed: Esc on the export progress sheet by tool (the Cancel
  button was used); the staging directory under TemporaryItems was not
  inspected directly (only a disk-space check); Overlay readability over a
  white page; the title-bar height with the accessory was not measured;
  Japanese pop-up widths were seen only by the owner in passing.

### Remaining Issues

- The string "Enter page numbers and ranges…" is left unused in the en/ja
  `Localizable.strings` (from the dropped accessory-field design).
- Exported entries get the current modification time; the originals'
  timestamps are not kept.

### Follow-up Suggestions

- AppController's Finder/drop routing does not treat a window with an
  export running as busy, so a new book can replace it mid-export (the
  export still completes correctly with its own loader).
- `CORarArchive` next-page prefetch follows page order, so solid books
  whose stream order differs from page order may still restart the
  viewer's cursor (speed only).
- `COBottomHUDOffset` ignores `Margin_PageBar` (pre-existing behaviour of
  the old constant).
- On a top page bar, a very large HUD font on a very short bar could reach
  the HUD row.
- Computer-use limits are now in the device-check skill: accessory fields
  and secure input cannot be typed by the tool, and screen-operating
  subagents should run in the foreground.
