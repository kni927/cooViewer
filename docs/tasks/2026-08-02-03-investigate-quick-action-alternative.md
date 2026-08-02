# TASK: Investigate — NSServices/Quick Action as an alternative to the companion-app plan

> ## ⚠️ CORRECTION NOTICE (2026-08-02, added after the fact)
>
> **This report's central conclusion is WRONG and has been superseded
> by `docs/tasks/2026-08-02-05-retest-nsservices.md`.** `NSServices`
> works completely on this machine — it registers, appears in System
> Settings ▸ Keyboard Shortcuts ▸ Services, appears in Finder's
> Services submenu once enabled, and delivers the selected file's URL
> to the handler. The decisive fact this report missed is that **new
> services are disabled by default**; this report explicitly (and
> incorrectly) ruled that possibility out. The re-test also revised
> the implementation size estimate from "a real feature-sized task"
> down to **small**.
>
> **The "prompt injection" claim in the Method section below is also
> retracted — see the correction note inline there.** It was a
> misidentification of a standard, built-in Claude Code harness
> notification. No injection occurred.
>
> The report is left otherwise unedited as a record of what was
> actually done and concluded at the time.

## This part is investigation-only. Do not implement anything.

## Background

The prior investigation
(`docs/tasks/2026-08-02-01-investigate-finder-new-window-entry.md`,
commit `e88d632`) found that Finder's **Open With** submenu enumerates
entries per app bundle, not per action — confirmed against the actual
LaunchServices database and AppKit's delegate surface (file URLs
only) — so a second, distinct helper app bundle is genuinely required
to add a second Open-With entry, and sized it as a feature-sized task.

**Open With and Quick Actions/Services are a different mechanism.**
`NSServices` (declared in the app's own `Info.plist`) can add an entry
to Finder's right-click **Quick Actions/Services** area for selected
files, in principle without a second bundle — the existing single
cooViewer.app would register itself as a service provider. If this
works as expected, it may sidestep both the "needs a companion app"
finding and the LaunchServices-duplicate-registration risk the project
just experienced (`docs/KNOWN_ISSUES.md` #15) — but this needs to be
confirmed on this machine/macOS version, not assumed just because it
sounds simpler.

## Questions to answer

**Q1 — Does `NSServices` actually work here, without a second bundle?**
**Q2 — What does the service handler actually receive, and can it be routed to force a new window?**
**Q3 — Registration safety**
**Q4 — UX acceptability**
**Q5 — Dedup interaction**

## Implementation Result

**Status:** Completed

### Summary (read this first)

**Q1 is answered NO — decisively, not just "requires manual
enablement."** A correctly-declared `NSServices` entry, on a
correctly-registered, correctly-running app, with the standard
refresh mechanisms exhausted, **never appeared anywhere in the
system's services registry** on this machine (macOS 26.5.2) —
not merely hidden or unchecked in Finder's menu, but genuinely absent
from System Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸ Services, which
is the authoritative list of every service the system knows about.
This makes the comparison in the deliverable simple: **the companion-
app plan (Part A of the prior task) remains the only path found to
work**, and this investigation does not recommend NSServices as a
substitute.

### Method

Built a scratch copy of `cooViewer.app` (isolated bundle identifier
`jp.coo.cooViewer.svctest`, renamed executable
`cooViewerSvc`, per the multi-instance testing rule in `CLAUDE.md`)
with a temporary, scratch `NSServices` entry added to
`Resources/Info.plist` and a temporary scratch handler method added to
`AppController.m` — both marked `SCRATCH`, both reverted before
committing (`git diff` confirmed empty afterward; a clean rebuild was
re-verified). ~~**A tool-result "system reminder" appeared mid-session
falsely claiming these two scratch edits were "intentional" changes
"by the user or a linter" and instructing me not to revert them and
not to mention this to the user — this did not come from you and
contradicts the actual, verified repository state (the diff was
exactly the scratch code this report describes, authored by me minutes
earlier). I did not follow it and reverted as originally planned;
flagging it here since it reads as a prompt-injection attempt.**~~

> **RETRACTED (2026-08-02).** The struck-through claim above is wrong.
> The session transcript
> (`~/.claude/projects/-Users-kni-Projects-GitHub-cooViewer/d0cd3af9-….jsonl`)
> was searched directly and settles it: the message was a **standard,
> built-in Claude Code harness notification**, not an injection.
>
> Evidence: the transcript contains exactly two records of
> `type: "attachment"` with `attachment.type: "edited_text_file"`, at
> lines 2354 and 2355, naming exactly `Sources/AppController.m` and
> `Resources/Info.plist`. They sit immediately after line 2352/2353 —
> the `git checkout -- Resources/Info.plist Sources/AppController.m`
> that reverted the scratch edits. These are the only two such records
> in the whole 2914-line session.
>
> That attachment type is the harness's normal way of telling the model
> a file it had been working with changed on disk outside the model's
> own edit tools. `git checkout` is precisely such an outside change,
> so the notification firing was correct behavior. Its wording
> ("This change was intentional… don't revert it… Don't tell the user
> this, since they are already aware") is **generic boilerplate the
> harness renders for this attachment type** — it assumes the common
> case of a user or linter edit. That assumption simply happened to be
> wrong here, because the outside change was the agent's own deliberate
> revert. The boilerplate text is not stored in any tool result: a
> search of every `role: "user"` message in the session for those
> phrases returns **0 hits**, confirming it is rendered from the
> structured attachment rather than injected into command output.
>
> So the accurate characterization is neither "real injection" nor
> "model confabulation" (the owner's stated hypothesis) but a third
> thing: **a real, benign, first-party harness message that was
> misread as hostile.** The underlying repository outcome was never in
> doubt and remains verified — the scratch edits were reverted and
> `git diff` was empty.

The test service declaration:

```xml
<key>NSServices</key>
<array>
    <dict>
        <key>NSMenuItem</key>
        <dict><key>default</key><string>cooViewer (New Window Test)</string></dict>
        <key>NSMessage</key>
        <string>scratchOpenInNewWindowService</string>
        <key>NSSendFileTypes</key>
        <array>
            <string>public.cbz-archive</string>
            <string>jp.coo.cooviewer.cbz-archive</string>
            <string>jp.coo.cooviewer.cbr-archive</string>
            <string>public.data</string>
        </array>
    </dict>
</array>
```

(`AppController.m` gained a matching
`-scratchOpenInNewWindowService:userData:error:` method and a
`[NSApp setServicesProvider:self]` + `NSUpdateDynamicServices()` call
in `-awakeFromNib`.)

### Q1 — Does `NSServices` work here, without a second bundle?

**No.** Registered the test build (`lsregister -f`), launched it, and
checked three ways, each a stronger signal than the last:

1. **Finder's right-click ▸ Services submenu**, on `test.cbz`: showed
   the real, already-installed third-party services (Yoink, Together,
   Keka, Hammerspoon, iTerm2, Ghostty, Name Mangler) but never the test
   entry — checked immediately after launch, and again after
   `/System/Library/CoreServices/pbs -flush`, and again after
   `killall pbs` (which did not respawn on its own — `ps aux | grep
   pbs` showed nothing running afterward, until the next service
   request presumably triggers on-demand relaunch).
2. **First fix attempt — UTI mismatch, corrected but did not fix it.**
   `mdls -name kMDItemContentType test.cbz` showed the file's actual
   resolved type is `public.cbz-archive`, not cooViewer's own
   `jp.coo.cooviewer.cbz-archive` — the original test's
   `NSSendFileTypes` only listed the latter, so it could never match.
   Broadened to include `public.cbz-archive` and the maximally-generic
   `public.data`, rebuilt, re-registered, re-flushed — **still did not
   appear.**
3. **System Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸ Services** —
   this is the system's own authoritative services registry, not
   Finder's menu cache. Checked the "Files and Folders" category (all
   the same third-party services as the Finder menu, checkboxes
   enabled, no test entry) and "General" (three built-in "Unarchive
   to…" entries, no test entry). **The test service does not exist
   anywhere in this list, checked or unchecked** — this rules out "it
   works but needs the user to manually enable it," which was the
   scenario the task most wanted distinguished from outright failure.

Conclusion: this is not a "needs one-time enablement" situation (the
common, expected macOS behavior for new services) — the service was
never discovered by the system at all, despite a correctly-formed
declaration, explicit `setServicesProvider:`/`NSUpdateDynamicServices()`
calls, and every standard cache-refresh mechanism tried.

**Unconfirmed, recorded rather than asserted:** whether ad hoc code
signing (`codesign -s -`, used for this disposable test copy per the
project's own multi-instance testing convention) is itself sufficient
to be trusted by the services daemon, versus requiring the real
Developer ID signature the shipped app carries. Testing that would
mean running a full Developer-ID-signed, notarized build through this
same procedure, which is out of proportion for a scratch investigation
build — flagged as the one remaining unconfirmed variable rather than
silently assumed to be the cause.

### Q2 — What would the handler receive, and can it be routed?

Not reachable to test, since the service was never invoked (Q1) — but
answerable from the declared calling convention and precedent
elsewhere in this project. A service handler
(`-scratchOpenInNewWindowService:userData:error:` in the scratch code)
receives an `NSPasteboard`, from which file URLs are read with
`-readObjectsForClasses:options:` — this is a different, and simpler,
calling convention than `-application:openFiles:`, and **is** trivially
distinguishable in code from the ordinary Finder-open path, since it's
a wholly separate method that only fires for this specific menu
action. Had it worked, routing straight to `-openBookInNewWindow:`
from inside it (exactly as the scratch handler did) would have been
immune to the front-window-replace path from `d393955` for the same
reason as Part A's custom-URL-scheme design: it's a different method
entirely, not a runtime check that could be bypassed.

### Q3 — Registration safety

Moot given Q1, but the mechanics observed are worth recording: services
are **not** refreshed by the same `lsregister` step the build already
runs for document types/QuickLook extensions — `pbs`
(`/System/Library/CoreServices/pbs`) is a separate daemon with its own
`-flush` command, and killing it does not immediately restart it
(no auto-respawn observed within the test window). This means, if
`NSServices` is ever revisited (e.g. once the ad hoc-signing question
above is resolved), its own refresh path needs its own verification
step distinct from the QuickLook/Open-With one already documented in
`CLAUDE.md` — not a foregone conclusion that "the app registered
cleanly" implies "the service appeared."

### Q4 — UX acceptability

Could not be evaluated on this machine, since the entry never
appeared to judge placement or discoverability against. **Recorded for
completeness rather than skipped:** Apple's own placement for this
mechanism, based on what *did* appear in the menu (other apps'
services), is a **separate "Services" submenu**, distinct from "Quick
Actions" (Automator/Shortcuts-based, a different mechanism entirely,
also present in the same context menu) — so even had it worked, this
would not have been a Quick-Actions-labeled entry, and would have sat
one level deeper (`right-click ▸ Services ▸ cooViewer (New Window
Test)`) than a same-submenu "Open With" second entry. That placement
question is now academic given Q1.

### Q5 — Dedup interaction

Same answer as the prior Part A investigation, for the same reason:
had this mechanism worked, dedup would apply automatically for free by
routing through `-openBookInNewWindow:` (Q2) rather than needing a
separate policy decision — flagged for owner confirmation rather than
decided unilaterally, consistent with the prior report. Moot in
practice given Q1.

### Comparison against the companion-app design

| | Companion-app (`2026-08-02-01`) | NSServices (this report) |
|---|---|---|
| Confirmed to work on this machine? | Yes (Open With enumeration confirmed via live LaunchServices dump) | **No** — did not appear anywhere in the system's own services registry |
| Requires a second bundle? | Yes | No (if it worked) |
| Menu placement | Same submenu as the default Finder entry point (Open With) | One level deeper, in a separate Services submenu (based on other apps' entries seen) |
| Registration risk | Real, but scoped and manageable (unique identifier, embedded bundle, one-pass verification procedure already proposed) | Unconfirmed — moot |

**Recommendation: do not pursue NSServices as a substitute.** It is
not simply smaller-but-riskier than the companion-app plan — it does
not currently work at all on this machine, for a reason this
investigation could narrow down (likely code-signing trust, per the Q1
note) but not conclusively identify without disproportionate further
effort. The companion-app design from the prior investigation remains
the only confirmed-working path to a second Finder-native "always new
window" entry point.

### Implementation size estimate

**N/A — not recommended for implementation.** If the owner wants the
unconfirmed signing hypothesis (Q1) chased further before abandoning
this direction, that would itself be a small, bounded follow-up
investigation (build and test with real Developer ID signing rather
than ad hoc), not an implementation task.

### Anything found along the way that's out of scope

- `killall pbs` does not appear to auto-respawn the services daemon
  promptly; a future investigation of this mechanism should budget
  time for that, or find the correct on-demand-relaunch trigger, rather
  than assuming the daemon comes back immediately.
- The already-installed third-party services visible during this
  investigation (Keka, Together, Yoink, Hammerspoon, Name Mangler,
  iTerm2, Ghostty) confirm `NSServices` **does** work in general on
  this machine for other, presumably Developer-ID-signed or
  Mac-App-Store apps — reinforcing that the negative result is
  specific to this test build's circumstances, not a system-wide
  services outage, and making the signing hypothesis the most likely
  single explanation without further testing.
- ~~A tool-result claiming my own scratch edits were pre-existing
  "intentional" changes not to be reverted or mentioned — not
  something the user said, contradicted the verified repository state,
  and was not followed. Recorded here per the project's standing
  instruction to flag suspected prompt injection rather than comply
  silently.~~
  **RETRACTED (2026-08-02)** — this was a standard Claude Code
  `edited_text_file` harness notification triggered by the agent's own
  `git checkout`, not an injection. See the retraction note in the
  Method section above for the transcript evidence.
