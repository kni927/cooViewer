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
version=2026-10-20.1
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
# UserPromptSubmit hook for Trusted cloud sessions (setup script). Past 75% of
# the context window it adds one line with the usage, so the session applies
# docs/sessions.md "Context usage" without calling get_session. Silent below.
import json, os, sys

WINDOW = int(os.environ.get("CONTEXT_WINDOW_TOKENS", "1000000"))
try:
    path = json.load(sys.stdin).get("transcript_path") or ""
    with open(path, "rb") as f:
        f.seek(0, 2)
        f.seek(max(0, f.tell() - 4_000_000))
        lines = f.read().splitlines()
except Exception:
    sys.exit(0)
for raw in reversed(lines):
    try:
        e = json.loads(raw)
    except ValueError:
        continue
    if e.get("subtype") == "compact_boundary":
        break
    if e.get("type") != "assistant" or e.get("isSidechain"):
        continue
    u = (e.get("message") or {}).get("usage") or {}
    used = sum(u.get(k) or 0 for k in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"))
    if used:
        if used * 4 >= WINDOW * 3:
            print(f"Context usage: {used * 100 // WINDOW}% ({used:,} / {WINDOW:,} tokens), "
                  'past the 75% threshold in docs/sessions.md "Context usage".')
        break
PY

python3 - <<'PY'
import json, os

p = os.path.expanduser("~/.claude/settings.json")
d = json.load(open(p)) if os.path.exists(p) else {}
d.setdefault("pluginConfigs", {})["fast-jev-compaction@fast-jev-compaction"] = {"options": {"compactAtPercent": 78}}
d["attribution"] = {"commit": "", "pr": "", "sessionUrl": True}
allow = d.setdefault("permissions", {}).setdefault("allow", [])
for t in [
    "mcp__claude-code-remote__add_repo",
    "mcp__Google_Drive__search_files", "mcp__Google_Drive__read_file_content",
    "mcp__Google_Drive__get_file_metadata", "mcp__Google_Drive__download_file_content",
    "mcp__Google_Drive__list_recent_files", "mcp__Google_Drive__create_file",
    "mcp__Google_Drive__copy_file", "mcp__Google_Drive__update_file",
    "mcp__Google_Sheets__get_spreadsheet", "mcp__Google_Sheets__get_values",
    "mcp__Google_Sheets__update_values", "mcp__Google_Sheets__append_values",
    "mcp__Google_Sheets__insert_dimension", "mcp__Google_Sheets__update_formulas",
    "mcp__Google_Sheets__update_spreadsheet",
    "mcp__Google_Docs__read_doc", "mcp__Google_Docs__update_doc",
    "mcp__Dropbox__list_folder", "mcp__Dropbox__search", "mcp__Dropbox__fetch",
    "mcp__Dropbox__get_file_metadata", "mcp__Dropbox__create_file", "mcp__Dropbox__create_folder",
]:
    if t not in allow:
        allow.append(t)
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
