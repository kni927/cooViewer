# Task: Fullscreen Default Behavior — Investigation Only

## Background
`docs/audit-20260711.md` / codebase inspection indicates the `Fullscreen`
preference defaults to **YES**, implying the app should launch into
fullscreen. Actual observed behavior does not launch into fullscreen.
This discrepancy needs to be resolved before MW-2 (native fullscreen
migration) is scoped, since the fix depends on which side is wrong.

## Scope
Investigation only. No code changes, no commits.

## Questions to answer
1. Where is the `Fullscreen` default registered (`registerDefaults:` or
   equivalent), and what does the key actually gate — window state at
   launch, per-book state, or something else (e.g. a display/rendering
   option unrelated to launch-time fullscreen)?
2. Is there a stored value for `Fullscreen` in the current
   `NSUserDefaults` (`defaults read <bundle-id> Fullscreen` or
   equivalent) that would override the coded default of YES?
3. Trace all read sites of the `Fullscreen` key/ivar and confirm what
   each one actually does with it.
4. Based on 1–3, state plainly: was the audit's "defaults to YES →
   launches fullscreen" claim correct, and if not, what is the actual
   current launch behavior and why?

## Deliverable
Short findings note (append to `docs/DECISIONS.md` or a new
`docs/tasks/`-archived file per `docs/task-workflow.md`) answering the
above. This unblocks the A2 decision for MW-2 — do not make the A2 call
yourself, just report the facts.

---

## Implementation Result

**Status:** Completed

Investigation only, as scoped. No source changes, no commits.

**Bottom line: the audit claim was wrong, and I was the one who made it.**
The registered default really is YES, but "the app launches fullscreen
out of the box" does not follow, for three independent reasons. The
observed behaviour on this machine is fully explained by a stored
preference value of `0`.

### Q1 — Where is the default registered, and what does the key gate?

Registered in `-[Controller awakeFromNib]`:

| Line | Code |
|---|---|
| `Controller.m:61` | `BOOL fullscreen;` (local, uninitialised) |
| `Controller.m:70` | `fullscreen = YES;` |
| `Controller.m:74` | `[appDefault setObject:@(fullscreen) forKey:@"Fullscreen"];` |
| `Controller.m:90` | `[defaults registerDefaults:appDefault];` |

So the **registered** default is YES. `registerDefaults:` populates the
volatile registration domain only — it is consulted solely when no value
exists in a higher-priority domain.

What the key gates: the `CustomWindow` **legacy fullscreen mode** — a
persistent, app-wide window-display mode. It is neither launch-time-only
nor per-book. `-[CustomWindow setFullScreen:]` (`CustomWindow.m:35`)
either restores the saved `"NormalWindow"` frame with the menu bar
visible and `hidesOnDeactivate = NO`, or forces the window to
`[[NSScreen mainScreen] frame]` (via `constrainFrameRect:toScreen:`)
with `hidesOnDeactivate = YES` and the menu bar hidden.

Crucially, the main window is `visibleAtLaunch="NO"`
(`MainMenu.xib:15`). **No window is shown at launch at all.** The window
appears only when a book opens (`openPage:last:` →
`[window makeKeyAndOrderFront:]`, `Controller.m:714`). A book opens at
launch only if `OpenLastFolder` is YES *and* a recent item exists
(`applicationDidFinishLaunching:`, `Controller.m:579-583`).

### Q2 — Is there a stored value overriding the coded default?

**Yes.** On this machine (`jp.coo.cooViewer`):

```
Fullscreen        = 0
OpenLastFolder    = 0
DontHideMenuBar   = 0
NSWindow Frame NormalWindow = 73 0 1707 1050 0 0 1920 1050
```

`Fullscreen = 0` in the persistent domain overrides the registered YES
outright. That alone explains the observed behaviour. `OpenLastFolder = 0`
independently means no window appears at launch either way.

How the stored `0` got there: `-[Controller fullscreen:]`
(`Controller.m:2864-2874`) is the **only** writer of `NO`, and it is the
Window ▸ Fullscreen menu action. A settings reset cannot produce it —
if the key were removed, the next launch would re-register YES and
`Controller.m:273` would persist YES. So the stored `0` is the result of
the menu item having been toggled off at some point. (When, I cannot
determine.)

### Q3 — All read sites

**`Fullscreen` user-default key**

| Site | What it does |
|---|---|
| `Controller.m:74, 90` | registers the default (YES) |
| `Controller.m:199` | reads it into a local |
| `Controller.m:200-202` | if NO, unchecks the Window ▸ Fullscreen menu item |
| `Controller.m:273` | **writes the value back into the persistent domain** |
| `Controller.m:2869, 2873` | `fullscreen:` action writes YES / NO |
| `CustomWindow.m:12` | reads it into the `fullscreen` ivar in `awakeFromNib` |
| `CustomWindow.m:23` | if NO, unchecks the same menu item (duplicate of `Controller.m:200-202`) |
| `FullImagePanel.m:27` | reads `DontHideMenuBar`, gated on the **menu item state** |

**`CustomWindow.fullscreen` ivar** — set at `CustomWindow.m:12` and in
`setFullScreen:` (35). Read by `isFullScreen` (50),
`constrainFrameRect:toScreen:` (57), `setHideMenuBar:` (74),
`keyDown:` (105), `performKeyEquivalent:` (118),
`makeKeyAndOrderFront:` (156), `mouseEntered:` (172), `mouseExited:`
(180), `updateTrackingRect` (194), `cursorHide` (203), `mouseMoved:`
(212), `becomeKeyWindow` (225). Externally via `isFullScreen` at
`Controller.m:3062, 3066` (skip frame autosave while fullscreen).

**Menu-item state as a third source of truth.** The Window ▸ Fullscreen
item is hardcoded `state="on"` in the nib (`MainMenu.xib:339`).
`FullImagePanel.m:27` and `:209` read `[[NSApp windowsMenu]
itemWithTitle:@"Fullscreen"] state]` as authoritative for menu-bar
hiding and window level, and the `SwitchFullscreen` key/mouse actions
(`Controller_input.m:772-781` case 49, `1762-1771` case 61) drive
fullscreen by calling `performActionForItemAtIndex:` on that item
rather than the API.

Two things I checked because they would have been latent bugs, and both
are **fine**: the Window submenu carries `systemMenu="window"`
(`MainMenu.xib:337`), so `[NSApp windowsMenu]` and
`[[NSApp mainMenu] itemWithTitle:@"Window"] submenu]` are the same
object; and `NSLocalizedString(@"Window")` → `"ウインドウ"`
(`ja.lproj/Localizable.strings:407`) matches the localized menu title
(`ja.lproj/MainMenu.strings:2`), so the title-based lookups resolve
under Japanese too.

### Q4 — Was the claim correct?

The claim in `docs/multiwindow-pass1.md:224`,
`docs/multiwindow-pass2.md:166`, `docs/multiwindow-plan.md:49` and the
2026-07-28 `docs/DECISIONS.md` entry reads: *"`Fullscreen` defaults to
**YES** — the app launches fullscreen out of the box."*

- *"defaults to YES"* — **correct**, as a statement about
  `registerDefaults:`.
- *"the app launches fullscreen out of the box"* — **wrong**, three ways:

1. **Nothing is shown at launch.** The window is `visibleAtLaunch="NO"`;
   the mode only becomes visible when the first book opens, and a book
   opens at launch only under `OpenLastFolder`. The accurate statement is
   "the window is in legacy-fullscreen mode when it first appears."
2. **The registered default is effectively one-shot.**
   `Controller.m:273` writes the value into the persistent domain on
   *every* launch, so from the second launch onward a stored value always
   exists and the registered default is never consulted again. Anyone who
   has ever toggled the menu item off has NO stored permanently — which
   is exactly this machine.
3. **Even on a genuinely fresh profile the first launch is not reliably
   fullscreen.** `CustomWindow -awakeFromNib` reads the key
   (`CustomWindow.m:12`) and `Controller -awakeFromNib` registers the
   default (`Controller.m:90`); AppKit does not define the relative order
   of `awakeFromNib` across nib objects, and the window object precedes
   the Controller in the nib (`MainMenu.xib:15` vs `:1895`). If the
   window's runs first, the key is absent and it reads NO for that
   session. **Not verified at runtime** — reported as a hazard, not as
   observed behaviour. It cannot produce a stored `0`, since
   `Controller.m:199/273` still reads and persists YES in the same
   launch.

**Actual current launch behaviour:** no window at launch (unless
`OpenLastFolder` is YES with a recent item); when a window does appear,
its mode comes from the *stored* `Fullscreen` value, which on this
machine is NO.

### Verification

- Build: not performed (investigation only; no source touched).
- Automated verification: none applicable.
- Manual verification: read all `@"Fullscreen"` / `setFullScreen:` /
  `isFullScreen` / `fullscreen` ivar sites listed above; read the actual
  persistent domain with `defaults read jp.coo.cooViewer …`; confirmed
  `visibleAtLaunch="NO"` and `systemMenu="window"` in `MainMenu.xib`;
  confirmed the ja localization of the title-based menu lookups.
- Not performed: no runtime test of first-launch behaviour on a clean
  defaults domain. Doing so would require clearing or relocating the real
  `jp.coo.cooViewer` domain, which holds the owner's bookmarks, book
  settings and recents; I did not consider that acceptable for an
  investigation task. Point 3 above is therefore code-level reasoning,
  explicitly unverified.

### Remaining Issues

Four documents still contain the disproven claim and I did **not** amend
them, since this task was scoped to investigation and to leaving the A2
call to the owner:

- `docs/multiwindow-pass1.md:224`, `docs/multiwindow-pass2.md:166` —
  archived analysis records; recommend leaving them and letting this note
  supersede them.
- `docs/multiwindow-plan.md:49` (assumption A2) and the 2026-07-28
  `docs/DECISIONS.md` entry — these are **forward-looking** and will be
  read when MW-2 is scoped. Recommend amending both; awaiting the
  owner's decision.

### Follow-up Suggestions

- `Controller.m:273` persisting a registered default on every launch is a
  general anti-pattern in `awakeFromNib`, not specific to `Fullscreen` —
  the same read-then-write-back appears for `OpenLastFolder`,
  `ReadSubFolder`, `Interpolation`, `ImageCache` and others. It makes
  every registered default one-shot and makes "reset to defaults"
  behave differently from a fresh install. Worth a separate task.
- The Window ▸ Fullscreen menu item's `state` being a de facto third
  source of truth (read by `FullImagePanel`, driven by the
  `SwitchFullscreen` input actions via `performActionForItemAtIndex:`)
  should be collapsed during MW-2, not carried into native fullscreen.
- `MainMenu.xib:339` hardcodes `state="on"`, which both
  `Controller.m:200-202` and `CustomWindow.m:23` then correct at
  runtime — the duplication is a leftover and can go with MW-2.