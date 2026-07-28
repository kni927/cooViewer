# Task: MW-2 — Migrate to Native AppKit Fullscreen

## Scope
Per `docs/multiwindow-plan.md` MW-2 (scope items and acceptance criteria
are defined there — follow them, don't restate). In short: remove the
legacy custom fullscreen implementation in `CustomWindow` and migrate to
`toggleFullScreen:`.

Note: MW-2 has NOT been started despite an erroneous claim in the MW-1
TASK.md. `CustomWindow.m` still contains the legacy implementation intact.

## Key points from the fullscreen investigation
(`docs/tasks/2026-07-28-02-fullscreen-default-investigation.md`)
- There are three sources of truth for fullscreen state, not one: the
  `Fullscreen` default, the `CustomWindow.fullscreen` ivar, and the menu
  item's `state` (read as authoritative by `FullImagePanel.m`, and driven
  by the `SwitchFullscreen` input action via
  `performActionForItemAtIndex:`). All three must be resolved.
- Removing the legacy path also eliminates the fresh-install
  `awakeFromNib` ordering hazard — do not fix that separately.
- Also removed here: the `DontHideMenuBar` preference, the process-wide
  `[NSMenu setMenuBarVisible:]` calls, and the `"NormalWindow"` shared
  frame key.

## Verify before starting
Confirm the MW-1 RAR libarchive-fallback path still loads correctly with
the new background archive read — this was left unverified by MW-1 and
touches the same load path.

## Regression check
Fullscreen enter/exit via green button, ⌃⌘F, and the `SwitchFullscreen`
key/mouse action; menu item state stays consistent; `FullImagePanel`
behaves correctly in both states.

Archive per `docs/task-workflow.md` on completion.

---

## Implementation Result

**Status:** Completed

### Verify-before-starting: RAR libarchive fallback under MW-1's background read

Verified, and it needed a fixture that did not exist. Every shipped `.cbr`
fixture takes `CORarArchive`'s fast header-parser path, so none of them
exercises the libarchive fallback. Probing `CORarParseHeadersAtPath`
directly over all of them confirmed that (`test.cbr`, `test_solid.cbr`,
`test_rar4.cbr`, `test_utf8.cbr`, `corrupt_bitflip.cbr` all ACCEPT).

A **multi-volume** RAR5 makes the header parser decline, which is the
trigger the fallback needs. Through `COArchive` that file reports
`class=CORarArchive`, `entries=2`, `progressCalls=2` — i.e. it really did
go through `indexArchiveViaLibarchiveWithProgress:` and really did drive
the progress callback. Opened in the app it loads and displays. The normal
fast path (`test_solid.cbr`) still loads too. So the MW-1 background read
is correct on that path.

(Both probes were throwaway harnesses in the scratchpad, not added to
`tests/`.)

### Changes

**`Sources/CustomWindow.{h,m}`** — the deletion. Gone: `setFullScreen:`,
`isFullScreen`, `constrainFrameRect:toScreen:`, `setHideMenuBar:`,
`updateTrackingRect`, `mouseEntered:`, `mouseExited:`, and the
`makeKeyAndOrderFront:` / `becomeKeyWindow` / `performClose:` /
`performMiniaturize:` / `deminiaturize:` / `performKeyEquivalent:`
overrides, along with every `[NSMenu setMenuBarVisible:]` call and the
`fullscreen` / `hideMenuBar` / `resizable` / `tag` / `mouseRect` ivars.
`awakeFromNib` now just declares
`NSWindowCollectionBehaviorFullScreenPrimary` and sets a frame autosave
name. Kept: `keyDown:` forwarding, `setFrame:display:` →
`setAccessoryWindowFrame`, and the cursor auto-hide timer, re-keyed off
`[self styleMask] & NSWindowStyleMaskFullScreen`.

The `setFrame:display:` override also lost its `if (!resizable) return;`
guard — that existed to block resizes while the old fullscreen was active,
and it would have blocked AppKit's own fullscreen resize.

**`MainMenu.xib`** — `hidesOnDeactivate="YES"` removed from the viewer
window. The Window ▸ Fullscreen item (⌘F, hardwired to `Controller`, with
`state="on"` baked into the nib) is replaced by a standard
`toggleFullScreen:` item on First Responder at ⌃⌘F. The
`DontHideMenuBar` checkbox and its outlet are removed.

**`Controller.{h,m}`** — removed the `Fullscreen` default registration,
read, write-back and menu-item uncheck; the `fullscreen:` IBAction; the
`validateMenuItem:` Fullscreen branch; both `DontHideMenuBar` blocks; the
`[window updateTrackingRect]` call; and `windowDidMove:`/`windowDidResize:`
(frame saving is now AppKit's). The recomposition that `fullscreen:` did
after resizing is factored into `-recomposeForCurrentSize`, shared with
`-viewDidEndLiveResize:` (which had a byte-identical body) and called from
new `windowDidEnterFullScreen:`/`windowDidExitFullScreen:` — needed because
entering full screen is a programmatic frame change and does not produce a
live resize.

**`Controller_input.m`** — the `SwitchFullscreen` key and mouse actions
(cases 49 and 61) called `performActionForItemAtIndex:` on the Window menu,
using the menu item's check-mark as the state store. Both now call
`[window toggleFullScreen:self]`.

**`FullImagePanel.m` / `ThumbnailPanel.m`** — `becomeKeyWindow` in both
hid the menu bar process-wide; both now do nothing beyond `super`.
`ThumbnailPanel -constrainFrameRect:toScreen:` branched on
`[NSMenu menuBarVisible]` and forced the main screen with -6/+16 fudges;
it returns `[screen visibleFrame]` for the screen it is actually on.

**`PreferenceController.{h,m}`** — `dontHideMenubarCheck` outlet and its
load/save halves removed.

**`mainScreen` sites** — the nine live non-`CustomWindow` sites now use the
owning window's own screen with a `mainScreen` fallback. In
`returnComposeImage:` I deliberately did **not** switch to the view's
bounds as the plan suggested: a spread is composed at screen resolution and
then downscaled to the view, so composing at view size would have made
windowed rendering worse. Only *which* screen changed. (Two further
`mainScreen` uses, `FullImagePanel.m:227` and its `setLevel:`, are inside
`/* */` blocks — left alone; dead-code removal is its own task.)

**`ja.lproj/MainMenu.strings`** — `926.title` → `フルスクリーンにする`.

### Verification

- **Build:** `BUILD SUCCEEDED`, Deployment. No new warnings; every warning
  in the changed files is a pre-existing deprecation on a line I did not
  touch.
- **Manual, on device** (`build/cooViewer.app`, main app only per
  CLAUDE.md; `/Applications` and `~/Applications` untouched):
  - Window menu now carries AppKit's own fullscreen items (Fill, Center,
    Move & Resize, Full Screen Tile, Move to <display>, Enter Full Screen).
  - ⌃⌘F enters full screen: `AXFullScreen = true`, menu title auto-toggles
    to "Exit Full Screen", page renders full-bleed with the menu bar hidden.
  - `SwitchFullscreen` key action toggles in **both** directions
    (`false → true → false`). No such binding exists by default, so this
    needed one added temporarily — see below.
  - Quitting **directly from full screen** leaves the menu bar visible.
    This is the concrete regression the old implementation caused.
  - `FullImagePanel` opens correctly windowed *and* full screen, correctly
    sized, without knocking the main window out of full screen.
  - Two-page spread compose and rotation both correct while full screen.
  - Menus are reachable in full screen (drove Rotate Right / Switch
    Single-Bind through the menu bar while full screen).
  - Frame autosave still persists to `NSWindow Frame NormalWindow`, so
    existing users keep their saved window frame.
  - `test.cbz` and the RAR fixtures open normally.
- **Preferences safety:** testing `SwitchFullscreen` required binding it,
  since the owner's profile has no binding for action 49. I exported the
  whole `jp.coo.cooViewer` domain first, imported a copy with one extra
  `KeyArray` entry, tested, then restored from the backup and **verified
  the restored domain is identical to the backup**, key by key
  (`FULL DOMAIN IDENTICAL: True`, 56 `KeyArray` entries before and after).
- **Not verified:** behaviour on a genuinely secondary display (the
  `mainScreen` → own-screen change is the fix for it, but this machine
  drove one display during testing); the loupe child window across a
  fullscreen transition (the page-bar child window was confirmed present,
  and both go through the same `setFrame:display:` path); Mission Control
  and Spaces interaction beyond the window getting its own Space.

### Remaining Issues

- The `Fullscreen` and `DontHideMenuBar` keys remain in existing users'
  defaults, now unread. Recorded as a deliberate choice in
  `docs/DECISIONS.md` rather than migrated away.
- `FullImagePanel.m` still contains two commented-out methods
  (`setLevel:`, `zoom:`) that reference the old menu-item-state and
  `mainScreen` patterns. Left as-is deliberately — CLAUDE.md makes dead
  code removal its own task.

### Follow-up Suggestions

- MW-2 removes the last reader of the `Fullscreen` key, which was the
  concrete instance of the `Controller.m` read-then-write-back pattern
  logged as `docs/KNOWN_ISSUES.md` #19. The general problem is untouched
  and still wants its own task.
- `-[Controller validateMenuItem:]` lost one of its 44 localized-title
  branches here. The remaining 43 are still title-string dispatch; MW-4
  keeps that behaviour deliberately, so converting them to selector
  dispatch remains an open follow-up.