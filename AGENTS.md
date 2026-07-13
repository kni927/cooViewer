# Project Instructions

## Workflow

* The project owner defines tasks.
* Do not redefine, extend, or split tasks on your own.
* Architecture, requirements, and design direction are decided through chat.
* Implementation is driven by `TASK.md` at the repository root.
* Read `TASK.md` before making changes.
* Implement only the scope requested in `TASK.md`.
* Do not add unrelated features or refactor unrelated code unless explicitly instructed.
* Build the project after implementation.
* Perform reasonable tests and verification appropriate to the task.
* Update relevant documentation when necessary.

## Task Completion

A task is considered finished when you stop work and report the result to the project owner.

A task may be finished even if it is not fully successful. In that case, record the failure, limitations, and any newly discovered follow-up work.

Before archiving `TASK.md`, append the following sections:

```md
## Implementation Result

**Status:** Completed | Completed with follow-up issues | Partially completed | Not completed

### Changes

- Summarize the implemented changes.
- Note important files or components that were modified.
- Record any intentional deviation from the requested scope.

### Verification

- Build:
- Tests:
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

1. Append the implementation result to `TASK.md`.
2. Record unresolved actionable problems in `docs/KNOWN_ISSUES.md` when appropriate.
3. Update `docs/DEV_LOG.md` when the task represents meaningful project progress.
4. Update `docs/DECISIONS.md` when a lasting design or architectural decision was made.
5. Archive `TASK.md` as:
   `docs/tasks/YYYY-MM-DD-NN-description.md`
6. Do not leave `TASK.md` in the repository after reporting.

Use a two-digit sequence number starting at `01` for each date.

Do not redefine, extend, or split a task on your own.
Any further work must be recorded as follow-up suggestions and handled as a new `TASK.md` after review by the project owner.

## Scope Control

* Do not implement features outside the requested scope unless explicitly instructed.
* Small changes required to build, test, or safely integrate the requested work are allowed.
* Record substantial newly discovered work as a follow-up issue rather than expanding the current task.

## Git Workflow

* Commits may be created when the completed work forms a coherent unit.
* Prefer one commit per task when practical.
* Use concise English commit messages.
* Build and verify before committing.
* Do not push to a remote repository unless explicitly instructed.
* Initial publication to GitHub and other significant push points are reviewed by the project owner.
* Direct branch merges are acceptable for small solo projects.
* Pull requests are not required unless explicitly requested.

## Documentation

* `docs/tasks/` contains the original task instructions and their implementation results.
* `docs/KNOWN_ISSUES.md` contains unresolved, reproducible, and actionable problems.
* `docs/DEV_LOG.md` contains notable project-level progress rather than detailed task history.
* `docs/DECISIONS.md` contains lasting architectural, technical, and product decisions.
* Avoid duplicating the same information across these files.

Create `docs/KNOWN_ISSUES.md`, `docs/DEV_LOG.md`, or `docs/DECISIONS.md` when the project
grows enough to benefit from them. Once created, keep them updated when relevant.

## Language

* Communication and explanations to the project owner are primarily in Japanese.
* Source code, identifiers, code comments, UI text, logs, and commit messages are in English.
* Project documentation is written in English by default.
* Use Japanese documentation only when explicitly required by the project.
* Preserve the existing language and style when editing established documentation.

## Licensing

Follow the licensing requirements of this repository.

- Preserve existing license files and copyright notices.
- Do not remove or modify third-party attribution unless explicitly instructed.
- When adding third-party code, ensure its license is compatible with the project.

## General Conventions

* Use English for filenames and identifiers.
* Follow the existing project structure and coding style.
* Prefer simple, maintainable solutions over unnecessary abstractions.
* Follow semantic versioning for tagged releases unless the project specifies otherwise.
