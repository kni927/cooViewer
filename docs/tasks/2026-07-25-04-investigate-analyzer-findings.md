# TASK: Investigate crash-prone analyzer findings (investigation only)

## Scope

Investigation only. Do not modify code, do not commit.

Examine the 9 findings in `docs/KNOWN_ISSUES.md` #16 that can cause
incorrect behaviour or crashes:

- Null pointer dereference (1)
- Receiver in message expression is an uninitialized value (8)

Dead stores (22) and potential leaks (7) are out of scope for this task.

## Steps

1. Re-run `xcodebuild analyze` and list the current findings for these two
   categories with file, line, and the analyzer's description. Confirm the
   counts still match #16; report any drift.
2. For each finding, report:
   - the code path the analyzer describes, in brief
   - whether the path is actually reachable at runtime, or whether the
     analyzer is following an infeasible branch
   - what triggers it from the user's perspective, if reachable
     (e.g. opening a malformed archive, a specific menu action)
   - severity: crash / silent wrong behaviour / analyzer false positive
   - proposed fix in one or two lines, without applying it
3. Note in Objective-C terms whether each uninitialized-receiver case would
   actually crash. Messaging `nil` is safe; an *uninitialized* pointer
   holding garbage is not. State which of the two each case is.
4. Group the findings by proposed fix where several share a root cause.
5. Recommend an order of repair, and whether they fit in one task or need
   splitting.

## Notes

- Investigation only. Report in chat; the archive comes with the fix task.
- If any finding turns out to be a false positive, say so plainly rather
   than proposing a defensive change.
- Do not touch `vendor/`.
## Implementation Result

**Status:** Completed

### Changes

Investigation only; no code modified. Full findings recorded below so they
survive outside the chat. Analyzer re-run: `xcodebuild analyze`
(scheme `cooViewer`, Deployment) → `** ANALYZE SUCCEEDED **`. Counts still
match `docs/KNOWN_ISSUES.md` #16 (1 null-deref + 8 uninitialized-receiver =
9). One line drift: `CustomImageView.m:1398 → 1397` (shifted by the line
deletion in `docs/tasks/2026-07-25-03-*`); all other locations unchanged.

**A. Null pointer dereference (1)**

- `COImageLoader.m:82` — `[contentPathArray addObject:…]`.
  Path: `self = [super init]` returns nil → the `if (self){…}` init block is
  skipped → `if ([self itemCount]==0)` (line 81, `[nil itemCount]`==0, true)
  → line 82 loads ivar `contentPathArray` through a nil `self` (null read).
  Reachable: no — `NSObject -init` does not return nil in practice
  (infeasible branch). nil-vs-garbage: not a receiver-nil case; it is an
  ivar load through a nil `self`, which would be a null read only if `self`
  were nil. Severity: effectively a false positive, but the structure is a
  real smell (the post-init `if ([self itemCount]==0){…}` block sits outside
  the `if (self)` guard). Proposed fix: move that block inside the
  `if (self){…}` body.

**B. Uninitialized receiver (8)**

- `COColorPopUpButton.m:169` — `[fillColor set]`.
  `NSColor *fillColor;` (line 87) is an uninitialized local, assigned per
  title in an `if/else if` chain with no final `else`; the `else` of the
  "Clear" check messages it. Reachable: no — the menu titles are a fixed
  closed set added by the same `awakeFromNib` (White…Yellow, Clear,
  Other…); every one is covered (Other returns early, Clear handled
  separately, all colors assign fillColor). nil-vs-garbage: uninitialized
  local → would be garbage if reached, but unreachable. Severity: **false
  positive**.

- `CustomImageView.m:988` and `:1397` — `[transform invert]`.
  `NSAffineTransform *transform;` uninitialized local, assigned in
  `switch (rotateMode)` cases 1/2/3; `default` does not assign; then
  `if (rotateMode!=0){ [transform invert]; [transform concat]; }`.
  Reachable: no — `rotateMode` is initialized to 0 and only mutated by
  `rotateLeft`/`rotateRight`, which strictly wrap it to [0,3]
  (`if(rotateMode<0)rotateMode=3;` / `if(rotateMode>3)rotateMode=0;`). For
  1/2/3 the case assigns transform; for 0 the guard skips. The default path
  (rotateMode not in {0,1,2,3}) never occurs. nil-vs-garbage: garbage if
  reached, but unreachable. Severity: **false positive** (both). Note:
  `:1397` is in `drawImages:and:` whose drawing body is commented out; the
  transform switch and invert/concat remain live — same pattern as 988.

- `ThumbnailController.m:1015, 1025, 1039, 1047, 1071` — `[lastCell …]`.
  `id lastCell;` (line 1002) is an uninitialized local, assigned **only**
  inside `if ([matrix getRow:&tmprow column:&tmpcol forPoint:point])`; it is
  then messaged unconditionally in each context-menu action branch
  (`[[lastCell alternateTitle] intValue]`, `[lastCell representedObject]`).
  `row`/`col` (from tmprow/tmpcol) are likewise uninitialized on that path.
  Reachable: **yes**. `ThumbnailMatrix -menu` only returns the menu when the
  right-click is over a cell image (else nil), but `contextAction:`
  re-derives the cell from `[NSApp currentEvent]` at selection time, whose
  location need not map back to a cell — so the second `getRow` can return NO
  while the menu was legitimately shown. `-menu` handles a getRow miss
  (returns nil); `contextAction:` does not honour its own guard — that
  asymmetry is the bug. Trigger: selecting a thumbnail context-menu action
  (Remove/Add Bookmark, Switch Single/Bind, Show in Finder) when the
  selection-time event does not resolve to a cell. nil-vs-garbage:
  uninitialized `id` → **garbage → crash** (not nil). All 5 share one root
  cause. Proposed fix: `id lastCell = nil;` and bail early when `getRow`
  fails (`if (![matrix getRow:…]) return;`).

**Grouping by root cause (G1–G4)**

- G1 — ThumbnailController ×5 (1015/1025/1039/1047/1071): uninitialized
  `lastCell`, guard result ignored. **Genuine, reachable crash.**
- G2 — CustomImageView 988 + 1397: uninitialized `transform`, switch has no
  default assignment; safe because rotateMode ∈ [0,3]. **False positive.**
- G3 — COColorPopUpButton 169: uninitialized `fillColor`; safe because the
  title set is fixed and fully covered. **False positive.**
- G4 — COImageLoader 82: post-init work outside the `if (self)` guard;
  assumes `[super init]` can return nil. **Infeasible; structural smell.**

**Recommended repair order / scope**

- Fix **G1 only** — the sole reachable crash — as a single focused task
  (one method; init `lastCell = nil` + early return on getRow miss). It fits
  in one task.
- G2 and G3 are false positives: per the workflow, no defensive change is
  proposed. (`= nil` would only silence the analyzer; not needed.)
- G4 is infeasible; the block-relocation is optional hygiene, unrelated to
  G1, and would be a separate small change if done at all.

### Verification

- Build: Not performed (investigation only).
- Automated verification: Not performed (investigation only) — beyond the
  read-only `xcodebuild analyze` re-run used to gather the findings.
- Manual verification: source inspection of each finding, the rotateMode
  domain, the fixed menu-title set, and the ThumbnailMatrix `-menu` /
  `contextAction:` asymmetry.

### Remaining Issues

None. The single actionable defect (G1) is handed to the fix task; G2/G3 are
false positives; G4 is infeasible.

### Follow-up Suggestions

- Next task: make `ThumbnailController -contextAction:` safe against a
  `getRow` miss (G1). G2–G4 need no code change.

### Process note

The previous investigation ("Investigate crash-prone analyzer findings")
was reported in chat but its root `TASK.md` was left in place instead of
being archived. Per `docs/task-workflow.md`, investigation tasks are
archived like any other; leaving `TASK.md` in place after reporting is a
process error. This archive corrects it; the step should not be repeated.
