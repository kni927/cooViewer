# Fix: Use-after-free crash when closing windows in multi-window setup

**STATUS: FIXED (commit ee5aeed)**

## Issue

v1.6.0 crashes with `EXC_BAD_ACCESS` (segmentation fault) when:
1. Multiple windows are open
2. One window is closed
3. A pending draw request for the closed window's AccessoryView fires

**Reproduction:** Open a book in one window → open the same or another book in a second window → close one of the windows

## Root Cause Analysis

The crash occurs in `-[AccessoryView drawRect:]` at offset +60, where it sends the `indicator` selector to a deallocated object.

### Timeline of the Crash

1. Window A and Window B are both open with their own `AccessoryWindow`/`AccessoryView` 
2. User closes Window A, triggering its `BookWindowController` to deallocate
3. However, a pending draw request for Window A's `AccessoryView` remains in the run loop
4. During the next `CA::Transaction::commit()`, the stale draw request fires
5. `AccessoryView.drawRect:` tries to message the dead `controller` (an unretained IBOutlet) with `[controller indicator]`
6. Result: `EXC_BAD_ACCESS` at the invalid pointer address

### Why IBOutlets Matter

- `AccessoryView` declares `controller` and `imageView` as IBOutlets (unretained references)
- Per the class comment (lines 26-49 of AccessoryView.m), these outlets are not retained by the view
- When `BookWindowController` (the controller) is deallocated due to window close, the outlet becomes a **dangling pointer**
- The pointer value is stale heap memory, not nil
- When a draw event fires after the controller is deallocated but before the view is released, the crash occurs
- This was never observed in single-window mode because closing the only window also quit the app

### Crash Address Analysis

Crash address `0x00657fec4301bf38`:
- ✗ NOT nil (would crash differently)
- ✓ Not in any valid VM region (upper bytes contain `0x65` = 'e' from reused heap data)
- ✓ Classic use-after-free: freed memory was reused by other data (e.g., string data)
- ✓ Pointer Authentication Check (PAC) fails because the invalid pointer can't be authenticated

**This is why nil guards alone cannot prevent this crash — the pointer is never nil.**

## The Fix (Commit ee5aeed)

### Main Fix: Clear Dangling Pointers in dealloc

**AccessoryWindow.m** — Add `-dealloc`:
```objc
- (void)dealloc
{
	AccessoryView *view = (AccessoryView *)[self contentView];
	if ([view isKindOfClass:[AccessoryView class]]) {
		[view clearOutletReferences];
	}
	[super dealloc];
}
```

**AccessoryView.m** — Add `-clearOutletReferences`:
```objc
- (void)clearOutletReferences
{
	[self setValue:nil forKey:@"controller"];
	[self setValue:nil forKey:@"imageView"];
}
```

**Why KVC for nil assignment?**

IBOutlets in AccessoryView.h are private instance variables:
```objc
IBOutlet id controller;
IBOutlet id imageView;
```

In Objective-C, instance variables are private by default. Options for clearing them:
1. ❌ Direct assignment: `view->controller = nil` — compiler error (private ivar)
2. ✅ **KVC**: `[view setValue:nil forKey:@"controller"]` — works, safe, standard Cocoa pattern
3. ❌ Runtime ivar lookup: fragile, non-portable

### Defensive Supplement: Nil Guards

Added nil checks in drawing methods as a safety net:
```objc
// Before: if ([controller indicator] && [imageView image])
// After:  if (controller && [controller indicator] && imageView && [imageView image])
```

Updated in:
- `drawRect:` (line 612) — primary crash site
- `mouseMoved:` (line 280)  
- `drawPageBarBubble` (line 320)
- `pageBarRect` (line 907)

These guards are **not the main fix** — they're a safety net. If somehow outlets aren't cleared, guards prevent dereferencing null values.

## How It Works

### Before (v1.6.0)
```
Window close → BookWindowController dealloc
              ↓
         AccessoryWindow survives (child window)
              ↓
         Pending draw request exists in CA::Transaction
              ↓
         Draw fires → [controller indicator]  (dangling pointer)
              ↓
         EXC_BAD_ACCESS crash
```

### After (v1.6.1+)
```
Window close → BookWindowController dealloc
              ↓
         AccessoryWindow survives but will eventually dealloc
              ↓
         AccessoryWindow.dealloc runs
              ↓
         [accessoryView clearOutletReferences]
              ↓
         controller = nil  (via KVC)
         imageView = nil   (via KVC)
              ↓
         Pending draw fires → drawRect:
              ↓
         Nil guard: if (controller && ...) → FALSE (short-circuit)
              ↓
         Drawing safely skipped, no crash
```

When outlets are nil, the view draws without page bar/info elements — acceptable during window close.

## Verification

See `docs/tasks/2026-07-30-02-crash-fix-verification.md` for complete NSZombie testing procedure.

**Key verification points:**
1. **Unfixed build**: Crashes reliably when closing a window
2. **Fixed build**: No crash on window close
3. **With NSZombieEnabled**: No zombie message sends to deallocated objects

## Implementation Details

- ✅ Build succeeds without errors or new warnings
- ✅ Code uses standard Cocoa patterns (KVC, dealloc cleanup)
- ✅ Minimal changes, low risk
- ✅ Defensive nil guards provide extra safety

## Follow-up Items

1. **For v1.6.1 release:**
   - Add dSYM artifact upload to CI workflow (allows future crash symbolication)
   - Currently dSYM is not archived, making address→line translation difficult

2. **For MW-8 completion:**
   - Verify all classes identified in MW-8 have proper cleanup
   - AccessoryWindow now has -dealloc as intended
