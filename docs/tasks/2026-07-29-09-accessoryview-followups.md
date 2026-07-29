# AccessoryView — Three Follow-Up Fixes from KNOWN_ISSUES #25

## Context

Fixing #25 (`2aa2ae0`, pushed) surfaced three adjacent problems in
`Sources/AccessoryView.m` that were deliberately left out of that task's
scope, to keep the crash fix minimal and reviewable. They are recorded in
the #25 entry in `docs/KNOWN_ISSUES.md`.

All three are memory-management / redundancy issues in the same file. None
is a crash today. This is a standalone cleanup task **before MW-6**, taken
while the surrounding code is still fresh.

Recall the #25 root cause, since two of these three are the same shape:
`-setPageString:` released the old value *before* building the new one,
while a caller passed `[pageString string]` — an object owned by the value
being released. MRC convention is **create new, then release old**.

## Scope — three independent fixes

### 1. `-[AccessoryView setInfoString:]` — same ordering hazard (latent)

`AccessoryView.m:681` has the identical release-then-create shape as the
bug fixed in #25. It is **currently unreachable**: `infoString` has no
getter, and every caller passes a freshly-constructed string, so no caller
can pass an object owned by the value being released.

Fix it anyway, the same way `-setPageString:` was fixed — this is
prophylactic. The moment someone adds an `infoString` getter, this becomes
the #25 crash again.

Confirm the "no getter, all callers pass fresh strings" claim still holds
before assuming it's unreachable; if some caller *can* reach it, that
changes this from latent to a real bug and should be noted.

### 2. `-[AccessoryView setPreferences]` — `pageStringAttr` leak

`AccessoryView.m:175` and `:182` reassign the retained `pageStringAttr`
without releasing the previous value. Result: one leaked `NSDictionary`
per Preferences ▸ OK.

This is an **under**-release — the opposite direction from #25 — so it
needs its own careful pass rather than a mechanical repeat of fix 1.
Release the old value correctly; watch for the same aliasing trap in
reverse (make sure nothing still reads the old dictionary after release).

### 3. `-setPreferences` calls `-setPageString:` twice

`AccessoryView.m:187` (the `didFirst` variant) and `:198`. The first looks
redundant.

**Do not delete it on "looks redundant" alone.** Determine what the
`didFirst` path was for — check history (`git log -p`/`git blame` on those
lines) and whether the two calls differ in the attributes in effect at
each point. If it genuinely has no observable effect, remove it and say
why in the archived task. If it *does* differ, leave it and document the
reason so nobody re-raises this later.

Note that #25's verification specifically confirmed the page bar still
redraws correctly after OK — that behavior must survive this change.

## Commit structure

Three separate commits, one per fix, in the order above (ascending risk /
descending certainty). Fix 3 is the only one that can change observable
behavior; land it last so a bisect points at it cleanly.

## Acceptance

- Preferences ▸ OK with a book open still works and still redraws the page
  bar correctly (the #25 regression surface).
- Also verify: Preferences ▸ Cancel, OK with no book open, and a settings
  round-trip (change a value → OK → reopen → persisted).
- Fix 2: confirm the leak is actually gone — Instruments (Leaks or
  Allocations) across repeated Preferences ▸ OK cycles, not just by
  reading the diff.
- Build clean, warnings must stay at **312** (all pre-existing
  deprecations); `diff` against the current warning set must be empty.
- No render-path change (CLAUDE.md's inviolable image-quality rule).
  Re-confirm with a spread window capture SHA-256 matching the current
  baseline, as #25's verification did.

## Verification

- Build with the documented command
  (`BUILD_TMP=... xcodebuild ... -scheme cooViewer_deploy -configuration Deployment ...`).
- On-device via the screen-shared Mac mini session.
- **Use the test build, never `/Applications/cooViewer.app`** — same bundle
  ID, same defaults domain (KNOWN_ISSUES #23). Back up `jp.coo.cooViewer`
  before testing, restore after, and diff to confirm zero delta.
- Run once under `NSZombieEnabled` after all three commits, to confirm the
  memory-management changes introduced no new over-release.
- Follow `docs/task-workflow.md` on completion: append the Implementation
  Result here, archive to
  `docs/tasks/2026-07-29-NN-accessoryview-followups.md`, update the #25
  entry in `docs/KNOWN_ISSUES.md` (these three were filed under it — close
  or amend as appropriate) and `docs/DEV_LOG.md`.

## Out of scope

KNOWN_ISSUES #24 (All Bookmark browser has no UI entry path since MW-4
retargeted `Edit Bookmark...` to First Responder) — different area,
different fix, and it needs a UI decision about where the entry point
should live. Not part of this task.

## Blocks

MW-6 (doing this first while `AccessoryView.m` is fresh).

---

## Implementation Result

**Status:** Completed with follow-up issues

Two of the three items were code changes; the third turned out not to be a
bug at all. Details below, since "we found nothing" needs its evidence
recorded as much as a fix does.

### Commit breakdown

| commit | item |
|---|---|
| `52f389e` | 1 — `-setInfoString:` safe setter ordering |
| `4c0b92d` | 2 — docs only: the `pageStringAttr` leak does not exist (claim retracted) |
| `f494a0a` | 3 — remove the duplicated `-setPageString:` call |

Item 2 produced no code change, so its commit carries the retraction instead.
That keeps one commit per item in the requested order, and keeps fix 3 — the
only behaviour-affecting change — last for bisecting.

### 1. `-[AccessoryView setInfoString:]` — done (prophylactic)

Re-confirmed the "unreachable" claim before changing anything:
`AccessoryView.h` declares only `-infoStringRect`, **no `infoString`
getter**, and every caller reaches the setter through
`-[CustomImageView setInfoString:]` from `BookWindowController`'s fit-mode,
read-mode, sort-mode and bookmark paths, all passing `[NSString
stringWithFormat:…]`, a literal, or `bookmarkTitle` (read out of a bookmark
dictionary, not out of `infoString`). So nothing can pass
`[infoString string]` today and the #25 crash cannot fire here.

Given the same create-then-release ordering anyway, matching `-setPageString:`.

### 2. `pageStringAttr` leak — **there is no leak; the claim was wrong**

The follow-up note filed under #25 (written by this same agent) cited only the
assignment sites at `AccessoryView.m:175` and `:182` and never read the
release block at the top of the same method. In full:

- First call — `!didFirst` branch — sets `pageStringAttr = nil` (`:58`), then
  assigns a retained dictionary. Balanced.
- Every later call — `else` branch — does `[pageStringAttr release]` (`:75`)
  *before* the reassignment. Balanced.

Also checked the reverse hazard the task warned about: `:75` releases without
nil-ing, so is the stale pointer read before `:175`? No — the only readers are
`-setInfoString:` (`:689`, `:692`) and `-setPageString:` (`:785`), and neither
runs until `:198`, after the reassignment. `-pageBarRect` at `:162` touches
none of the released ivars. So there is no dangling read either.

Runtime confirmation, as the task required rather than "reading the diff":
`leaks` against a running instrumented build (`MallocStackLogging` injected
via `LSEnvironment` in a throwaway bundle copy) reported

```
Process 28152: 327 leaks for 25408 total leaked bytes.
```

**identically before and after three Preferences ▸ OK cycles**, with no
allocation attributed to `-[AccessoryView setPreferences]`. A one-dictionary
per-OK leak would have shown as +3.

No code change. The claim is retracted in the #25 task archive and in the
#25 entry itself so it is not acted on later.

### 3. Duplicated `-setPageString:` — removed

`-[AccessoryView pageString]` returns `[pageString string]`, so
`[self setPageString:[self pageString]]` (`:187`) and
`[self setPageString:[pageString string]]` (`:198`) were **the same
expression**. Two further findings decided it:

- The `if (didFirst)` guard on `:187` was **dead**: `didFirst` is set to `YES`
  at `:29`, at the top of the same method, so by `:187` it is always true.
  Whatever the guard once meant, it had stopped meaning it.
- The only state changing between the two calls is `autoHidedPageString`
  (`:193-197`), which `-setPageString:` consults *only* to decide whether to
  call `setNeedsDisplayInRect:`. `[self display]` at `:199` redraws the whole
  view unconditionally, so that difference is not observable.

`git log -L 185,200:Sources/AccessoryView.m` shows both lines arriving in the
file's **first** commit (`77b2275`, "1.2b24") — no later change to interpret,
so there was no intent to preserve. Removed, with the reasoning left in a
comment at the site so this is not re-raised.

### Verification

- **Build:** clean build after each commit. `312` warnings, and `diff`
  against the pre-task warning set is **empty** — the required baseline held.
- **On device**, test build only (`build/cooViewer.app` and throwaway copies
  under the scratchpad; `/Applications` never touched). The
  `jp.coo.cooViewer` domain was exported before testing and restored after —
  **zero differing keys across all 81** on the final diff.
  - Preferences ▸ OK with a book open: no crash, and the page bar redraws
    with its string (`#1-2/4 (page02.jpg 1200x1800 | page01.jpg 1200x1800)`)
    — the #25 regression surface, and specifically what fix 3 could have
    broken.
  - `-setInfoString:` exercised after fix 1: ⌘2 / ⌘3 / ⌘1 render
    "Fit to Screen Width" etc. correctly.
  - Preferences ▸ Cancel, Preferences ▸ OK with **no** book open, and a
    settings round-trip (Open Recent count 40 → 17 → OK → reopen → 17 → back
    to 40) all behave as before.
  - **`NSZombieEnabled` run after all three commits** (injected via
    `LSEnvironment`, confirmed present with `ps eww`): the whole sequence
    above ran with **no zombie message** in the unified log and no crash, so
    the memory-management edits introduced no new over-release.
  - **Render:** spread window capture is **byte-identical (same SHA-256)** to
    the MW-5 baseline.
- **Not performed:** Instruments GUI (used the `leaks` CLI instead, which
  answers the same question and is scriptable); encrypted archives, Apple
  Remote, multi-display.

### Remaining Issues

None for the three scoped items.

### Follow-up Suggestions

- **New finding from the `leaks` run:** 6 of the process's 327 leaked
  allocations are attributed to
  `-[AccessoryView setFrame:]` → `+[NSBezierPath bezierPathWithRectWithDoubleArc:]`
  (reached from `-[CustomWindow setFrame:display:]` →
  `-resizeSubviewsWithOldSize:`). The count did **not** grow across
  Preferences cycles, so it is bounded, not per-event. `-setFrame:` itself
  releases and reassigns `pageBarBezierPath` correctly, so the allocation is
  inside the path helper or its retained internals. Small and pre-existing;
  worth a look only if `AccessoryView`/`NSBezierPath_Adding` is opened again.
- `AccessoryView` has **no `-dealloc` at all**, so every retained ivar it owns
  is released only by process exit. Harmless while the view is a nib
  top-level object living for the app's lifetime — but MW-7 gives each window
  its own `AccessoryView`, and then it stops being harmless. Worth folding
  into MW-6 or MW-7 rather than filing separately.
- KNOWN_ISSUES #24 (All Bookmark browser has no UI entry point) remains open
  and out of scope here, as the task specified.
- MW-6 is unblocked.
