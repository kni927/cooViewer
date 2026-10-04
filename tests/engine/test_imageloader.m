// COImageLoader harness: book-level behaviour on top of COArchive (page
// lists, nested archives). Built and run by run_tests.sh after the COArchive
// harness; links AppKit because COImageLoader returns NSImage pages.
//
// Usage: test_imageloader <generated-fixtures-dir>

#import <Cocoa/Cocoa.h>
#import "COImageLoader.h"

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

        if (failures == 0) {
            printf("\nALL PASS (%d checks)\n", checks);
            return 0;
        }
        printf("\n%d FAILED of %d checks\n", failures, checks);
        return 1;
    }
}
