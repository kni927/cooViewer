// COImageLoader harness: book-level behaviour on top of COArchive (page
// lists, nested archives). Built and run by run_tests.sh after the COArchive
// harness; links AppKit because COImageLoader returns NSImage pages.
//
// Usage: test_imageloader <generated-fixtures-dir>

#import <Cocoa/Cocoa.h>
#import "COImageLoader.h"
#import "COBookReadLane.h"
#include <objc/runtime.h>

// COImageLoader extracts nested archives under NSTemporaryDirectory(), which
// is the per-user /var/folders/…/T even when $TMPDIR points elsewhere — and a
// sandboxed run (an agent session) cannot write there. A definition in this
// object file takes precedence over Foundation's at link time, so the loader
// under test uses $TMPDIR instead; outside a sandbox the two are the same.
NSString *NSTemporaryDirectory(void)
{
    const char *tmp = getenv("TMPDIR");
    return tmp ? [NSString stringWithUTF8String:tmp] : @"/tmp";
}

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

static COImageLoader *loaderFor(NSString *dir, NSString *name)
{
    NSString *path = [dir stringByAppendingPathComponent:name];
    return [[[COImageLoader alloc] initWithPath:path readSubFolder:NO controller:nil] autorelease];
}

// A host that reads the archive itself (KNOWN_ISSUES #33, the loading half).
static COImageLoader *deferredLoaderFor(NSString *path, id controller)
{
    return [[[COImageLoader alloc] initWithPath:path
                                    displayPath:path
                                  readSubFolder:NO
                                     controller:controller
                            deferPasswordPrompt:YES
                               deferArchiveRead:YES] autorelease];
}

// -readArchive on a worker thread, as the window controller runs it; returns
// once it has.
static void readOnWorkerThread(COImageLoader *loader)
{
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [loader readArchive];
        dispatch_semaphore_signal(done);
    });
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    dispatch_release(done);
}

// A controller whose progress callback cancels the read, as the progress
// sheet's Cancel button does through -[BookWindowController
// archiveReadProgress:total:]. Counts the calls, so a test can tell that a
// read really was cancelled from the callback rather than never reported.
@interface CancellingController : NSObject {
@public
    _Atomic int calls;
}
- (BOOL)archiveReadProgress:(long long)done total:(long long)total;
@end

@implementation CancellingController
- (BOOL)archiveReadProgress:(long long)done total:(long long)total
{
    atomic_fetch_add(&calls, 1);
    return NO;
}
@end

static int pixelsWide(NSImage *image)
{
    return (int)[[[image representations] firstObject] pixelsWide];
}

// --- KNOWN_ISSUES #46: the book read lane and the display planner ---

// Runs the main run loop (where the lane delivers) until `done` answers YES
// or `timeout` seconds have passed; answers `done`'s last answer.
static BOOL spinUntil(BOOL (^done)(void), NSTimeInterval timeout)
{
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!done() && [deadline timeIntervalSinceNow] > 0) {
        @autoreleasepool {
            [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode
                                  beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
    }
    return done();
}

static void spinFor(NSTimeInterval seconds)
{
    spinUntil(^BOOL{ return NO; }, seconds);
}

// A loader that counts the threads inside -itemAtIndex: at once.
@interface CountingLoader : COImageLoader {
@public
    _Atomic int inside;
    _Atomic int maxInside;
    _Atomic int calls;
}
@end

@implementation CountingLoader
- (id)itemAtIndex:(int)index
{
    int now = atomic_fetch_add(&inside, 1) + 1;
    int seen = atomic_load(&maxInside);
    while (seen < now && !atomic_compare_exchange_weak(&maxInside, &seen, now)) {}
    atomic_fetch_add(&calls, 1);
    usleep(2000);
    id image = [super itemAtIndex:index];
    atomic_fetch_sub(&inside, 1);
    return image;
}
@end

// A loader that returns nothing for page 1.
@interface NilPageLoader : COImageLoader
@end

@implementation NilPageLoader
- (id)itemAtIndex:(int)index
{
    return index == 1 ? nil : [super itemAtIndex:index];
}
@end

static NSString *planString(CODisplayPlan plan)
{
    NSMutableString *out = [NSMutableString string];
    switch (plan.kind) {
        case CODisplayPlanNothing: return @"nothing";
        case CODisplayPlanNextBook: return @"nextbook";
        case CODisplayPlanPrevBook: return @"prevbook";
        case CODisplayPlanPrevBookLast: return @"prevbooklast";
        default: break;
    }
    [out appendString:@"{"];
    int i;
    for (i = 0; i < plan.pageCount; i++) {
        [out appendFormat:@"%@%d", i ? @"," : @"", plan.pages[i]];
    }
    [out appendString:@"}"];
    if (plan.probe >= 0) [out appendFormat:@"+%d", plan.probe];
    return out;
}

static CODisplayState st(int nowPage, int count, int shown, int spread, int single, int loop)
{
    CODisplayState s;
    s.nowPage = nowPage; s.count = count; s.shown = shown;
    s.spreadShown = spread; s.singleMode = single; s.loopCheck = loop;
    return s;
}

static void expectPlan(CODisplayAction action, CODisplayState s, int arg, NSString *expected, NSString *what)
{
    NSString *got = planString(CODisplayPlanFor(action, s, arg));
    check([got isEqualToString:expected],
          [NSString stringWithFormat:@"plan %@: expected %@, got %@", what, expected, got]);
}

static void testDisplayPlans(void)
{
    printf("display plans\n");
    // next: the page, and in spread mode the next one if the first is small
    expectPlan(CODisplayNext, st(3,10,1,0,0,0), 0, @"{3}+3", @"next spread");
    expectPlan(CODisplayNext, st(3,10,1,0,1,0), 0, @"{3}", @"next single");
    expectPlan(CODisplayNext, st(9,10,1,0,0,0), 0, @"{9}", @"next spread, last page");
    expectPlan(CODisplayNext, st(10,10,1,0,0,0), 0, @"{0,1}", @"next at end, loop");
    expectPlan(CODisplayNext, st(10,10,1,0,0,1), 0, @"nextbook", @"next at end, next book");
    expectPlan(CODisplayNext, st(10,10,1,0,0,2), 0, @"nextbook", @"next at end, next book (2)");
    expectPlan(CODisplayNext, st(10,10,1,0,0,3), 0, @"{}", @"next at end, stop");
    expectPlan(CODisplayNext, st(10,1,1,0,0,0), 0, @"nothing", @"next past the end");
    expectPlan(CODisplayNext, st(0,0,0,0,0,0), 0, @"nothing", @"no pages");
    // prev
    expectPlan(CODisplayPrev, st(5,10,1,0,1,0), 0, @"{3,4}", @"prev single");
    expectPlan(CODisplayPrev, st(1,10,1,0,1,0), 0, @"{9}", @"prev single at start, loop");
    expectPlan(CODisplayPrev, st(1,10,1,0,1,1), 0, @"prevbook", @"prev single at start, book");
    expectPlan(CODisplayPrev, st(1,10,1,0,1,2), 0, @"prevbooklast", @"prev single at start, book last");
    expectPlan(CODisplayPrev, st(1,10,1,0,1,3), 0, @"nothing", @"prev single at start, stop");
    expectPlan(CODisplayPrev, st(1,10,1,0,0,0), 0, @"{8,9}", @"prev one page at start, loop");
    expectPlan(CODisplayPrev, st(1,1,1,0,0,0), 0, @"{0}", @"prev one-page book, loop");
    expectPlan(CODisplayPrev, st(2,10,1,0,0,0), 0, @"{0,1}", @"prev one page at 2");
    expectPlan(CODisplayPrev, st(5,10,1,0,0,0), 0, @"{2,3,4}", @"prev one page");
    expectPlan(CODisplayPrev, st(2,10,1,1,0,0), 0, @"{8,9}", @"prev spread at start, loop");
    expectPlan(CODisplayPrev, st(2,10,1,1,0,3), 0, @"nothing", @"prev spread at start, stop");
    expectPlan(CODisplayPrev, st(3,10,1,1,0,0), 0, @"{0,1,2}", @"prev spread at 3");
    expectPlan(CODisplayPrev, st(6,10,1,1,0,0), 0, @"{2,3,4,5}", @"prev spread");
    // half steps
    expectPlan(CODisplayHalfNext, st(4,10,1,1,0,0), 0, @"{3}+3", @"halfnext from spread");
    expectPlan(CODisplayHalfNext, st(4,10,1,0,0,0), 0, @"{4}+4", @"halfnext from one page");
    expectPlan(CODisplayHalfNext, st(10,10,1,1,0,1), 0, @"nextbook", @"halfnext at end");
    expectPlan(CODisplayHalfPrev, st(5,10,1,1,0,0), 0, @"{2,3}", @"halfprev spread");
    expectPlan(CODisplayHalfPrev, st(2,10,1,1,0,0), 0, @"{8,9}", @"halfprev spread at start");
    expectPlan(CODisplayHalfPrev, st(1,10,1,0,0,0), 0, @"{9}", @"halfprev one page at start");
    expectPlan(CODisplayHalfPrev, st(5,10,1,0,0,0), 0, @"{2,3,4}", @"halfprev one page");
    expectPlan(CODisplayHalfPrev, st(5,10,1,0,1,0), 0, @"{3,4}", @"halfprev single");
    // jumps
    expectPlan(CODisplayLast, st(3,10,1,0,1,0), 0, @"{9}", @"last single");
    expectPlan(CODisplayLast, st(3,10,1,0,0,0), 0, @"{8,9}", @"last spread");
    expectPlan(CODisplayLast, st(10,10,1,0,0,0), 0, @"nothing", @"last at end");
    expectPlan(CODisplayLast, st(0,1,0,0,0,0), 0, @"{0}", @"last one-page book");
    expectPlan(CODisplayTop, st(2,10,1,1,0,0), 0, @"nothing", @"top on first spread");
    expectPlan(CODisplayTop, st(3,10,1,1,0,0), 0, @"{0}+0", @"top from spread");
    expectPlan(CODisplayTop, st(1,10,1,0,0,0), 0, @"nothing", @"top on first page");
    expectPlan(CODisplayTop, st(5,10,0,0,0,0), 0, @"{0}+0", @"top with nothing shown");
    expectPlan(CODisplayFirst, st(1,10,1,0,1,0), 0, @"{0}", @"first single");
    expectPlan(CODisplayGoTo, st(1,10,1,0,0,0), -5, @"{0}+0", @"goto below 0");
    expectPlan(CODisplayGoTo, st(1,10,1,0,0,0), 99, @"{9}", @"goto past the end");
    expectPlan(CODisplayGoTo, st(1,10,1,0,0,0), 4, @"{4}+4", @"goto");
    // skips
    expectPlan(CODisplaySkip, st(4,10,1,0,0,0), 10, @"{8,9}", @"skip past the end");
    expectPlan(CODisplaySkip, st(4,10,1,0,0,0), 4, @"{6,7,8}", @"skip");
    expectPlan(CODisplaySkip, st(1,10,1,0,0,0), 1, @"{0,1,2}", @"skip clamped at 0");
    expectPlan(CODisplayBackSkip, st(8,10,1,0,0,0), 4, @"{2,3}", @"backskip");
    expectPlan(CODisplayBackSkip, st(8,10,1,0,0,0), 10, @"{0,1}", @"backskip clamped");
    // spread switch and re-layout
    expectPlan(CODisplaySwitchSingle, st(6,10,1,1,0,0), 0, @"{}", @"switch from spread");
    expectPlan(CODisplaySwitchSingle, st(10,10,1,0,0,0), 0, @"{}", @"switch on last page");
    expectPlan(CODisplaySwitchSingle, st(4,10,1,0,0,0), 0, @"{4}", @"switch to spread");
    expectPlan(CODisplayRedisplay, st(6,10,1,1,0,0), 0, @"{4,5}", @"relayout spread");
    expectPlan(CODisplayRedisplay, st(6,10,1,0,0,0), 0, @"{5}+5", @"relayout one page");
    expectPlan(CODisplayRedisplay, st(6,10,1,0,1,0), 0, @"{5}", @"relayout single");
    expectPlan(CODisplayRedisplay, st(6,10,0,0,0,0), 0, @"nothing", @"relayout, nothing shown");
    expectPlan(CODisplayOpenLast, st(8,10,0,0,1,0), 0, @"{8,9}", @"open last");
    expectPlan(CODisplayOpenLast, st(0,1,0,0,0,0), 0, @"{0}", @"open last, one page");
    check(CODisplayActionIsRelative(CODisplayNext) && !CODisplayActionIsRelative(CODisplayGoTo)
          && !CODisplayActionIsRelative(CODisplayOpenLast) && CODisplayActionIsRelative(CODisplayRedisplay),
          @"relative actions");
}

static void testReadLane(NSString *gen)
{
    NSString *cbz = [gen stringByAppendingPathComponent:@"test.cbz"];
    COImageLoader *loader = [[[COImageLoader alloc] initWithPath:cbz readSubFolder:NO controller:nil] autorelease];
    int pages = [loader itemCount];
    check(pages >= 4, [NSString stringWithFormat:@"lane: test.cbz has 4 pages (got %d)", pages]);
    if (pages < 4) return;

    // (1) one delivery, on the main thread, with the pages asked for
    printf("read lane: delivery\n");
    {
        COBookReadLane *lane = [[[COBookReadLane alloc] initWithLoader:loader] autorelease];
        __block int deliveries = 0;
        __block BOOL onMain = NO;
        __block NSDictionary *got = nil;
        unsigned int token = [lane beginRequest];
        [lane readPages:@[ @0, @1 ] token:token completion:^(NSDictionary *images) {
            deliveries++;
            onMain = [NSThread isMainThread];
            got = [images retain];
        }];
        spinUntil(^BOOL{ return deliveries > 0; }, 10);
        spinFor(0.2);
        check(deliveries == 1 && onMain, [NSString stringWithFormat:@"lane: delivered once on main (%d)", deliveries]);
        check([got count] == 2 && pixelsWide([got objectForKey:@0]) > 0 && pixelsWide([got objectForKey:@1]) > 0,
              @"lane: both pages delivered as valid images");
        [got release];
    }

    // (2) a newer request supersedes: only B is delivered
    printf("read lane: supersede\n");
    {
        COBookReadLane *lane = [[[COBookReadLane alloc] initWithLoader:loader] autorelease];
        __block int aDelivered = 0, bDelivered = 0;
        unsigned int a = [lane beginRequest];
        [lane readPages:@[ @0, @1, @2, @3 ] token:a completion:^(NSDictionary *images) { aDelivered++; }];
        unsigned int b = [lane beginRequest];
        [lane readPages:@[ @1 ] token:b completion:^(NSDictionary *images) {
            bDelivered += ([images objectForKey:@1] != nil);
        }];
        spinUntil(^BOOL{ return bDelivered > 0; }, 10);
        spinFor(0.2);
        check(aDelivered == 0 && bDelivered == 1,
              [NSString stringWithFormat:@"lane: superseded A dropped (%d), B delivered (%d)", aDelivered, bDelivered]);
    }

    // (3) a cancelled request delivers nothing
    printf("read lane: cancel\n");
    {
        COBookReadLane *lane = [[[COBookReadLane alloc] initWithLoader:loader] autorelease];
        __block int delivered = 0;
        unsigned int token = [lane beginRequest];
        [lane readPages:@[ @2, @3 ] token:token completion:^(NSDictionary *images) { delivered++; }];
        [lane cancel];
        spinFor(0.5);
        check(delivered == 0, @"lane: cancelled request not delivered");
    }

    // (4) a job blocked on decodeLock does not block the main thread; a job
    // cancelled while blocked is dropped, the next one is delivered
    printf("read lane: blocked decodeLock\n");
    {
        COBookReadLane *lane = [[[COBookReadLane alloc] initWithLoader:loader] autorelease];
        NSLock *decodeLock = [lane decodeLock];
        dispatch_semaphore_t locked = dispatch_semaphore_create(0);
        dispatch_semaphore_t release = dispatch_semaphore_create(0);
        dispatch_semaphore_t unlocked = dispatch_semaphore_create(0);
        [NSThread detachNewThreadWithBlock:^{
            [decodeLock lock];
            dispatch_semaphore_signal(locked);
            dispatch_semaphore_wait(release, DISPATCH_TIME_FOREVER);
            [decodeLock unlock];
            dispatch_semaphore_signal(unlocked);
        }];
        dispatch_semaphore_wait(locked, DISPATCH_TIME_FOREVER);

        __block int ticks = 0;
        NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.01 repeats:YES block:^(NSTimer *t) { ticks++; }];
        __block int aDelivered = 0, bDelivered = 0;
        unsigned int a = [lane beginRequest];
        [lane readPages:@[ @0 ] token:a completion:^(NSDictionary *images) { aDelivered++; }];
        spinFor(0.3);
        int ticksWhileBlocked = ticks;
        unsigned int b = [lane beginRequest];   // A is cancelled while it waits
        [lane readPages:@[ @3 ] token:b completion:^(NSDictionary *images) {
            bDelivered += ([images objectForKey:@3] != nil);
        }];
        dispatch_semaphore_signal(release);
        spinUntil(^BOOL{ return bDelivered > 0; }, 10);
        spinFor(0.2);
        [timer invalidate];
        dispatch_semaphore_wait(unlocked, DISPATCH_TIME_FOREVER);
        check(ticksWhileBlocked >= 10,
              [NSString stringWithFormat:@"lane: main run loop kept running while decodeLock was held (%d ticks)", ticksWhileBlocked]);
        check(aDelivered == 0 && bDelivered == 1,
              [NSString stringWithFormat:@"lane: blocked A dropped (%d), B delivered (%d)", aDelivered, bDelivered]);
        dispatch_release(locked);
        dispatch_release(release);
        dispatch_release(unlocked);
    }

    // (5) lane jobs and a lookahead-like thread taking the same decodeLock are
    // never inside the loader together
    printf("read lane: one decoder at a time\n");
    {
        CountingLoader *counting = [[[CountingLoader alloc] initWithPath:cbz readSubFolder:NO controller:nil] autorelease];
        COBookReadLane *lane = [[[COBookReadLane alloc] initWithLoader:counting] autorelease];
        NSLock *decodeLock = [lane decodeLock];
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        [NSThread detachNewThreadWithBlock:^{
            int i;
            for (i = 0; i < 40; i++) {
                @autoreleasepool {
                    [decodeLock lock];
                    [counting itemAtIndex:i % 4];
                    [decodeLock unlock];
                }
            }
            dispatch_semaphore_signal(done);
        }];
        __block int delivered = 0;
        int round;
        for (round = 0; round < 10; round++) {
            unsigned int token = [lane beginRequest];
            [lane readPages:@[ @0, @1, @2, @3 ] token:token completion:^(NSDictionary *images) { delivered++; }];
            spinUntil(^BOOL{ return delivered > round; }, 10);
        }
        while (dispatch_semaphore_wait(done, DISPATCH_TIME_NOW) != 0) spinFor(0.01);
        dispatch_release(done);
        check(delivered == 10, [NSString stringWithFormat:@"lane: 10 rounds delivered (%d)", delivered]);
        check(atomic_load(&counting->maxInside) == 1 && atomic_load(&counting->calls) >= 80,
              [NSString stringWithFormat:@"lane: at most one thread in -itemAtIndex: (max %d, %d calls)",
               atomic_load(&counting->maxInside), atomic_load(&counting->calls)]);
    }

    // (5b) a page the loader returns nothing for is still answered (NSNull),
    // so the controller does not ask for it again
    printf("read lane: page with no image\n");
    {
        NilPageLoader *nilLoader = [[[NilPageLoader alloc] initWithPath:cbz readSubFolder:NO controller:nil] autorelease];
        COBookReadLane *lane = [[[COBookReadLane alloc] initWithLoader:nilLoader] autorelease];
        __block NSDictionary *got = nil;
        [lane readPages:@[ @0, @1, @2 ] token:[lane beginRequest] completion:^(NSDictionary *images) {
            got = [images retain];
        }];
        spinUntil(^BOOL{ return got != nil; }, 10);
        check([got count] == 3 && [got objectForKey:@1] == [NSNull null]
              && pixelsWide([got objectForKey:@0]) > 0 && pixelsWide([got objectForKey:@2]) > 0,
              [NSString stringWithFormat:@"lane: unreadable page answered with NSNull (%@)", [got objectForKey:@1]]);
        [got release];
    }

    // (6) a solid RAR read backwards through the lane gives the same pages as
    // reading it in order
    NSString *solidPath = [gen stringByAppendingPathComponent:@"test_solid.cbr"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:solidPath]) {
        printf("read lane: solid RAR backwards\n");
        COImageLoader *forward = [[[COImageLoader alloc] initWithPath:solidPath readSubFolder:NO controller:nil] autorelease];
        COImageLoader *backward = [[[COImageLoader alloc] initWithPath:solidPath readSubFolder:NO controller:nil] autorelease];
        int count = [forward itemCount];
        NSMutableArray *expected = [NSMutableArray array];
        NSMutableArray *order = [NSMutableArray array];
        int i;
        for (i = 0; i < count; i++) {
            NSImage *image = [forward itemAtIndex:i];
            [expected addObject:[NSString stringWithFormat:@"%dx%d", pixelsWide(image),
                                 (int)[[[image representations] firstObject] pixelsHigh]]];
            [order insertObject:@(i) atIndex:0];
        }
        COBookReadLane *lane = [[[COBookReadLane alloc] initWithLoader:backward] autorelease];
        __block NSDictionary *got = nil;
        [lane readPages:order token:[lane beginRequest] completion:^(NSDictionary *images) { got = [images retain]; }];
        spinUntil(^BOOL{ return got != nil; }, 20);
        BOOL same = (count > 0 && (int)[got count] == count);
        for (i = 0; same && i < count; i++) {
            NSImage *image = [got objectForKey:@(i)];
            NSString *size = [NSString stringWithFormat:@"%dx%d", pixelsWide(image),
                              (int)[[[image representations] firstObject] pixelsHigh]];
            same = [size isEqualToString:[expected objectAtIndex:i]] && pixelsWide(image) > 0;
        }
        check(same, [NSString stringWithFormat:@"lane: solid RAR read backwards matches (%d pages, got %d)",
                     count, (int)[got count]]);
        [got release];
    }
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "usage: test_imageloader <generated-dir>\n");
            return 2;
        }
        NSString *gen = [NSString stringWithUTF8String:argv[1]];

        // --- L2: one unreadable nested archive must not cost the book its
        // other pages (it used to abandon the whole page list) ---
        printf("broken_nested.cbz\n");
        {
            COImageLoader *loader = loaderFor(gen, @"broken_nested.cbz");
            NSArray *pages = [loader pathArray];
            NSMutableArray *names = [NSMutableArray array];
            for (NSString *page in pages) [names addObject:[page lastPathComponent]];
            check([loader itemCount] == 3,
                  [NSString stringWithFormat:@"broken_nested: 3 pages (got %d: %@)",
                   [loader itemCount], names]);
            check([names containsObject:@"001.jpg"] && [names containsObject:@"002.jpg"],
                  @"broken_nested: the top-level pages are listed");
            check([names containsObject:@"inner.jpg"],
                  @"broken_nested: the readable nested archive's page is listed");
            check(![names containsObject:@"lost.jpg"],
                  @"broken_nested: the unreadable nested archive adds no page");
        }

        // --- L4: repeated entry names are separate pages, each with its
        // own entry's image (they all used to show the first one), also
        // for repeated nested archives. The source images differ in width:
        // 001.png 2000, 002.jpg 1200, 003.png 1600, 004.jpg 800 ---
        printf("dup_names.cbz\n");
        {
            COImageLoader *loader = loaderFor(gen, @"dup_names.cbz");
            int want[] = { 2000, 1600, 1200, 800, 1200 };
            check([loader itemCount] == 5,
                  [NSString stringWithFormat:@"dup_names: 5 pages (got %d: %@)",
                   [loader itemCount], [loader pathArray]]);
            if ([loader itemCount] == 5) {
                int i;
                for (i = 0; i < 5; i++) {
                    NSImage *image = [loader itemAtIndex:i];
                    NSImageRep *rep = [[image representations] firstObject];
                    check([rep pixelsWide] == want[i],
                          [NSString stringWithFormat:@"dup_names: page %d (%@) is %ld px wide, want %d",
                           i + 1, [[loader pathArray] objectAtIndex:i], (long)[rep pixelsWide], want[i]]);
                }
            }
        }

        // --- KNOWN_ISSUES #30: a book with no readable pages has no pages
        // (it used to get a stand-in page and open as a one-page book) and
        // says why; a book with one corrupt page still has all its pages ---
        {
            NSString *dir = [gen stringByAppendingPathComponent:@"no_pages"];
            struct { NSString *name; COImageLoaderPagesStatus want; BOOL optional; } cases[] = {
                { @"empty_dir",             COImageLoaderNoImages,               NO },
                { @"text_only_dir",         COImageLoaderNoImages,               NO },
                { @"garbage_only_dir",      COImageLoaderNoImages,               NO },
                { @"text_only.cbz",         COImageLoaderNoImages,               NO },
                // an archive with no entries at all is reported by the
                // archive layer ("no readable entries") exactly like one
                // whose every entry is damaged
                { @"no_entries.cbz",        COImageLoaderUnreadable,             NO },
                { @"garbage.cbz",           COImageLoaderUnreadable,             NO },
                { @"garbage.cbr",           COImageLoaderUnreadable,             NO },
                { @"garbage.7z",            COImageLoaderUnreadable,             NO },
                { @"garbage.pdf",           COImageLoaderUnreadable,             NO },
                { @"encrypted.7z",          COImageLoaderEncryptionUnsupported,  YES },
                { @"encrypted_headers.7z",  COImageLoaderUnreadable,             YES },
            };
            size_t i;
            for (i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
                NSString *path = [dir stringByAppendingPathComponent:cases[i].name];
                if (cases[i].optional && ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
                    printf("%s (skipped: not generated)\n", [cases[i].name UTF8String]);
                    continue;
                }
                printf("%s (no readable pages)\n", [cases[i].name UTF8String]);
                COImageLoader *loader = loaderFor(dir, cases[i].name);
                check([loader itemCount] == 0,
                      [NSString stringWithFormat:@"%@: no pages (got %d: %@)",
                       cases[i].name, [loader itemCount], [loader pathArray]]);
                check([loader mode] >= 0,
                      [NSString stringWithFormat:@"%@: mode %d, not a failed open",
                       cases[i].name, [loader mode]]);
                check([loader pagesStatus] == cases[i].want,
                      [NSString stringWithFormat:@"%@: status %d, want %d",
                       cases[i].name, (int)[loader pagesStatus], (int)cases[i].want]);
            }

            // a path that is not there, and a refused solid RAR4: the open
            // did not happen, which the host does not report as "no pages"
            printf("missing path, solid RAR4 (not opened)\n");
            COImageLoader *missing = loaderFor(dir, @"no_such_book.cbz");
            check([missing itemCount] == 0 && [missing pagesStatus] == COImageLoaderNotOpened,
                  [NSString stringWithFormat:@"missing: %d pages, status %d",
                   [missing itemCount], (int)[missing pagesStatus]]);
            COImageLoader *solid = loaderFor(gen, @"test_rar4_solid.cbr");
            check([solid itemCount] == 0 && [solid pagesStatus] == COImageLoaderNotOpened &&
                  [solid isUnsupportedSolidRAR4],
                  [NSString stringWithFormat:@"solid RAR4: %d pages, status %d",
                   [solid itemCount], (int)[solid pagesStatus]]);

            // a password-protected ZIP with no image in it, through the
            // host-driven password path: once the password is accepted it is
            // a book with no images, not a failed open
            NSString *encPath = [dir stringByAppendingPathComponent:@"encrypted_text_only.cbz"];
            if ([[NSFileManager defaultManager] fileExistsAtPath:encPath]) {
                printf("encrypted_text_only.cbz (password, then no readable pages)\n");
                COImageLoader *loader = [[[COImageLoader alloc] initWithPath:encPath
                                                                 displayPath:encPath
                                                               readSubFolder:NO
                                                                  controller:nil
                                                         deferPasswordPrompt:YES] autorelease];
                check([loader needsPassword] && [loader pagesStatus] == COImageLoaderNotOpened,
                      [NSString stringWithFormat:@"encrypted_text_only: needs a password first (status %d)",
                       (int)[loader pagesStatus]]);
                check([loader tryPassword:@"wrong"] == COArchiveCryptoWrongPassword,
                      @"encrypted_text_only: wrong password rejected");
                check([loader tryPassword:@"SECRET"] == COArchiveCryptoOK,
                      @"encrypted_text_only: password accepted");
                check([loader itemCount] == 0 && [loader pagesStatus] == COImageLoaderNoImages,
                      [NSString stringWithFormat:@"encrypted_text_only: %d pages, status %d",
                       [loader itemCount], (int)[loader pagesStatus]]);
            } else {
                printf("encrypted_text_only.cbz (skipped: not generated)\n");
            }

            // one page that cannot be decoded is still a page
            for (NSString *name in @[ @"corrupt_page_dir", @"corrupt_page.cbz" ]) {
                printf("%s (one corrupt page)\n", [name UTF8String]);
                COImageLoader *loader = loaderFor(dir, name);
                check([loader itemCount] == 4 && [loader pagesStatus] == COImageLoaderHasPages,
                      [NSString stringWithFormat:@"%@: 4 pages and HasPages (got %d, status %d)",
                       name, [loader itemCount], (int)[loader pagesStatus]]);
                if ([loader itemCount] == 4) {
                    NSImage *good = [loader itemAtIndex:0];
                    check([good isValid] && [[good representations] count] > 0,
                          [NSString stringWithFormat:@"%@: page 1 decodes", name]);
                    // the app shows its "broken" asset for such a page; this
                    // harness has no asset catalog, so that resolves to nil
                    NSImage *bad = [loader itemAtIndex:3];
                    check(bad == nil,
                          [NSString stringWithFormat:@"%@: page 4 does not decode", name]);
                }
            }
        }

        // --- KNOWN_ISSUES #33, the loading half: a deferred loader holds
        // nothing until it is read; read on a worker thread and finished on
        // this (main) thread it lists exactly the pages an inline loader
        // does, and they decode the same ---
        for (NSString *name in @[ @"test.7z", @"test.tar", @"test.zip", @"test.cbr" ]) {
            NSString *path = [gen stringByAppendingPathComponent:name];
            if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
                printf("%s deferred read (skipped: not generated)\n", [name UTF8String]);
                continue;
            }
            printf("%s (deferred read)\n", [name UTF8String]);
            COImageLoader *inline_ = loaderFor(gen, name);
            COImageLoader *deferred = deferredLoaderFor(path, nil);
            check([deferred needsArchiveRead] && [deferred itemCount] == 0 &&
                  [deferred mode] < 0 && [deferred pagesStatus] == COImageLoaderNotOpened,
                  [NSString stringWithFormat:@"%@: deferred loader holds nothing before the read "
                   "(needs %d, %d pages, status %d)", name, [deferred needsArchiveRead],
                   [deferred itemCount], (int)[deferred pagesStatus]]);
            readOnWorkerThread(deferred);
            check([deferred needsArchiveRead] && [deferred itemCount] == 0,
                  [NSString stringWithFormat:@"%@: nothing listed before -finishArchiveRead", name]);
            [deferred finishArchiveRead];
            check(![deferred needsArchiveRead] && [deferred pagesStatus] == COImageLoaderHasPages &&
                  [deferred mode] == [inline_ mode],
                  [NSString stringWithFormat:@"%@: deferred read finished (status %d, mode %d vs %d)",
                   name, (int)[deferred pagesStatus], [deferred mode], [inline_ mode]]);
            check([inline_ itemCount] > 0 && [[deferred pathArray] isEqualToArray:[inline_ pathArray]],
                  [NSString stringWithFormat:@"%@: same pages as an inline read (%d vs %d)",
                   name, [deferred itemCount], [inline_ itemCount]]);
            if ([deferred itemCount] == [inline_ itemCount]) {
                int i;
                for (i = 0; i < [inline_ itemCount]; i++) {
                    int want = pixelsWide([inline_ itemAtIndex:i]);
                    int got = pixelsWide([deferred itemAtIndex:i]);
                    check(want > 0 && got == want,
                          [NSString stringWithFormat:@"%@: page %d decodes the same (%d vs %d px)",
                           name, i + 1, got, want]);
                }
            }
        }

        // B3: a solid RAR5 book read the deferred way (the window's book)
        // decodes ahead into the loader's temporary directory, which goes
        // with the loader; a non-solid one creates no directory.
        for (NSString *name in @[ @"test_solid.cbr", @"test.cbr" ]) {
            NSString *path = [gen stringByAppendingPathComponent:name];
            if (![[NSFileManager defaultManager] fileExistsAtPath:path]) continue;
            BOOL solid = [name isEqualToString:@"test_solid.cbr"];
            printf("%s (deferred read, decode-ahead %s)\n", [name UTF8String], solid ? "on" : "off");
            NSString *tempDir = nil, *cacheDir = nil;
            @autoreleasepool {
                COImageLoader *loader = deferredLoaderFor(path, nil);
                readOnWorkerThread(loader);
                [loader finishArchiveRead];
                id archive = object_getIvar(loader, class_getInstanceVariable([COImageLoader class], "archiveContainer"));
                tempDir = [object_getIvar(loader, class_getInstanceVariable([COImageLoader class], "tempDir")) retain];
                if ([archive respondsToSelector:@selector(decodeAheadCacheDirectory)])
                    cacheDir = [[archive performSelector:@selector(decodeAheadCacheDirectory)] retain];
                if (solid) {
                    check(tempDir && cacheDir && [cacheDir hasPrefix:tempDir],
                          [NSString stringWithFormat:@"%@: decode-ahead directory %@ in the loader's %@",
                           name, cacheDir, tempDir]);
                    check([loader itemCount] == 4 && pixelsWide([loader itemAtIndex:3]) > 0,
                          [NSString stringWithFormat:@"%@: pages read with decode-ahead on", name]);
                } else {
                    check(!tempDir && !cacheDir,
                          [NSString stringWithFormat:@"%@: no temporary directory for a non-solid book", name]);
                }
            }
            check(!tempDir || ![[NSFileManager defaultManager] fileExistsAtPath:tempDir],
                  [NSString stringWithFormat:@"%@: the loader's temporary directory is gone with it", name]);
            [tempDir release];
            [cacheDir release];
        }

        // A folder book is listed in the initializer as before: there is no
        // archive of its own to defer.
        printf("corrupt_page_dir (deferred loader, not an archive)\n");
        {
            NSString *path = [[gen stringByAppendingPathComponent:@"no_pages"]
                              stringByAppendingPathComponent:@"corrupt_page_dir"];
            COImageLoader *loader = deferredLoaderFor(path, nil);
            check(![loader needsArchiveRead] && [loader itemCount] == 4 &&
                  [loader pagesStatus] == COImageLoaderHasPages,
                  [NSString stringWithFormat:@"folder: no deferred read, 4 pages (needs %d, %d pages)",
                   [loader needsArchiveRead], [loader itemCount]]);
        }

        // A cancelled deferred read is a book that was not opened, as a
        // cancelled inline read is: by the controller's progress callback
        // (the sheet's Cancel button), or by -cancelArchiveRead (a close or a
        // quit). These two formats go through libarchive's full read, which
        // reports progress.
        for (NSString *name in @[ @"test.7z", @"test.tar" ]) {
            NSString *path = [gen stringByAppendingPathComponent:name];
            if (![[NSFileManager defaultManager] fileExistsAtPath:path]) continue;
            printf("%s (cancelled deferred read)\n", [name UTF8String]);
            CancellingController *cancelling = [[[CancellingController alloc] init] autorelease];
            COImageLoader *loader = deferredLoaderFor(path, cancelling);
            readOnWorkerThread(loader);
            [loader finishArchiveRead];
            check(atomic_load(&cancelling->calls) > 0,
                  [NSString stringWithFormat:@"%@: the read reported progress", name]);
            check([loader itemCount] == 0 && [loader mode] < 0 &&
                  [loader pagesStatus] == COImageLoaderNotOpened && ![loader needsArchiveRead],
                  [NSString stringWithFormat:@"%@: cancelled from the callback: %d pages, status %d",
                   name, [loader itemCount], (int)[loader pagesStatus]]);

            COImageLoader *stopped = deferredLoaderFor(path, nil);
            [stopped cancelArchiveRead];
            readOnWorkerThread(stopped);
            [stopped finishArchiveRead];
            check([stopped itemCount] == 0 && [stopped pagesStatus] == COImageLoaderNotOpened,
                  [NSString stringWithFormat:@"%@: cancelled by -cancelArchiveRead: %d pages, status %d",
                   name, [stopped itemCount], (int)[stopped pagesStatus]]);
        }

        // An encrypted ZIP read the deferred way still hands the password to
        // the host afterwards.
        {
            NSString *encPath = [[gen stringByAppendingPathComponent:@"no_pages"]
                                 stringByAppendingPathComponent:@"encrypted_text_only.cbz"];
            if ([[NSFileManager defaultManager] fileExistsAtPath:encPath]) {
                printf("encrypted_text_only.cbz (deferred read, then password)\n");
                COImageLoader *loader = deferredLoaderFor(encPath, nil);
                readOnWorkerThread(loader);
                [loader finishArchiveRead];
                check([loader needsPassword] && [loader pagesStatus] == COImageLoaderNotOpened,
                      @"encrypted_text_only: deferred read asks for the password");
                check([loader tryPassword:@"SECRET"] == COArchiveCryptoOK &&
                      [loader pagesStatus] == COImageLoaderNoImages,
                      @"encrypted_text_only: deferred read, password accepted, no images");
            }
        }

        testDisplayPlans();
        testReadLane(gen);

        if (failures == 0) {
            printf("\nALL PASS (%d checks)\n", checks);
            return 0;
        }
        printf("\n%d FAILED of %d checks\n", failures, checks);
        return 1;
    }
}
