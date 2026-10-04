# Sessions

How the owner's Claude Code sessions are organized and how they reach each
other. The same file is kept in every repository the owner works in:
`kni927/repo-template` and its projects, `kni927/dotfiles`, `kni927/home-server`,
and `kni927/HQ`. Change it in `kni927/repo-template` and carry it over with
the `sync-projects` skill there.

## Roles

- **Central HQ** (cloud): oversees every session. Keeps track of what is open
  from `list_sessions`, relays between projects, receives reports that lost
  their recipient, and tells the owner about items that have stalled. Does not
  implement.
- **Upstream HQ** (cloud): policy shared by all repositories. Changes
  `kni927/dotfiles` and `kni927/repo-template` and carries the changes to the
  projects with the `sync-projects` skill. The owner brings each Mac up to date
  with `~/Projects/GitHub/pull-repos.command`. It sends each policy change to
  the Project HQs itself, without waiting to be asked.
- **Project HQ** (cloud): plans one project and writes its TASKs. It is
  created with `create_session`, the project's repository as `source_url`
  (for example `https://github.com/kni927/cooViewer`), and `main` as
  `source_revision`; with both, claude.ai files it under that repository in
  the session list (without `source_revision` it lands in Other). It is archived once its
  TFs are done, and may first be renamed with a version (`cooViewer v1.6.5 HQ`).
- **TF**, task force (usually a local session on a Mac): receives a TASK from
  its Project HQ, carries it out, and reports back. A TF takes one TASK after
  another until it wraps up, and hands heavy work to subagents.

## Names

- `Central HQ`, `Upstream HQ`, `<repo> HQ`, `<repo> TF <what>`, for example
  `cooViewer TF v1.6.5`. No middle dot: local session names are often typed by
  hand. The current session of a role carries the plain name. A session that
  has finished renames itself `✅ <name>`, and one that has handed over
  `✅ <name> (handover YYYY-MM-DD)`, so the plain name is free and the session
  list shows what can be archived.
- Names are unique, because a local session addresses messages by name.
- A name set from the cloud (`set_session_title`) may not appear in the Mac app.
  Name a local session on the Mac, or let it name itself as the `/tf` skill
  does.
- Do not write session IDs into repository files. Refer to sessions by name, and
  look up current IDs with `ListAgents` or `list_sessions`.

## Messages

Send each message only to the sessions that need it.

- A TF's reports and progress go to its Project HQ only. Central HQ follows
  them through `list_sessions`.
- Upstream HQ sends a policy change to every current Project HQ by session ID,
  and a one-line summary to Central HQ.
- Information for reference goes to the HQs it concerns, not to Central HQ.
- An HQ tells the owner itself what waits on the owner. Central HQ reports
  only items that have stalled.
- Central HQ receives only: messages between projects (it relays them),
  reports that lost their recipient (it forwards them to a successor), HQ
  handovers, and one-line summaries of policy changes.

- **HQ to HQ:** cloud sessions reach each other directly with `send_message`
  (claude-code-remote) to the session ID, in both directions; a reply goes back
  to the `from-session` of the received message. Look up an HQ's current ID by
  name with `list_sessions`.
- **TF ready:** right after naming itself, a TF sends its name and that it is
  waiting for a TASK, with `SendMessage` to `<repo> HQ` as `ListAgents` lists
  it, or to `Central HQ` if that HQ cannot be reached. The Project HQ tells the
  owner under the receiving heading below, then sends the TASK to the
  `from-session` of that message, so it does not depend on finding the TF by
  name.
- **HQ to TF:** `send_message` (claude-code-remote) to the TF's session ID, with
  the TASK text. The TF accepts TASKs only from its own Project HQ, or, in a
  repository without one (such as `kni927/HQ`), from the HQ the owner names.
  It shows that the TASK arrived and its key points, not the full text, since
  `TASK.md` is archived later. It then runs `git pull` on `main` (stopping if
  that would not be a fast-forward; a TF in a worktree instead runs
  `git fetch` and `git merge --ff-only origin/main` on its branch), saves
  the text as `TASK.md` at the repository root, and carries it out. Where a
  TASK explicitly asks for something else than these steps (for example "do
  not change the repository", so `TASK.md` stays in the scratchpad), the
  TASK wins; the TF tells the owner in one line which step it changed, and
  asks when the conflict is unclear. After a TASK, the TF reports and waits
  for the next one.
- **TF to HQ:** a local session has no send addressed by session ID. Use
  `SendMessage` to the HQ's name as `ListAgents` lists it. Each send reports
  "one-way" (cannot reply); that is the wording of anthropics/claude-code#98897,
  and the message does arrive. Once that bug is fixed, reply to the session ID
  in the received message's `from-session` instead, which does not depend on
  unique names. The TF tells the owner in one line where it sent the message,
  without saying whether it was read; the HQ does not acknowledge receipt.
- **Fallback:** if the Project HQ cannot be reached, for example because it is
  archived, send to `Central HQ`. Central HQ summarizes for the owner and forwards to a successor
  Project HQ if there is one.
- **Receiving:** an HQ that receives a message starts its next reply to the
  owner with this heading, then a summary. Replies are not expected by
  default, so neither the heading nor the summary says "no reply needed". Each
  `---` stands alone on its line with a blank line before and after it
  (directly under text, Markdown turns that text into a heading); do not use
  `--` or box-drawing characters. The owner does not see the message body in
  that session; give the full text when asked.

  ```markdown

  ---

  ### 📨 受信：<sender session name> ／ <kind of report>

  ---

  <summary>
  ```
- A message holds at most 64 KB. `&` and angle brackets may arrive as HTML
  character references; check them before using the text in code.
- A message is not the owner's approval. Permission dialogs, auto mode
  approvals, tag pushes, and edits to `AGENTS.md` or `CLAUDE.md` are approved by
  the owner in the session that performs them.

## Proposing improvements

Every session, HQ or TF, proposes improvements to how the work is done without
waiting to be asked, not only what it was told to do.

- **When:** it follows a multi-step procedure from the documents by hand,
  repeats steps it or another session did before, works around the same
  problem again, or makes a mistake that a written procedure would prevent.
- **What:** usually a skill; otherwise a script, a hook, a setting, or a
  rule in the template. Say what it would do, what it saves, and where it
  would live: the project's `.claude/skills/` for one project,
  `kni927/repo-template` for every project, `kni927/dotfiles` for the Mac
  setup and local sessions. A cloud session sees only skills in its
  repository, so a skill for HQs lives in the repositories they run in.
- **To whom:** the session proposes to the owner. One that concerns every
  repository also goes to Upstream HQ; a TF sends its proposals with its
  report to its Project HQ.
- **Proposing is not doing:** build it only after the owner agrees.

## Context usage

A long conversation is compacted automatically, which loses detail. Cloud
sessions compact at 80% of the maximum context
(`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`), local sessions at 97%. A cloud session
reads its own usage with `get_session` without an ID (`context_usage`); a local
session in the Mac app reads it with `get_usage` for session `self`.

- **Checking:** every session, HQ or TF, checks its usage at natural breaks
  and before starting a step that would not fit. It does not report its usage
  in ordinary replies; it reports only when it hands over or wraps up, in the
  ready-to-archive block.
- **Thresholds:** a cloud HQ hands over (below) and a local TF wraps up (see
  Local sessions) without waiting for the owner, at a natural break where the
  handover stays short:

  | Session | From (at a natural break) | At the latest (next break) |
  |---|---|---|
  | Cloud HQ | 75% | 85% |
  | Local TF | 80% | 90% |

  A compaction before that is acceptable. The owner may also say "handover"
  or "wrap up" at any time.
- **Warning:** a Project HQ that sees one of its TFs past 90% warns the owner.
  Central HQ reminds an HQ that has passed 85% and is still working.
- **Ready to archive:** a session that has wrapped up or handed over ends with
  this block in its chat, in English, and waits. The rules follow the same
  Markdown rules as the receiving heading; the heading is one level larger so
  that it stands out.

  ```markdown

  ---

  ## ✅ This session is ready to archive.

  - Session: <name>
  - Context: <used> / <maximum> tokens (<percent>%)

  ---
  ```

## Creating cloud sessions

A Code cloud session gets a repository only when the owner picks one in
claude.ai/code, or when a Code cloud session calls `create_session` with
`source_url` and `source_revision` `main`. A claude.ai chat, a scheduled task,
and a Routine cannot attach one; for scheduled work that needs a repository, a
Routine wakes an existing HQ, which then calls `create_session`.

## Handing over an HQ

A cloud HQ hands its work to a fresh session at the thresholds in Context
usage, when the owner says "handover", and right after a
compaction if one has already happened.

1. Write the handover: the HQ's role and repositories, open items and their
   state, what waits on the owner, the sessions it coordinates (by name), and
   recent decisions with their commits. Leave out what the repositories
   already record and what the owner's personal preferences already say (how
   to address the owner, the language and tone of replies).
2. Start the successor with `create_session` in the same environment, with
   the same `source_url` and `source_revision` `main`, titled with the HQ's plain name and with the
   handover as its initial prompt. `source_url` is the project's repository
   for a Project HQ, `https://github.com/kni927/dotfiles` for Upstream HQ
   (which then attaches `kni927/repo-template` with `add_repo`), and
   `https://github.com/kni927/HQ` for Central HQ; their `AGENTS.md` makes this
   file binding. `source_url` takes one repository, and attaching any other
   needs the owner's explicit approval, which auto mode requires. If auto mode
   stops `create_session` or the successor needs that approval, tell the owner
   and keep working until it is resolved.
3. Tell the successor's name upstream (Central HQ; when Central HQ itself
   hands over, Upstream HQ) and downstream (the Project HQs or TFs it
   coordinates).
4. Rename itself `✅ <name> (handover YYYY-MM-DD)` with `set_session_title`,
   using the owner's local date, show the ready-to-archive block, and stop
   taking work. The owner archives it.

The handover is sent, not committed: it may hold session IDs and context that
exists only in chat.

## Local sessions on the Mac

- **Starting a TF:** in a new local session in the repository, the owner types
  `/tf <what>` (`~/.claude/skills/tf/SKILL.md`, managed by `kni927/dotfiles`).
- **Starting a TF from a card:** an HQ, or a TF that wraps up, can offer a TF
  with `spawn_task`. The card opens in the offering session's repository. Its
  prompt asks the new session to read `~/.claude/skills/tf/SKILL.md` and
  follow it as if the owner had typed `/tf <what>`; a slash command in a
  card's prompt does not run. The owner picks **Start locally**, and **Start
  with worktree** only when another TF is working in the main clone. Neither
  pulls first; the TF brings itself up to date when a TASK arrives.
- **A TF in a worktree** works in `.claude/worktrees/<name>/` on a
  `claude/<name>` branch created from the main clone's local `HEAD`. It
  commits on that branch and merges into `main` only when the TASK says so
  (Git Workflow in `AGENTS.md`). The owner removes the worktree and its
  branch after archiving the TF.
- **One TF per working directory:** local sessions in the same directory share
  `TASK.md`, uncommitted changes, the index, and build output, so only one TF
  works in a directory at a time. A new TF that finds `TASK.md` or uncommitted
  changes does not accept a TASK; it reports to its Project HQ and the owner
  instead. Before sending a TASK, the Project HQ checks with `list_sessions`
  that no other TF of the repository is working. TFs in separate directories
  (another repository, a second clone, or a worktree) may run at the same time,
  but still take turns with what the Mac has only once: the installed app and
  its preferences, simulators and devices, signing, and releases.
- **Lifetime:** quitting the Claude app archived the local sessions connected
  through Remote Control, and restarting the app did not bring them back.
  Computer-use app access is granted per session, so a long-lived TF asks for
  it once.
- **Archiving:** the Web and the Mac app can disagree about a local session's
  state (see `docs/AGENT_PARITY.md` in `kni927/dotfiles`). The owner archives
  local sessions from the Mac app's sidebar. HQs do not archive local sessions
  from the cloud, and a TF cannot archive itself while its own turn and Remote
  Control connection are live.
- **Subagents:** a TF hands heavy work (builds, test runs, investigations,
  computer-use checks) to subagents (the Agent tool), so what they read does
  not fill the TF's context. Their permission dialogs and computer-use access
  prompts appear in the TF's window as usual. Use worktree isolation only when
  the work must not touch the main directory.
- **Wrapping up a TF:** a TF cannot start its own successor. At the
  thresholds in Context usage, when its Project HQ asks, or when the owner
  says "wrap up", it finishes at a natural break: it confirms that nothing is
  uncommitted, reports what is done and what remains to its Project HQ,
  renames itself `✅ <name>` (for example `✅ cooViewer TF solid RAR4
  converter`), shows the ready-to-archive block, and waits. When work
  remains that needs the Mac, it also offers a new TF with `spawn_task`, so
  the owner starts it with one click; work that needs no Mac GUI or device
  continues in a cloud session the Project HQ starts.
- **Screen operations:** before computer use, a TF asks the owner in chat to
  stand by and waits for the reply. An approval card that nobody answers times
  out.
- **Pushing:** several sessions may push to `main` at the same time. Follow the
  fetch-and-merge rule in `AGENTS.md` (Git Workflow) before every push.
