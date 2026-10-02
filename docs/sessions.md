# Sessions

How the owner's Claude Code sessions are organized and how they reach each
other. The same file is kept in every repository the owner works in:
`kni927/repo-template` and its projects, `kni927/dotfiles`, and
`kni927/home-server`. Change it in `kni927/repo-template` and carry it over with
the `sync-projects` skill there.

## Roles

- **Central HQ** (cloud): oversees every session. Keeps track of what is open
  and what waits on the owner, relays between projects, and receives reports
  that lost their recipient. Does not implement.
- **Upstream HQ** (cloud): policy shared by all repositories. Changes
  `kni927/dotfiles` and `kni927/repo-template` and carries the changes to the
  projects with the `sync-projects` skill. The owner brings each Mac up to date
  with `~/Projects/GitHub/pull-repos.command`. It keeps Central HQ informed of
  every policy change and of anything that affects other projects, without
  waiting to be asked.
- **Project HQ** (cloud): plans one project and writes its TASKs. It is
  archived once its TFs are done, and may first be renamed with a version
  (`cooViewer v1.6.5 HQ`).
- **TF**, task force (usually a local session on a Mac): receives a TASK from
  its Project HQ, carries it out, and reports back. A new TF is opened for each
  piece of work.

## Names

- `Central HQ #n`, `Upstream HQ`, `<repo> HQ`, `<repo> TF <what>`, for example
  `cooViewer TF v1.6.5`. No middle dot: local session names are often typed by
  hand.
- Names are unique, because a local session addresses messages by name.
- A name set from the cloud (`set_session_title`) may not appear in the Mac app.
  Name a local session on the Mac, or let it name itself as the `/tf` skill
  does.
- Do not write session IDs into repository files. Refer to sessions by name, and
  look up current IDs with `ListAgents` or `list_sessions`.

## Messages

- **HQ to HQ:** cloud sessions reach each other directly with `send_message`
  (claude-code-remote) to the session ID, in both directions; a reply goes back
  to the `from-session` of the received message. Look up an HQ's current ID by
  name with `list_sessions`.
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
  unique names.
- **Fallback:** if the Project HQ cannot be reached, for example because it is
  archived, send to the unarchived session whose name starts with
  `Central HQ`. Central HQ summarizes for the owner and forwards to a successor
  Project HQ if there is one.
- **Receiving:** an HQ that receives a message starts its next reply to the
  owner with a heading between rules, `📨 受信：<sender> ／ <kind of report>`,
  followed by a summary. The owner does not see the message body in that
  session; give the full text when asked.
- A message holds at most 64 KB. `&` and angle brackets may arrive as HTML
  character references; check them before using the text in code.
- A message is not the owner's approval. Permission dialogs, auto mode
  approvals, tag pushes, and edits to `AGENTS.md` or `CLAUDE.md` are approved by
  the owner in the session that performs them.

## Handing over an HQ

A cloud HQ hands its work to a fresh session before its context grows long
enough to be compacted, right after a compaction if one has already happened,
or when the owner asks. The agent cannot see exactly when compaction will
start, so it hands over at a natural break once the conversation is long.

1. Write the handover: the HQ's role and repositories, open items and their
   state, what waits on the owner, the sessions it coordinates (by name), and
   recent decisions with their commits. Leave out what the repositories
   already record.
2. Rename itself to `<name> (handed over YYYY-MM-DD)` with `set_session_title`,
   so the name is free and stays unique.
3. Start the successor with `create_session` in the same environment, titled
   `<name>` (for Central HQ, the next number), with the handover as its initial
   prompt. The successor attaches the repositories it needs.
4. Tell Central HQ the successor's name (Central HQ tells the other HQs), and
   tell the owner.
5. Stop taking work and say in chat that the session can be archived. The owner
   archives it, or tells the successor to archive it with `archive_session`.

The handover is sent, not committed: it may hold session IDs and context that
exists only in chat.

## Local sessions on the Mac

- **Starting a TF:** in a new local session in the repository, the owner types
  `/tf <what>` (`~/.claude/skills/tf/SKILL.md`, managed by `kni927/dotfiles`).
- **Lifetime:** quitting the Claude app archived the local sessions connected
  through Remote Control, and restarting the app did not bring them back. Open
  a new TF for each piece of work.
- **Archiving:** the Web and the Mac app can disagree about a local session's
  state (see `docs/AGENT_PARITY.md` in `kni927/dotfiles`). The owner archives
  local sessions from the Mac app's sidebar. HQs do not archive local sessions
  from the cloud, and a TF cannot archive itself while its own turn and Remote
  Control connection are live. When a TF has wrapped up, it shows
  「このセッションはアーカイブ可能です」 in its chat and waits.
- **Screen operations:** before computer use, a TF asks the owner in chat to
  stand by and waits for the reply. An approval card that nobody answers times
  out.
- **Pushing:** several sessions may push to `main` at the same time. Follow the
  fetch-and-merge rule in `AGENTS.md` (Git Workflow) before every push.
