#!/bin/bash
# Setup script of the Trusted cloud environment, shared by every repository
# (kni927/repo-template, scripts/copy-shared.sh). The environment's Setup
# script field holds one line that runs the first copy it finds:
#   for f in /home/user/*/.claude/cloud-setup.sh; do [ -f "$f" ] && exec bash "$f"; done; true  # rev 3
# (no repository attached: nothing to run, and the session still starts).
# The environment caches its result for about seven days, so it also
# registers a SessionStart hook that runs this file again with --refresh at
# every session start: a change synced to the repositories applies there
# without touching the field. Only a plugin change needs the rev raised,
# because plugins load before the hook runs.
# The repositories are already cloned when it runs, but GitHub is not yet
# reachable. kni927/dotfiles docs/CLOUD_ENVIRONMENTS.md explains each part.
version=2026-11-01.4
refresh=0; [ "${1:-}" = --refresh ] && refresh=1

if [ $refresh = 0 ]; then
    claude plugin marketplace add kni927/fast-jev-compaction
    claude plugin install fast-jev-compaction@fast-jev-compaction
fi

# Merge on a diverged pull, as the repositories' rules require.
git config --global pull.rebase false
# Lint for the repositories' bash scripts; not needed to start a session.
# From PyPI (seconds; apt-get update stalled for minutes in a session).
command -v shellcheck >/dev/null ||
    timeout 120 python3 -m pip install -q --user shellcheck-py >/dev/null 2>&1 || true

mkdir -p ~/.claude/hooks
cat > ~/.claude/hooks/context-alert.py <<'PY'
# UserPromptSubmit hook for Trusted cloud sessions (setup script). When a
# step of docs/sessions.md "Context usage" first applies (70% before any
# compaction, 75% after one, each later compaction), it adds one line with
# the usage, the compaction count, and that step; later prompts in the same
# step stay silent (owner, 2026-10-31: the session rail shows usage).
import json, os, sys

WINDOW = int(os.environ.get("CONTEXT_WINDOW_TOKENS", "1000000"))
try:
    path = json.load(sys.stdin).get("transcript_path") or ""
    compactions, used = 0, 0
    with open(path, "rb") as f:
        for raw in f:
            if b'"compact_boundary"' in raw:
                try:
                    if json.loads(raw).get("subtype") == "compact_boundary":
                        compactions, used = compactions + 1, 0
                        continue
                except ValueError:
                    pass
            if b'"usage"' not in raw or b'"assistant"' not in raw:
                continue
            try:
                e = json.loads(raw)
            except ValueError:
                continue
            if e.get("type") != "assistant" or e.get("isSidechain"):
                continue
            u = (e.get("message") or {}).get("usage") or {}
            used = sum(u.get(k) or 0 for k in
                       ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens")) or used
except Exception:
    sys.exit(0)
pct = used * 100 // WINDOW
if compactions == 0 and pct >= 70:
    step = ("no compaction yet: a cloud HQ ends its reply with the one-line /compact "
            "request and does not hand over")
elif compactions == 1 and pct >= 75:
    step = "compacted once: a cloud HQ hands over at the next natural break"
elif compactions >= 2:
    step = f"compacted {compactions} times: a cloud HQ hands over at the next natural break"
else:
    sys.exit(0)
stage, mark = str(min(compactions, 99)), path + ".context-alert"
try:
    with open(mark) as f:
        if f.read().strip() == stage:
            sys.exit(0)
except OSError:
    pass
try:
    with open(mark, "w") as f:
        f.write(stage)
except OSError:
    pass
print(f'Context usage: {pct}% ({used:,} / {WINDOW:,} tokens); {step} '
      '(docs/sessions.md "Context usage").')
PY

# Stop hook: notation-check, a verbatim copy of kni927/dotfiles
# dot_local/bin/claude-hooks/executable_notation-check (change it there and
# copy it here), so sessions without a dotfiles clone get it too.
cat > ~/.claude/hooks/notation-check <<'PY'
#!/usr/bin/env python3
"""Stop hook: catch notation drift in the reply before it reaches the owner.

The Notation rules (custom instructions, AGENTS.md "Language and notation")
say dates are YYYY-MM-DD or M/D and Japanese text has no space next to Latin
letters, digits or inline code. Long sessions drift back to their own earlier
style anyway (Central HQ wrote "10-23" after reloading the rules, 2026-11-01),
and more rule text does not stop that. This hook reads the reply's last text
and, on a year-less MM-DD date or such a space, blocks the stop once with the
matches. The model then writes only the corrected sentences, not the whole
reply again and with no line saying it fixed them (owner, 2026-11-01: the
reply was shown twice, then a "notation fixed" line). A Stop hook runs after
the reply is shown, so the original stays on screen; only the repeat can be
kept short.

On a Mac, each block appends one JSON line to
~/Library/Logs/claude-notation-check.log, so how often the hook catches a
reply can be counted. Cloud sessions have no such folder; their blocks stay
in the transcripts as "Stop hook feedback" messages. Quoted text is
left alone: link text, URLs, and 「」『』 quotations, which keep their source's
spelling (an article title "AI の…" was a false match).

It blocks at most once per reply (a marker beside the transcript keyed by the
owner's last message), and any read error allows the stop.
"""

import json
import os
import re
import sys
import time

JP = r"[\u3040-\u30ff\u3400-\u9fff]"
LAT = r"[A-Za-z0-9`*]"
SPACE = re.compile(rf"{JP} +{LAT}|{LAT} +{JP}")
MMDD = re.compile(r"(?<![\d.:/\-])(?:0[1-9]|1[0-2])-(?:0[1-9]|[12]\d|3[01])(?![\d:/\-])")
FENCE = re.compile(r"```.*?```", re.DOTALL)
INLINE = re.compile(r"`[^`\n]*`")
QUOTED = re.compile(r"\[[^\]\n]*\]\([^)\s]*\)|https?://\S+|「[^」\n]*」|『[^』\n]*』")
NAME = "notation-check"


def allow():
    sys.exit(0)


def is_owner_message(entry):
    if entry.get("type") != "user" or entry.get("isMeta"):
        return False
    content = entry.get("message", {}).get("content")
    if isinstance(content, str):
        return True
    if isinstance(content, list):
        return any(b.get("type") == "text" for b in content if isinstance(b, dict))
    return False


def main():
    try:
        data = json.load(sys.stdin)
        path = data["transcript_path"]
        with open(path, encoding="utf-8") as f:
            entries = [json.loads(line) for line in f if line.strip()]
    except Exception:
        allow()

    owner = [i for i, e in enumerate(entries) if is_owner_message(e)]
    turn = entries[owner[-1]].get("uuid", str(owner[-1])) if owner else "start"
    mark = f"{path}.{NAME}"
    try:
        with open(mark, encoding="utf-8") as f:
            if f.read().strip() == turn:
                allow()
    except OSError:
        pass

    text = ""
    for e in entries[(owner[-1] + 1) if owner else 0:]:
        if e.get("type") != "assistant":
            continue
        for b in e.get("message", {}).get("content") or []:
            if isinstance(b, dict) and b.get("type") == "text" and b.get("text", "").strip():
                text = b["text"]
    if not text:
        allow()

    body = QUOTED.sub("\u3013", FENCE.sub(" ", text))
    plain = INLINE.sub("`x`", body)
    found = []
    for m in MMDD.finditer(INLINE.sub(" ", body)):
        found.append(f'year-less date "{m.group(0)}" (write YYYY-MM-DD, or M/D)')
    for m in SPACE.finditer(plain):
        found.append(f'space between Japanese and Latin text: "{m.group(0)}"')
    if not found:
        allow()

    try:
        with open(mark, "w", encoding="utf-8") as f:
            f.write(turn)
    except OSError:
        allow()
    logs = os.path.expanduser("~/Library/Logs")
    if os.path.isdir(logs):
        try:
            with open(os.path.join(logs, "claude-notation-check.log"), "a", encoding="utf-8") as f:
                f.write(json.dumps({
                    "time": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                    "cwd": data.get("cwd", ""),
                    "session": data.get("session_id", ""),
                    "dates": sum(1 for x in found if x.startswith("year-less")),
                    "spaces": sum(1 for x in found if x.startswith("space")),
                }) + "\n")
        except OSError:
            pass
    print(json.dumps({
        "decision": "block",
        "reason": "Notation (AGENTS.md, Language and notation): "
        + "; ".join(found[:6])
        + (f"; and {len(found) - 6} more" if len(found) > 6 else "")
        + ". Do not repeat the reply and do not say that you fixed anything: "
        "write only the corrected sentence or sentences, each once, and nothing else.",
    }, ensure_ascii=False))
    sys.exit(0)


if __name__ == "__main__":
    main()
PY
chmod 755 ~/.claude/hooks/notation-check

python3 - <<'PY'
import json, os

p = os.path.expanduser("~/.claude/settings.json")
d = json.load(open(p)) if os.path.exists(p) else {}
d.setdefault("pluginConfigs", {})["fast-jev-compaction@fast-jev-compaction"] = {"options": {"compactAtPercent": 78}}
d["attribution"] = {"commit": "", "pr": "", "sessionUrl": True}
allow = d.setdefault("permissions", {}).setdefault("allow", [])
# A connector appears under its readable name or under its UUID (a session
# that starts before the names resolve gets the UUID), so allow both.
connectors = [
    (["mcp__Google_Drive__", "mcp__ca13bbc7-3ace-4182-a80a-b7d9af123922__"],
     ["search_files", "read_file_content", "get_file_metadata", "download_file_content",
      "list_recent_files", "create_file", "copy_file", "update_file"]),
    (["mcp__Google_Sheets__", "mcp__2d95d009-6258-4f5b-abda-f43840ca0f1e__"],
     ["get_spreadsheet", "get_values", "update_values", "append_values",
      "insert_dimension", "update_formulas", "update_spreadsheet"]),
    (["mcp__Google_Docs__", "mcp__103325ab-b59c-4104-8fa2-2268c2d45ec3__"],
     ["read_doc", "update_doc"]),
    (["mcp__Dropbox__", "mcp__66031e7b-6d10-46d4-8e1b-9e116400fb26__"],
     ["list_folder", "search", "fetch", "get_file_metadata", "create_file", "create_folder"]),
]
for t in ["mcp__claude-code-remote__add_repo", "mcp__claude-code-remote__archive_session",
          "mcp__claude-artifacts__db_write"] + [
    pre + tool for prefixes, tools in connectors for pre in prefixes for tool in tools
]:
    if t not in allow:
        allow.append(t)
# Connectors (kni927/dotfiles DECISIONS 2026-10-23). With a kni927/dotfiles
# clone, its connector-guard hook and lists decide Gmail send and the AI
# calendar, as on the Macs. Without one, send is denied and a calendar delete
# asks. Reply and forward are denied either way.
src = "/home/user/dotfiles"
guard_src = f"{src}/dot_local/bin/claude-hooks/executable_connector-guard"
guarded = os.path.isfile(guard_src)
guard = os.path.expanduser("~/.claude/hooks/connector-guard")
if guarded:
    import shutil
    shutil.copyfile(guard_src, guard)
    os.chmod(guard, 0o755)
    conf = os.path.expanduser("~/.config/claude-hooks")
    os.makedirs(conf, exist_ok=True)
    for name in ("mail-recipients", "ai-calendars"):
        shutil.copyfile(f"{src}/dot_config/claude-hooks/{name}", f"{conf}/{name}")
perms = d["permissions"]
gmail = ["mcp__Gmail__", "mcp__2e96074d-f9a9-46b6-ba7f-03f3f1fd2fe5__"]
calendar = ["mcp__Google_Calendar__", "mcp__3a55ff32-6a11-4191-bb2c-b9c58d7989e9__"]
for key, tools, wanted in [
    ("deny", [g + t for g in gmail for t in ("reply", "forward")], True),
    ("deny", [g + "send_message" for g in gmail], not guarded),
    ("ask", [c + "delete_event" for c in calendar], not guarded),
    # Exa's agent_run is metered (up to $5 a run by default); search and fetch stay free of a dialog.
    ("ask", ["mcp__Exa__agent_run"], True),
]:
    rules = perms.setdefault(key, [])
    for tool in tools:
        if wanted and tool not in rules:
            rules.append(tool)
        if not wanted and tool in rules:
            rules.remove(tool)
pre = d.setdefault("hooks", {}).setdefault("PreToolUse", [])
pre[:] = [g for g in pre if guard not in json.dumps(g)]
if guarded:
    pre.append({"matcher": "mcp__.*__(send_message|reply|forward|create_event|update_event|delete_event)",
                "hooks": [{"type": "command", "command": guard, "timeout": 10}]})
ask_src = f"{src}/dot_local/bin/claude-hooks/executable_owner-ask-check"
ask_check = os.path.expanduser("~/.claude/hooks/owner-ask-check")
stop = d.setdefault("hooks", {}).setdefault("Stop", [])
stop[:] = [g for g in stop if ask_check not in json.dumps(g)]
if os.path.isfile(ask_src):
    import shutil
    shutil.copyfile(ask_src, ask_check)
    os.chmod(ask_check, 0o755)
    stop.append({"hooks": [{"type": "command", "command": ask_check, "timeout": 10}]})
notation = os.path.expanduser("~/.claude/hooks/notation-check")
stop[:] = [g for g in stop if notation not in json.dumps(g)]
stop.append({"hooks": [{"type": "command", "command": notation, "timeout": 10}]})
refresh = ('for f in /home/user/*/.claude/cloud-setup.sh; do [ -f "$f" ] && '
           'exec bash "$f" --refresh >/dev/null 2>&1; done; true')
for event, hook in [
    ("UserPromptSubmit", {"type": "command", "command": "python3 -I ~/.claude/hooks/context-alert.py", "timeout": 10}),
    ("SessionStart", {"type": "command", "command": refresh, "timeout": 120}),
]:
    groups = d.setdefault("hooks", {}).setdefault(event, [])
    if not any(hook in g.get("hooks", []) for g in groups):
        groups.append({"hooks": [hook]})
os.makedirs(os.path.dirname(p), exist_ok=True)
json.dump(d, open(p, "w"), indent=2)
PY

# Which copy ran last, for checking a session.
echo "$version $(date -u +%FT%TZ) refresh=$refresh" > ~/.claude/cloud-setup.version
