# TASK: Page bar settings, title-bar fill, status bar opacity, v1.6.8 follow-ups

The decisions in it are the owner's (Master 承認済み, cooViewer HQ chat, 2026-10-12 to 2026-10-15).

## Background

v1.6.8 shipped the page bar number, file-name HUD/status bar and Export
(`docs/tasks/2026-10-12-01-page-bar-and-export.md`). The owner held every
binary change after that release for the next one and decided the items
below in the cooViewer HQ chat (2026-10-12 to 2026-10-15). They are listed
in `docs/STATUS.md` ▸ On hold ("Held until the next binary change" and
"Also for the next binary change").

## Goal

The page bar's size can be set again, the page number has its own settings,
the page bar can be drawn as a fill of the title bar, the status bar's
opacity is a setting, and the small v1.6.8 follow-ups are fixed.

## Scope

### In scope

**Part 1: page bar size and page number settings**

- The page bar size can no longer be changed in Preferences (reported after
  v1.6.8). Find the cause and fix it; say whether v1.6.8 introduced it.
- The bar height is the user's setting. When the page number is drawn in the
  bar, its font size follows the bar height automatically (a little smaller
  than the bar); no separate size applies there.
- Preferences gets its own "Page Number" section: location (In bar / Above
  bar / Title bar / Off) and the font used for Above bar and Title bar. The
  "Page Bar" section keeps position, size, colours, and the new title-bar
  fill (Part 2). Existing `PageBarNumber` values keep their meaning.

**Part 2: page bar as a title-bar fill**

- A new page bar option fills the title bar's background with a light grey
  from the start up to the reading position (from the right for right-to-left
  books), behind the title and the position text. Both stay clearly readable
  in light and dark mode; lighter when the window is inactive.
- Display only: no click or drag on the title bar.
- In full screen the title bar is hidden, so nothing is shown (no fallback to
  the normal bar).
- Build it on the existing title-bar accessory (`COTitleBarLabelView`) or an
  equivalent that leaves `window.title` and the Window menu as the plain book
  name.

**Part 3: status bar opacity**

- The file-name status bar's opacity (how see-through it is over the image)
  becomes a setting, next to "File Name ▸ Show in". The current look is the
  default.

**Part 4: v1.6.8 follow-ups** (details in the v1.6.8 task archive)

1. Remove the unused "Enter page numbers and ranges…" string from the en/ja
   `Localizable.strings`.
2. Finder/drop routing must treat a window with an export running as busy,
   so a new book does not replace it mid-export.
3. Exported entries keep the original files' modification times where the
   source provides them.
4. `COBottomHUDOffset` honours `Margin_PageBar`.
5. Solid RAR next-page prefetch follows page order and can restart the
   cursor (speed only). Fix it if it is small and safe; otherwise record why
   not and leave it.

### Out of scope

- The items held as minor on 2026-10-08, OPDS, and EPUB conversion
  (`docs/STATUS.md` ▸ On hold).
- A release. It is a separate task after this one.

### Parts

Parts 1-4 as above, one or more commits each. Subagents may take parts; they
touch overlapping files (`AccessoryView`, Preferences), so run them one
after another or in separate worktrees and merge.

## Implementation notes

- Image-quality rule (`CLAUDE.md`): nothing here may touch the render path.
  The title-bar fill and status bar are window-chrome or overlay drawing; the
  image's layout and size must not change. State the resampling count in the
  report.
- Register new defaults next to the existing ones in `BookWindowController.m`.
- Keep `README.md` current for the new settings (`AGENTS.md`).
- `git push` when a part is done and verified; the permission dialog is the
  owner's approval.
- Owner steps (stand-by for screen checks) come from you only; HQ reads your
  transcript (`docs/sessions.md`). Keep reports to HQ to a short pointer.
- Update `docs/STATUS.md` at completion: move the items you finish out of
  On hold.

## Verification

Build with the `build-app` skill (engine tests ALL PASS). On-device checks
with the `device-check` skill; ask the owner to stand by first.

1. Page bar size changes in Preferences take effect; the in-bar number scales
   with it; Above bar / Title bar use the Page Number font.
2. Title-bar fill: progress in both reading directions, light and dark mode,
   active and inactive window; nothing in full screen; Window menu shows the
   plain name.
3. Status bar opacity: the setting changes the look; the image does not move.
4. Follow-ups: drop a book on a window while it exports (refused or routed
   elsewhere, export completes); exported mtimes match originals
   (`unzip -l`); HUD offset follows `Margin_PageBar`.

Restore preferences and unregister the build afterwards.

## Progress

- Last completed step: all parts done, verified on device, documented.
- Current partial state: none.
- Exact next step: none (archived).

## Implementation Result

**Status:** Completed with follow-up issues

### Changes

Environment: this Mac had no vendored libraries and no cmake; the owner
approved `brew install cmake` and `vendor/build-libs.sh` (2026-10-15).

**Part 1 (84a919e, fix 3233c11): page bar size and Page Number settings.**
- Cause of "size can no longer be changed": the drag-to-resize and the save
  of `PageBarSize` were unchanged and work (on device the height went 18 →
  46 and was saved). v1.6.8 (f5f8951, "Page bar number at HUD text size")
  made the in-bar number take its size from the File Name font
  (`TextFont`) instead of the bar height and let it spill past the bar, so
  changing the bar height no longer changed what the bar looked like. So
  yes, v1.6.8 introduced it.
- In bar: the number's size follows the bar height
  (`COPageBarInBarFontSize`, about 3 px smaller than the bar, 6 pt minimum).
- Preferences ▸ Appearance gets a **Page Number** box: Show in (In bar /
  Above bar / Title bar / Off; tags 0/1/3/2, so `PageBarNumber` keeps its
  stored meaning; "Overlay" is now labelled "Above bar") and Font (new key
  `PageNumberFont`, default the regular system font at 13 pt, used for
  Above bar and Title bar; disabled for In bar and Off). The Appearance tab
  is 64 pt taller; 3233c11 moves "Show thumbnail view on open", which
  84a919e had left behind inside the Loupe box.
- Files: `Sources/COPageLabel.*`, `AccessoryView.*`,
  `AccessorySettingView.*`, `COTitleBarLabelView.*`,
  `BookWindowController.m`, `PreferenceController.*`,
  `Resources/Base.lproj/MainMenu.xib`, en/ja `MainMenu.strings`,
  `tests/engine/test_pagelabel.m`, `README.md`, `docs/DECISIONS.md`.

**Part 2 (19c6911, fixes a47d873 and 3b70ba8): Fill title bar.**
- Page Bar ▸ **Fill title bar** (key `PageBarTitleBarFill`, default NO),
  independent of Show. Built on `COTitleBarLabelView`; `window.title` and
  the Window menu stay the plain book name. Fill: black 10%/5% (light,
  active/inactive), white 14%/7% (dark), behind the name and position, from
  the right for right-to-left books. The view takes no clicks.
- Full screen: the title bar there is hosted by a separate system window,
  so the view's own window check missed it (a47d873: the controller tells
  the view). That window's title is empty too, so no book name showed in
  the full-screen title bar, also in v1.6.8's Title bar mode. Owner chose
  (2026-10-15) to show the system title there: 3b70ba8 hides the accessory
  in full screen and shows the system title; leaving full screen restores
  both. Title bar mode's position is therefore not shown in full screen.

**Part 3 (d6c4f27): status bar opacity.** File Name ▸ **Bar opacity**
(key `StatusBarOpacity`, percent, default 80 = the default colours' alpha,
so the default look is unchanged; 100…0 in steps of 10). A profile with a
custom File Name background alpha now shows the status bar at 80% until the
setting is changed.

**Part 4.**
1. 13fa99e: unused "Enter page numbers and ranges…" removed from en/ja
   `Localizable.strings`.
2. 12282cb: a window with an export running (pages sheet, save panel or
   export) is a routing gate (`gate:target.exporting=YES`); the book opens
   in another or a new window.
3. 75a607a: exported entries keep the source's modification time (zip,
   libarchive, RAR header index, folder files; DOS time, 2 s resolution);
   pages without one get the export time as before.
4. f5fdc60: `COBottomHUDOffset` adds a bottom bar's `Margin_PageBar` y.
5. Not changed. For solid books read through the header index, decode-ahead
   already serves an entry behind the cursor from disk or waits for the
   pass; what remains (books without decode-ahead) would only move the same
   decode to the page turn, and the cursor state is only consistent on
   `readQueue`, so a pre-dispatch check would race. Not small and safe.

Also: defbfd4 records in the `device-check` skill that `open -a Claude` runs
right before a computer-use approval request (owner, 2026-10-15).

Image quality: resampling count unchanged, one `drawInRect:` per page; no
change touches `CustomImageView` or the image layout.

### Verification

- Build: Deployment via the `build-app` procedure after each part and fix;
  no new warnings in changed files. `build/` holds only `cooViewer.app`.
- Automated verification: `tests/engine/run_tests.sh` ALL PASS on the last
  build: coarchive 479, imageloader 146, pagelabel 114, export 540
  (7z fixtures and `enc_pages_aes.cbz` skipped: `7zz` not installed).
  `run_encryption_test.sh` and `run_password_test.sh` passed after Part 4.
- Manual verification (on device, owner standing by; test book a 24-page
  CBZ built from the repository fixtures in a scratch folder):
  - Page bar resize, top and bottom bar: `PageBarSize` changes, bar and
    in-bar number scale. Above bar / Title bar use the Page Number font;
    Font disabled for In bar / Off. Appearance tab fits (en).
  - Fill title bar: grows from the left / right by reading direction;
    light and dark, active and inactive; title bar still drags; Window menu
    shows the plain name. Full screen (final build): the slid-in title bar
    shows the system title "many.cbz" and no fill, also after a page turn;
    after leaving full screen the centred name and the fill return.
  - Status bar opacity 80/100/50/0 changes the bar; an image region away
    from the bar was pixel-identical across all settings.
  - Export: books opened during the pages sheet and the save panel went to
    new windows (`gate:target.exporting=YES` in the WindowRouting log);
    the export completed. `unzip -l` dates of all 24 exported entries match
    the source. Bottom HUDs rise with a raised bottom bar.
  - Preferences restored and verified after each run; build unregistered.
- Not performed: Appearance tab in Japanese; a drop during the export
  progress phase (the export finished too quickly); the RAR4 DOS-time path
  has no fixture with a valid time (code reading only); `capture` was
  refused (Screen Recording), so evidence is computer-use screenshots.

### Remaining Issues

- Title bar mode no longer shows the position in the full-screen title bar
  (system title instead), by the owner's choice above.
- `StatusBarOpacity` overrides a custom File Name background alpha for the
  status bar.
- Bottom page bar drag-to-resize also moves the bar down (already in
  v1.6.7).

### Follow-up Suggestions

- Triage `docs/KNOWN_ISSUES.md` #47 (Preferences OK resets reading
  direction, overlay after Window ▸ Fill, unreadable font previews in light
  mode, `build-libs.sh` lipo check, incremental build PlistBuddy failure).
- Release as its own task.
