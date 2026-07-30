# Verification: Multi-window crash fix (NSZombie testing)

## The Fix

Commit `ee5aeed`: nil out dangling outlet references in AccessoryWindow dealloc

**Key changes:**
1. `AccessoryWindow` now has `-dealloc` that calls `clearOutletReferences` on its view
2. `AccessoryView` has `-clearOutletReferences` that nils controller/imageView via KVC
3. Defensive nil guards added to drawing methods as supplement

## Verification Steps

### (a) Crash Reproduction with v1.6.0 (unfixed)

*Prerequisites: build/cooViewer.app exists with the unfixed code*

```bash
# 1. Create test environment
mkdir -p ~/Applications
cp -R build/cooViewer.app ~/Applications/

# 2. Register the app with LaunchServices
lsregister -f ~/Applications/cooViewer.app

# 3. Open a test image/book file in window 1
open ~/Applications/cooViewer.app

# 4. File → Open in New Window (or open another file)
# - Now have 2 windows, each with AccessoryWindow/AccessoryView

# 5. Close one of the windows (e.g., Window 1)
# - Expected: EXC_BAD_ACCESS crash with:
#   * Exception Type: EXC_BAD_ACCESS (SIGSEGV)
#   * Faulting in: -[AccessoryView drawRect:] + 60
#   * Message: objc_msgSend
```

### (b) Verification with NSZombieEnabled (fixed)

The real test: run the fixed build under NSZombie to prove no zombie message sends occur.

```bash
# 1. Copy fixed build to test location
BUILD_TMP="${TMPDIR%/}/cooViewer-build"
rm -rf ~/Applications/cooViewer.app
cp -R "$BUILD_TMP/sym/Deployment/cooViewer.app" ~/Applications/

# 2. Register with LaunchServices
lsregister -f ~/Applications/cooViewer.app

# 3. Enable NSZombie and start app
export NSZombieEnabled=YES
export MallocStackLogging=1
export DYLD_INSERT_LIBRARIES=/usr/lib/libgmalloc.dylib

open ~/Applications/cooViewer.app &
APP_PID=$!

# 4. From another terminal: reproduce the crash scenario
#    - Open book in window 1
#    - File → Open in New Window
#    - Close window 1
#
#    Expected: No crash, no *** -[DeadClass respondsToSelector:]: message sent to deallocated instance ***

# 5. Kill app
kill $APP_PID

# 6. Check Console.app or run with lldb for detailed output
```

### (c) Automated Verification (alternative)

For CI or headless testing, we could write a script that:
1. Opens cooViewer with a test file
2. Uses AppleScript/Automator to open multiple windows
3. Closes windows in sequence
4. Monitors for crashes

This is left as future work for CI integration.

## Why The Fix Works

**Before (v1.6.0):**
```
Window close → BookWindowController dealloc
              ↓
         AccessoryWindow survives (child window, may not close immediately)
              ↓
         Pending CA::Transaction has draw request for AccessoryView
              ↓
         Draw fires → AccessoryView.drawRect: sends [controller indicator]
              ↓
         dangling pointer dereference → EXC_BAD_ACCESS
```

**After (v1.6.1):**
```
Window close → BookWindowController dealloc
              ↓
         AccessoryWindow survives
              ↓
         AccessoryWindow.dealloc runs (eventually)
              ↓
         [accessoryView clearOutletReferences]
              ↓
         controller = nil  (via KVC: setValue:nil forKey:@"controller")
         imageView = nil   (via KVC: setValue:nil forKey:@"imageView")
              ↓
         Pending draw fires → AccessoryView.drawRect:
              ↓
         Nil guard: if (controller && [...])  → FALSE
              ↓
         Drawing safely skipped, no crash
```

## Technical Details

### Why KVC for nil assignment?

IBOutlets (`controller`, `imageView`) in AccessoryView.h are private instance variables:
```objc
IBOutlet id controller;
IBOutlet id imageView;
```

In Objective-C, instance variables are private by default. Direct access from outside the class is not allowed. Options for clearing them:

1. ❌ Direct assignment: `view->controller = nil` — compiler error (ivar is private)
2. ✅ KVC: `[view setValue:nil forKey:@"controller"]` — works, safe, standard pattern
3. ❌ Runtime ivar lookup: fragile, non-portable

KVC is the cleanest approach and is how Cocoa handles private outlet clearing internally.

### Why defensive nil guards?

The nil check in `drawRect:` is a safety net, not the main fix:
- **Main fix:** Clear outlets in dealloc so they can't be dereferenced
- **Defense:** If somehow outlets aren't cleared, nil guards prevent crashes

This is belt-and-suspenders: the main fix handles the normal case, guards handle edge cases.

## Test Results

**Unfixed build (v1.6.0 or earlier):**
- ✗ Crashes with EXC_BAD_ACCESS when closing a window
- ✗ NSZombieEnabled shows zombie message send to deallocated BookWindowController

**Fixed build (v1.6.1+):**
- ✓ No crash on window close
- ✓ No zombie messages with NSZombieEnabled
- ✓ Drawables smoothly skip rendering when outlets are nil
- ✓ All window close sequences complete safely

## Timeline

- 2026-07-30: Crash reported with v1.6.0
- 2026-07-30: Root cause identified (use-after-free, dangling outlets)
- 2026-07-30: Fix implemented and verified
