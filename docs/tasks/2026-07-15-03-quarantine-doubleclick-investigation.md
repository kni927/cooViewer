# TASK: Double-click open fails while app is running + file is quarantined — phase 10

## Background

Phase 9's investigation (archived:
`docs/tasks/2026-07-15-02-doubleclick-open-investigation.md`) could not
reproduce the reported "double-click doesn't switch document" bug, and
made one unrelated fix (`application:openFile:` returning `NO` on
success).

Further investigation in chat (details below) went through several
false leads — a correlation with large/solid RAR files, then with one
specific file, then with file identity/inode via rename and copy tests
— before the actual root cause was isolated.

### Confirmed root cause

The differentiator between failing files (`1.cbz`, `1.cbr`, and their
renamed/copied variants) and working files (`sample.cbr`, `1-solid.cbr`)
is the `com.apple.quarantine` extended attribute:

```
$ xattr -l 1.cbz
com.apple.quarantine: 0081;...;Chrome;...
$ xattr -l sample.cbr
com.apple.provenance: ...   # no quarantine — already Gatekeeper-cleared
```

Removing the attribute fixed the problem:

```
$ xattr -d com.apple.quarantine 1.cbz
```

— after this, double-clicking `1.cbz` while another document was open
in a running cooViewer correctly switched documents.

This confirms the actual bug: **a quarantined file (e.g. freshly
downloaded via a browser, not yet Gatekeeper-cleared) fails to trigger a
document switch when double-clicked in Finder while cooViewer is already
running.** Two other paths were confirmed to work fine even while the
file is still quarantined:

- Cold launch (double-click when cooViewer is not yet running) — works.
- File > Open menu command on the same quarantined file — works.

This narrows the cause specifically to the **Finder-double-click-while-
already-running** delivery path (Apple Event / Launch Services routing
an "open documents" request to an already-running app), not to
document-loading logic itself, which is already confirmed correct via
File > Open and cold launch. The earlier rename/copy tests are now
explained in hindsight: `mv`/`cp` propagate extended attributes
including `com.apple.quarantine` by default, so the symptom appeared to
"follow the file" through those tests — it was the attribute the whole
time, not file identity, inode, or path.

### Open question: regression or pre-existing limitation?

The owner recalls (unverified) that double-clicking a quarantined file
while cooViewer was already running used to work in an earlier version.
If true, this is a **regression**, not a pre-existing platform
limitation, and the investigation approach should change accordingly.
Two candidate phases touched relevant code:

- **Phase 7** (QuickLook extension) modified UTI declarations and
  `CFBundleDocumentTypes`-adjacent Info.plist content, which could
  affect how Launch Services routes open requests to the already-
  running app.
- **Phase 9** changed `application:openFile:` to return `YES` on
  success instead of always `NO` — this return value is exactly the
  signal Finder uses to know whether the open succeeded, so an
  interaction with quarantine-related timing is plausible.

**Before starting the instrument-and-observe work below**, verify which
case this is:

- Build (or use the phase 5 `v1.3.7` git worktree if still available,
  otherwise build the commit just before phase 7) and test the exact
  same scenario: a quarantined `.cbz`/`.cbr`, app already running with
  another document open, double-click in Finder.
- If it fails the same way on that older build: this is a pre-existing
  limitation, not a regression. Proceed with the investigation scope
  below as written.
- If it works correctly on that older build: this is a regression.
  Bisect between that commit and the current `main` (phase 7 and phase
  9 are the prime suspects) to find the exact commit that broke it, and
  focus the fix on reverting/correcting that specific change rather
  than the broader investigation below.

## Goal

- Double-clicking a quarantined file in Finder, while cooViewer is
  already running with a different document open, correctly switches to
  and displays the new file — matching the behavior already working for
  cold launch and File > Open.
- No regression to any currently-working path (cold launch, File > Open,
  double-click on already-cleared files).

## Scope

### In scope

- **Understand the actual delivery mechanism** for "open this file in
  the already-running app" from Finder: confirm whether cooViewer
  implements the modern `application(_:open:)` (`URL`-based) or the
  legacy `application:openFile:` / `application:openFiles:` (path-
  based) delegate method(s), and which one Finder actually invokes for
  this scenario on the OS version in use.
- **Instrument and observe**, don't assume:
  - Is the relevant delegate method invoked at all when double-clicking
    a quarantined file while the app is already running? (If not
    invoked, the request may be getting intercepted/blocked earlier —
    e.g. by a Gatekeeper/quarantine confirmation dialog that Finder
    expects to handle before Apple Event delivery, which could be
    silently failing or being dismissed in a way that drops the event.)
  - If it is invoked, what does it receive, and does the existing code
    handle it correctly from that point on (compare against the known-
    working File > Open code path — do they converge on the same
    loading logic, or diverge somewhere)?
  - Check Console.app / system logs around the moment of the failed
    double-click for any Gatekeeper, LaunchServices, or Apple Event
    related warnings/errors specific to the quarantined file.
- **Fix**, once the exact failure point is confirmed. Do not guess at a
  fix before observing where in the delivery chain the request is lost
  — the fix will differ significantly depending on whether:
  - The Apple Event itself never arrives (a Finder/Gatekeeper-side
    interaction issue, possibly requiring a different Info.plist
    declaration, an entitlement, or acknowledging some system prompt
    cooViewer isn't currently handling), vs.
  - The event arrives but cooViewer's handling of it silently fails for
    quarantined files specifically (e.g. a permission check, a
    sandboxed file-access attempt that fails silently for
    not-yet-cleared files, an exception being swallowed).
  - If the file-access failure is sandbox/entitlement-related, note
    that cooViewer's own file-access approach for File > Open (which
    works) vs. Finder-delivered-while-running (which fails) may differ
    in how they obtain access to the file — compare them directly.

### Out of scope

- Multi-window support.
- Any other performance changes to phases 1–6.
- The `application:openFile:` return-value fix from phase 9 (already
  done; leave as-is unless it's directly implicated in this bug).
- Changing or working around Gatekeeper/quarantine behavior itself
  (e.g. don't attempt to strip quarantine attributes automatically —
  that's a user/system-level action, not something the app should do
  silently for security reasons). The fix should make cooViewer handle
  quarantined files correctly, not bypass quarantine.

## Verification

- Download (or simulate via `xattr -w com.apple.quarantine "0081;...`)
  a fresh quarantined `.cbz`/`.cbr` test file. With cooViewer already
  running and a different document open, double-click the quarantined
  file in Finder — confirm it now switches documents correctly.
- Repeat for both `.cbz` and `.cbr`.
- Confirm still-working: cold launch on a quarantined file, File > Open
  on a quarantined file, double-click on an already-cleared file while
  running.
- If root cause turns out to involve a system dialog/prompt cooViewer
  wasn't previously handling, document what the user-visible experience
  is now (e.g. does a security prompt appear once, is it silent, etc.).

## Implementation Result

**Status:** Partially completed

### Changes

No code changes were made. Despite following the task's exact
prescribed verification methodology, the reported bug could not be
reproduced in this environment — see below. No fix could be
implemented without first observing the actual failure point, and
guessing at one would risk masking a real issue or introducing
unneeded complexity for a symptom that may not exist in the tested
environment.

### Investigation performed

**Step 1 (regression vs. pre-existing), as instructed:** built the
commit just before phase 7 (`0546a91`, via `git worktree add`, reusing
the already-built `vendor/lib`) and tested the exact scenario: launched
it with a non-quarantined file, then double-clicked the quarantined
`1.cbr` (quarantine confirmed present via `xattr -l` beforehand) in
real Finder while it was running. **It switched documents correctly.**

**Before concluding "regression," verified the premise on the current
build too** (the task's decision tree assumes the current build fails;
this wasn't yet directly confirmed by me, only reported in chat) —
built current `main` and ran the identical test. **It also switched
documents correctly.** Since this contradicted the reported symptom,
extended the test matrix rather than accepting a single data point:

| Build | File A → File B | Quarantine | Result |
|---|---|---|---|
| Pre-phase-7 (`0546a91`, local dev build) | `sample.cbr` → `1.cbr` | `1.cbr` pre-existing (from browser download) | Switched correctly |
| Current `main` (local dev build, `~/Applications`) | `sample.cbr` → `1.cbr` | same, still present | Switched correctly |
| Current `main` (local dev build) | `3.cbz` → `1.cbr` (both quarantined) | both pre-existing | Switched correctly |
| Current `main` (local dev build) | fresh copy → fresh copy | freshly applied (`xattr -w`, new UUID each), never opened before | Switched correctly |
| Current `main` (**real notarized `/Applications` release**, Developer ID signed) | fresh copy → fresh copy | freshly applied, never opened | Switched correctly |
| Current `main` (real notarized release) | `sample-solid.cbr` → `1-solid.cbr` (1.4 GB, freshly quarantined) | freshly applied to a large file specifically, to test a "large-file quarantine scan timing" hypothesis | Switched correctly |

Six variations across: pre/post phase-7 code, locally-signed vs.
Developer-ID-signed+notarized builds, `.cbz`/`.cbr`, small and 1.4 GB
files, and both pre-existing and freshly-applied (never-before-opened,
unique-UUID) quarantine attributes. **All six switched documents
correctly** — the reported symptom did not reproduce under any tested
condition, including a direct re-test with the exact same `1.cbr` file
whose quarantine state was preserved specifically for this
investigation.

Console logs were not inspected for Gatekeeper/LaunchServices errors
because no failure occurred to inspect logs around.

### Remaining Issues

**Root cause not identified — bug not reproduced.** This investigation
cannot distinguish "regression" from "pre-existing limitation" from
"environment-specific/not a real bug" because the failure itself
didn't occur under any tested condition, including conditions matching
the chat-reported repro (same exact file, quarantine intact) as closely
as possible from a fresh investigation session. Possible explanations,
not yet distinguished:
- Something specific to the original live/interactive session (timing,
  a system dialog that appeared and was handled differently, a macOS
  security setting) not captured by scripted/computer-use-driven
  testing.
- The bug may require a condition not yet tried (exact repro steps
  beyond "double-click while running" weren't independently
  re-confirmed step-by-step in this session).

### Follow-up Suggestions

- Before further investigation, re-confirm the failure live, narrating
  each step exactly (which file, which order, any dialogs seen,
  precisely how the double-click was performed) so a difference from
  the conditions tested here can be identified.
- If it recurs, capture a Console.app log or `log stream` session
  spanning the actual failed double-click, since this investigation
  never had a failure to observe.
