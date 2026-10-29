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
   - `permission_mode`: `auto`. Left out, the session starts in `default`
     and asks for every write and every `add_repo` (2026-10-28);
   - `source_url`: the project's repository for a Project HQ,
     `https://github.com/kni927/dotfiles` for Upstream HQ,
     `https://github.com/kni927/HQ` for Central HQ;
   - `source_revision`: `main` (without it the session lands in Other); `source_url` takes one repository;
   - `title`: `☁️ ` and the plain name (for example `☁️ cooViewer HQ`);
   - `prompt`: the handover.
   A session started by another sits one level deeper in its lineage, and
   at the limit (`lineage` in `get_session`, 8 on 2026-10-29) it can start
   no session or Routine. If `create_session` is refused for that, save the
   handover to Google Drive `AI/Handoff/<Project>/handover-YYYY-MM-DD.md`
   and ask the owner, in one English line, to start the successor in
   claude.ai/code (`Trusted`, the `source_url` above, auto mode, the title
   above) with the prompt "Read Google Drive AI/Handoff/<Project>/
   handover-YYYY-MM-DD.md and follow it." An owner-started session is
   expected to start a fresh lineage (not yet checked).
   If auto mode refuses a call, tell the owner and keep working until it is
   resolved.
5. **Mark this session done.** Rename it with `set_session_title` to
   `☁️ ✅ <name> (handover YYYY-MM-DD)`, using the owner's local date, send
   the successor one line saying the handover is done (repositories
   pushed), and end the reply with the ready-to-archive block from
   `docs/sessions.md`. Then stop taking work. The successor does the rest
   in its first turn, so long tool output stays out of this nearly full
   context. Never archive this session yourself (`docs/sessions.md`,
   Stand-by).

## Successor's first turn

The owner decided on 2026-10-22 that a successor does these without asking,
as part of the handover. Run steps 1 to 4 in one foreground `Agent`
subagent, giving it the handover's repository list, session names and IDs,
and the predecessor's ID, so the long tool output (clone messages, Routine
prompts) stays out of the main context; it returns a short report.
Subagents can call the claude-code-remote and connector tools (checked
2026-10-29). If a step is refused, it says which and why.

1. Attach the repositories the handover lists with `add_repo`, clone each
   one at a time, and `register_repo_root` it.
2. Upstream HQ only: in Google Drive `AI/Status/Sessions/`, rename the one
   `upstream-hq.<session ID>` file (`update_file`, `title`) to carry this
   session's ID, and check that it is the only such file. claude-app-watch
   on the Macs sends its notices to the ID in that name.
3. **Routines.** With `list_triggers`, find those bound to the predecessor
   (`persistent_session_id`). Create each again bound to this session
   (same name, schedule, and prompt), then delete the old one. A Routine is
   bound to one session and cannot be rebound; one that starts a fresh
   session on each firing needs nothing. A session at the lineage limit
   cannot create Routines: then leave the old ones, and the report says so.
4. **Tell the others** with `send_message`, giving this session's name and
   ID, once: upstream (Central HQ; when Central HQ itself hands over,
   Upstream HQ) and downstream (the Project HQs or TFs it coordinates; a TF
   on the Mac cannot be reached from the cloud while that is refused, so use
   the Mac mini relay in `docs/sessions.md`).
5. When the predecessor's "handover done" line has arrived and step 3 left
   no Routine bound to it, check that its title carries `✅` and that its
   repositories have nothing unpushed; then archive it with
   `archive_session` and tell the owner in one line, with anything the
   subagent could not do. If something is missing, ask the predecessor with
   `send_message` before archiving.
