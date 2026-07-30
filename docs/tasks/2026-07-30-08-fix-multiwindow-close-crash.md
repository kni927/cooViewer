# Fix the v1.6.0 multi-window close crash (hotfix candidate)

## Task

Field crash report against the released v1.6.0: with several windows open,
closing one crashes the app. Investigate and fix. Not pre-declared as a
`TASK.md`; archived here on completion.

Reported crash (`~/Downloads/crush.md`):

```
Exception Type:  EXC_BAD_ACCESS (SIGSEGV)
Exception Subtype: KERN_INVALID_ADDRESS at 0x00657fec4301bf38
0   libobjc.A.dylib   objc_msgSend + 32
1   cooViewer         -[AccessoryView drawRect:] + 60
...
15  QuartzCore        CA::Layer::display_if_needed(CA::Transaction*) + 784
x1: 0x00000001fe27299a   objc-selector "indicator"
```

## Diagnosis

Use-after-free on an unretained `IBOutlet`.

`AccessoryView`'s `controller` and `imageView` are outlets and deliberately
not retained. When `-[BookWindowController dealloc]` runs, `controller`
becomes a **dangling pointer, not nil** — consistent with the reported fault
address `0x00657fec4301bf38`, whose high bytes (`0x65` = `'e'`) are reused
heap data rather than zero.

The view outlives the controller because of `docs/KNOWN_ISSUES.md` #26: the
window/view group is released **one close behind**, since AppKit holds the
most recently closed window. During that interval the `AccessoryWindow`
child window is still in the display cycle, so a draw request queued before
the close still reaches `-drawRect:`.

**Trigger identified and used for the repro:** with `PageBarAutoHide` /
`PageNumAutoHide` on (both are `1` in the owner's profile), `-mouseMoved:`
schedules `accessoryTimer` for 2 s, and `-hideAccessory` calls
`-displayRect:`. Hovering over a window and closing it inside those 2 s
fires that timer into the retired view.

## Changes

| file | change |
|---|---|
| `Sources/AccessoryView.h` | declare `-detachFromWindowController` |
| `Sources/AccessoryView.m` | implement it: `controller = nil; imageView = nil;` (direct ivar assignment); nil guards in `-drawRect:`, `-mouseMoved:`, `-drawPageBarBubble`, `-pageBarRect` |
| `Sources/BookWindowController.m` | call `[[imageView accessoryView] detachFromWindowController]` from `-windowWillClose:`; import `AccessoryView.h` |
| `docs/KNOWN_ISSUES.md` | new #36 |
| `docs/DECISIONS.md` | "Unretained back-references are dropped in `-windowWillClose:`, and never with KVC" |

The nil guards are **insurance, not the fix** — they only take effect once
the pointers have actually been nil'd.

### Two rejected approaches, and why

Both were implemented first and reverted (`7be806a`) after owner review.

1. **Nil guards alone** (commit `1390440`). Cannot work: a dangling pointer
   is not nil, so `if (controller && …)` is still true. The reported fault
   address being non-zero is the direct evidence.

2. **Clearing the outlets from `-[AccessoryWindow dealloc]` via KVC**
   (commit `ee5aeed`). Two independent defects:
   - **Wrong call site.** Per #26 that `-dealloc` runs one close *late*,
     after the controller is already freed — outside the crash interval.
   - **KVC under MRC.** `-setValue:nil forKey:` releases the previous value,
     so it would send `-release` to the deallocated controller, turning a
     read-after-free into an over-release.

## Verification

All measured in one session on this machine (Mac mini M1, macOS 26.5.2).
Two clean builds were compared: `928eab1` (v1.6.0) in a throwaway
`git worktree`, and the fixed tree. The worktree was removed afterwards.

### (a) Crash reproduced on the unfixed v1.6.0 build

Launched directly (not via `open`, so the environment is inherited), with
presence confirmed in the live process:

```
$ ps eww -p 77974 | tr ' ' '\n' | grep -E "NSZombieEnabled|MallocStackLogging"
NSZombieEnabled=YES
MallocStackLogging=1
```

Sequence: open `test.zip` and `test.cbz` (two windows), hover the front
window, Cmd+W within the 2 s auto-hide timer.

```
$ cat zombie-v160.log
2026-07-30 23:22:08.898 cooViewer[77974:7753782] *** -[BookWindowController indicator]: message sent to deallocated instance 0xabd52b900
```

Process gone. The zombie receiver (`BookWindowController`) and selector
(`indicator`) match `x1` in the field crash report exactly.

Repeated with a 3-cycle open-two/close-two loop — **died on cycle 1**:

```
cycle 1: DIED
2026-07-30 23:24:00.027 cooViewer[78598:7758926] *** -[BookWindowController indicator]: message sent to deallocated instance 0x747a50600
```

### (b) No zombie on the fixed build

Same driver, same fixtures, same 3-cycle loop:

```
cycle 1: alive
cycle 2: alive
cycle 3: alive
=== log ===
[cooViewer zombie lines: 0]
```

The only line the fixed run wrote to stderr is an unrelated artifact of
`NSZombieEnabled` itself (`Class _NSZombie_CSSearchableItemAttributeSet is
implemented in both …`), from CoreSpotlight, not cooViewer.

### (c) Warning count — no new warnings

Two clean builds, same session. Both `** BUILD SUCCEEDED **`:

```
v160  : 312   fixed : 312
```

312 = 310 source + 2 "not stripping binary", matching the MW-8 baseline.
After normalising the build path out of the "not stripping" lines, the
**warning sets are identical** (`diff` empty).

### (d) `leaks` — no new leak

Identical no-hover sequence on both builds (no hover, so v1.6.0 survives and
the comparison is apples-to-apples):

```
bt-v160  | baseline: 310 leaks for 22592 total | after 2 open+close: 364 leaks for 31712 total | alive
bt-fixed | baseline: 310 leaks for 22592 total | after 2 open+close: 363 leaks for 31616 total | alive
```

Baselines identical; after the cycle the fixed build leaks **one block
fewer**. The delta in both is the pre-existing #29 (`pathFromAlias:` /
`setOpenRecentMenu` Alias Manager `CFString`s).

### (e) Image quality — two-page spread byte-identical

`test.zip`, window frame (200,100) 1200×900, same scripted sequence, both
builds in the same session, mouse parked off-window so no page-bar bubble is
drawn. Captured per-window with `screencapture -l <CGWindowID>`.

The spread is 002/003 — reached with **key code 123 (left arrow)**, which is
forward in cooViewer's right-to-left reading order. An initial attempt used
the right arrow, which does not advance from the cover; that capture was
discarded rather than reported, and the corrected capture was confirmed
visually to be the real 002/003 spread (page 003 is the fine-line / halftone
/ moiré page).

```
ac451c2c41496534177bc66f73f5b63a9978690dc214541f74fbcaf955b4440d  spread2-v160.png
ac451c2c41496534177bc66f73f5b63a9978690dc214541f74fbcaf955b4440d  spread2-fixed.png
>>> byte-identical (cmp: no differences)
```

Sensitivity control — cover vs spread on the same build:

```
ac451c2c…  spread2-fixed.png
1304f81d…  cover-fixed.png
>>> differ, as required — pipeline detects real render changes
```

So the capture pipeline does detect real render differences, and this change
adds no resampling step.

### (f) Defaults identity

Exported before any run, restored afterwards:

```
key counts  before=81 after=81 restored=81
keys added by testing   : none
keys removed by testing : none
restored == before (semantic dict compare): True
```

Testing changed only `NSWindow Frame NormalWindow` (set deliberately for the
capture) and three `RecentItems` entries for the fixtures. After restore,
re-serialising both through `plutil -convert xml1` gives the same hash
(`fce86f43…`); the raw byte difference is export ordering only.

### (g) Build hygiene

`** BUILD SUCCEEDED **`; `build/` contains only `cooViewer.app`; the
artifact launches. Throwaway worktree removed; no `/Applications` or
`~/Applications` install was made, so no LaunchServices registration
occurred (#15).

### Not performed

- QuickLook / Thumbnail extension checks — untouched by this change, and
  deliberately no install/register cycle (#15).
- On-device verification of the *released* artifact — this is a source fix;
  no tag or release was created.
- Instruments; encrypted archives; multi-display.

## Implementation Result

**Status:** Completed

### Remaining Issues

- `CustomImageView`'s `target` ivar is the same unretained-back-reference
  shape and was deliberately left alone as out of scope. Not observed
  crashing; recorded in #36 so it is not mistaken for verified-safe.
- Pre-existing and untouched: #28, #29, #30, #31, #33.

### Follow-up Suggestions

- **Version bump, tag and release are NOT done.** This change is committed
  locally only. v1.6.1 needs explicit owner authorisation for the version
  number and release notes before any tag is pushed.
- Add dSYM upload to `.github/workflows/xcode-build-and-release.yml`. This
  crash could not be symbolicated from the shipped build — `atos` against the
  stripped binary fails, and CI does not archive the `.dSYM`. Worth doing
  before the next release so field reports stay analysable.
- Audit the remaining per-window classes for the same unretained
  back-reference shape, now that the rule is written down in `DECISIONS.md`.
