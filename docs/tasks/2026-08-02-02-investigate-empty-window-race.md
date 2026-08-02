# TASK: Investigate — the `emptyWindowController`/`hasBookOpen` timing race

## This is an investigation task. Do not implement anything.

The deliverable is a written report with file:line references,
measured/reproduced behaviour, and an implementation size estimate. No
code changes, no new preferences, no new UI.

## Background

During the v1.6.2 release spot-check, acting quickly after launch
briefly caused a real, mid-load restored book to be replaced by a test
file being opened. This was attributed at the time to "a pre-existing
timing window in already-shipped `emptyWindowController`/`hasBookOpen`
logic" — but that was an in-the-moment characterization during a
release verification, not a proper investigation. Establish the actual
mechanism by measurement.

## Working hypothesis (confirm or refute — do not assume it's correct)

A newly-created or restoring window may be treated as "empty" (i.e. a
valid target for "load into the current front window") by whatever
reads `hasBookOpen`, even while an asynchronous restoration/archive
load is still in flight for that same window — because the flag isn't
set to "occupied" until the load *completes*, not when it *starts*. A
second open request landing in that window mid-load then races the
original restore.

## Questions to answer

**Q1 — Every read/write site of the "empty" state**
**Q2 — Restoration's actual timeline**
**Q3 — Reproduce deterministically**
**Q4 — Which entry points are vulnerable**
**Q5 — Recommended fix**

(Full question text as originally written is preserved in the task
history; answers below address each in turn.)

## Implementation Result

**Status:** Completed

### Summary of finding (read this first)

**The working hypothesis is correct in mechanism but too narrow in
scope.** `bookOpen` is indeed only set at load *completion*
([BookWindowController.m:1450](../../Sources/BookWindowController.m#L1450)),
never at load start — confirmed by reproduction. But the restoration
path is **not** the vulnerable one: restoration is already explicitly
protected by a dedicated flag set (`restorationInFlight`,
`restoredBookPending`, `restoredBookOpening`), and the guard that
matters (`isWindowControllerEmpty:`) already consults them. What is
*not* protected is the **ordinary, non-restored open** — any slow
archive load through `-openPage:last:` leaves its window looking empty
to `isWindowControllerEmpty:` for the entire duration of the load,
with no flag covering it at all. Both were reproduced deterministically
(Q3); the second is the real defect and is broader than the incident
that prompted this task.

### Q1 — Every read/write site of the "empty" state

The real ivar is `bookOpen`
([BookWindowController.h:210](../../Sources/BookWindowController.h#L210)),
read through `-hasBookOpen`
([BookWindowController.m:1933-1936](../../Sources/BookWindowController.m#L1933-L1936)).
Confirmed from source, not assumed from the incident report.

**Writes to `bookOpen` — only two, both in `BookWindowController.m`:**

| Line | Write | When |
|---|---|---|
| [1450](../../Sources/BookWindowController.m#L1450) | `bookOpen = YES` | End of `-openPageWithLoader:page:last:fromFileName:`, **after** the archive is fully loaded and pages are in `imageMutableArray` |
| [3440](../../Sources/BookWindowController.m#L3440) | `bookOpen = NO` | `-windowWillClose:` teardown |

There is **no** write at load *start* anywhere — this is the crux of
the whole issue.

**Reads of `-hasBookOpen`:**

| Site | Purpose | Race-relevant? |
|---|---|---|
| [AppController.m:631](../../Sources/AppController.m#L631) `-isWindowControllerEmpty:` | The "is this window reusable" predicate | **Yes — the critical one** |
| [AppController.m:237](../../Sources/AppController.m#L237) `-application:openFiles:` front-window-replace gate (`d393955`) | Decides whether to replace the front window's book | **Yes** |
| [AppController.m:584](../../Sources/AppController.m#L584) `-openBookInNewWindow:` size inheritance (v1.6.2) | Whether to inherit the front window's size | Cosmetic only (wrong size at worst) |
| [AppController.m:549](../../Sources/AppController.m#L549) `-windowControllerShowingBook:` | Dedup #32's lookup | **Yes** (see Q4) |
| [AppController.m:278](../../Sources/AppController.m#L278) `-applicationDockMenu:` | Menu item enablement | No (cosmetic) |
| [BookWindowController.m:762](../../Sources/BookWindowController.m#L762), [854](../../Sources/BookWindowController.m#L854), [1028](../../Sources/BookWindowController.m#L1028), [1041](../../Sources/BookWindowController.m#L1041), [1246](../../Sources/BookWindowController.m#L1246), [3439](../../Sources/BookWindowController.m#L3439) | OpenLastFolder gate, abandon-open teardown, restorable-state encode, decode re-entry guard, previous-book teardown, close teardown | No — all per-window, self-consistent |

**The composite guard**, `-isWindowControllerEmpty:`
([AppController.m:629-634](../../Sources/AppController.m#L629-L634)):

```objc
return (![aController hasBookOpen]
        && ![aController isAwaitingRestoredBook]
        && ![aController isWaitingForUserInput]);
```

Note what it covers and what it doesn't: restoration
(`isAwaitingRestoredBook` = `restorationInFlight || restoredBookPending`,
[BookWindowController.m:928-936](../../Sources/BookWindowController.m#L928-L936))
and password prompts (`isWaitingForUserInput`). **There is no term for
"an ordinary archive load is in progress."**

### Q2 — Restoration's actual timeline

`-window:didDecodeRestorableState:`
([BookWindowController.m:1013](../../Sources/BookWindowController.m#L1013))
→ `-restoreStateWithCoder:` does **not** open the book synchronously.
It sets `restoredBookPending = YES`
([:1079](../../Sources/BookWindowController.m#L1079)) and defers the
actual open by a run-loop turn
([:1090](../../Sources/BookWindowController.m#L1090),
`performSelector:@selector(openRestoredBook) ... afterDelay:0.0`).
`-openRestoredBook` then clears `restoredBookPending` and sets
`restoredBookOpening = YES`
([:1106-1111](../../Sources/BookWindowController.m#L1106-L1111))
*before* calling `-openPage:last:`.

So during a restored book's load: `bookOpen` is still `NO`
(it isn't set until :1450, after the load), but `restoredBookOpening`
is `YES`. **Crucially, `-isAwaitingRestoredBook` deliberately excludes
`restoredBookOpening`** — the header comments this explicitly
([BookWindowController.h:474-476](../../Sources/BookWindowController.h#L474-L476),
[:485-488](../../Sources/BookWindowController.h#L485-L488)): the window
"has to be reusable if the open fails." Only
`-isRestoredBookUnfinished`
([BookWindowController.m:938-946](../../Sources/BookWindowController.m#L938-L946))
includes it, and that is consumed solely by
`-[AppController settleLaunch]`
([AppController.m:750](../../Sources/AppController.m#L750)) to gate the
launch-time Finder queue — **not** by `-isWindowControllerEmpty:`.

This is a deliberate, documented design decision, not an oversight —
which is why the fix in Q5 must not simply bolt `restoredBookOpening`
onto the empty check without addressing the "reusable if the open
fails" requirement that decision exists to satisfy.

### Q3 — Reproduce deterministically

Two separate repros, both with a temporary scratch delay in a
throwaway build (isolated bundle ID + renamed executable per
`CLAUDE.md`'s multi-instance rule; **all scratch code reverted, all
test artifacts and defaults domains deleted afterward** — `git diff`
confirmed empty, clean build re-verified).

**Repro A — restoration path (the incident's scenario).** Deferred
`-openPage:last:` inside `-openRestoredBook` by 8s while keeping the
run loop live. Launched with restoration state pending, then fired a
Finder-open 1s in:

```
SCRATCH: restoredBookOpening=YES bookOpen=0 — deferring -openPage:last: 8s
  [window title at this moment: "Viewer" — restored book not yet loaded]
  [Finder-open of test_utf8.zip fired here]
  [1s later, window title: "test_utf8.zip"]     <- hijacked
SCRATCH: resuming -openPage:last: now, bookOpen=1 hasBookOpen=1 isAwaitingRestoredBook=0
  [final window title: "test_utf8.zip"]         <- restored book silently lost
```

**Confirmed: the race reproduces.** The restored book was silently
abandoned — no crash, no error, no leak reported; the restored book's
own `-openPage:last:` completed *after* the intruder and set
`bookOpen = YES`, but the visible/final content was the intruder's.
This matches the release-incident symptom exactly ("no crash, just
wrong content").

Note this repro deliberately widened the window: in shipping code
`-openRestoredBook` calls `-openPage:last:` synchronously, and
`-application:openFiles:`'s launch queue (`settleLaunch`,
KNOWN_ISSUES #32) covers the launch-time case via
`-isRestoredBookUnfinished`. The incident occurred because a *real,
slow* book load spun the run loop long enough to be interrupted after
the launch had already settled.

**Repro B — ordinary (non-restored) open. This is the broader
finding.** Pumped the run loop for 8s immediately before
`bookOpen = YES` at :1450, on a completely ordinary open — no
restoration involved at all. Launched fresh (no restoration state),
Finder-opened `test.cbz`, then Finder-opened `test_utf8.zip` 1s later:

```
SCRATCH: general-path pre-bookOpen pause, hasBookOpen=0    <- test.cbz mid-load
  [Finder-open of test_utf8.zip fired here]
  [window title 1s later: "test_utf8.zip"]                 <- hijacked
SCRATCH: resuming general-path open, about to set bookOpen=YES
SCRATCH: general-path pre-bookOpen pause, hasBookOpen=1
SCRATCH: resuming general-path open, about to set bookOpen=YES
  [final: "test_utf8.zip"]
```

**Confirmed: the same race exists with no restoration involved.** Any
sufficiently slow archive load leaves its window classified as empty
for the whole load. Since `-openPage:last:` spins the run loop (MW-1's
modal session — noted at
[AppController.m:718-719](../../Sources/AppController.m#L718-L719)),
incoming Finder events *are* delivered mid-load, so this is reachable
in normal use, not only under artificial delay.

### Q4 — Which entry points are vulnerable

| Entry point | Reads the empty state? | Vulnerable? |
|---|---|---|
| **Finder-open front-window-replace** (`d393955`, [AppController.m:237](../../Sources/AppController.m#L237)) | `[front hasBookOpen]` | **Yes** — but note the gate requires `hasBookOpen == YES`, so mid-load (`NO`) it falls *through* to `-openBookInNewWindow:` rather than replacing. The damage happens one step later, at `emptyWindowController` |
| **`-openBookInNewWindow:`** ([AppController.m:610-616](../../Sources/AppController.m#L610-L616) via `-emptyWindowController`) | `-isWindowControllerEmpty:` | **Yes — the actual point of failure.** It does *not* always create a fresh window: it reuses any window that looks empty, which mid-load includes the loading window |
| **Dedup #32** ([AppController.m:549](../../Sources/AppController.m#L549)) | `[aController hasBookOpen] && [[aController currentBookPath] isEqual...]` | **Yes, differently** — a mid-load window fails the `hasBookOpen` test, so dedup *misses* a book that is already being opened. Opening the same file twice in quick succession can therefore produce two windows for one book |
| **v1.6.2 size inheritance** ([AppController.m:584](../../Sources/AppController.m#L584)) | `[front hasBookOpen]` | Cosmetic only — a new window may miss the inherited size |
| **Part A's proposed forwarding** (`docs/tasks/2026-08-02-01-...`) | Would call `-openBookInNewWindow:` | **Would inherit the same exposure**, via `emptyWindowController` |

**Corrects the release-incident write-up:** that report characterized
`-openBookInNewWindow:` as safe because it "always creates a fresh
window." It does not — the empty-window-reuse branch is exactly where
this lands.

### Q5 — Recommended fix

**Do not simply add `restoredBookOpening` to `-isWindowControllerEmpty:`.**
That would fix Repro A only, leave Repro B (the broader case) open, and
collide with the deliberate "reusable if the open fails" design in
Q2.

**Recommended: a general "a load is in flight" flag, set at load start,
cleared on every exit path.**

1. Add an ivar (e.g. `bookLoadInFlight`) set to `YES` at the top of
   `-openPage:last:` ([BookWindowController.m:1163](../../Sources/BookWindowController.m#L1163)) —
   i.e. at load *start*, which is precisely what is missing today.
2. Clear it on **every** exit: the success tail of
   `-openPageWithLoader:...` (next to `bookOpen = YES`, :1450), the
   failure path `-abandonOpenWithLoader:fromFileName:closeWindow:`
   ([:849](../../Sources/BookWindowController.m#L849)), and the
   password-deferred branch ([:1217-1224](../../Sources/BookWindowController.m#L1217-L1224))
   where `-openPage:last:` returns early with the sheet up — that case
   is already covered by `isWaitingForUserInput`, so the flag must not
   double-count or get stranded there.
3. Add it to `-isWindowControllerEmpty:` as a fourth term.

**This directly addresses the Q5 sub-question about a failed load
getting stuck "occupied":** because the flag is cleared in
`-abandonOpenWithLoader:` — the single, already-existing funnel for
every failure (bad archive, cancelled password), per its own comment
at [:839-848](../../Sources/BookWindowController.m#L839-L848) — a
window whose load fails becomes available again exactly as it does
today. This is why the fix hangs off that existing funnel rather than
inventing new cleanup: the "reusable if the open fails" guarantee is
preserved by construction, not by a new parallel code path that could
drift from it.

Dedup (#32) is a **separate** sub-problem: fixing "empty" does not make
a mid-load window *findable* by `-windowControllerShowingBook:`, which
needs `hasBookOpen` **and** a matching `currentBookPath`. Note
`currentBookPath` *is* already set before the load (via
`-setCurrentBookPathAndOldBookPath:`,
[:1123](../../Sources/BookWindowController.m#L1123) /
[:895](../../Sources/BookWindowController.m#L895)), so the data is
present — only the `hasBookOpen` gate hides it. Whether dedup should
match mid-load windows is a **behavioral decision for the owner**
(matching prevents duplicate windows for the same book, but means a
second request gets focus on a window still showing nothing), so it is
flagged rather than folded into the recommendation.

### Implementation size estimate

**One small task** for the core fix (one ivar, one set site, three
clear sites, one added term in `-isWindowControllerEmpty:` — all in
already-well-commented code with an existing failure funnel to hang
the cleanup off). Verification is the larger half: it needs the Q3
scratch-delay repro re-run to confirm both Repro A and Repro B stop
reproducing, plus a regression pass over restoration, the launch-time
Finder queue (#32), password-protected archives (#33), and failed
opens — this project's usual multi-window regression surface.

The dedup question above is **needs an owner decision**, and should be
split out rather than bundled: it is a user-visible behavior change,
not a defect fix.

### Anything found along the way that's out of scope

- **The release-incident characterization was partly wrong** and is
  corrected here (see Q4): `-openBookInNewWindow:` is not immune. The
  v1.6.2 archive (`docs/tasks/2026-08-01-01-release-v1.6.2.md`) is
  left as written — it is an accurate record of what was believed at
  the time — with this report as the corrected finding.
- **Repro B implies a user-reachable bug with no restoration
  involved**: double-clicking two large archives in quick succession
  can drop the first. Not reproduced against real-world-sized files
  here (only under scratch delay), so its practical frequency is
  unmeasured — worth a note in `docs/KNOWN_ISSUES.md` when the fix
  task is written, rather than filing a speculative issue now.
- `-openPage:last:` spinning the run loop (MW-1's modal session) is
  the underlying enabler for all of this. Making archive loading
  non-run-loop-spinning would remove the whole class of problem, but
  that is a far larger architectural change than the targeted fix
  above and is explicitly **not** being recommended here.
