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

        if (failures == 0) {
            printf("\nALL PASS (%d checks)\n", checks);
            return 0;
        }
        printf("\n%d FAILED of %d checks\n", failures, checks);
        return 1;
    }
}
