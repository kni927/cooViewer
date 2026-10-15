// COPageLabel harness: the page bar's position number, the file-name HUD,
// and the one-time move of the page bar's default height. Foundation only.
// Built and run by run_tests.sh.
//
// Usage: test_pagelabel

#import <Foundation/Foundation.h>
#import "COPageLabel.h"
#include <math.h>

static int failures = 0;
static int checks = 0;

static void check(BOOL ok, NSString *what)
{
    checks++;
    if (!ok) {
        failures++;
        printf("FAIL: %s\n", [what UTF8String]);
    }
}

static void checkString(NSString *got, NSString *want, NSString *what)
{
    BOOL ok = (got == nil && want == nil) || [got isEqualToString:want];
    check(ok, [NSString stringWithFormat:@"%@: got \"%@\", want \"%@\"", what, got, want]);
}

static NSDictionary *barSize(int width, int height)
{
    return [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithInt:width], @"width",
            [NSNumber numberWithInt:height], @"height", nil];
}

static void testPositionString(void)
{
    printf("page bar position\n");
    checkString(COPageBarPositionString(9, 9, 20), @"9/20", @"single page");
    checkString(COPageBarPositionString(9, 10, 20), @"9-10/20", @"spread, reading order");
    checkString(COPageBarPositionString(1, 1, 1), @"1/1", @"one-page book");
    checkString(COPageBarPositionString(19, 20, 20), @"19-20/20", @"last spread");
    checkString(COPageBarPositionString(0, 0, 20), nil, @"page 0");
    checkString(COPageBarPositionString(21, 21, 20), nil, @"past the end");
    checkString(COPageBarPositionString(10, 9, 20), nil, @"reversed");
    checkString(COPageBarPositionString(1, 1, 0), nil, @"empty book");
}

static void testFileNameHUD(void)
{
    printf("file-name HUD\n");
    NSArray *one = [NSArray arrayWithObject:@"009.jpg"];
    NSArray *two = [NSArray arrayWithObjects:@"009.jpg", @"010.jpg", nil];
    NSArray *twoRTL = [NSArray arrayWithObjects:@"010.jpg", @"009.jpg", nil];
    NSArray *sizes2 = [NSArray arrayWithObjects:@"1400x2000", @"1400x2000", nil];

    checkString(COFileNameHUDString(two, sizes2), @"009.jpg (1400x2000) | 010.jpg (1400x2000)",
                @"spread with sizes, both shown even when equal");
    checkString(COFileNameHUDString(twoRTL, sizes2), @"010.jpg (1400x2000) | 009.jpg (1400x2000)",
                @"screen order is the caller's (right-to-left spread)");
    checkString(COFileNameHUDString(two, nil), @"009.jpg | 010.jpg", @"spread without sizes");
    checkString(COFileNameHUDString(one, [NSArray arrayWithObject:@"1400x2000"]), @"009.jpg (1400x2000)",
                @"single page with size");
    checkString(COFileNameHUDString(one, nil), @"009.jpg", @"single page without size");
    checkString(COFileNameHUDString(two, [NSArray arrayWithObjects:[NSNull null], @"800x600", nil]),
                @"009.jpg | 010.jpg (800x600)", @"size unknown for one page");
    checkString(COFileNameHUDString(two, [NSArray arrayWithObject:@"800x600"]),
                @"009.jpg (800x600) | 010.jpg", @"fewer sizes than names");
    checkString(COFileNameHUDString([NSArray array], nil), nil, @"no pages");
    NSString *hud = COFileNameHUDString(two, sizes2);
    check([hud rangeOfString:@"#"].location == NSNotFound, @"no '#' in the HUD");
    check(![hud hasPrefix:@"("], @"no outer parentheses");
}

static void testHeightMigration(void)
{
    printf("page bar height migration\n");
    NSDictionary *migrated = COMigratedPageBarSize(barSize(200, 15));
    check(migrated && [[migrated objectForKey:@"height"] intValue] == COPageBarDefaultHeight &&
          [[migrated objectForKey:@"width"] intValue] == 200,
          @"old default 15 moves to the new default, width kept");
    check(COMigratedPageBarSize(barSize(300, 22)) == nil, @"custom height kept");
    check(COMigratedPageBarSize(barSize(200, 18)) == nil, @"new default left alone");
    check(COMigratedPageBarSize(nil) == nil, @"no PageBarSize");
    check(COMigratedPageBarSize(@"junk") == nil, @"not a dictionary");
    check(COMigratedPageBarSize([NSDictionary dictionaryWithObject:@200 forKey:@"width"]) == nil,
          @"no height");

    /* The store-level migration runs once per profile. */
    NSMutableDictionary *store = [NSMutableDictionary dictionary];
    [store setObject:barSize(250, 15) forKey:@"PageBarSize"];
    check(COMigratePageBarHeight(store) == YES, @"old profile: migrated");
    check([[[store objectForKey:@"PageBarSize"] objectForKey:@"height"] intValue] == COPageBarDefaultHeight &&
          [[[store objectForKey:@"PageBarSize"] objectForKey:@"width"] intValue] == 250,
          @"old profile: height 18, width kept");
    check([store objectForKey:COPageBarHeightMigratedKey] != nil, @"old profile: marker set");

    /* A user who later picks 15 on purpose keeps it. */
    [store setObject:barSize(250, 15) forKey:@"PageBarSize"];
    check(COMigratePageBarHeight(store) == NO &&
          [[[store objectForKey:@"PageBarSize"] objectForKey:@"height"] intValue] == 15,
          @"second run: deliberate 15 kept");

    NSMutableDictionary *custom = [NSMutableDictionary dictionary];
    [custom setObject:barSize(200, 24) forKey:@"PageBarSize"];
    check(COMigratePageBarHeight(custom) == NO &&
          [[[custom objectForKey:@"PageBarSize"] objectForKey:@"height"] intValue] == 24 &&
          [custom objectForKey:COPageBarHeightMigratedKey] != nil,
          @"custom height: kept, marker set");

    NSMutableDictionary *fresh = [NSMutableDictionary dictionary];
    check(COMigratePageBarHeight(fresh) == NO && [fresh objectForKey:@"PageBarSize"] == nil &&
          [fresh objectForKey:COPageBarHeightMigratedKey] != nil,
          @"fresh profile: nothing written but the marker");
}

static BOOL near(double a, double b)
{
    return fabs(a - b) < 0.001;
}

static void testModeTags(void)
{
    printf("PageBarNumber and FileNameLocation values match the Preferences popup tags\n");
    check(COPageBarNumberInBar == 0 && COPageBarNumberOverlay == 1 && COPageBarNumberOff == 2,
          @"In bar 0, Overlay 1, Off 2");
    check(COPageBarNumberTitleBar == 3, @"Title bar 3");
    check(COPageBarNumberModeFromStored(3) == COPageBarNumberTitleBar, @"stored 3 kept");
    check(COPageBarNumberModeFromStored(2) == COPageBarNumberOff, @"stored 2 kept");
    check(COPageBarNumberModeFromStored(4) == COPageBarNumberInBar, @"stored 4 (old Status bar) -> In bar");
    check(COPageBarNumberModeFromStored(-1) == COPageBarNumberInBar, @"stored -1 -> In bar");
    check(COFileNameLocationHUD == 0 && COFileNameLocationStatusBar == 1, @"HUD 0, Status bar 1");
    checkString(COFileNameLocationKey, @"FileNameLocation", @"FileNameLocation key");
}

static void testFileNameEntries(void)
{
    printf("file-name entries\n");
    NSArray *two = [NSArray arrayWithObjects:@"009.jpg", @"010.jpg", nil];
    NSArray *sizes = [NSArray arrayWithObjects:@"1400x2000", [NSNull null], nil];
    NSArray *entries = COFileNameEntries(two, sizes);
    check([entries count] == 2 && [[entries objectAtIndex:0] isEqualToString:@"009.jpg (1400x2000)"]
          && [[entries objectAtIndex:1] isEqualToString:@"010.jpg"], @"per-page entries, size where known");
    entries = COFileNameEntries(two, nil);
    check([entries isEqualToArray:two], @"no sizes: names only");
    check(COFileNameEntries([NSArray array], nil) == nil, @"no pages: nil");
}

static void testTitleBarLayout(void)
{
    printf("title bar layout\n");
    /* View 900 wide, window centre at 430 in view coordinates, name from 4,
       12 between name and number. */
    COTitleBarLayout l = COTitleBarLayoutMake(900, 430, 4, 200, 12, 50);
    check(near(l.nameX, 4) && near(l.nameWidth, 200) && near(l.numberX, 405),
          @"short name left-aligned, number centred");

    l = COTitleBarLayoutMake(900, 430, 4, 389, 12, 50);
    check(near(l.nameWidth, 389) && near(l.numberX, 405), @"name ending exactly at the gap: kept");

    l = COTitleBarLayoutMake(900, 430, 4, 600, 12, 50);
    check(near(l.nameX, 4) && near(l.nameWidth, 389) && near(l.numberX, 405),
          @"long name truncated before the centred number");

    l = COTitleBarLayoutMake(900, 430, 4, 600, 12, 0);
    check(near(l.nameWidth, 600), @"no number: name keeps its width");
    l = COTitleBarLayoutMake(500, 430, 4, 600, 12, 0);
    check(near(l.nameWidth, 496), @"no number: name truncated at the view's end");

    l = COTitleBarLayoutMake(900, 880, 4, 100, 12, 50);
    check(near(l.numberX, 850), @"centre near the right end: number kept within the view");
    l = COTitleBarLayoutMake(900, 10, 4, 100, 12, 50);
    check(near(l.numberX, 0) && near(l.nameWidth, 0), @"centre near the left end: number at 0, no name");
}

static void testStatusBarLayout(void)
{
    printf("status bar layout\n");
    check(near(COStatusBarHeight(14), 18), @"height = text + 4");
    check(near(COStatusBarHeight(13.2), 18), @"text height rounded up");

    /* Bar 800 wide, 6 padding, 16 gap. */
    COStatusBarLayout l = COStatusBarLayoutMake(800, 6, 16, 1, 0, 800, 200, 0, 0, 0);
    check(near(l.leftX, 300) && near(l.leftWidth, 200), @"single page filling the bar: centred");
    l = COStatusBarLayoutMake(800, 6, 16, 1, 100, 500, 200, 0, 0, 0);
    check(near(l.leftX, 200) && near(l.leftWidth, 200), @"single page offset: centred under the page");
    l = COStatusBarLayoutMake(800, 6, 16, 1, 600, 900, 300, 0, 0, 0);
    check(near(l.leftX, 494) && near(l.leftWidth, 300), @"single page partly past the end: kept inside the bar");
    l = COStatusBarLayoutMake(800, 6, 16, 1, 0, 800, 1000, 0, 0, 0);
    check(near(l.leftX, 6) && near(l.leftWidth, 788), @"single long entry truncated to the bar");

    /* Spread: pages 100..400 and 400..700, shared edge 400. */
    l = COStatusBarLayoutMake(800, 6, 16, 2, 100, 400, 100, 400, 700, 120);
    check(near(l.leftX, 200) && near(l.leftWidth, 100) && near(l.rightX, 490) && near(l.rightWidth, 120),
          @"spread: each entry centred under its page");
    l = COStatusBarLayoutMake(800, 6, 16, 2, 100, 400, 500, 400, 700, 120);
    check(near(l.leftX, 100) && near(l.leftWidth, 292) && near(l.rightX, 490),
          @"long left entry truncated within its page, gap kept");
    l = COStatusBarLayoutMake(800, 6, 16, 2, 100, 400, 100, 400, 700, 500);
    check(near(l.rightX, 408) && near(l.rightWidth, 292) && near(l.leftX, 200),
          @"long right entry truncated within its page, gap kept");
    l = COStatusBarLayoutMake(800, 6, 16, 2, 100, 400, 280, 400, 700, 280);
    check(near(l.leftX, 110) && near(l.rightX, 410), @"wide entries: centred, still apart");
    check(l.leftX + l.leftWidth + 16 <= l.rightX + 0.001, @"never closer than the gap");

    /* Unequal pages: 0..300 and 300..800 (edge 300). */
    l = COStatusBarLayoutMake(800, 6, 16, 2, 0, 300, 100, 300, 800, 100);
    check(near(l.leftX, 100) && near(l.rightX, 500), @"unequal pages: each under its own centre");

    /* Pages scrolled past the bar's ends (zoomed): kept inside the bar. */
    l = COStatusBarLayoutMake(800, 6, 16, 2, -400, 400, 200, 400, 1200, 200);
    check(near(l.leftX, 6) && near(l.rightX, 594), @"pages past the ends: entries inside the bar");

    /* No usable page rects (stacked by rotation, or none): the halves. */
    l = COStatusBarLayoutMake(800, 6, 16, 2, 100, 700, 100, 100, 700, 100);
    check(near(l.leftX, 150) && near(l.rightX, 550), @"stacked pages: halves of the bar");
    l = COStatusBarLayoutMake(800, 6, 16, 2, 0, 0, 100, 0, 0, 100);
    check(near(l.leftX, 150) && near(l.rightX, 550), @"no rects: halves of the bar");

    l = COStatusBarLayoutMake(20, 6, 16, 2, 0, 10, 100, 10, 20, 100);
    check(near(l.leftWidth, 0) && near(l.rightWidth, 0), @"too narrow: nothing drawn");
}

static void testBottomOffsets(void)
{
    printf("page bar lift and bottom HUD offsets\n");
    check(near(COPageBarStatusBarLift(2, 18), 18), @"bottom-left bar lifted");
    check(near(COPageBarStatusBarLift(3, 18), 18), @"bottom-right bar lifted");
    check(near(COPageBarStatusBarLift(0, 18), 0), @"top bar not lifted");
    check(near(COPageBarStatusBarLift(2, 0), 0), @"no status bar: no lift");

    /* Without a status bar: the values Part 1 had. */
    check(near(COBottomHUDOffset(COPageBarNumberOff, 2, 15, 14, 0), 17), @"Off, 15 px bottom bar: 17");
    check(near(COBottomHUDOffset(COPageBarNumberOff, 0, 30, 14, 0), 17), @"top bar: 17");
    check(near(COBottomHUDOffset(COPageBarNumberOff, 2, 18, 14, 0), 20), @"Off, 18 px bar: 20");
    check(near(COBottomHUDOffset(COPageBarNumberOverlay, 2, 18, 14, 0), 35), @"Overlay: above the number");
    check(near(COBottomHUDOffset(COPageBarNumberInBar, 2, 18, 14, 0), 20), @"In bar, text within the bar");
    check(near(COBottomHUDOffset(COPageBarNumberInBar, 2, 10, 20, 0), 17), @"In bar, short bar: text clear");
    check(near(COBottomHUDOffset(COPageBarNumberInBar, 2, 10, 30, 0), 22), @"In bar, tall text");
    check(near(COBottomHUDOffset(COPageBarNumberTitleBar, 2, 18, 14, 0), 20), @"Title bar mode: bar only");

    /* With an 18 px status bar: the HUD (offset + 2) clears it by 1 px, or
       the bottom bar raised onto it. */
    check(near(COBottomHUDOffset(COPageBarNumberOff, 0, 18, 14, 18), 17), @"status, top bar: 17 (HUD from 19)");
    check(near(COBottomHUDOffset(COPageBarNumberOff, 0, 18, 14, 28), 27), @"tall status bar: cleared");
    check(near(COBottomHUDOffset(COPageBarNumberOff, 2, 18, 14, 18), 38), @"status + bottom bar");
    check(near(COBottomHUDOffset(COPageBarNumberOverlay, 2, 18, 14, 18), 53), @"status + bottom bar + overlay number");
    check(near(COBottomHUDOffset(COPageBarNumberInBar, 2, 18, 14, 18), 38), @"status + bottom bar, number in it");
}

static void testInBarFontSize(void)
{
    printf("in-bar number size follows the bar height\n");
    check(near(COPageBarInBarFontSize(18, 1.2), 12.5), @"18 px bar (default): 12.5 pt");
    check(near(COPageBarInBarFontSize(15, 1.2), 10), @"15 px bar: 10 pt");
    check(near(COPageBarInBarFontSize(30, 1.2), 22.5), @"30 px bar: 22.5 pt");
    check(COPageBarInBarFontSize(40, 1.2) > COPageBarInBarFontSize(20, 1.2), @"taller bar, larger number");
    check(near(COPageBarInBarFontSize(5, 1.2), 6), @"very short bar: 6 pt minimum");
    check(near(COPageBarInBarFontSize(18, 0), 12.5), @"no metrics: 1.2 assumed");
    double size = COPageBarInBarFontSize(24, 1.19);
    check(size * 1.19 <= 24 - 3 + 0.0001, @"line fits inside the bar");
}

static void testTitleBarFill(void)
{
    printf("title-bar fill and centred name\n");
    COTitleBarFill f = COTitleBarFillMake(800, 0.25, YES);
    check(near(f.x, 0) && near(f.width, 200), @"left to right: from the left edge");
    f = COTitleBarFillMake(800, 0.25, NO);
    check(near(f.x, 600) && near(f.width, 200), @"right to left: from the right edge");
    f = COTitleBarFillMake(800, 1, NO);
    check(near(f.x, 0) && near(f.width, 800), @"last page: the whole span");
    f = COTitleBarFillMake(800, 0, YES);
    check(near(f.width, 0), @"no position: nothing filled");
    f = COTitleBarFillMake(800, 1.5, YES);
    check(near(f.width, 800), @"fraction above 1: clamped");
    f = COTitleBarFillMake(800, -0.5, NO);
    check(near(f.width, 0) && near(f.x, 800), @"negative fraction: nothing filled");
    f = COTitleBarFillMake(801, 1.0/3, YES);
    check(near(f.width, 267), @"whole points");
    f = COTitleBarFillMake(-5, 0.5, YES);
    check(near(f.width, 0), @"negative width: nothing filled");

    COTitleBarLayout l = COTitleBarCentredNameLayout(900, 430, 4, 200);
    check(near(l.nameX, 330) && near(l.nameWidth, 200), @"name centred on the window");
    l = COTitleBarCentredNameLayout(900, 50, 4, 200);
    check(near(l.nameX, 4) && near(l.nameWidth, 200), @"centre near the buttons: kept after them");
    l = COTitleBarCentredNameLayout(900, 880, 4, 200);
    check(near(l.nameX, 700), @"centre near the right end: kept within the view");
    l = COTitleBarCentredNameLayout(300, 150, 4, 500);
    check(near(l.nameX, 4) && near(l.nameWidth, 296), @"long name: narrowed to the view");
}

static void testStatusBarOpacity(void)
{
    printf("status bar opacity\n");
    check(COStatusBarDefaultOpacity == 80, @"default 80 %, the default colours' alpha");
    check(near(COStatusBarAlpha(COStatusBarDefaultOpacity), 0.8), @"default: alpha 0.8, the look before the setting");
    check(near(COStatusBarAlpha(100), 1), @"100 %: opaque");
    check(near(COStatusBarAlpha(0), 0), @"0 %: no background");
    check(near(COStatusBarAlpha(35), 0.35), @"35 %");
    check(near(COStatusBarAlpha(-10), 0), @"below 0: clamped");
    check(near(COStatusBarAlpha(250), 1), @"above 100: clamped");
    checkString(COStatusBarOpacityKey, @"StatusBarOpacity", @"key name");
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        testTitleBarFill();
        testPositionString();
        testFileNameHUD();
        testHeightMigration();
        testModeTags();
        testFileNameEntries();
        testTitleBarLayout();
        testStatusBarLayout();
        testBottomOffsets();
        testInBarFontSize();
        testStatusBarOpacity();
        if (failures == 0) {
            printf("\nALL PASS (%d checks)\n", checks);
            return 0;
        }
        printf("\n%d FAILED of %d checks\n", failures, checks);
        return 1;
    }
}
