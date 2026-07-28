# Task: Multi-Window Support — Reconsideration & Implementation

## Background
- Multi-window support was previously investigated and left pending. That earlier judgment is documented in `docs/audit-20260711.md` (Claude Code audit).
- Codex has now produced a fresh audit at `docs/codex-audit-20260728.md` (written in Japanese).
- This round is not about re-litigating whether to do it — the direction is to proceed with implementation. The goal is to determine the best approach.

## Process (2-pass — mandatory, do not skip)

### Pass 1: Independent investigation
- Do NOT read `docs/audit-20260711.md` or `docs/codex-audit-20260728.md` yet.
- Base this pass only on the current codebase (window/document management, Controller, any singleton/global state) and general NSDocument/NSWindowController best practices.
- Points to cover:
  - NSDocument-based architecture vs. multiple NSWindowControllers within the current structure — which fits better here
  - State that must be shared across windows vs. state that must stay per-window (preferences, recently opened files, QuickLook, etc.)
  - Inventory of existing single-window assumptions (globals, singletons, etc.) and their blast radius
  - Staged implementation plan (minimal viable step → incremental expansion)
- Write the Pass 1 conclusion to `docs/multiwindow-pass1.md` and stop there.

### Pass 2: Reconciliation with prior audits
- After Pass 1 is written, read both `docs/audit-20260711.md` and `docs/codex-audit-20260728.md`.
- Compare against the Pass 1 conclusion and produce:
  - Points of agreement
  - Points Codex/the prior audit raised that Pass 1 missed
  - Points Pass 1 raised that the other audits missed
  - Whether the original reason for pending is still valid or has since been resolved
- State the final design direction and implementation plan.

## Deliverables
- `docs/multiwindow-pass1.md` (Pass 1 conclusion)
- `docs/multiwindow-pass2.md` (reconciliation + final direction)
- Once agreed, break down into implementation tasks

---

## Implementation Result

**Status:** Completed

Investigation and planning task only — no source code was changed.

### Changes

- `docs/multiwindow-pass1.md` (new) — Pass 1, written from the current
  codebase alone, before either audit was read. Covers the NSDocument
  vs. NSWindowController choice, shared/per-window state classification,
  an inventory of single-window assumptions with a mechanical blast-radius
  table, and a staged plan.
- `docs/multiwindow-pass2.md` (new) — Pass 2 reconciliation against
  `docs/audit-20260711.md` §2a and `docs/codex-audit-20260728.md`:
  points of agreement, what each side missed, resolution of the one
  genuine design disagreement, and a verified answer to whether the
  original reason for deferring still holds.
- `docs/multiwindow-plan.md` (new) — the agreed task breakdown,
  MW-1 … MW-9, after the project owner settled the Step 0 behaviour
  questions. Each MW task carries scope, out-of-scope, acceptance
  criteria, risk and dependencies.
- `docs/DECISIONS.md` — new entry "Multi-window: AppController +
  NSWindowController, not NSDocument (2026-07-28)", recording the
  architecture decision, the reasons NSDocument is rejected, and the
  five Step 0 behaviour decisions.
- `docs/codex-audit-20260728.md` — committed as a task input (was
  untracked).

Deviation from scope: none. The two-pass order was followed strictly —
Pass 1 was written and saved before either audit file was opened.

### Verification

- Build: not performed (documentation-only change; no source touched).
- Automated verification: none applicable.
- Manual verification: every code claim in both passes was checked
  against the current tree, including the 42 nib references to object
  484 (9 outlets + 33 action targets), the app-wide event pump in
  `archiveReadProgress:total:` (`Controller.m:1134`), the app-modal
  password prompt (`Controller.m:1161`), the 16 `[NSScreen mainScreen]`
  sites, the 44 localized-title branches in `validateMenuItem:`, and
  the status of all six "quick wins" from the 2026-07-11 audit.
- Not performed: any code change, build, or on-device run.

### Remaining Issues

None blocking. Two behaviour questions are carried into the plan as
flagged assumptions with recommendations, to be settled in the task
that needs them rather than up front:

- **A1** — with "File ▸ Open replaces" plus "quit on last window
  close", no in-app route creates a second window. Recommended:
  add "Open in New Window… (⌥⌘O)". Decided in MW-7.
- **A2** — the `Fullscreen` preference defaults to YES (the app
  launches fullscreen today). Recommended: retire that launch
  behaviour under native fullscreen. Decided in MW-2.

### Follow-up Suggestions

- Start MW-1 (load-time concurrency and modality safety) as the next
  `TASK.md`. It is the highest-risk code, is fully verifiable while
  the app is still single-window, and is the one defect that would
  silently corrupt input across windows later.
- Independent cleanups surfaced but deliberately kept out of the
  multi-window arc: Alias Manager → `NSURL` bookmarks
  (`Controller.m`); `[NSImage imageFileTypes]` → `imageTypes` (5
  sites); the 4 remaining `NSRunAlertPanel`/`NSBeginAlertSheet` sites
  in `PreferenceController.m`; converting `validateMenuItem:`'s 44
  localized-title branches to selector dispatch.