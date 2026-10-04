#!/bin/bash
# On-device check helpers for a local build at build/cooViewer.app.
#
# Run from the repository root, exactly as `tools/device_check.sh <command>`,
# on its own (no pipes, redirects, `&&` or command substitution). That form
# is listed in .claude/settings.json under sandbox.excludedCommands, because
# `defaults`, `lsregister` and the quit Apple event do not work inside the
# sandbox. See CLAUDE.md, "On-Device Verification Procedure".
#
#   status         list running cooViewer processes and which copy each is
#   prefs-backup   save the jp.coo.cooViewer preferences outside the repo
#   launch         open build/cooViewer.app by path and wait for its pid
#   quit           send the quit Apple event to the build copy only
#   prefs-restore  put the saved preferences back and verify them
#   unregister     lsregister -u the build and the intermediate products
#   diag [secs]    CPU/memory/state of the build; with secs, also `sample` it
#
# The real (Homebrew) copy in /Applications shares the bundle id and the
# preferences domain; nothing here launches, quits or unregisters it.
set -euo pipefail

DOMAIN="jp.coo.cooViewer"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$REPO_ROOT/build/cooViewer.app"
EXE="$APP/Contents/MacOS/cooViewer"
TMP_ROOT="$(getconf DARWIN_USER_TEMP_DIR)"
STATE_DIR="${TMP_ROOT}cooViewer-device-check"
BACKUP="$STATE_DIR/prefs-backup.plist"
ABSENT_MARK="$STATE_DIR/prefs-absent"
BUILD_TMP="${TMP_ROOT}cooViewer-build"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

die() { echo "device_check: $*" >&2; exit 1; }

# pid and executable path of every process whose executable is named cooViewer
# (paths may contain spaces, so split only at the first run of blanks)
list_processes() {
    ps -axo pid=,comm= | sed -E 's/^ *([0-9]+) +/\1 /' | grep -E '/cooViewer$' || true
}

build_pids() {
    local pid path
    while read -r pid path; do
        [ "$path" = "$EXE" ] && echo "$pid"
    done < <(list_processes)
    return 0
}

wait_for_build_exit() {
    local i
    for i in $(seq 1 20); do
        [ -z "$(build_pids)" ] && return 0
        sleep 0.5
    done
    return 1
}

cmd_status() {
    local pid path found=0
    while read -r pid path; do
        [ -n "$pid" ] || continue
        found=1
        if [ "$path" = "$EXE" ]; then
            echo "$pid build  $path"
        else
            echo "$pid other  $path"
        fi
    done < <(list_processes)
    [ "$found" -eq 1 ] || echo "no cooViewer process running"
    if [ -f "$BACKUP" ] || [ -f "$ABSENT_MARK" ]; then
        echo "preferences backup: present ($STATE_DIR)"
    else
        echo "preferences backup: none"
    fi
}

cmd_prefs_backup() {
    mkdir -p "$STATE_DIR"
    if [ -f "$BACKUP" ] || [ -f "$ABSENT_MARK" ]; then
        die "a backup already exists in $STATE_DIR; run prefs-restore first, or remove it by hand if it is stale"
    fi
    [ -z "$(build_pids)" ] || die "the build copy is running; back up before launching it"
    if defaults export "$DOMAIN" "$BACKUP" 2>/dev/null; then
        echo "saved $DOMAIN to $BACKUP ($(plutil -convert xml1 -o - "$BACKUP" | grep -c '<key>') keys)"
    else
        rm -f "$BACKUP"
        touch "$ABSENT_MARK"
        echo "$DOMAIN has no preferences yet; restore will delete the domain"
    fi
}

cmd_launch() {
    [ -d "$APP" ] || die "no build at $APP"
    [ -z "$(build_pids)" ] || die "the build copy is already running (pid $(build_pids))"
    if [ ! -f "$BACKUP" ] && [ ! -f "$ABSENT_MARK" ]; then
        echo "warning: no preferences backup; run prefs-backup first if the check may change preferences" >&2
    fi
    open "$APP"
    local i pid=""
    for i in $(seq 1 20); do
        pid="$(build_pids)"
        [ -n "$pid" ] && break
        sleep 0.5
    done
    [ -n "$pid" ] || die "the build did not start (LaunchServices may have opened another copy; run status)"
    echo "build running: pid $pid ($EXE)"
    echo "confirm the frontmost app is this pid before each key or click"
}

cmd_quit() {
    local pid
    pid="$(build_pids)"
    [ -n "$pid" ] || { echo "the build copy is not running"; return 0; }
    # NSRunningApplication -terminate sends the quit Apple event to this pid
    # only, so the real copy, which shares the bundle id, is not touched.
    osascript -l JavaScript -e "ObjC.import('AppKit'); \$.NSRunningApplication.runningApplicationWithProcessIdentifier($pid).terminate" >/dev/null
    if wait_for_build_exit; then
        echo "build (pid $pid) quit"
    else
        die "build (pid $pid) is still running after the quit event (a modal or sheet may be holding it)"
    fi
}

cmd_prefs_restore() {
    [ -f "$BACKUP" ] || [ -f "$ABSENT_MARK" ] || die "no backup in $STATE_DIR"
    [ -z "$(build_pids)" ] || die "quit the build copy first (tools/device_check.sh quit)"
    if [ -n "$(list_processes)" ]; then
        echo "warning: another cooViewer copy is running and shares these preferences; it may write them again" >&2
    fi
    # The app's last writes reach cfprefsd shortly after it exits.
    sleep 2
    defaults delete "$DOMAIN" 2>/dev/null || true
    if [ -f "$ABSENT_MARK" ]; then
        if defaults export "$DOMAIN" - >/dev/null 2>&1; then
            die "the domain still exists after delete"
        fi
        rm -f "$ABSENT_MARK"
        echo "restored: $DOMAIN removed (it did not exist before)"
        return 0
    fi
    defaults import "$DOMAIN" "$BACKUP"
    local now="$STATE_DIR/prefs-now.plist"
    defaults export "$DOMAIN" "$now"
    if cmp -s <(plutil -convert xml1 -o - "$BACKUP") <(plutil -convert xml1 -o - "$now"); then
        rm -f "$now"
        mv "$BACKUP" "$STATE_DIR/prefs-backup.$(date +%Y%m%d-%H%M%S).restored.plist"
        echo "restored and verified: $DOMAIN matches the backup"
    else
        diff <(plutil -convert xml1 -o - "$BACKUP") <(plutil -convert xml1 -o - "$now") || true
        die "restored preferences differ from the backup (kept both in $STATE_DIR)"
    fi
}

cmd_unregister() {
    [ -z "$(build_pids)" ] || die "quit the build copy first (tools/device_check.sh quit)"
    local p
    for p in "$APP" "$BUILD_TMP/sym/Deployment/cooViewer.app"; do
        [ -d "$p" ] || continue
        # -10814 (kLSApplicationNotFoundErr) only means it was not registered
        local err rc=0
        err="$("$LSREGISTER" -u "$p" 2>&1)" || rc=$?
        if [ "$rc" -eq 0 ] && [ -z "$err" ]; then
            echo "unregistered $p"
        elif printf '%s' "$err" | grep -q -- '-10814'; then
            echo "not registered: $p"
        else
            printf '%s\n' "$err" >&2
            [ "$rc" -eq 0 ] && echo "unregistered $p (with the warning above)"
        fi
    done
    local left
    left="$("$LSREGISTER" -dump | grep -E "path: +($APP|$BUILD_TMP)" || true)"
    if [ -n "$left" ]; then
        echo "still registered:" >&2
        echo "$left" >&2
        exit 1
    fi
    echo "no build or intermediate product left registered"
}

# CPU, memory and state of the build, and optionally a call-graph sample
# (ps and sample are refused inside the sandbox; this needs no bypass).
cmd_diag() {
    local pid
    pid="$(build_pids)"
    [ -n "$pid" ] || { echo "the build copy is not running"; return 0; }
    ps -o pid=,%cpu=,%mem=,rss=,etime=,state= -p "$pid" |
        awk '{ printf "pid %s  cpu %s%%  mem %s%%  rss %d MB  elapsed %s  state %s\n", $1, $2, $3, $4/1024, $5, $6 }'
    local secs="${1:-}"
    [ -n "$secs" ] || return 0
    case "$secs" in *[!0-9]*) die "diag: seconds must be a number" ;; esac
    mkdir -p "$STATE_DIR"
    local out="$STATE_DIR/sample-$(date +%Y%m%d-%H%M%S).txt"
    sample "$pid" "$secs" -file "$out" >/dev/null 2>&1 || die "sample failed"
    echo "sample written to $out"
    # the main thread's heaviest frames, enough to see what blocks the UI
    awk '/^Call graph:/{f=1} f && /Thread_.*main-thread/{m=1} m{print; if (++n >= 40) exit}' "$out"
}

case "${1:-}" in
    status)        cmd_status ;;
    prefs-backup)  cmd_prefs_backup ;;
    launch)        cmd_launch ;;
    quit)          cmd_quit ;;
    prefs-restore) cmd_prefs_restore ;;
    unregister)    cmd_unregister ;;
    diag)          cmd_diag "${2:-}" ;;
    *) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
