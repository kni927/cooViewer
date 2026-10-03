# Sessions

How the owner's Claude Code sessions are organized and how they reach each
other. The same file is kept in every repository the owner works in:
`kni927/repo-template` and its projects, `kni927/dotfiles`, and
`kni927/home-server`. Change it in `kni927/repo-template` and carry it over with
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
  created with `create_session` and the project's repository as `source_url`
  (for example `https://github.com/kni927/cooViewer`), which also files it
  under that repository in the claude.ai session list. It is archived once its
  TFs are done, and may first be renamed with a version (`cooViewer v1.6.5 HQ`).
- **TF**, task force (usually a local session on a Mac): receives a TASK from
  its Project HQ, carries it out, and reports back. A new TF is opened for each
  piece of work.

## Names

- `Central HQ`, `Upstream HQ`, `<repo> HQ`, `<repo> TF <what>`, for example
  `cooViewer TF v1.6.5`. No middle dot: local session names are often typed by
  hand. The current session of a role carries the plain name; a session that
  has handed over becomes `<name> (handover YYYY-MM-DD)`.
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
  the TASK text. The TF accepts TASKs only from its own Project HQ. It shows
  that the TASK arrived and its key points, not the full text, since `TASK.md`
  is archived later. It then runs `git pull` on `main`, saves the text as
  `TASK.md` at the repository root, and carries it out.
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
  owner with this heading, then a summary. Each `---` stands alone on its line
  with a blank line before and after it (directly under text, Markdown turns
  that text into a heading); do not use `--` or box-drawing characters. The
  owner does not see the message body in that session; give the full text
  when asked.

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

## Context usage

A long conversation is compacted automatically, which loses detail. Cloud
sessions compact at 80% of the maximum context
(`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`), local sessions at 97%. A cloud session
reads its own usage with `get_session` without an ID (`context_usage`); a local
session in the Mac app reads it with `get_usage` for session `self`.

- **Proposing:** every session, HQ or TF, checks its usage at natural breaks.
  Once it passes two thirds of the maximum, it proposes to the owner to hand
  over (an HQ) or to wrap up (a TF), before starting a step that would not fit.
  It acts on the owner's word, "handover" or "wrap up". Any session may also
  propose this for another one whose usage it can see.
- **Warning:** a Project HQ that sees one of its TFs past 80% warns the owner.
  Central HQ reminds an HQ that has passed two thirds without proposing.
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

## Handing over an HQ

A cloud HQ hands its work to a fresh session when the owner says "handover",
usually after the HQ proposed it (see Context usage), and right after a
compaction if one has already happened.

1. Write the handover: the HQ's role and repositories, open items and their
   state, what waits on the owner, the sessions it coordinates (by name), and
   recent decisions with their commits. Leave out what the repositories
   already record.
2. Rename itself to `<name> (handover YYYY-MM-DD)` with `set_session_title`,
   using the owner's local date, so the plain name is free and stays unique.
3. Start the successor with `create_session` in the same environment, titled
   `<name>`, with the handover as its initial prompt. A Project HQ's successor
   gets the project's repository as `source_url`, like the first one; Upstream
   HQ and Central HQ are created without one. `source_url` takes one
   repository; the successor's first reply asks the owner to approve attaching
   any others with `add_repo`, which auto mode does not allow without the
   owner's explicit approval.
4. Tell Central HQ the successor's name (Central HQ tells the other HQs), and
   tell the owner.
5. Stop taking work and show the ready-to-archive block. The owner archives
   the session, or tells the successor to archive it with `archive_session`.

The handover is sent, not committed: it may hold session IDs and context that
exists only in chat.

## Local sessions on the Mac

- **Starting a TF:** in a new local session in the repository, the owner types
  `/tf <what>` (`~/.claude/skills/tf/SKILL.md`, managed by `kni927/dotfiles`).
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
  through Remote Control, and restarting the app did not bring them back. Open
  a new TF for each piece of work.
- **Archiving:** the Web and the Mac app can disagree about a local session's
  state (see `docs/AGENT_PARITY.md` in `kni927/dotfiles`). The owner archives
  local sessions from the Mac app's sidebar. HQs do not archive local sessions
  from the cloud, and a TF cannot archive itself while its own turn and Remote
  Control connection are live.
- **Wrapping up a TF:** when its Project HQ asks, when the owner says "wrap
  up", or after the TF proposed it and the owner agreed, the TF confirms that
  nothing is uncommitted or waiting on the owner, reports to its Project HQ,
  and shows the ready-to-archive block.
- **Screen operations:** before computer use, a TF asks the owner in chat to
  stand by and waits for the reply. An approval card that nobody answers times
  out.
- **Pushing:** several sessions may push to `main` at the same time. Follow the
  fetch-and-merge rule in `AGENTS.md` (Git Workflow) before every push.
