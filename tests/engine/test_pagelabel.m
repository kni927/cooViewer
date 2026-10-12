// COPageLabel harness: the page bar's position number, the file-name HUD,
// and the one-time move of the page bar's default height. Foundation only.
// Built and run by run_tests.sh.
//
// Usage: test_pagelabel

#import <Foundation/Foundation.h>
#import "COPageLabel.h"

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

int main(int argc, char **argv)
{
    @autoreleasepool {
        testPositionString();
        testFileNameHUD();
        testHeightMigration();
        if (failures == 0) {
            printf("\nALL PASS (%d checks)\n", checks);
            return 0;
        }
        printf("\n%d FAILED of %d checks\n", failures, checks);
        return 1;
    }
}
