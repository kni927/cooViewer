---
name: hq-handover
description: Hand this cloud HQ (Central HQ, Upstream HQ, or a Project HQ) over to a fresh cloud session, as docs/sessions.md "Cloud sessions" (Handover) describes. Use when docs/sessions.md "Context usage" calls for it (the threshold after the first compaction, or a second compaction) or when the owner says "handover".
---

# Hand over a cloud HQ

`docs/sessions.md` ("Context usage" and "Cloud sessions") is the rule;
this is the procedure. It applies to cloud HQs only. A local TF wraps up
instead (`/tf`, step 8).
An HQ with no work left and no successor needed goes on stand-by
(`💤`, "Stand-by" in `docs/sessions.md`) rather than handing over.

1. **Find a natural break.** Finish or stop the current step so the handover
   stays short. Read the context usage with `get_session` (no session ID).
2. **Leave the repositories clean.** Bring `docs/STATUS.md` up to date in
   each repository this HQ keeps (`docs/sessions.md`, Status files): open
   items and their state, what is on hold, what waits on the owner. In every
   repository this HQ changed, commit what belongs there and push it under
   that repository's rules (fetch, merge `origin/main` if it moved, then
   push). Note anything that cannot be pushed.
3. **Write the handover** in the owner's language, as the successor's first
   prompt. Include:
   - the role, the plain name, and the repositories it works in;
   - what to do first: "Successor's first turn" below, and the repositories
     it attaches with `add_repo` without asking the owner (owner's decision,
     2026-10-22);
   - a pointer to the status files for open items and what waits on the
     owner, plus only what they cannot hold (session IDs, chat-only
     context);
   - the sessions it coordinates, by name (IDs may be included: the
     handover is sent, not committed);
   - recent decisions with their commits;
   - environment quirks met in this session.
   Leave out what the repositories already record and what the owner's
   personal preferences already say (how to address the owner, language,
   tone).
4. **Start the successor** with `create_session` (claude-code-remote):
   - no `environment_id`, so it inherits this environment;
   - `source_url`: the project's repository for a Project HQ,
     `https://github.com/kni927/dotfiles` for Upstream HQ,
     `https://github.com/kni927/HQ` for Central HQ;
   - `source_revision`: `main` (without it the session lands in Other); `source_url` takes one repository;
   - `title`: `☁️ ` and the plain name (for example `☁️ cooViewer HQ`);
   - `prompt`: the handover.
   Upstream HQ's successor then attaches its other repositories with
   `add_repo` in its first turn, without asking the owner. A cloud session
   ignores allow rules in a repository's `.claude/settings.json`; the
   `Trusted` setup script allows `add_repo` in the user settings
   (`docs/CLOUD_ENVIRONMENTS.md` in `kni927/dotfiles`), in containers
   created after 2026-10-12.
   If auto mode refuses a call, tell the owner and keep working until it is
   resolved.
5. **Move this session's Routines.** With `list_triggers`, find the Routines
   bound to this session (`persistent_session_id` is this session, or they
   resume it). Create each again with `create_trigger`: same name, schedule,
   and prompt, and `persistent_session_id` set to the successor. Then delete
   the old one with `delete_trigger`. A Routine is bound to one session and
   cannot be rebound. Central HQ has at least the morning reconnect check. Routines that start a fresh session on
   each firing need no change.
6. **Tell the others** with `send_message`, giving the successor's name and
   session ID: upstream (Central HQ; when Central HQ itself hands over,
   Upstream HQ) and downstream (the Project HQs or TFs it coordinates; a TF
   on the Mac cannot be reached from the cloud while that is refused, so give
   the owner one English line to paste into it).
   The Macs need nothing: Upstream HQ's successor points claude-app-watch
   at itself (below).
7. **Mark this session done.** Rename it with `set_session_title` to
   `☁️ ✅ <name> (handover YYYY-MM-DD)`, using the owner's local date. End the
   reply with the ready-to-archive block from `docs/sessions.md`, and send
   the successor one line saying the handover is done (Routines moved, others
   told, repositories pushed). Then stop taking work. The successor archives
   this session (owner's decision, 2026-10-22); never archive it yourself
   (`docs/sessions.md`, Stand-by).

## Successor's first turn

The owner decided on 2026-10-22 that a successor does these without asking,
as part of the handover.

1. Attach the repositories the handover lists with `add_repo`, clone each
   one at a time, and `register_repo_root` it.
2. Upstream HQ only: in Google Drive `AI/Status/Sessions/`, rename the one
   `upstream-hq.<session ID>` file (`update_file`, `title`) to carry this
   session's ID, and check that it is the only such file. claude-app-watch
   on the Macs sends its notices to the ID in that name.
3. When the predecessor's "handover done" line arrives, check that its title
   carries `✅`, that `list_triggers` shows no Routine bound to it, and that
   its repositories have nothing unpushed; then archive it with
   `archive_session` and tell the owner in one line. If something is
   missing, ask the predecessor with `send_message` before archiving.
