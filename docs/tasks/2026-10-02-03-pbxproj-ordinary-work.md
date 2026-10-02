# TASK: Agent guidance — treat project.pbxproj edits as ordinary project work

## Background

During TASK A2 (`docs/tasks/2026-10-02-02-launch-drain-replaces-front-window.md`)
Claude Code's auto mode classifier denied two routine steps as "Modify Shared
Resources":

- editing `cooViewer.xcodeproj/project.pbxproj` (raising
  `MACOSX_DEPLOYMENT_TARGET` to 12.0), and
- running the `CLAUDE.md` build command with a build-setting override on the
  command line.

The owner had to make the edit by hand. According to the Claude Code
documentation (auto mode configuration), the classifier reads `CLAUDE.md`
but not task files such as `TASK.md`, so the approval written in `TASK.md`
did not count. The next release (TASK F, v1.6.4) edits `project.pbxproj`
again for the version bump, so the same denial is expected unless
`CLAUDE.md` says that this file is the project's own build configuration.

Separately, the owner has already edited `AGENTS.md` so that conversation
with the owner, including progress updates, is in Japanese. That edit
belongs to this task.

## Goal

1. `CLAUDE.md` states, in the "Project-specific (cooViewer)" section, that
   editing `project.pbxproj` and running the build command are ordinary work
   in this repository.
2. The owner's `AGENTS.md` language change is committed.

## Scope

### In scope

- Add this text to `CLAUDE.md` ▸ Project-specific (cooViewer), as one bullet
  near the build command. Wording may be tightened, but keep the meaning and
  the last sentence:

  > `cooViewer.xcodeproj/project.pbxproj` is this repository's own build
  > configuration. Editing it — build settings, version numbers, targets,
  > file references — when `TASK.md` calls for it is ordinary project work,
  > not a change to shared infrastructure. The same applies to running the
  > build command above, including build-setting overrides on the command
  > line. This does not relax the Releasing rules: pushing a tag still needs
  > the owner's explicit authorization.

- `AGENTS.md`: check `git status` and `git diff AGENTS.md`.
  - If the owner's language-rule edit is uncommitted, include it unchanged in
    this task's commit.
  - If it is already committed, nothing to do; say which commit has it.
  - Do not reword the owner's edit.

### Out of scope

- Any other change to `CLAUDE.md` or `AGENTS.md`.
- Source code, the project file itself, and build settings.
- Pushing. TASK F pushes `main` together with the release.
- Any other uncommitted change found in the worktree: report it and ask, per
  `AGENTS.md` ▸ Scope Control.

## Implementation notes

- This is a documentation-only task. No build is required.
- Whether the classifier actually honours the new text can only be observed
  the next time `project.pbxproj` is edited (the TASK F version bump). Say so
  in the result rather than claiming it was verified.

## Verification

- `git diff --check` is clean.
- The final diff touches only `CLAUDE.md`, `AGENTS.md` (only if the owner's
  edit was uncommitted), and the task archive.
- Follow `docs/task-workflow.md` ▸ Task Completion (archive this file under
  `docs/tasks/`, one commit).

## Progress

- Last completed step: Implementation Result filled in; archived under
  `docs/tasks/`.
- Current partial state: Staging (`git add CLAUDE.md <archive>`) was denied
  by the auto mode classifier ("[Self-Modification]"); the owner commits.
- Exact next step: None for the agent.

## Implementation Result

**Status:** Completed with follow-up issues

### Changes

- `CLAUDE.md` ▸ Project-specific (cooViewer): added the bullet stating that
  editing `cooViewer.xcodeproj/project.pbxproj` and running the build
  command (including command-line build-setting overrides) is ordinary
  project work, and that the Releasing rules are not relaxed. The text is
  the wording from this task, unchanged, placed directly after the build
  command bullet.
  - Deviation: the agent's own edit of `CLAUDE.md` was denied by the Claude
    Code auto mode classifier (reason given: "[Self-Modification]"). The
    owner added the bullet by hand; the agent checked the resulting diff
    against the requested text. Staging `CLAUDE.md` with the archive
    (`git add`) was then also denied ("[Self-Modification]"), so the owner
    made the commit. No workaround was attempted for either denial.
- `AGENTS.md`: no uncommitted change existed (`git status`, `git stash
  list`, and `git worktree list` showed nothing). The language rule was last
  changed in `eb04d30` ("Write the whole Completion Report in Japanese"),
  which says everything addressed to the owner is in polite Japanese. That
  text does not literally say "progress updates"; if the owner intended a
  further wording change, it was not present in this checkout.

### Verification

- Build: not required (documentation only)
- Automated verification: `git diff --check` clean. The commit touches only
  `CLAUDE.md` and this archive.
- Manual verification: `git diff CLAUDE.md` read and compared with the
  requested text.
- Not performed: Whether the auto mode classifier now allows editing
  `project.pbxproj` and running the build command with overrides. This can
  only be observed the next time the file is edited (the TASK F version
  bump).

### Remaining Issues

- Editing and staging `CLAUDE.md` are both denied by the classifier as
  self-modification, so future changes to agent instructions may need to be
  made and committed by the owner.

### Follow-up Suggestions

- In TASK F, record in the Completion Report whether the `project.pbxproj`
  version bump and the build command were allowed or denied.
