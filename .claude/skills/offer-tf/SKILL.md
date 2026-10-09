---
name: offer-tf
description: Offer the owner a new local TF on the Mac as a one-click spawn_task card, with a prompt that actually starts the TF. Use when an HQ needs a TF for its repository, or when a TF wraps up and work that needs the Mac remains.
---

# Offer a TF with a card

`docs/sessions.md` ("Starting a TF from a card") is the rule; this is the
procedure.

1. **Get the tool.** `mcp__ccd_session__spawn_task` may be deferred; load it
   with ToolSearch. If it is not available, tell the owner to open a local
   session in the repository and type `/tf <what>`, and stop here.
2. **Check the repository.** The card opens in this session's repository.
   For a TF in another repository, ask that repository's HQ to offer it.
3. **Check that the main clone is free.** With `list_sessions`, look for
   another TF of this repository that is still working. If there is one,
   the owner must pick Start with worktree; say so in step 5.
4. **Queue the card** with `spawn_task`. `<what>` starts with the TF's number,
   `#NN` (TF numbers in `docs/sessions.md`), for example `#02 blender-pilot`:
   - `title`: `Start <repo> TF <what>`;
   - `tldr`: one or two sentences in the owner's language on what the TF
     will do;
   - `prompt`, starting with exactly this line, then any context the TF
     needs:

     ```
     Start this session as a TF: read `~/.claude/skills/tf/SKILL.md` and follow it exactly as if I had typed `/tf <what>`, so `$ARGUMENTS` is `<what>`.
     ```

   Do not start the prompt with `/tf`: a slash command in a card's prompt
   does not run, and `/tf` cannot be invoked by the model.
5. **Tell the owner** the card's title and which button to press: Start
   locally, or Start with worktree when step 3 found a working TF. No pull is
   needed first; the TF brings itself up to date when a TASK arrives. When
   the TF announces itself, send the TASK to the `from-session` of that
   message.
6. If the card becomes unnecessary, withdraw it with `dismiss_task`.
