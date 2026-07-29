# MW-3 (cont.) — Persistence API + Full Verification

## Context

MW-3 (splitting `Controller` into `AppController` + window-side `Controller`,
per `docs/multiwindow-plan.md`) is partially done: commits landed for
`registerDefaults:`/version-migration → `+[AppController initialize]` and for
AppController creation + delegate/nib rewiring + remote-control move. See the
archived task at `docs/tasks/2026-07-29-03-mw3-extract-appcontroller.md` and
the corresponding `docs/DECISIONS.md` entry for exact findings and call sites.

Two things were deliberately deferred from that session and are this task's
scope:

1. The single-writer persistence API (highest regression risk — real user data).
2. On-device visual verification that the prior session's sandbox couldn't run
   (no working interactive window-server session there).

## Scope

### 1. Persistence API (Commit 3 from the original MW-3 plan)

Add `AppController` methods wrapping the RecentItems / LastPages /
BookSettings CRUD currently inlined at:
- `openPage:last:` (~L693–950)
- `windowWillClose:` (~L2704–2857)
- `strongSetBookmark` (~L2212)

Also move the three read helpers to `AppController`, with `Controller`
calling `[appController ...]`:
- `searchFromBookSettings:key:[more:]`
- `searchFromRecentItems:index:`
- `searchFromLastPages:index:`

No nib change needed — the `appController` outlet already exists from the
prior commit.

**Verify by:** exercising Open Recent, book settings (bookmarks/read-mode
persistence across reopen), and last-page-on-reopen before and after,
comparing `defaults read` output for the four keys (RecentItems, LastPages,
BookSettings, plus a bookmark add/remove) on a scratch profile.

### 2. Deferred on-device verification (from prior session)

Run in a real interactive session (not the Tailscale/CLI sandbox):
- Dock menu (Cmd-Tab / right-click Dock icon), with and without a book open
- Book-settings round-trip (bookmarks, read mode persist across reopen)
- `OpenLastFolder`-at-launch behavior
- PDF pixel-rendering (visual check, not just "opens without crashing")
- Apple Remote path, if hardware available (else note as not verified,
  consistent with prior session)

## Verification (applies to both parts)

- Build after each change with the documented command
  (`BUILD_TMP=... xcodebuild ... -scheme cooViewer_deploy -configuration Deployment ...`),
  zero new warnings.
- No image-quality regression: confirm by inspection that no touched code
  sits between decode and `drawInRect:` (CLAUDE.md's inviolable rule).
- Follow `docs/task-workflow.md` on completion: append the Implementation
  Result to this file, archive to `docs/tasks/2026-07-29-NN-mw3-persistence-api...md`,
  update `docs/KNOWN_ISSUES.md` and `docs/DEV_LOG.md`.

## Session-budget checkpoint

If on-device verification can't be completed in this session (e.g. same
sandbox limitation recurs), land the persistence-API refactor first (it's
independently buildable/testable via `defaults read`), commit it, and leave
the visual-verification checklist above as the explicit remaining step —
don't leave the persistence refactor half-done.

Once this task is fully verified, MW-3 is complete and MW-4 can proceed.

## Implementation Result

**Status:** Completed with follow-up issues

### Changes

Part 1 (persistence API) is fully implemented. Part 2 (on-device
verification) is partially done — see Verification below.

- `Sources/AppController.h`/`.m`: added a single-writer persistence API.
  - Moved bodily from `Controller`: the four read helpers
    `searchFromBookSettings:key:`, `searchFromBookSettings:key:more:`,
    `searchFromRecentItems:index:`, `searchFromLastPages:index:`. Their
    internal `-pathFromAliasData:`/`-aliasDataFromPath:` calls now go through
    the existing `controller` outlet, since those Alias Manager helpers
    stayed window-side (out of scope here, per `docs/multiwindow-plan.md`'s
    listed out-of-scope cleanups).
  - New: `-recordClosingBookSettings:name:alias:bookmarks:bookSetting:page:
    openRecentLimit:alwaysRememberLastPage:` — wraps the "close the old
    book" block from `-[Controller openPage:last:]` (~L773-864 before this
    change).
  - New: `-recordBookSettingsOnWindowClose:name:alias:bookmarks:bookSetting:
    page:openRecentLimit:alwaysRememberLastPage:rememberBookSettings:` —
    wraps the persistence block from `-[Controller windowWillClose:]`
    (~L2648-2749 before this change).
  - The two write methods are deliberately **not unified** even though their
    bodies are almost identical: `-recordBookSettingsOnWindowClose:...`
    removes a stale `RecentItems`/`LastPages` entry via a plain
    `-pathFromAliasData:` comparison, where `-recordClosingBookSettings:...`
    uses `-searchFromRecentItems:`/`-searchFromLastPages:` — a divergence
    that predates this refactor (present in the original `windowWillClose:`
    vs. `openPage:last:` bodies) and was preserved as-is rather than
    reconciled, since reconciling it wasn't asked for and touches real user
    data. Documented in both files.
  - `nowPage`'s `secondImage`-dependent decrement stays in `Controller` (it's
    a `Controller` ivar used elsewhere); `Controller` computes the final page
    number and passes it in as a plain `int`.
- `Sources/Controller.h`: removed the four now-moved `searchFrom*`
  declarations (left the two pre-existing, never-implemented `...more:(BOOL)b`
  declarations for `searchFromRecentItems:`/`searchFromLastPages:`
  untouched — dead code unrelated to this task, out of scope per CLAUDE.md's
  Dead Code policy).
- `Sources/Controller.m`: replaced all `RecentItems`/`LastPages`/
  `BookSettings` access at the three named call sites and at
  `-openTheLastPage:` (an additional read-only call site the "move the read
  helpers" bullet covers) with `[appController ...]` calls. The two write
  blocks became short calls to the new `AppController` methods, with the
  `nowPage` decrement kept local immediately before the call.

**Deliberately not touched** (real, additional writers of these same
defaults keys, found while auditing call sites, but outside this task's
three named sites): `-setOpenRecentMenu`'s self-healing `RecentItems` write
(drops entries whose alias no longer resolves), `-preferencesDidChange:`'s
`RecentItems` truncation when `OpenRecentLimit` shrinks, the 1.2b10
version-migration block in `-awakeFromNib`, and `PreferenceController.m`'s/
`BookmarkController.m`'s own reads/writes of `BookSettings`/`LastPages`. A
fully single-writer API would need to route these through `AppController`
too — recorded as a follow-up, not done here (see `docs/DECISIONS.md`'s
2026-07-29 update to the MW-3 extraction entry).

### Verification

- **Build:** `BUILD_TMP="${TMPDIR%/}/cooViewer-build2" xcodebuild -project
  cooViewer.xcodeproj -scheme cooViewer_deploy -configuration Deployment
  SYMROOT="$BUILD_TMP/sym" OBJROOT="$BUILD_TMP/obj" -derivedDataPath
  "$BUILD_TMP/dd" clean build` — **BUILD SUCCEEDED**, zero new warnings (grepped
  the build log for `Controller.m`/`AppController.m`/`.h`; none). Final app
  copied to `build/cooViewer.app`; `build/` verified to contain only that.
- **Image-quality check (CLAUDE.md inviolable rule):** not applicable — this
  task touched only defaults persistence (`AppController`/`Controller`), no
  code between decode and `drawInRect:`.
- **Automated verification:** none (no test suite for this codebase).
- **Manual verification (real defaults domain, not a mock):**
  - Backed up the live `jp.coo.cooViewer` defaults domain first
    (`defaults export jp.coo.cooViewer <scratch file>`), restored it
    (`defaults import`) after each exercise below, confirmed restored state
    matched the backup.
  - `open -a build/cooViewer.app tests/fixtures/generated/test.cbz` (no book
    previously open in that launch) — `RecentItems`' `test.cbz` entry moved
    to index 0, confirming `-openTheLastPage:`'s/`openPage:last:`'s "add
    RecentItem" logic works through `[appController searchFromRecentItems:...]`.
  - `open -a build/cooViewer.app tests/fixtures/generated/test.cbr` while
    `test.cbz` was still open — File Open replaces the current window's book
    (MW-3 decision 3), exercising `-[Controller openPage:last:]`'s "close the
    old book" path. Confirmed via `defaults read`: `test.cbz` gained a
    `page = 0` entry in `RecentItems` (written by
    `-recordClosingBookSettings:...`), and `test.cbr` was added at index 0.
  - `osascript -e 'tell application "cooViewer" to quit'` (a direct Apple
    Event, not `System Events` UI scripting) with `test.cbr` open — quitting
    runs `NSApplication`'s normal terminate sequence, which sends
    `windowWillClose:` to the open window. Confirmed via `defaults read`:
    `test.cbr`'s `RecentItems` entry gained `page = 0`, written by
    `-recordBookSettingsOnWindowClose:...`. `BookSettings` correctly gained
    **no** entry for either test file (no bookmark had been set, so the
    `if ([bookSetting count]>2)` gate correctly stayed closed) — confirms
    that gate survived the move intact.
  - App launched and quit cleanly every time (no crash, no hang).
- **Not performed** (same root cause the prior MW-3 session hit, see
  `docs/KNOWN_ISSUES.md` #22 — this session has a working process
  launcher/Apple Event dispatch, confirmed above, but no working
  accessibility or screen session): Dock menu behaviour, bookmark
  add/reopen round-trip via the actual UI (only the underlying
  `BookSettings` gate was confirmed, not a real "Add Bookmark" menu click),
  `OpenLastFolder`-at-launch, PDF pixel rendering, Apple Remote (no hardware
  either). `System Events` window-count queries returned 0 for a running,
  visible app; `keystroke` commands silently no-op; `screencapture -x`
  failed with "could not create image from display"; `lsappinfo info -only
  front` returned nothing even right after activating the app — confirming
  no real interactive window-server session, not something these changes
  affect.

### Remaining Issues

- MW-3's on-device visual-verification checklist (dock menu, real bookmark
  round-trip via the UI, `OpenLastFolder`-at-launch, PDF pixel rendering,
  Apple Remote) is still unverified, for the same environment reason as the
  prior MW-3 session. Per TASK.md's own closing condition ("Once this task
  is fully verified, MW-3 is complete and MW-4 can proceed"), **MW-3 is not
  yet fully closed** and MW-4 should not start until a session with a real
  interactive window-server session completes that checklist.

### Follow-up Suggestions

- Re-run the on-device visual checklist above in a genuinely interactive
  session (physical Mac session or a sandbox confirmed to have a working
  window server) before starting MW-4.
- If cooViewer's persistence API should become single-writer in the fuller
  sense, route `-setOpenRecentMenu`'s self-healing write,
  `-preferencesDidChange:`'s `RecentItems` truncation, and
  `PreferenceController.m`'s/`BookmarkController.m`'s `BookSettings`/
  `LastPages` writes through `AppController` too — scoped as its own task,
  not folded into this one.
