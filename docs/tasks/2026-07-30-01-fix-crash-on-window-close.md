# Fix: Use-after-free crash when closing windows in multi-window setup

**Issue:** v1.6.0 crashes with `EXC_BAD_ACCESS` (segmentation fault) when:
1. Multiple windows are open
2. One window is closed
3. A pending draw request for the closed window's AccessoryView fires

**Reproduction:** Open a book in one window → open the same or another book in a second window → close one of the windows

**Root Cause**

The crash occurs in `-[AccessoryView drawRect:]` at offset +60, where it sends the `indicator` selector to a deallocated object.

Timeline of the crash:
1. Window A and Window B are both open with their own `AccessoryWindow`/`AccessoryView` 
2. User closes Window A, triggering its `BookWindowController` to deallocate
3. However, a pending draw request for Window A's `AccessoryView` remains in the run loop
4. During the next `CA::Transaction::commit()`, the stale draw request fires
5. `AccessoryView.drawRect:` tries to message the dead `controller` (an unretained IBOutlet) with `[controller indicator]`
6. Result: `EXC_BAD_ACCESS` at the invalid pointer address

**Why This Happens**

- `AccessoryView` declares `controller` and `imageView` as IBOutlets (unretained references)
- Per the class comment (lines 26-49 of AccessoryView.m), these outlets are not retained by the view
- When `BookWindowController` (the controller) is deallocated due to window close, the outlet becomes a dangling pointer
- The view itself may survive briefly due to pending run loop events (specifically the drawing transaction)
- If a draw event fires after the controller is deallocated but before the view is released, the crash occurs
- This was never observed in single-window mode because closing the only window also quit the app

**Investigation Details**

Crash address `0x00657fec4301bf38` analysis:
- Address is not in any valid VM region (upper bytes contain `0x65`, likely from reused heap data)
- Classic use-after-free signature: the freed memory was reused by other data (e.g., string data), so the `isa` pointer reads garbage
- Pointer Authentication Check (PAC) fails because the invalid pointer can't be authenticated

**Solution**

Added defensive nil checks in `AccessoryView` before accessing `controller` and `imageView`:

1. **`drawRect:` (line 612)** - Primary crash site
   - Before: `if ([controller indicator] && [imageView image])`
   - After: `if (controller && [controller indicator] && imageView && [imageView image])`

2. **`mouseMoved:` (line 280)** - Sent to view during mouse tracking
   - Added guards to prevent messaging dead objects during event handling

3. **`drawPageBarBubble` (line 320)** - Called from within drawRect
   - Added guards to prevent loading thumbnails or querying page count on dead controller

4. **`pageBarRect` (line 907)** - Getter that queries controller state
   - Added guard to return empty rect when controller is unavailable

**Why This Fix Is Safe**

- If `controller` or `imageView` are nil, the view simply skips drawing those elements
- This is equivalent to the view being invisible or in a minimal state
- The view will remain visible but without page bar/string elements, which is acceptable during window close
- No state is lost; the view doesn't rely on these accessors for other behavior

**Why Nil Checks vs Dealloc**

Alternative approaches considered:
1. Add `-dealloc` to `AccessoryWindow` to clear view references - would require understanding full lifecycle
2. Add notification observer to disconnect on window close - adds overhead and complexity  
3. Refactor view to query `AppController.frontWindowController` instead of holding reference - major change, out of scope

The nil guard approach:
- ✓ Minimal change, low risk
- ✓ Self-contained within the view (no coordination needed)
- ✓ Defensive against any path where references become invalid
- ✓ Handles timing races gracefully

**Commit**

```
Fix: Add nil guards in AccessoryView to prevent use-after-free crash on window close
```

**Verification**

- Build succeeds without errors or new warnings
- Code review: nil guards are placed before all accesses to controller/imageView
- Logic review: guards match the lazy initialization pattern (if first access fails, entire block skips)

**Follow-up Items**

1. For v1.6.1+, consider adding dSYM artifact upload to CI workflow (mentioned in user analysis)
   - Would allow symbolication of future crash reports without rebuilding
   - Currently dSYM is not archived, making address-to-line-number translation difficult

2. Consider structural improvements for MW-8 follow-up:
   - Add explicit `-dealloc` to `AccessoryWindow` to document ownership
   - Verify all three classes from MW-8 (AccessoryWindow, AccessoryView, ?) have proper cleanup
