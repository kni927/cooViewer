# TASK: Investigate — a second Finder context-menu entry that always opens a new window

## This is an investigation task. Do not implement anything.

The deliverable is a written report with file:line references,
measured/reproduced behaviour, and an implementation size estimate. No
code changes, no new preferences, no new UI, no companion app bundles
created — proposals only.

## Background

The default Finder "Open With" entry for `.cbr`/`.cbz` now loads into
the existing front window when one is open (`d393955`,
`docs/tasks/2026-07-31-06-finder-open-reuses-window.md`). There is
currently no way to force "open in a new window" from Finder's context
menu — only via the app's own menu (File ▸ Open in New Window, ⌥⌘O),
which requires the app to already be active. The owner wants a second
entry in the same "Open With" submenu — something like
"cooViewer (New Window)" — as an additional Finder-native entry point
for opening in a new window.

## Why this needs investigation before implementation

macOS's "Open With" context-menu entries are enumerated by
LaunchServices per registered **application bundle** (bundle
identifier) for a given UTI — not per "action" within one app. A
single app bundle showing up twice with different behavior is not a
standard, built-in capability; achieving it typically requires a
second, distinct helper app bundle that is also registered as a
handler for the same file types, and which forwards the request to the
main app rather than opening the file itself. This has real
LaunchServices-registration risk of its own — the project just
recovered from a duplicate-registration Finder confusion needing a
reboot (`docs/KNOWN_ISSUES.md` #15) — so the mechanism needs to be
confirmed before committing to a design, not assumed.

## Questions to answer

**Q1 — How does Finder actually enumerate "Open With" entries for `.cbr`/`.cbz`?**
Confirm (don't assume) whether entries are keyed by bundle identifier
only, and whether a single bundle can register two named handlers for
the same UTI. Check `LSCopyApplicationURLsForURL` /
`NSWorkspace` APIs and `lsregister -dump` output for the current
cooViewer registration as a starting point for how the system
currently sees it.

**Q2 — Does Finder pass any "action" information through `-application:openFiles:`, or only file paths?**
Confirm whether there is any built-in way for a single app to detect
"the user picked entry B, not entry A" from Finder — or whether this
is fundamentally impossible without a second bundle. Look at what
`open(1)`/`LSOpenURLSpecification` and `-application:openFiles:`
actually deliver.

**Q3 — Minimal viable design if a second bundle is required**

If Q1/Q2 confirm a second bundle is necessary: describe the smallest
possible companion bundle — e.g. a tiny helper app (own bundle
identifier, `LSUIElement` to avoid a Dock flash) that registers as a
document handler for the relevant UTIs, and on receiving
`-application:openFiles:` forwards a "force new window, this path" 
request to the main cooViewer process (mechanism TBD — Apple Events,
a custom URL scheme, distributed notification — evaluate options and
recommend one) and then terminates itself immediately. Note explicitly
that this is a bigger structural change (a second bundled executable)
than a typical cooViewer task, and flag it as such rather than
downplaying it.

**Q4 — Interaction with existing behavior**

The forwarded "new window" request must always go through
`-openBookInNewWindow:` (same as ⌥⌘O), never the front-window-replace
path from `d393955`. State explicitly whether Finder-open dedup (#32)
should still apply to this entry point (i.e., if the file is already
open somewhere, focus that window instead of opening yet another new
one) — this is an open design question, not something to assume either
way; propose an answer but flag it for owner confirmation.

**Q5 — Registration safety**

Given the project's very recent LaunchServices duplicate-entry
incident (fixed only by a reboot), what specifically needs to be true
of the new bundle's registration (unique bundle identifier, distinct
`CFBundleName`/display name, no leftover copies under `build/`, clean
`lsregister -f` behavior) to avoid recreating that problem. Propose a
verification procedure for confirming the two-entry menu looks correct
after registration, in one pass, without repeated
install/register cycles (per the existing On-Device Verification
Procedure's stated risk).

## Deliverable

A report with:
1. Answers to Q1–Q5, each backed by an actual command/API result, not
   inference.
2. A recommended design (or an explicit statement that this isn't
   feasible / isn't worth the complexity, if that's what the
   investigation finds — do not force a design if the honest
   conclusion is "not recommended").
3. An implementation size estimate: **small** (if some built-in
   mechanism turns out to exist and Q1-2 refute the "second bundle"
   assumption), **a real feature-sized task** (companion bundle +
   IPC + registration), or **needs an owner decision** (e.g. if it
   requires accepting meaningfully more app-bundle complexity than the
   owner may want).
4. Anything found along the way that's out of scope, recorded rather
   than fixed.

## Implementation Result

**Status:** Completed

### Method

Inspected the live LaunchServices database on this machine
(`lsregister -dump`) for the real, currently-registered
`/Applications/cooViewer.app` (v1.6.2), read the project's own
`Resources/Info.plist` `CFBundleDocumentTypes` declarations, and
confirmed the AppKit API surface (`application(_:open:)`) via Apple's
own documentation. No code was written; no companion bundle was
created.

### Q1 — How Finder enumerates "Open With" entries

**Confirmed: one entry per registered application bundle, not per
action.** `lsregister -dump`'s record for the real install shows
exactly one `bundle id: cooViewer` block for `/Applications/cooViewer.app`,
carrying a single flat `claimed UTIs:` list (24 UTIs — `.cbz`, `.cbr`,
`.zip`, `.7z`, `.tar` variants, `.pdf`, image types, `.cvbdl`, etc.) and
a single `plugin Identifiers:` line for the two QuickLook extensions.
Underneath it, per-type `claim id:` records (e.g. "7-Zip Archive",
"Gzip Tar Archive") each point back to the **same** `bundle: cooViewer`
— there is no field anywhere in the record for a second, named handler
sharing that bundle. This matches `Resources/Info.plist`'s own
structure ([Resources/Info.plist:7-9](../../Resources/Info.plist#L7-L9)):
`CFBundleDocumentTypes` is a flat array of per-extension dicts, each
with `CFBundleTypeRole = Viewer`, all implicitly under the one
`CFBundleIdentifier` (`jp.coo.cooViewer`) declared once for the whole
bundle. There is no property (in either the live registration or the
source Info.plist) that could produce a second, independently-named
"Open With" row for an already-registered bundle — the identity Finder
displays and launches by *is* the bundle.

**A significant, unrelated finding surfaced while reading the dump**:
the live LaunchServices database currently holds **91 distinct stale
path registrations** for bundle identifier `jp.coo.cooViewer`, nearly
all pointing at long-deleted scratch build directories from past
development sessions (`/private/tmp/claude-501/.../scratchpad/*/cooViewer.app`,
`${TMPDIR}/cooViewer-*/sym/{Deployment,Development}/cooViewer.app`,
one even under `~/.Trash/`). None of this is causing a problem today —
only the real `/Applications/cooViewer.app` entry currently resolves
for QuickLook/Open-With (confirmed separately during the v1.6.2
release verification, `docs/tasks/2026-08-01-01-release-v1.6.2.md`) —
but it is exactly the class of accumulated registration state
`docs/KNOWN_ISSUES.md` #15 warns about, and it is large enough now
that a bad interaction (e.g. a stale path briefly winning precedence
during some future registration event) is not implausible. See "out of
scope" below; not fixed here.

### Q2 — Does Finder pass "action" info through `-application:openFiles:`?

**Confirmed: no.** Apple's documentation for
`application(_:open:)` (the delegate method AppKit calls for both
`-application:openFiles:`'s modern form and Finder-driven opens)
specifies the payload as an array of `URL`s — file locations only.
There is no accompanying parameter for which registered handler, rank,
or display name Finder's menu resolved through; from the receiving
app's perspective, a launch via Finder's default double-click and a
launch via an explicit "Open With ▸ AppName" selection are
indistinguishable once they reach `-application:openFiles:` — both are
just "here are some files, open them." This is consistent with the Q1
finding: since a bundle can't have two named entries, there is nothing
for such a parameter to distinguish between in the first place.
**Conclusion: a second, Finder-visible entry with different behavior
fundamentally requires a second, distinct application bundle** — this
is not an assumption this investigation is relying on, but the
direct consequence of Q1 and Q2 taken together.

### Q3 — Minimal viable design (a second bundle is required)

Given Q1/Q2, the smallest workable shape:

1. **A tiny companion app bundle** (e.g. `cooViewerNewWindow.app`),
   with:
   - Its own, permanent, distinct `CFBundleIdentifier` (e.g.
     `jp.coo.cooViewer.NewWindowHelper` — never reused for anything
     else, and never a scratch/build-generated value — see Q5).
   - `CFBundleDocumentTypes` claiming the same UTIs cooViewer already
     claims (all 24, or a curated subset — owner's call), each with
     `CFBundleTypeRole = Viewer`, and a distinct `CFBundleName`
     (`"cooViewer (New Window)"` or similar) — this is the string
     Finder shows in "Open With."
   - `LSUIElement = YES`, so it never shows a Dock icon or steals
     focus — it is a pure forwarder, never a visible app.
   - No main window, no `MainMenu.xib` of its own beyond the minimum
     `NSApplication`/delegate boilerplate needed to receive
     `-application:openFiles:`.
2. **On launch**, its `-application:openFiles:` receives the file
   path(s) Finder resolved it against, and forwards each one to the
   real, already-registered `cooViewer.app` — **recommended
   mechanism: a private custom URL scheme** (e.g.
   `cooviewer-newwindow://`), registered only by the main app via its
   own `CFBundleURLTypes`, carrying the URL-encoded file path. The
   helper calls `[[NSWorkspace sharedWorkspace] openURL:...]` (or
   equivalently shells out to `open`) with that URL and then calls
   `[NSApp terminate:nil]` immediately — it never opens the file
   itself, never shows UI, and its own process lifetime is a fraction
   of a second.
   - Weighed against the alternatives the task named: Apple Events
     would require either a full `.sdef` scripting suite or raw
     `NSAppleEventDescriptor` construction for a one-shot,
     single-payload message — more moving parts for no benefit here.
     Distributed notifications are broadcast (any process can observe
     them) and not designed to carry a reliable "deliver exactly once,
     to exactly this already-running app" guarantee — wrong shape for
     a targeted forward. A custom URL scheme is the standard,
     well-supported pattern for exactly this "hand off to my real app"
     use case, requires no scripting bridge, and macOS already
     guarantees delivery to (and, if needed, launches) the registered
     handler.
3. **The main app's own `-application:openURL:`** (a new, small
   handler alongside the existing `-application:openFiles:`) decodes
   the forwarded path from the custom-scheme URL and calls
   `-openBookInNewWindow:` directly — bypassing
   `-application:openFiles:`'s front-window-replace logic entirely, so
   Part A's forwarded requests are structurally incapable of landing
   in the front-window-replace path from `d393955` (see Q4).

This is a genuinely new bundled executable with its own build target,
signing, and embedding (most naturally alongside the existing
`cooViewerThumbnail.appex`/`cooViewerPreview.appex` pattern already
proven safe in this project — embedded under
`cooViewer.app/Contents/`, so it ships and gets cleaned up atomically
with the main app rather than needing separate install/uninstall
steps), plus a new Xcode target, a new Info.plist, a URL-scheme
handler on the main app side, and its own signing/notarization
entry in the CI release workflow. **This is explicitly a
feature-sized addition, not a small patch** — flagged per the task's
own instruction not to downplay it.

### Q4 — Interaction with existing behavior

Because the recommended design (Q3) routes the forwarded request
through a *new*, separate delegate method
(`-application:openURL:`) that calls `-openBookInNewWindow:` directly,
**it is structurally impossible for it to go through
`d393955`'s front-window-replace path** — that logic lives entirely
inside `-application:openFiles:`
([Sources/AppController.m:203-246](../../Sources/AppController.m#L203-L246)),
which the new handler never calls. This isn't a runtime check that
could be bypassed by a future edit; it's a different method entirely.
No design decision is needed here beyond "don't call
`-application:openFiles:` from the new handler," which the recommended
design already doesn't.

**Dedup (#32):** since the recommended design forwards straight into
`-openBookInNewWindow:` — the exact same function ⌥⌘O already calls —
and that function's own de-duplication check
([AppController.m:534-541](../../Sources/AppController.m#L534-L541),
`windowControllerShowingBook:`) runs unconditionally at its top before
any window-creation decision is made, **dedup already applies for
free, with no extra design work.** This resolves what the task
labeled an open question: the recommended design doesn't introduce a
choice here at all — "does dedup still apply" is answered by which
function is called, not by a policy this task needs to invent. Still
flagging it explicitly for owner confirmation as instructed, since "a
file already open somewhere gets focused instead of getting yet
another new window, even from the dedicated 'always new window' Finder
entry" is a real behavioral choice, just one this design doesn't have
to author — the owner may want the *literal* "always new window, no
exceptions" reading instead, which is available for it) but would need
a small design change to reach.

### Q5 — Registration safety

Given the newly-found 91 stale registrations (Q1), the concrete
requirements for the new bundle:

- **A `CFBundleIdentifier` that is used for nothing else, ever** —
  including never being reused as a placeholder/scratch value during
  development, which is exactly how the project's *existing*
  `jp.coo.cooViewer` accumulated 91 stale entries (ad hoc test/scratch
  builds all sharing the real identifier). Any local test copy of the
  helper bundle built during its own implementation should get its own
  scratch-suffixed identifier (e.g. `jp.coo.cooViewer.NewWindowHelper.test`),
  exactly the discipline already documented for the main app in
  `CLAUDE.md`'s "multi-instance testing hazard" note
  ([CLAUDE.md:158-168](../../CLAUDE.md#L158-L168)).
- **A distinct `CFBundleName`/display string**, so Finder's "Open
  With" list shows two visually distinguishable rows, not two
  identical-looking "cooViewer" entries a user can't tell apart.
- **Embedding inside `cooViewer.app`** (Q3), not a standalone
  top-level `.app` requiring its own separate install step — this
  means there is exactly one thing to install/uninstall/verify (the
  main app), and no orphaned helper bundle can be left behind after a
  main-app uninstall the way a sibling `.app` could.
- **No leftover copies under `build/`** — already covered by the
  project's existing repository-layout rule (`CLAUDE.md`, "Repository
  Layout": `build/` contains only the final product) and the existing
  `On-Device Verification Procedure`'s single-pass discipline; nothing
  new to add here beyond applying it to the helper bundle too.

**Proposed one-pass verification procedure** (no repeated
install/register cycles, per the existing procedure's own stated
risk): after a single `lsregister -f` of the (test-copy, per
`CLAUDE.md`'s multi-instance rule) built `cooViewer.app`, right-click a
`.cbz`/`.cbr` test fixture in Finder once, screenshot or read the
"Open With" submenu's contents via Accessibility (`System Events`,
which this project's own release-verification sessions already use
successfully — see `docs/tasks/2026-08-01-01-release-v1.6.2.md`), and
confirm both entries appear with visually distinct labels, in one
pass, before doing anything else with that test copy. This mirrors
the existing QuickLook check's "complete all checks needed before
cleanup" discipline
([CLAUDE.md:195-196](../../CLAUDE.md#L195-L196)) rather than adding a
new procedure from scratch.

### Recommended design

As detailed in Q3: a small, embedded, `LSUIElement` helper bundle with
its own permanent identifier, forwarding via a private custom URL
scheme into the main app's `-openBookInNewWindow:` through a new
`-application:openURL:` handler. Dedup and the front-window-replace
exclusion both fall out of this design for free (Q4) rather than
needing separate policy decisions.

**This is not a "small" task** — see the size estimate below — but the
investigation does not find it infeasible or unsafe, provided the
identifier/embedding discipline in Q5 is followed.

### Implementation size estimate

**A real feature-sized task** (companion bundle + IPC + registration),
per the task's own second bucket — not "small" (no built-in mechanism
exists that avoids a second bundle; Q1/Q2 confirm rather than refute
that assumption), and not strictly "needs an owner decision" either,
since the investigation did not find a blocking unknown or a case
where the owner must choose between meaningfully different
architectures — the one open item (Q4's dedup framing) is a
confirmation, not a fork. Concretely, the work involves: a new Xcode
target and Info.plist, a URL-scheme handler on the main app
(`-application:openURL:` → `-openBookInNewWindow:`), embedding and
signing/notarizing the helper alongside the existing QuickLook
extensions in the release workflow, and the Q5 registration
verification pass. Comparable in shape (not necessarily size) to the
existing `cooViewerThumbnail.appex`/`cooViewerPreview.appex` work
already in this project — a known, previously-successful pattern, not
unprecedented territory — but still meaningfully larger than a typical
cooViewer bug-fix or behavior-change task.

### Anything found along the way that's out of scope

- **91 stale LaunchServices registrations** for `jp.coo.cooViewer`,
  all pointing at deleted scratch build paths from past sessions (see
  Q1). Not currently causing a problem (the real `/Applications`
  install correctly wins for QuickLook/Open-With today), but it is
  exactly the accumulation pattern `docs/KNOWN_ISSUES.md` #15 already
  warns about, at a scale (91, not a handful) worth the owner knowing
  about. Not cleaned up here — `lsregister -kill -r -domain local
  -domain user` (or similar) would need its own careful, single-pass
  investigation to confirm it's safe and doesn't affect other
  installed apps, which is out of this task's scope.
- The recommended design's `-application:openURL:` handler is new
  attack surface in the sense that any process could construct a
  `cooviewer-newwindow://` URL and hand it to the main app — worth a
  brief validation note (reject anything that isn't a well-formed,
  existing local file path) when this is actually implemented; not a
  blocker for the design, just a detail to not forget then.
