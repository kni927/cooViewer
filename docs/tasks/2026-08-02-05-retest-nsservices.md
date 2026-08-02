# TASK: Re-test — does `NSServices` actually fail on this machine?

## This part is investigation-only. Do not implement anything.

## Why this was re-tested

The prior investigation (commit `896fd16`,
`docs/tasks/2026-08-02-03-investigate-quick-action-alternative.md`)
concluded that a correctly-declared `NSServices` entry never appears in
the system service registry on this machine (macOS 26.5.2), and
recommended falling back to the companion-app (second bundle) design.
That negative result was not accepted, for four specific reasons the
owner listed: bundle-ID collision, registration location, wrong refresh
mechanism, and declaration completeness.

## Result in one line

**The prior conclusion is REFUTED.** `NSServices` works completely on
this machine — registration, System Settings listing, Finder context
menu, and end-to-end handler invocation with the file URL delivered.
The prior negative was a test-setup failure, exactly as suspected.

---

## Q1 — With a distinct bundle ID in a scanned location, does a trivial service register and appear?

**YES, on both counts.**

### The probe

A purpose-built minimal app (not cooViewer), source at
`scratchpad/nsprobe/main.m` — a bare `NSApplication` with
`[NSApp setServicesProvider:self]` and two handler methods. Bundle
identifier `jp.coo.nsservices-probe`, executable and `CFBundleName`
both `NSServicesProbe` — definitively distinct from cooViewer's
`jp.coo.cooViewer` (suspect #1 controlled). Installed to
`~/Applications` per this project's rule, never `/Applications`
(suspect #2 controlled).

### The exact `NSServices` block used

```xml
<key>NSServices</key>
<array>
    <dict>
        <key>NSMenuItem</key>
        <dict>
            <key>default</key>
            <string>NSPROBE Text Control</string>
        </dict>
        <key>NSMessage</key>
        <string>probeTextService</string>
        <key>NSPortName</key>
        <string>NSServicesProbe</string>
        <key>NSSendTypes</key>
        <array>
            <string>NSStringPboardType</string>
            <string>public.utf8-plain-text</string>
        </array>
    </dict>
    <dict>
        <key>NSMenuItem</key>
        <dict>
            <key>default</key>
            <string>NSPROBE Open in New Window</string>
        </dict>
        <key>NSMessage</key>
        <string>probeFileService</string>
        <key>NSPortName</key>
        <string>NSServicesProbe</string>
        <key>NSSendFileTypes</key>
        <array>
            <string>public.cbz-archive</string>
            <string>public.cbr-archive</string>
            <string>public.data</string>
        </array>
    </dict>
</array>
```

Both the trivial text-selection control **and** the real file-selection
service were declared in one plist and registered in **one pass**, so
the trivial case acts as an in-pass control without a second
install/register cycle (single-pass discipline, `KNOWN_ISSUES.md` #15).
`NSPortName` was included — the prior test omitted it (suspect #4).

### Refresh mechanisms actually used, verbatim

```
$ lsregister -f ~/Applications/NSServicesProbe.app
lsregister -f exit=0

$ /System/Library/CoreServices/pbs -flush
exit=0
```

`lsregister -f` was the mechanism that mattered. `NSUpdateDynamicServices()`
was **not** used and is not applicable — it is for *dynamic* services,
not static `Info.plist` declarations (the prior test relied on it;
suspect #3 confirmed as a red herring).

### `lsregister -dump` — the probe's record (registered, with both services)

```
bundle id:                  NSServicesProbe (0x60c8)
path:                       /Users/kni/Applications/NSServicesProbe.app (0xb3e0)
directory:                  ~/Applications
identifier:                 jp.coo.nsservices-probe
executable:                 Contents/MacOS/NSServicesProbe
item flags:                 package  application  container  native-app
                            extension-hidden  services (000000000030008e)
--------------------------------------------------------------------------------
service id:                 NSPROBE Text Control (0xb68)
menu:                       NSPROBE Text Control
port:                       NSServicesProbe
message:                    probeTextService
timeout:                    -1
send types:                 public.utf8-plain-text, "NSStringPboardType"
--------------------------------------------------------------------------------
service id:                 NSPROBE Open in New Window (0xb6c)
menu:                       NSPROBE Open in New Window
port:                       NSServicesProbe
message:                    probeFileService
timeout:                    -1
```

Note the `services` bit in `item flags` — present on the probe.

### `lsregister -dump` — the real cooViewer install, for contrast

```
bundle id:                  cooViewer (0x5f6c)
path:                       /Applications/cooViewer.app (0xb05c)
directory:                  /Applications
identifier:                 jp.coo.cooViewer
item flags:                 package  application  container  native-app
                            extension-hidden (000000000010008e)
```

No `services` flag, no service records — as expected, since shipped
cooViewer declares no `NSServices`. The two bundles are unambiguously
distinguishable in the registry, so **suspect #1 (bundle-ID collision)
is ruled out by direct evidence**, not assumption.

### `pbs` itself sees both services

```
$ /System/Library/CoreServices/pbs -dump_pboard | grep -B12 -A6 NSPROBE
    {
    NSBundleIdentifier = "jp.coo.nsservices-probe";
    NSBundlePath = "/Users/kni/Applications/NSServicesProbe.app";
    NSMenuItem = { default = "NSPROBE Text Control"; };
    NSMessage = probeTextService;
    NSPortName = NSServicesProbe;
    NSSendTypes = ( NSStringPboardType, "public.utf8-plain-text" );
    },
    {
    NSBundleIdentifier = "jp.coo.nsservices-probe";
    NSBundlePath = "/Users/kni/Applications/NSServicesProbe.app";
    NSMenuItem = { default = "NSPROBE Open in New Window"; };
    NSMessage = probeFileService;
    NSPortName = NSServicesProbe;
    NSSendFileTypes = ( "public.cbz-archive", "public.cbr-archive", ... );
    }
```

`NSSendFileTypes` was absorbed correctly.

### System Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸ Services

Both entries are present — **and this is the key detail the prior
investigation missed: they are UNCHECKED (disabled) by default.**

- Under **Text**: `NSPROBE Text Control` — checkbox off, shortcut `none`
- Under **Files and Folders**: `NSPROBE Open in New Window` — checkbox
  off, shortcut `none`

Both were confirmed by zoomed screenshot, in the correct category for
their declared send types. The prior report's claim that the entry was
absent "not merely hidden or unchecked" is therefore wrong on its own
terms — this test found exactly the "present but unchecked" state that
report explicitly ruled out.

---

## Q2 — Does the `.cbr`/`.cbz` file-selection service appear, and where?

**YES**, after enabling the checkbox once.

- **Before enabling:** not present in Finder's right-click ▸ Services
  submenu for a selected `.cbz`. (Consistent with the prior session's
  observation — that part of the prior report was a correct
  observation with an incorrect conclusion drawn from it.)
- **After ticking the checkbox** in System Settings ▸ Keyboard
  Shortcuts ▸ Services ▸ Files and Folders:
  right-click `test.cbz` ▸ **Services ▸ "NSPROBE Open in New Window"**
  appears, listed alphabetically among the other third-party services
  (Yoink, Together, Keka, Ghostty, iTerm2, Name Mangler, Hammerspoon).

**Exact placement:** the **Services** submenu — *not* "Quick Actions",
which is a separate submenu in the same context menu backed by a
different mechanism (Automator/Shortcuts). So this is one level deeper
than an "Open With" entry would be.

**Enablement requirement:** yes, one-time, per user, in System
Settings. This is the single genuine UX cost of this approach, and it
is the answer to what the prior report failed to establish.

A useful corroborating data point found in the same `pbs` dump:
**EdgeView 2** — another comic viewer installed on this machine —
ships exactly this kind of declaration
(`NSSendFileTypes = ( "public.item" )`), and it likewise does not
appear in the Finder Services submenu, presumably for the same
default-disabled reason. So this mechanism is in real-world shipping
use for precisely this use case.

---

## Q3 — Can a service-invoked open be distinguished in code and routed to `-openBookInNewWindow:`?

**YES — trivially, and proven end-to-end.**

The service handler is a **completely separate method** from
`-application:openFiles:`:

```objc
- (void)probeFileService:(NSPasteboard *)pboard
                userData:(NSString *)userData
                   error:(NSString **)error
```

It is only ever called for this specific menu action, so routing it
straight to `-openBookInNewWindow:` is structurally incapable of
touching the front-window-replace path from `d393955` — the same
"different method entirely, not a runtime check" property the
companion-app design relies on.

**Direct proof the handler runs and receives the file:**

```
2026-08-02 22:20:39.024 NSServicesProbe[9370] NSPROBE: servicesProvider set
2026-08-02 22:21:04.195 NSServicesProbe[9370] NSPROBE: probeFileService invoked, urls=(
    "file:///.file/id=6571367.396056374"
)
```

The system also **auto-launched the probe on demand** the first time
the menu item was clicked (probe was not running; process appeared at
the moment of the click, and the menu bar switched to
"NSServicesProbe") — so a shipped implementation does not need the app
already running.

**One implementation detail worth recording:** the URL arrives in
macOS's opaque `file:///.file/id=…` form, not a plain path. It must be
resolved (e.g. `[url path]` / `-URLByResolvingSymlinksInPath`) before
being handed to `-openBookInNewWindow:`, which expects a filesystem
path. This is a small but real gotcha that would otherwise surface as
a mysterious "file not found" at implementation time.

---

## Q4 — If it genuinely does not work…

Not applicable — it works. Recorded here so the question is visibly
answered rather than silently dropped.

**What actually caused the prior false negative:** two of the four
suspects were live in the prior test and both were corrected here:

| Suspect | Prior test | This test |
|---|---|---|
| #1 bundle-ID collision | `jp.coo.cooViewer.svctest` — distinct, but never verified in `lsregister` | `jp.coo.nsservices-probe`, verified distinct in the dump |
| #2 registration location | `${TMPDIR}/cooViewer-svc/test/` — **not a scanned location** | `~/Applications` — scanned |
| #3 refresh mechanism | relied partly on `NSUpdateDynamicServices()` — **not applicable to static declarations** | `lsregister -f` + `pbs -flush` |
| #4 declaration completeness | **no `NSPortName`** | `NSPortName` present |

**I did not isolate which of #2 and #4 was individually decisive** —
doing so would have required additional install/register cycles, which
single-pass discipline (`KNOWN_ISSUES.md` #15) rules out for a question
that does not change the recommendation. Both are recorded as
contributing causes rather than one being asserted.

**Additionally**, the prior report's own UI check was wrong on its
central claim regardless of registration: it asserted the entry was
absent from System Settings "not merely hidden or unchecked", when the
actual behavior of a correctly-registered new service is precisely
*present but unchecked*.

---

## Q5 — Comparison against the companion-app design

| | Companion app (`2026-08-02-01`) | NSServices (this report) |
|---|---|---|
| Second bundle required | **Yes** — new target, Info.plist, signing, notarization, embedding | **No** — one `Info.plist` block + one method in the existing app |
| IPC required | **Yes** — custom URL scheme + new `-application:openURL:` handler | **No** — the system delivers the pasteboard directly |
| Menu placement | **Open With** submenu — same place users already look | **Services** submenu — one level deeper |
| User setup needed | None | **One-time enable** in System Settings ▸ Keyboard Shortcuts ▸ Services |
| LaunchServices duplicate-registration risk (#15) | Real, needs the mitigation plan in the prior report | **None** — no second bundle |
| Confirmed working on this machine | Mechanism confirmed by dump; design not built | **Yes — end-to-end, handler invoked with the file URL** |

**Recommendation: NSServices, unless the one-time enablement is
unacceptable to the owner.** It is dramatically smaller, carries none
of the registration risk this project has already been burned by, and
is confirmed working. The companion app buys exactly one thing — better
menu placement with no user setup — at the cost of a second signed,
notarized, embedded executable plus IPC.

**This is a genuine trade-off and the owner should pick**, because the
enablement step is not trivial in practice: a feature most users never
discover is arguably worse than no feature. Flagging rather than
deciding.

**Dedup (#32) interaction — unchanged, still for owner confirmation:**
as with the companion-app design, routing through
`-openBookInNewWindow:` means dedup applies automatically (that method
runs its own `windowControllerShowingBook:` check first). Whether the
dedicated "always new window" entry point *should* honor dedup, or
force a literal new window every time, remains the open question from
the original investigation. Not decided here.

---

## Implementation size estimate

**Small** — the first of the three buckets, and a genuine change from
the prior report's "a real feature-sized task".

Concretely: one `NSServices` array in `Resources/Info.plist` (~20
lines), one handler method on `AppController` (~8 lines) that resolves
the `/.file/id=` URLs and calls the existing `-openBookInNewWindow:`,
and one `[NSApp setServicesProvider:self]` line. No new target, no new
bundle, no IPC, no CI/notarization change, no LaunchServices risk
mitigation plan.

The only non-code work is deciding how to tell users about the one-time
enable step (README note, or a first-run hint — owner's call, and out
of scope here).

---

## Cleanup — confirmed

```
$ pkill -f NSServicesProbe                → probe not running
$ lsregister -u ~/Applications/NSServicesProbe.app   → exit=0
$ rm -rf ~/Applications/NSServicesProbe.app          → bundle gone
$ pbs -flush                                          → exit=0
$ pbs -dump_pboard | grep -c NSPROBE                  → 0
$ lsregister -dump | grep -c nsservices-probe         → 0
```

The checkbox enabled during Q2 left a residue key in
`pbs NSServicesStatus`. It was removed with PlistBuddy, deleting
**only** the probe's key — the owner's four pre-existing Automator
service settings (`Convert to UTF-8`, `Open in Zed`, `convert to mp4`,
`heic to jpg`) were verified present before and after:

```
BEFORE: 4 user entries + "jp.coo.nsservices-probe - NSPROBE Open in New Window - probeFileService"
AFTER:  4 user entries, probe key gone
$ defaults read pbs | grep -ci "nsprobe\|nsservices-probe"  → 0
```

No test service remains registered on the owner's system. The cooViewer
repository was never modified by this investigation (`git status` clean
apart from `TASK.md`).

Full raw evidence log: `scratchpad/nsprobe-evidence.log` (387 lines,
scratch — not committed).

---

## Anything found along the way that's out of scope

- **EdgeView 2 ships an `NSServices` file handler**
  (`NSSendFileTypes = ( "public.item" )`) and is installed on this
  machine. If the owner ever wants a real-world reference for how a
  comparable comic viewer exposes this, it is right there in
  `pbs -dump_pboard`.
- **New services are disabled by default on macOS 26.5.2.** This is not
  cooViewer-specific and is the single most important fact for anyone
  evaluating this mechanism — worth remembering independently of this
  task's outcome.
- The 91 stale `jp.coo.cooViewer` LaunchServices registrations recorded
  in `2026-08-02-01`'s out-of-scope section are still present; this
  investigation did not touch them.
