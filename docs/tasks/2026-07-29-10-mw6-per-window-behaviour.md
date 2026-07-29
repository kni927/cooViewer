# MW-6 — Per-window Window Behaviour

## Context

MW-5 and the two AccessoryView cleanup tasks are done and pushed (through
`7053fc0`). MW-6 is the last task before multiple windows actually exist:
still one window, but every remaining "there is only one" assumption gets
removed. See `docs/multiwindow-plan.md` MW-6, and `docs/DECISIONS.md` for
the Step-0 decisions this implements against.

**The plan doc's file names and line numbers predate MW-5.** `Controller`
is now `BookWindowController`, `BookmarkController` was split into a
per-book controller plus `AllBookmarkController`, and the window/panels
moved into `BookWindow.xib`. Treat every reference below as a pointer to
*what* to change, not *where* — locate the current call sites yourself.

Note also the plan's own erratum: MW-6's `screenCacheArray` item is **no
longer applicable** (the composited render path was deleted before MW-3),
so there is nothing to do there.

## Scope

1. **Window frame.** Replace the shared
   `saveFrameUsingName:@"NormalWindow"` / `setFrameUsingName:`
   (originally `CustomWindow.m:19,41`, `Controller.m:3062,3066`) with:
   saved frame for the first window, `cascadeTopLeftFromPoint:` for each
   one after it.
2. **Panel autosave names.** Give per-window frame autosave names to the
   panels that currently share one: `"Bookmark"` / `"AllBookmark"`
   (originally `BookmarkController.m:20-21` — now split across two
   classes, so check both halves) and `"FilterPanel"`
   (`FilterPanelController.m:13`).
3. **Rebuild shared main-menu state on `windowDidBecomeMain:`** — the
   bookmark menu, the "Open from same folder" submenu, and the read-mode /
   sort-mode check-marks.
   **Important:** read mode and sort mode are **per-book overrides on a
   global default** (`currentBookSetting[@"readMode"]` /
   `[@"sortMode"]`), so the check-marks must reflect the front book, not a
   preference. Getting this backwards is the most likely subtle bug in
   this task.
4. **Replace `[window isVisible]` as the "a book is open" predicate** with
   explicit controller state. Original sites: `windowWillClose:` (2906),
   `openPage:last:` (757/776), `applicationDidFinishLaunching:` (580),
   `Controller_input.m:2924`. Note MW-3 already added a small "is a book
   open" accessor for the dock menu — reuse or generalise it rather than
   inventing a second predicate.
5. **Fix `[[NSApp keyWindow] makeKeyAndOrderFront:self]`** in
   `PreferenceController.m:1609,1628`.
6. **Add `-dealloc` to `AccessoryView`** (from the AccessoryView
   follow-up task's findings). It currently has none. Harmless today —
   the view is nib-owned and lives as long as the app — but once MW-7
   gives each window its own `AccessoryView`, every closed window leaks
   it and everything it retains.
   **Caveat, state it in the archive:** with one window this `-dealloc`
   never runs, so it *cannot be verified in this task*. Write it from the
   ownership actually visible in the class (audit every retained ivar,
   including `pageString`, `infoString`, `pageStringAttr` and any
   attributes dictionaries), keep it a separate commit, and list it as an
   explicit MW-7 verification item.
   While there, check whether the sibling per-window classes moved into
   `BookWindow.xib` in MW-5 have the same gap — this is the natural
   moment for that audit, and MW-5 already deferred "no leaked nib
   top-level objects" to MW-7.

## Commit structure

Items 1, 2, 4, 5 and 6 are independent and each small; item 3 is the
substantial one. Suggested: land the small mechanical ones first, item 3
on its own, and item 6 as its own clearly-labelled commit (since it's the
only one that can't be verified now). Confirm or revise this after reading
the code, as the MW-3 and MW-5 sessions both did — and say why before
writing code.

## Acceptance

- **No behavioural difference with one window.** This is the bar for the
  whole task.
- Menu state is rebuilt from the front window rather than assumed —
  verify the read-mode and sort-mode check-marks track the *book*, by
  opening two books in sequence with different per-book overrides and
  confirming the marks follow.
- Window frame still restores as before on relaunch with a single window
  (cascading only becomes observable in MW-7).

## Verification

- Build with the documented command
  (`BUILD_TMP=... xcodebuild ... -scheme cooViewer_deploy -configuration Deployment ...`).
  Warning baseline is **312**, all pre-existing deprecations; the diff
  against the current warning set must be empty.
- No render-path change (CLAUDE.md's inviolable image-quality rule).
  Re-confirm with a spread window capture SHA-256 against the current
  baseline, as the last three tasks did.
- On-device via the screen-shared Mac mini session. Exercise: bookmark
  menu, Open from same folder, read/sort mode check-marks across two
  books, panel positions persisting per panel, Preferences ▸ OK returning
  focus correctly (item 5), window frame restore on relaunch.
- **Use the test build, never `/Applications/cooViewer.app`** — same
  bundle ID, same defaults domain (KNOWN_ISSUES #23). Back up
  `jp.coo.cooViewer` before testing, restore after, diff to confirm zero
  delta.
- Run once under `NSZombieEnabled` at the end — item 6 touches memory
  management, and items 1-4 change object lifetimes around window state.
- Follow `docs/task-workflow.md` on completion: append the Implementation
  Result here, archive to `docs/tasks/2026-07-NN-NN-mw6-...md`, update
  `docs/DECISIONS.md` / `docs/DEV_LOG.md` / `docs/KNOWN_ISSUES.md`.

## Session-budget checkpoint

If the task can't be finished this session, stop after whichever commit
leaves the app fully working single-window, and update this TASK.md with
the exact remaining items. Never stop mid-item-3 with the menu rebuild
half-wired.

## Out of scope

KNOWN_ISSUES #24 (All Bookmark browser has no UI entry path) — still
needs a UI decision about where the entry point belongs. Reconsider when
MW-7 adds the Window menu.

## Depends on

MW-5 (done, pushed). **Blocks:** MW-7 (the feature itself).

Risk noted in the plan: medium.

---

## Implementation Result

**Status:** Completed

### Changes

Six commits on `main`, `d1bab93`..`58a66bf`, one per scope item plus the
docs commit. The suggested commit structure was revised in one place and
the reason stated before any code was written: **items 1 and 2 are not
independent.** Per-window panel autosave names need a per-window identity,
and item 1 has to introduce that identity anyway for the main window's
frame — so item 1 lands first and item 2 builds on it.

- **Item 4 — explicit "a book is open" state** (`d1bab93`).
  `[[self window] isVisible]` and `[imageView image]` were both standing in
  for it, and neither is that question: `-openPage:last:` orders the window
  front *before* the load starts, and the view's image is a side effect of
  the display pass. New `bookOpen` ivar on `BookWindowController`, set when
  a load completes and cleared when `-windowWillClose:` tears the book
  down; every site routes through the existing `-hasBookOpen` accessor
  (MW-3's dock-menu predicate, generalised as the task asked, not
  duplicated). Sites: `-applicationDidFinishLaunchingSetup:`, both branches
  of `-openPage:last:`, `-windowWillClose:`,
  `-[BookWindowController(Input) slideshow:]`.
  The one place old and new differ is a failed *first* open, where
  `-openPage:last:` closes the window it had just ordered front:
  `isVisible` was YES there, so the teardown block ran, and every statement
  in it is a no-op when no book was ever loaded. Noted rather than
  preserved.
- **Item 1 — per-window main window placement** (`ecb5f37`).
  `setFrameAutosaveName:@"NormalWindow"` moved out of
  `-[CustomWindow awakeFromNib]` into `-[BookWindowController windowDidLoad]`:
  *which* name a window uses, and whether it restores a saved frame at all,
  is a per-window decision the window controller makes. The first window
  keeps the name, so frames users already have saved still restore; later
  windows cascade from the previous one via `-cascadeTopLeftFromPoint:`,
  seeded with `NSZeroPoint` so the first window's restored frame is left
  alone. `NSWindowController`'s own `-shouldCascadeWindows` is switched off
  explicitly: it only acts from `-showWindow:`, which this app never calls
  for the book window, but the two must not both apply in MW-7.
  Introduces the per-window identity: `windowIndex`, assigned by
  `AppController` before the nib loads (constant 0 today — the registry has
  one slot; MW-7 hands out the first free one), and
  `-[BookWindowController frameAutosaveName:]`, which returns the historical
  unsuffixed name for slot 0 and a `-N` suffix otherwise.
- **Item 2 — per-window panel frame autosave names** (`56536fc`).
  The Bookmark and Filter panels live in `BookWindow.xib`, so there is one
  of each per window; both now ask their window controller for the name.
  `FilterPanelController` gained a `controller` outlet to File's Owner for
  this, mirroring the one `BookmarkController` already had
  (`BookWindow.xib`). **The `"AllBookmark"` half was checked and
  deliberately left shared:** since MW-5 split it out, the All Bookmark
  browser is app-wide — one instance in `MainMenu.xib`, outliving any
  window — so it has nothing to share a name with.
- **Item 5 — Preferences focus return** (`ef94b0d`).
  Both exits from the modal loop ended with
  `[[NSApp keyWindow] makeKeyAndOrderFront:self]`, asking NSApp for the key
  window *after* the panel had been ordered out, by which point AppKit has
  already picked some other window or none. The window is now captured
  while still key, at the top of `-[PreferenceController preferences]`, and
  re-fronted by name. The
  `[[[appController controller] window] isVisible]` guard on the OK path
  went with it: with no book open there is no key window to capture, and
  `-makeKeyAndOrderFront:` on `nil` is a no-op — which is what the guard was
  arranging by hand.
- **Item 3 — rebuild shared main-menu state on `-windowDidBecomeMain:`**
  (`92e903f`). The bookmark menu, the "Open from same folder" submenu and
  the read/sort check-marks are one shared object each on the single main
  menu, but their contents describe one window's book.
  - Bookmark menu: rebuilt outright from the front window's `bookmarkArray`.
  - Same-folder submenu: the delegate is re-pointed at the new front window
    and the submenu flagged for a **forced** rebuild, but the rebuild stays
    in `-menuNeedsUpdate:`. Doing it eagerly would enumerate the book's
    parent folder on every window activation — the folder-access-prompt
    problem the lazy build exists to avoid. The force matters because
    `-setSameFolderMenu:` otherwise keeps the previous window's items, and
    their `target`, whenever both books share a folder. The delegate check
    also means nothing at all happens when the front window has not changed,
    so the single-window case is untouched.
  - Read/sort check-marks: these are **per-book overrides on a global
    default** (`currentBookSetting[@"readMode"]`/`[@"sortMode"]` over the
    `ReadMode`/`SortMode` preferences), so they follow the front *book*.
    `-validateMenuItem:` already derives exactly that from the window's
    `readMode`/`sortMode` ivars, so the items carrying
    `changeReadModeMenu:`/`changeSortModeMenu:` are re-validated rather than
    duplicating its 8-branch localized-title dispatch in a second place.
- **Item 6 — `-dealloc` for `AccessoryView`** (`58a66bf`, its own commit
  because it is the one change that cannot be verified now).
  Written from the ownership visible in the class, not from a leak trace:
  `controller` and `imageView` are IBOutlets and not retained; every other
  object ivar is retained by `-setPreferences` / `-setFrame:` /
  `-setPageString:` / `-setInfoString:` and is released — `pageStringAttr`,
  `pageBarBezierPath`, `pageBarCursor`, the five page-bar font/colour ivars,
  the four text font/colour ivars, `pageString`, `infoString`. Both timers
  are invalidated. **Caveat, as the task required:** with one window this
  method never runs, so it is untested; it is an explicit MW-7 verification
  item (`docs/KNOWN_ISSUES.md` #26).
  The sibling audit the task asked for was done and is recorded in #26: of
  the eleven per-window classes in `BookWindow.xib`, **none** has a
  `-dealloc`, `BookWindowController` itself included.

Nothing in the render path was touched. `screenCacheArray` was already gone,
per the plan's own erratum — nothing to do there.

### Verification

- **Build:** clean `Deployment` build with the documented command.
  **312 warnings**, and the diff of the warning set (file + message,
  normalised for the line-number shift these changes cause) against the
  pre-task baseline is **empty**.
- **Render path:** spread window capture at a fixed frame is
  **byte-identical (SHA-256 `2ddb2d1c…`)** before and after the whole task.
- **On device**, test build only (`build/cooViewer.app`; `/Applications`
  never touched, no `lsregister`/`pluginkit`). `jp.coo.cooViewer` exported
  before and re-imported after — final diff is **zero delta across all 81
  top-level keys**.
  - Read/sort check-marks track the **book**, not a preference: bookA set to
    Left to Right + Shuffle, bookB opened → Right to Left + Name (the
    globals), bookA reopened → Left to Right + Shuffle again.
  - Bookmark menu tracks the book: bookmark added in bookA → listed; bookB →
    only "Edit Bookmark…" + separator; bookA reopened → listed again;
    window closed → cleared.
  - "Open in Same Folder" submenu lists both books with the current one
    check-marked, and opening from it works in both directions.
  - Panel frames persist per panel and under the expected (unsuffixed,
    slot-0) keys: `NSWindow Frame FilterPanel`, `NSWindow Frame NormalWindow`.
  - Preferences ▸ OK and ▸ Cancel with a book open: no crash (the #25
    surface), and focus returns to the book window in both cases.
  - Window frame restore on relaunch: window moved to 300,200 900×600, quit,
    relaunched → restored exactly.
  - Item 4's two launch paths: with `OpenLastFolder` on and no file
    argument, the last book auto-opens; with a file argument, that file
    opens and `OpenLastFolder` does **not** double-open.
  - Slideshow start/stop, window close and reopen all behave as before.
  - **`NSZombieEnabled` run** over the whole sequence (verified present in
    the running process with `ps eww`, stderr redirected to a file and the
    redirect confirmed with `lsof`): **no zombie message, no crash**.
- **Not performed:** anything requiring a second window — the cascade, the
  per-window suffixed autosave names, the `-windowDidBecomeMain:` rebuild
  actually *changing* anything, and `-[AccessoryView dealloc]` running at
  all. All four are MW-7 verification items by construction, which is what
  "no behavioural difference with one window" means. Also not performed:
  Instruments, encrypted archives, Apple Remote, multi-display.

### Remaining Issues

None for the six scoped items.

### Follow-up Suggestions

- **Open Recent's menu items are still per-window in a shared menu.**
  `-setOpenRecentMenu` sets `[menuItem setTarget:self]` on every item, so
  with two windows the Recent Books menu would open books into whichever
  window built it last. Same shape as the three things item 3 fixed, but not
  in item 3's list, so left alone. MW-7 should either rebuild it in
  `-windowDidBecomeMain:` too or retarget it at First Responder.
- **`-validateMenuItem:`'s `[[self window] isVisible]` tests** (24 of them)
  are the same "is a book open" proxy item 4 removed elsewhere, and were not
  in item 4's site list. They are harmless — validation runs against the key
  window's controller — but they should become `-hasBookOpen` for
  consistency the next time that method is opened.
- **No per-window class in `BookWindow.xib` has a `-dealloc`** — see
  `docs/KNOWN_ISSUES.md` #26. MW-7 needs a decision on how far to take this.
- The `-[AccessoryView setFrame:]` bounded 6-allocation leak from the MW-5
  follow-up task is still open and still small.
- KNOWN_ISSUES #24 (All Bookmark browser has no UI entry path) remains open
  and out of scope, as the task specified.
