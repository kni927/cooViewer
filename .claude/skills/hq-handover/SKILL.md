---
name: hq-handover
description: Hand this cloud HQ (Central HQ, Upstream HQ, or a Project HQ) over to a fresh cloud session, as docs/sessions.md "Handing over an HQ" describes. Use when docs/sessions.md "Context usage" calls for it (a fallback to the built-in summary, a second compaction, or the thresholds after the first compaction) or when the owner says "handover".
---

# Hand over a cloud HQ

`docs/sessions.md` ("Context usage" and "Handing over an HQ") is the rule;
this is the procedure. It applies to cloud HQs only. A local TF wraps up
instead (`/tf`, step 8).

1. **Find a natural break.** Finish or stop the current step so the handover
   stays short. Read the context usage with `get_session` (no session ID).
2. **Leave the repositories clean.** In every repository this HQ changed,
   commit what belongs there and push it under that repository's rules
   (fetch, merge `origin/main` if it moved, then push). Note anything that
   cannot be pushed.
3. **Write the handover** in the owner's language, as the successor's first
   prompt. Include:
   - the role, the plain name, and the repositories it works in;
   - what to do first, including each `add_repo` that needs the owner's
     approval (the successor asks for it in its first reply);
   - open items and their state, and what waits on the owner;
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
   - `source_revision`: `main` (without it the session lands in Other);
   - `title`: `☁️ ` and the plain name (for example `☁️ cooViewer HQ`);
   - `prompt`: the handover.
   If auto mode refuses the call, tell the owner and keep working until it
   is resolved.
5. **Move this session's Routines.** With `list_triggers`, find the Routines
   bound to this session (`persistent_session_id` is this session, or they
   resume it). Create each again with `create_trigger`: same name, schedule,
   and prompt, and `persistent_session_id` set to the successor. Then delete
   the old one with `delete_trigger`. Routines that start a fresh session on
   each firing need no change.
6. **Tell the others** with `send_message`, giving the successor's name and
   session ID: upstream (Central HQ; when Central HQ itself hands over,
   Upstream HQ) and downstream (the Project HQs or TFs it coordinates).
7. **Mark this session done.** Rename it with `set_session_title` to
   `☁️ ✅ <name> (handover YYYY-MM-DD)`, using the owner's local date. End the
   reply with the ready-to-archive block from `docs/sessions.md`, stop taking
   work, and forward anything that still arrives to the successor.
