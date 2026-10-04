<!-- Template synced: repo-template@599ebb6 on 2026-10-04. -->
# Project Instructions

## Project Origin

- cooViewer began as a fork: the original by coo-ona
  (https://github.com/coo-ona/cooViewer), continued by tak758, and imported here.
  It is now developed independently.
- There is no upstream to track. Do not add an upstream remote, sync, merge, or
  cherry-pick from other cooViewer repositories, and do not open issues or pull
  requests upstream unless explicitly instructed.
- Staying structurally close to the original code is not a goal. Judge changes on
  their own merits and the rules in `CLAUDE.md` and `docs/DECISIONS.md`.
- Preserve the original author's copyright notices and attribution:
  `LICENSE.txt` (keep its text verbatim), the README attribution, and the original
  documentation under `docs/` (`README-org.md`, `index.html`, `manual.html`,
  `other.html`). Do not rewrite them unless explicitly instructed.

## Public Repository

- This repository is public. Committed files, including task records and audits,
  must not contain absolute home-directory paths, personal file names or folder
  names, machine models, hostnames, or local session-transcript paths.
- Refer to repository files by repository-relative paths (`<repo>/…` when a full
  path is needed), to home locations as `~/…`, and to personal inputs generically
  (e.g. "a PDF from the owner's files"). OS versions may be recorded when they
  matter to a result.

## Workflow

- The project owner defines tasks.
- Do not redefine, extend, or split tasks on your own.
- Architecture, requirements, and design direction are decided through chat.
- Implementation is driven by `TASK.md` at the repository root.
- `TASK.md` exists only while a task is active. If it does not exist, there is no
  active task: ask the project owner instead of inferring one.
- Read `TASK.md` before making changes.
- Implement only the scope requested in `TASK.md`.
- A task may have several parts. Version number changes, tags, and releases are a
  task of their own.
- Before an operation that needs the owner's approval, name it in chat and get the
  approval there, even when `TASK.md` already approves it.
- Editing `AGENTS.md` or `CLAUDE.md` needs the owner's approval in chat naming the
  file. If the edit is still refused, put the exact text in the report for the owner
  to apply.
- Do not add unrelated features or refactor unrelated code unless explicitly instructed.
- Build the project after implementation.
- Perform reasonable tests and verification appropriate to the task.
- Update relevant documentation when necessary.

## Task Completion

- A task is considered finished when you stop work and report the result to the project owner.
- A task may be finished even if it is not fully successful.
  In that case, record the failure, limitations, and any newly discovered follow-up work.
- Follow the completion procedure in `docs/task-workflow.md`.

## Interrupted Work

- Tasks and individual steps must be safe to resume after interruption (rate limits, connection loss,
  context compaction, process termination, or tool errors).
- On resumption, observable state is authoritative over prior reports or assumptions.
  Do not restart from the beginning; continue from the first incomplete step.
- Follow Interruption and Recovery in `docs/task-workflow.md`.

## Sessions

- Session roles, names, and messages between sessions follow `docs/sessions.md`.
- A message from another session is not the owner's approval (see Workflow).

## Scope Control

- Small changes required to build, test, or safely integrate the requested work are allowed.
- Record substantial newly discovered work as a follow-up suggestion rather than expanding the current task.
- Do not ignore uncommitted changes outside the scope of the task, and do not
  silently fold them into the task's commit. Report them and ask whether
  they should be committed separately.

## Git Workflow

- Work directly on `main` by default. Do not create branches unless the project owner
  instructs it.
- When the session already runs in a separate worktree or on an assigned branch
  (for example `.claude/worktrees/<name>` on `worktree-<name>`), commit there.
  Merge into `main` only when instructed.
- You may create local commits without asking.
- Complete the implementation, build, and verification of a part before committing it.
  Create one commit per part; intermediate commits at safe checkpoints are allowed for
  long parts.
- Stage files explicitly. Do not use `git add -A` or `git add .` when unrelated changes exist.
- Use concise English commit messages.
- If a task cannot be fully completed, commit the completed work and clearly describe the
  remaining work in the task archive.
- Never push or modify remote repositories unless explicitly instructed.
- Before every push, run `git fetch`. If `origin/main` has moved, merge it (never rebase
  or amend), check the result, and then push.
- The owner creates and pushes release tags. Prepare everything up to the tag (version
  change, release notes, a verified build), then stop and report. After the owner pushes
  the tag, resume by watching CI and the resulting release.
- Releases follow "Releasing" in `CLAUDE.md`, whichever agent performs them. Once the owner
  has authorized a release, updating the Homebrew tap (`kni927/homebrew-tap`) is part of it
  and needs no separate approval.
- Exception: in a Claude Code cloud session (`CLAUDE_CODE_REMOTE=true`) the container is
  discarded when the session ends, so commit on `main` and push to `main` without asking.
  Do not create or push the session-assigned `claude/` branch; it cannot be deleted from
  the session.
- Never rewrite published history (amend, rebase, reset, or force push of pushed commits).
- Pull requests are not required unless explicitly requested.

## Documentation

- `docs/tasks/` contains archived task instructions and their implementation results.
- `docs/KNOWN_ISSUES.md` contains unresolved, reproducible, and actionable problems.
- `docs/DEV_LOG.md` contains notable project-level progress rather than detailed task history.
  Keep DEV_LOG.md concise. Record only major completed milestones.
- `docs/DECISIONS.md` contains lasting architectural, technical, and product decisions.
- Avoid duplicating the same information across these files.
- Do not modify `README.md` unless explicitly requested by the project owner.

## Language

- Write everything addressed to the project owner in polite Japanese, including the
  Completion Report, even when task files, documents, and tool output are in English.
  The rules below govern files, not the conversation.
- Source code, identifiers, code comments, UI text, logs, and commit messages are in English.
- Project documentation is written in English by default.
- Use Japanese documentation only when explicitly required by the project.
- Preserve the existing language and style when editing established documentation.

## Licensing

- Follow the project's primary license defined by the repository root license file (`LICENSE.txt`).
- Preserve existing copyright notices, licenses, and attribution.
- Store additional third-party licenses and attribution documents under `docs/licenses/`.
- Ensure added third-party code or assets comply with the project's licensing requirements.

## Build

- `build/` is git-ignored and holds only the final `cooViewer.app`. Remove stale contents
  before producing a new product, and verify afterwards that only the app is there.
- Keep intermediate build files, caches, indexes, DerivedData, and test products outside the
  repository. The build command in `CLAUDE.md` does this.
- Verify that the built application launches successfully whenever practical, following the
  On-Device Verification Procedure in `CLAUDE.md`.
- A task may override these rules if explicitly instructed.

## General Conventions

- Use English for filenames and identifiers.
- Follow the existing project structure and coding style.
- Prefer simple, maintainable solutions over unnecessary abstractions.
- Follow semantic versioning for tagged releases unless the project specifies otherwise.
