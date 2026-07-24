# Task Workflow

## Interruption and Recovery

Work may be interrupted by rate limits, connection failures, context
compaction, process termination, or tool errors. The same prompt may be
re-sent verbatim. When resuming:

1. Do not assume the last requested or reported step failed.
2. Inspect the current repository and relevant external state before making
   further changes.
3. Determine which steps are completed, partially completed, or not started.
4. Continue from the first incomplete step. Re-run a completed step only
   when its result is missing, invalid, or cannot be verified.

The original goal and acceptance criteria remain authoritative throughout.

When determining execution progress, observable state is authoritative,
including:

- Presence or absence of `TASK.md` at the repository root. Its absence
  together with a matching `docs/tasks/YYYY-MM-DD-NN-*.md` archive is strong
  evidence that the task was already completed and reported.
- Files and generated build artifacts such as under `build/`.
- `git status`, diffs, and commit history.
- Local commits not yet pushed, using `git log @{u}..HEAD` when an upstream
  branch is configured.
- Existing branches, tags (`git tag -l`), releases (`gh release view`),
  and uploaded assets.
- Build and test output.

Before any non-idempotent operation or external side effect, including
commit, tag, push, release creation, or asset upload, explicitly confirm
that the intended result does not already exist.

For long-running or multi-stage work, update `TASK.md` at meaningful phase
boundaries with the last completed step, current partial state, and exact
next step, consistent with the Compact Instructions in `CLAUDE.md`.

## Handover and Session Transfer

Choose the record type by situation. Do not produce more than one for the
same event.

- **Normal completion:** append the implementation result to `TASK.md`,
  archive it under `docs/tasks/`, and provide the chat completion report
  (see Task Completion and Completion Report below). No handover file.
- **Deliberate transfer of an incomplete task to a new chat:** create a
  handover report at `docs/handovers/YYYY-MM-DD-NN-<desc>-hNN.md`, matching
  the task's date and sequence number. Use the template at
  `docs/handover-template.md`.
- **Resuming after an unexpected interruption:** normally just update
  `TASK.md` per Interruption and Recovery above. Only for a genuinely
  complex recovery, record it at `docs/recoveries/YYYY-MM-DD-NN-<desc>-rNN.md`,
  reusing the handover template.

A handover records only what exists in this chat and cannot be recovered
from the repository or existing docs. Do not transcribe repository state
(git status, tags, releases); the next session inspects it directly.

## Task Completion

Follow the task completion and archiving procedure.

```md
## Implementation Result

**Status:** 
- Completed
- Completed with follow-up issues
- Partially completed
- Not completed

### Changes

- Summarize the implemented changes.
- Note important files or components that were modified.
- Record any intentional deviation from the requested scope.

### Verification

- Build:
- Automated verification:
- Manual verification:
- Not performed:

### Remaining Issues

- List unresolved problems directly related to the task.
- Write `None` if no known issues remain.

### Follow-up Suggestions

- List meaningful next-step suggestions discovered during implementation.
- Do not implement them as part of the current task.
- Write `None` if there are no suggestions.
```

When reporting back:

- Append the implementation result to `TASK.md`.
- Record unresolved actionable problems in `docs/KNOWN_ISSUES.md` when appropriate.
- Update `docs/DEV_LOG.md` when the task represents meaningful project progress.
- Update `docs/DECISIONS.md` when a lasting design or architectural decision was made.
- Archive `TASK.md` as: `docs/tasks/YYYY-MM-DD-NN-description.md`.
- Do not leave `TASK.md` in the repository after reporting.

- Use a two-digit sequence number starting at `01` for each date.

- Do not redefine, extend, or split a task on your own.
- Any further work must be recorded as follow-up suggestions and handled as a new `TASK.md` after review by the project owner.

## Completion Report

At the end of every task, provide a concise completion report in the chat response that can be copied directly into another conversation.

- The completion report is intended to be copied into a follow-up chat if needed.

- Use the following structure:

### Completion Report

- Status: Completed / Partially completed / Could not complete
- Summary:
- Files changed:
- Build:
- Automated verification:
- Manual verification:
- Commit:
- Push:
- Remaining issues:
- Suggested next step:

Include exact file paths, commands, test counts, and the local commit hash when available.

Clearly distinguish:
- Verified automatically
- Verified manually
- Not verified

Do not rely on `docs/DEV_LOG.md` or the archived task as the only completion report.
Keep the report self-contained and concise.