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

        if (failures == 0) {
            printf("\nALL PASS (%d checks)\n", checks);
            return 0;
        }
        printf("\n%d FAILED of %d checks\n", failures, checks);
        return 1;
    }
}
