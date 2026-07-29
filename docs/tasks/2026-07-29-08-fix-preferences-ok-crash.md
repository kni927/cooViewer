# Fix KNOWN_ISSUES #25 — Crash on Preferences ▸ OK with a book open

## Context

Discovered during MW-5 verification, but **confirmed pre-existing**: the
crash reproduces on `3d88521` (MW-4, the last pushed state before MW-5),
on `2cacdc2` (mid-MW-5), and on the final MW-5 build. It is not caused by
the multi-window work.

Symptom: with a book open, opening Preferences and pressing OK crashes the
app. Under `NSZombieEnabled`:

```
-[CFString copyWithZone:]: message sent to deallocated instance
```

i.e. an over-released `NSString` — something is being released without an
owning retain, or released twice. This is an MRC codebase, so it's a
manual retain/release accounting bug, not ARC weirdness.

This is being fixed as a standalone task **before MW-6**, so that later
multi-window sessions don't have to keep distinguishing "is this my
regression or issue #25?".

## Scope

- Find and fix the over-release. Fix the actual ownership bug — do not
  paper over it by adding a stray `retain` at the crash site if the real
  problem is elsewhere.
- Root-cause it before patching: identify *which* string, *who* released
  it, and *why* the release is unbalanced. Record that in the archived
  task, not just "added a retain".
- Likely area to start from (confirm, don't assume): the Preferences OK
  path — `PreferenceController`'s OK handling, `setPreferences` and the
  `PreferencesDidChange` notification path added in MW-3, and any string
  read out of `NSUserDefaults` and passed across that boundary. Note that
  MW-3 changed `[controller setPreferences]` into a posted notification,
  and MW-5 changed how `PreferenceController` reaches the window (via
  `appController`) — but since the crash predates both on `3d88521`,
  neither is the cause. Use them as map, not as suspect.

## Investigation approach

- Reproduce under `NSZombieEnabled` and capture the full backtrace at the
  point of the zombie message — that gives the *reader*. Then find the
  *releaser*: `malloc_history` / `MallocStackLoggingNoCompact` on the
  zombie address, or Instruments' Zombies template, will give the
  retain/release history for that allocation.
- Guard Malloc is also available if the zombie trail is ambiguous.
- Check whether the string is autoreleased somewhere and additionally
  released, a common MRC pattern failure (e.g. a `stringWith...`
  convenience constructor being `release`d by the receiver, or a getter
  returning an autoreleased object that a caller treats as owned).

## Acceptance

- Preferences ▸ OK with a book open no longer crashes, verified on-device.
- Also verify with **no** book open (the other state), and that
  Preferences ▸ Cancel and a settings round-trip (change a value → OK →
  reopen Preferences → value persisted) still behave correctly.
- Run once under `NSZombieEnabled` after the fix to confirm the zombie
  message is gone, not merely that the crash window moved.
- Build clean, zero new warnings (current baseline: 312, all pre-existing
  deprecations — must stay 312).
- No render-path change (per CLAUDE.md's inviolable image-quality rule);
  this fix should not touch anything between decode and `drawInRect:`.

## Verification

- Build with the documented command
  (`BUILD_TMP=... xcodebuild ... -scheme cooViewer_deploy -configuration Deployment ...`).
- On-device via the screen-shared Mac mini session.
- **Use the test build, never `/Applications/cooViewer.app`** — same bundle
  ID, same defaults domain (see KNOWN_ISSUES #23). Back up the
  `jp.coo.cooViewer` domain before testing and restore after, as prior
  sessions did.
- Follow `docs/task-workflow.md` on completion: append the Implementation
  Result here, archive to `docs/tasks/2026-07-29-NN-fix-preferences-ok-crash.md`,
  close #25 in `docs/KNOWN_ISSUES.md`, update `docs/DEV_LOG.md` (and
  `docs/DECISIONS.md` if any non-obvious ownership convention gets
  established by the fix).

## If it turns out not to be fixable quickly

If root-causing runs long, prefer landing a well-documented diagnosis
(exact object, exact unbalanced release, exact call path) over a guessed
patch. A precise write-up in #25 is more useful to the next session than a
speculative `retain`.

## Blocks

MW-6 (recommended to fix first, per the MW-5 completion report).

---

## Implementation Result

**Status:** Completed

### Root cause

The over-released string is the page bar's, and the unbalanced release is
inside `-[AccessoryView setPageString:]` itself — an **aliasing** bug, not a
missing retain somewhere else. Backtrace captured at the zombie message
(`lldb`, `NSZombieEnabled=YES`, `-k "bt"` so the batch session prints a stack
on the fault):

```
-[BookWindowController setPreferences]
  -> -[CustomImageView setPreferences]
    -> -[AccessoryView setPreferences]
      -> -[AccessoryView setPageString:]
        -> -[NSConcreteAttributedString initWithString:attributes:]   <- reads freed memory
```

- **Which string:** the `NSString` returned by
  `-[NSAttributedString string]` for `AccessoryView`'s `pageString` ivar
  (an `NSAttributedString`). It is the attributed string's own backing store,
  so its lifetime *is* the attributed string's.
- **Who released it:** `-setPageString:` itself, via `[pageString release]`
  — releasing the attributed string deallocated its backing string.
- **Why the release is unbalanced:** it isn't, in isolation. The bug is the
  *order*. `-[AccessoryView setPreferences]` re-renders the current page
  string with the newly built `pageStringAttr` by calling
  `-setPageString:[pageString string]` (`AccessoryView.m:187`, `:198`), and
  `-[AccessoryView pageString]` returns that same inner object. So the
  argument was owned by the value the setter released on its first line, and
  the next line read it:

  ```objc
  [pageString release];                                                  // frees `string`
  pageString = [[NSAttributedString alloc] initWithString:string ...];   // reads `string`
  ```

- **Why only with a book open:** with no book,
  `-[BookWindowController]` calls `[imageView setPageString:nil]`, so
  `pageString` is nil and `-setPageString:` takes its `if (!string)` early
  return. The `else` branch — the unsafe one — is reached only when
  `pageString` is already non-nil.

### Changes

- `Sources/AccessoryView.m`, `-setPageString:` only: build the new
  `NSAttributedString` first, then release the old one, then assign. The
  `if (!pageString) … else …` split disappears with it, because
  `[nil release]` is a no-op and the `else` branch *was* the unsafe ordering.
  No `retain` was added at the crash site and no caller was changed — the
  callers are correct, the setter was not.

### Verification

- **Build:** clean build with the documented command, `** BUILD SUCCEEDED **`.
  Warning count **312**, and `diff` against the pre-fix warning set is empty
  — zero new warnings, as required.
- **Automated:** none (no test harness in this project; see
  `docs/KNOWN_ISSUES.md` #10).
- **Manual, on device** (test build only, never `/Applications`; the
  `jp.coo.cooViewer` domain was exported before testing and restored
  afterwards, verified by a key-by-key diff showing zero differing keys):
  - Preferences ▸ OK **with a book open** — no crash. Repeated under
    `NSZombieEnabled=YES` (injected via `LSEnvironment` in a throwaway copy of
    the bundle, so the env var reached the process actually driven, and
    confirmed with `ps eww`): **no zombie message in the unified log**, so the
    crash is gone rather than displaced.
  - The page bar still renders after OK: `#3-4/4 (page04.jpg 1200x1800 |
    page03.jpg 1200x1800)` drawn correctly, i.e. the re-render with the new
    attributes — the thing `setPreferences` was calling the setter *for* —
    still works.
  - Preferences ▸ **Cancel** with a book open — fine.
  - Preferences ▸ OK with **no book open** — fine (this path never crashed,
    checked as the control).
  - **Settings round-trip:** "Number of items in the Open Recent menu"
    40 → 12 → OK → reopen Preferences → shows 12 → set back to 40 → OK.
  - **Render check:** a per-window `screencapture` of the two-page spread is
    **byte-identical (same SHA-256)** to the MW-5 baseline, so nothing between
    decode and `drawInRect:` moved. (`AccessoryView` is the page-bar HUD in a
    child window and is not on the image render path at all, but the check is
    cheap.)
- **Not performed:** encrypted archives, Apple Remote, multi-display,
  slideshow — unrelated to this path.

### Remaining Issues

None for this crash.

One deliberate non-change, recorded in #25 for the next reader:
`-[AccessoryView setInfoString:]` (`AccessoryView.m:681`) has the **identical**
release-then-consume ordering. It cannot fire today — `infoString` has no
getter and every caller passes a freshly built string, never
`[infoString string]` — and this task was scoped to the actual over-release,
so it was left alone rather than silently widened.

### Follow-up Suggestions

- Give `-[AccessoryView setInfoString:]` the same create-then-release ordering
  next time that file is touched (latent, not currently reachable).
- `-[AccessoryView setPreferences]` reassigns the retained `pageStringAttr`
  ivar (`AccessoryView.m:175`, `:182`) **without releasing the previous
  dictionary** — a small leak of one `NSDictionary` per Preferences ▸ OK. It is
  an under-release, the opposite of the bug this task was about, so it was not
  folded in. Worth a one-line fix in its own change.
- `-[AccessoryView setPreferences]` calls `-setPageString:` twice with the same
  value (`:187` guarded by `didFirst`, then `:198` unconditionally). The first
  call appears redundant; confirm before removing.
- MW-6 is now unblocked.
