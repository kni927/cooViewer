---
name: mac-relay
description: Send a later message from a cloud session to a local session on the Mac mini through the Google Drive inbox that handoff-relay delivers, as docs/sessions.md "Messages" (Mac mini relay) describes. Use when a cloud HQ or TF must reach Mac mini HQ, Mac mini Gate, or a Mac mini TF after it has started, since cloud-to-local send_message is refused.
---

# Message a Mac mini session through the relay

1. Write one Markdown file to Google Drive `AI/Handoff/Inbox/` with the
   connector's `create_file` (`contentMimeType` `text/markdown`,
   `disableConversionToGoogleType` true), named
   `YYYYMMDD-HHMMSS-<topic>.md`.
2. The file holds `To: <the session's name>`, then `From: <your name> (<your
   session ID>)`, a `---` line, then the message.
   - `To:` may list alternatives separated by ` | `, and a trailing `*`
     matches a name prefix. The Gate is `🖥️ Mac mini Gate | macminihq-*`:
     `ListAgents` names a server session by the server's `--name` or a
     folder-based name, and `set_session_title` from the cloud changes only
     the claude.ai title, never the name on the Mac.
   - A TASK for a TF names its HQ on the `From:` line; the TF accepts it as
     from its HQ (`/tf`, step 4).
3. `handoff-relay` on the Mac mini (dotfiles `docs/AUTOMATIONS.md`) delivers
   it within about five minutes with a local `SendMessage` and moves the file
   to `done/`; a file it cannot deliver goes to `failed/` and the owner gets
   an alert. The receiver replies to your session directly.
4. After ten minutes, check the file's parent with `get_file_metadata` (a
   title search lags behind a move). Still in the inbox, or in `failed/`:
   write an English message for the owner to paste. A MacBook session is not
   reached this way; give the owner that message from the start.
5. Say where it went in one English line (`Sent to: 🖥️ Mac mini HQ (relay)`).
