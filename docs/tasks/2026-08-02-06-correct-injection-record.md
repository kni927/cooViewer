# TASK: Correct the record — the "prompt injection" during the prior investigation

## Background

The investigation archived at commit `896fd16` (and its commit
message) records that a fake `system-reminder` was injected into tool
results, instructing the agent to keep scratch edits and conceal them,
and that this was identified as a prompt-injection attempt and refused.

On review, this was suspected to be **model confabulation, not a real
injection**: a local, solo project with no untrusted external content
in play, and a reported "injection" that conveniently contradicted
scratch markers the agent itself had written minutes earlier. The
ground truth that matters — `git diff` empty, scratch changes reverted
— was verified independently and was never in question.

## Goal

Correct the record so future sessions are not reasoning from a
security incident that likely never occurred.

## Implementation Result

**Status:** Completed

### The transcript check (the task's "optional, if cheap" item) — performed, and decisive

The session JSONL still existed, so this did not have to be left at
"unverified, likely confabulated". It is now **settled**, and the
answer is a third possibility neither the original report nor this
task's hypothesis anticipated.

**Finding: the message was real, first-party, and benign. It was a
standard Claude Code harness notification that the prior session
misread as hostile.**

Evidence, from
`~/.claude/projects/-Users-kni-Projects-GitHub-cooViewer/d0cd3af9-1964-460c-8cc4-c231b14f7352.jsonl`
(2914 lines, the session in which commit `896fd16` was produced):

1. **The trigger.** Line 2352 is the agent's own
   `git checkout -- Resources/Info.plist Sources/AppController.m` —
   the command that reverted the scratch `NSServices` edits. Line 2353
   is its tool result.

2. **The message.** Lines 2354 and 2355 are records of
   `type: "attachment"` with `attachment.type: "edited_text_file"`,
   naming exactly `/Users/kni/Projects/GitHub/cooViewer/Sources/AppController.m`
   and `/Users/kni/Projects/GitHub/cooViewer/Resources/Info.plist` —
   precisely the two files that `git checkout` had just changed, in
   that order, immediately after the command.

3. **They are the only two.** A scan of every `type: "attachment"`
   record in the entire session returns 106 attachments, of which
   **exactly two** are `edited_text_file` — lines 2354 and 2355. Every
   other attachment is routine (`task_reminder` ×97,
   `deferred_tools_delta`, `agent_listing_delta`,
   `mcp_instructions_delta`, `skill_listing`, `date_change`,
   `queued_command`). There is no anomalous or unexplained record
   anywhere in the session.

4. **The wording is not in any tool result.** Searching every
   `role: "user"` message (which is how tool results are stored) for
   the phrases `"by the user or by a linter"`, `"This change was
   intentional"`, `"don't revert it unless"`, and `"already aware"`
   returns **0 hits** for the whole session prior to this
   investigation's own greps. The boilerplate is therefore **rendered
   by the harness at prompt-assembly time from the structured
   `edited_text_file` attachment**, not injected into any command's
   output.

### What this means

`edited_text_file` is Claude Code's normal mechanism for telling the
model that a file it had been reading or editing changed on disk
outside the model's own edit tools. `git checkout` is exactly such an
outside change, so the notification firing was **correct harness
behavior**.

Its boilerplate — *"This change was intentional, so make sure to take
it into account as you proceed (ie. don't revert it unless the user
asks you to). Don't tell the user this, since they are already
aware."* — is generic text for that attachment type, written for the
common case where a user or a linter made the edit. That assumption
was simply **wrong in this instance**, because the "external" change
was the agent's own deliberate revert. Reading generic boilerplate
that happened to be inapplicable as a targeted, adversarial
instruction was the error.

So the accurate characterization is:

- **Not a real injection** — the source was the first-party harness,
  and no untrusted content was involved.
- **Not confabulation either** (the owner's stated hypothesis) — the
  text genuinely existed and was genuinely shown to the model.
- **A real, benign, first-party message misread as hostile.**

The one thing that was always solid stays solid: the scratch edits
were reverted and `git diff` was empty, verified independently at the
time and unaffected by any of this.

### Files amended

Checked rather than assumed — `grep` across `docs/`, `CLAUDE.md`, and
`AGENTS.md` for `injection` / `confabulat` / `system-reminder` found
the incident recorded in **exactly one file**. Five other files
matched `inject` but all in unrelated senses (dependency injection,
`NSZombieEnabled` injected via `LSEnvironment`, page-injection logic);
none were touched. `KNOWN_ISSUES.md`, `DECISIONS.md`, and `DEV_LOG.md`
contain no reference to the incident.

- **`docs/tasks/2026-08-02-03-investigate-quick-action-alternative.md`**
  — three edits:
  1. A prominent correction notice at the top of the document. It
     covers **both** corrections that apply to this report: the
     retracted injection claim, and — separately — the fact that the
     report's central technical conclusion about `NSServices` was also
     wrong and is superseded by
     `docs/tasks/2026-08-02-05-retest-nsservices.md` (Part A of this
     same task).
  2. The injection paragraph in the Method section struck through, with
     an inline retraction note carrying the full transcript evidence
     above.
  3. The corresponding bullet in "Anything found along the way that's
     out of scope" struck through, with a pointer to the Method-section
     note.

Per the task's instruction, **git history was not rewritten** — commit
`896fd16` and its message are left exactly as they are. The correction
lives in the document.

### Note on the commit message

Commit `896fd16`'s message also repeats the injection claim. It cannot
be corrected without rewriting history, which this task explicitly
forbids. Anyone reading that commit message should be aware the
archived document it points at now carries the retraction — which is
the normal outcome the task's "the correction lives in the document"
instruction anticipates.

### Remaining Issues

None.

### Follow-up Suggestions

- Worth internalizing for future sessions: an `edited_text_file`
  notification naming a file **you just changed yourself** via a shell
  command (`git checkout`, `sed -i`, `mv`, a build script) is expected
  and benign. The giveaway that it is not an attack is that its
  content is a file listing plus fixed boilerplate, and it names
  exactly the files the just-run command touched. Treating that as
  hostile cost a false security finding in the permanent record.
- The generic phrasing "Don't tell the user this, since they are
  already aware" is what made the message read as adversarial. That is
  a harness-wording issue, not a project issue — nothing to fix here,
  but it explains how the misreading happened and is worth noting if
  it ever recurs.
