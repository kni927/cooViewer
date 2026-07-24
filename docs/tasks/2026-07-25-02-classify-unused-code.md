# TASK: Classify unused-code warnings before removal (investigation only)

## Scope

Investigation only. Do not delete or modify any code.
Produce a classification table for the 12 unused-code warnings so the
following task can define a safe removal scope.

## Part A: unused-variable (11 items)

For each of the 11 `-Wunused-variable` warnings, report:

- file and line
- the declaration as written
- whether the initializer returns an owning reference
  (`alloc` / `new` / `copy` / `mutableCopy` / `retain`), a non-owning
  reference, or a scalar
- whether a matching `release` / `autorelease` exists in the same scope
- whether the initializer expression has side effects that must be
  preserved even if the variable is removed
- whether the warning overlaps an entry in `docs/KNOWN_ISSUES.md` #16
- proposed disposition, one of:
  - safe to delete (scalar or no ownership, no side effects)
  - delete variable but keep the initializer expression (side effects)
  - requires rework (ownership present; removal would leak or over-release)
  - leave in place (evidence it is intentional or load-bearing)

## Part B: hotKeyEventHandler

- Report the full definition of `hotKeyEventHandler` in
  `GlobalKeyboardDevice.h:47` and its surrounding context.
- Determine whether it was ever wired to a Carbon event handler
  (`InstallEventHandler`, `RegisterEventHotKey`, or similar) anywhere in
  the project, including commented-out code.
- Report whether the project has a hotkey feature that is expected to work,
  and whether it currently functions.
- Propose a disposition: dead residue safe to remove, or an unwired feature
  that should be recorded as a bug rather than deleted.
- Note why a static function in a header produces one warning per
  translation unit, and whether moving it into a `.m` would be part of any
  fix.

## Notes

- Investigation only. No code changes, no commits.
- Report the table in chat; do not create documentation files for it.
- Do not fix anything found along the way. Record new findings as
  observations only.
## Implementation Result

**Status:** Completed

### Changes

Investigation only; no code modified. The full per-variable ownership
analysis is reproduced below so it survives outside the chat.

**Part A — `-Wunused-variable` classification (11 items)**

Ownership legend: owning = initializer returns `alloc`/`new`/`copy`/
`mutableCopy`/`retain`; non-owning = other object accessor; scalar/value =
primitive or C struct (e.g. `NSRect`).

| # | Location | Declaration | Ownership | Matching release | Side effects to keep | Overlaps #16 | Disposition |
|---|---|---|---|---|---|---|---|
| 1 | `COImageLoader.m:500` | `NSArray* items=[archiveContainer contents];` | non-owning (`contents` getter) | none needed | none (pure getter) | yes | safe to delete |
| 2 | `COImageLoader.m:501` | `NSData* data;` | none (no initializer) | none needed | none | no | safe to delete |
| 3 | `Controller.m:1232` | `int heightValue = 0, …;` | scalar | none needed | none (consumer is commented out) | no | safe to delete |
| 4 | `Controller.m:1232` | `… widthValue = 0 …` | scalar | none needed | none | no | safe to delete |
| 5 | `Controller.m:1232` | `… repi = 0;` | scalar | none needed | none | no | safe to delete |
| 6 | `CustomImageView.m:1347` | `NSRect fullscreenRect = NSRectFromString([infodic objectForKey:@"fullscreenRect"]);` | value (NSRect) | none needed | none (pure fn + dict lookup) | yes | safe to delete |
| 7 | `FilterPanelController.m:85` | `NSRect docBounds = [[scrollView documentView] bounds];` | value (NSRect) | none needed | none (side-effect-free accessors) | yes | safe to delete |
| 8 | `LoupeView.m:177` | `float sx = sImageSize.width/sTempRect.size.width;` | scalar (float) | none needed | none | yes | safe to delete |
| 9 | `LoupeView.m:213` | `float sx = sImageSize.width/fTempRect.size.width;` | scalar (float) | none needed | none | yes | safe to delete |
| 10 | `NSString_Compare.m:47` | `NSFileManager *manager = [NSFileManager defaultManager];` | non-owning (shared singleton) | none needed | none | yes | safe to delete |
| 11 | `NSString_Compare.m:60` | `NSFileManager *manager = [NSFileManager defaultManager];` | non-owning (singleton) | none needed | none | yes | safe to delete |

MRR note: this is a manual retain/release project (`CLANG_ENABLE_OBJC_ARC`
unset → NO; corroborated by `[super dealloc]`, explicit `retain`/`release`).
However, **none of the 11 unused variables holds an owning reference**
(6 scalar, 2 NSRect value, 3 non-owning: 1 getter + 2 `defaultManager`
singleton). Therefore removing any of them cannot leak or over-release —
all 11 are *safe to delete*. No item needs "keep the initializer for side
effects" and none is "requires rework".

**Part B — `hotKeyEventHandler` (the one `-Wunused-function`)**

- `GlobalKeyboardDevice.h:47` holds a `static` **declaration**:
  `static OSStatus hotKeyEventHandler(EventHandlerCallRef, EventRef, void*);`
  The **definition** is `GlobalKeyboardDevice.m:220`. Source: Martin Kahr's
  RemoteControlWrapper (MIT, `docs/licenses/License_RemoteControlWrapper.txt`).
- It **is** wired to Carbon inside the class:
  `GlobalKeyboardDevice.m:145-146` `InstallEventHandler(...)` and
  `:175` `RegisterEventHotKey(...)`.
- But the class is **never instantiated by the app**: `Controller.m:588`
  creates `remoteControl = [[AppleRemote alloc] initWithDelegate:self]`
  only; `GlobalKeyboardDevice` appears nowhere outside its own files. So the
  keyboard-shortcut remote feature is latent/unwired and does not run;
  cooViewer uses the AppleRemote path only.
- Disposition: **not** dead residue removable in isolation (deleting the
  function breaks the `InstallEventHandler` reference). It is a live handler
  inside an unwired third-party feature — record as an observation, not a
  bug. Whether to keep or drop `GlobalKeyboardDevice` wholesale is a
  separate third-party-code decision.
- Warning mechanism: a `static` function has internal linkage, so every
  translation unit that imports the header gets its own private prototype;
  only `GlobalKeyboardDevice.m` defines/uses it, so all other importing TUs
  warn `-Wunused-function` (1 distinct location, many raw hits). Moving the
  declaration out of the header into `GlobalKeyboardDevice.m` (before its
  first use at line 145) confines it to the single using TU and silences the
  warning without changing behavior — this relocation is the core of any
  warning fix.

### Verification

- Build: Not performed (investigation only).
- Automated verification: Not performed (investigation only).
- Manual verification: Source inspection of the 12 warning sites, the
  Carbon wiring in `GlobalKeyboardDevice.m`, and the remote-control setup in
  `Controller.m`.

### Remaining Issues

None.

### Follow-up Suggestions

Removal scope for the next task:

- Part A: all 11 `-Wunused-variable` items are *safe to delete* (see table).
  For `Controller.m:1232` (#3-5) note the values belonged to a commented-out
  block; deleting the declarations is safe, but confirm the block is not
  meant to be restored.
- Part B: do **not** delete `hotKeyEventHandler`. Fix the warning by moving
  its declaration from `GlobalKeyboardDevice.h:47` into
  `GlobalKeyboardDevice.m` above line 145 (behavior-preserving). Separately,
  decide whether the unwired `GlobalKeyboardDevice` class should remain.
- Ownership-bearing findings (potential leaks, uninitialized values, dead
  stores) remain out of scope and are tracked in `docs/KNOWN_ISSUES.md` #16.

### Process note

The earlier investigation task "Survey for dead code analysis
(investigation only)" (run 2026-07-24) was reported in chat but never
archived — its root `TASK.md` was overwritten by the next task. Per the
corrected workflow it should have been archived; it is noted here rather
than reconstructed.
