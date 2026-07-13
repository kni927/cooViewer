/*
 * test_coarchive — engine gate harness for COArchive/COZipArchive.
 *
 * Runs COArchive against every fixture archive and verifies:
 *   - entry count and entry order (archive order)
 *   - decoded entry names against the baseline in
 *     tests/fixtures/README.md (ASCII and Japanese UTF-8/CP932)
 *   - SHA-256 of every entry payload against tests/fixtures/src
 *   - zip/cbz dispatch to the libzip lazy reader (COZipArchive),
 *     other formats stay on the libarchive path
 *   - the libzip path is locale-independent (CP932 names survive a
 *     forced C locale; the libarchive zip reader needed the UTF-8
 *     locale workaround in main.m)
 *   - graceful handling of truncated and bit-flipped archives
 *
 * usage: test_coarchive <fixtures-generated-dir> <fixtures-src-dir>
 * exit code: number of failed checks (0 = all pass)
 */
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#include <locale.h>
#include <objc/runtime.h>
#import "COArchive.h"
#import "COZipArchive.h"

static int failures = 0;

static void check(BOOL ok, NSString *what)
{
    if (!ok) {
        failures++;
        printf("  FAIL: %s\n", [what UTF8String]);
    }
}

static NSString *sha256(NSData *data)
{
    unsigned char md[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256([data bytes], (CC_LONG)[data length], md);
    NSMutableString *s = [NSMutableString string];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++)
        [s appendFormat:@"%02x", md[i]];
    return s;
}

static void testArchive(NSString *path, NSArray *names, NSArray *srcHashes)
{
    // 7z/rar fixtures are optional (make_fixtures.sh skips them when
    // the tools are missing, e.g. on CI runners)
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        printf("%s: SKIP (fixture not generated)\n",
               [[path lastPathComponent] UTF8String]);
        return;
    }
    printf("%s\n", [[path lastPathComponent] UTF8String]);
    COArchive *ar = [[[COArchive alloc] initWithPath:path] autorelease];

    // dispatch check: zip/cbz must take the libzip lazy path, every
    // other format must stay on the libarchive path
    NSString *ext = [[path pathExtension] lowercaseString];
    BOOL wantZip = [ext isEqualToString:@"zip"] || [ext isEqualToString:@"cbz"];
    check([ar isKindOfClass:[COZipArchive class]] == wantZip,
          [NSString stringWithFormat:@"dispatch: %@ opened as %s",
           [path lastPathComponent], class_getName([ar class])]);

    check([ar itemCount] == (int)[names count],
          [NSString stringWithFormat:@"entry count %d != %lu (lastError=%@)",
           [ar itemCount], (unsigned long)[names count], [ar lastError]]);
    if ([ar itemCount] != (int)[names count]) return;

    int i;
    for (i = 0; i < [ar itemCount]; i++) {
        COArchiveEntry *e = [[ar contents] objectAtIndex:i];
        NSString *want = [names objectAtIndex:i];
        check([[e path] isEqualToString:want],
              [NSString stringWithFormat:@"name #%d '%@' != '%@'", i + 1, [e path], want]);
        NSString *h = sha256([e data]);
        check([h isEqualToString:[srcHashes objectAtIndex:i]],
              [NSString stringWithFormat:@"sha256 #%d mismatch (%@)", i + 1, [e path]]);
    }
}

int main(int argc, char **argv)
{
    if (argc < 3) {
        fprintf(stderr, "usage: %s <generated-dir> <src-dir>\n", argv[0]);
        return 64;
    }
    @autoreleasepool {
        NSString *gen = [NSString stringWithUTF8String:argv[1]];
        NSString *src = [NSString stringWithUTF8String:argv[2]];

        NSArray *srcFiles = @[ @"001.png", @"002.jpg", @"003.png", @"004.jpg" ];
        NSMutableArray *srcHashes = [NSMutableArray array];
        for (NSString *f in srcFiles) {
            NSData *d = [NSData dataWithContentsOfFile:
                         [src stringByAppendingPathComponent:f]];
            if (!d) {
                fprintf(stderr, "missing source image %s\n", [f UTF8String]);
                return 64;
            }
            [srcHashes addObject:sha256(d)];
        }

        NSArray *asciiNames = srcFiles;
        NSArray *jpNames = @[ @"001_表紙.png", @"002_縦長表示.jpg",
                              @"003_網点とカケアミ.png", @"004_拡大縮小.jpg" ];

        // --- positive matrix ---
        for (NSString *f in @[ @"test.zip", @"test.cbz", @"test.tar",
                               @"test.7z", @"test.cbr" ])
            testArchive([gen stringByAppendingPathComponent:f], asciiNames, srcHashes);

        for (NSString *f in @[ @"test_utf8.zip", @"test_utf8.7z",
                               @"test_utf8.cbr", @"test_sjis.zip" ])
            testArchive([gen stringByAppendingPathComponent:f], jpNames, srcHashes);

        // --- locale independence of the libzip path: CP932 names must
        // decode correctly even under the C locale (the libarchive zip
        // reader corrupts them without the main.m setlocale workaround)
        {
            printf("test_sjis.zip under LC_ALL=C\n");
            char *saved = strdup(setlocale(LC_ALL, NULL));
            setlocale(LC_ALL, "C");
            NSString *p = [gen stringByAppendingPathComponent:@"test_sjis.zip"];
            COArchive *ar = [[[COArchive alloc] initWithPath:p] autorelease];
            check([ar isKindOfClass:[COZipArchive class]], @"C locale: not on libzip path");
            check([ar itemCount] == 4, @"C locale: entry count");
            int i;
            for (i = 0; i < [ar itemCount] && i < 4; i++) {
                COArchiveEntry *e = [[ar contents] objectAtIndex:i];
                check([[e path] isEqualToString:[jpNames objectAtIndex:i]],
                      [NSString stringWithFormat:@"C locale name #%d = %@", i, [e path]]);
            }
            setlocale(LC_ALL, saved);
            free(saved);
        }

        // --- corruption: truncated zip (central directory cut off);
        // zip_open fails, must fall back to the libarchive path ---
        {
            NSString *p = [gen stringByAppendingPathComponent:@"corrupt_truncated.zip"];
            printf("corrupt_truncated.zip\n");
            COArchive *ar = [[[COArchive alloc] initWithPath:p] autorelease];
            check(![ar isKindOfClass:[COZipArchive class]],
                  @"truncated zip did not fall back to libarchive");
            check([ar itemCount] <= 1, @"truncated zip yielded too many entries");
            check([ar lastError] != nil, @"truncated zip should set lastError");
        }

        // --- corruption: bit-flipped first entry payload. The central
        // directory is intact so the lazy reader lists all 4 entries;
        // the corrupt one is detected at read time (-data == nil) and
        // the rest stay readable. (The libarchive path dropped corrupt
        // entries at open time instead — behavior change documented in
        // COZipArchive.h.) ---
        {
            NSString *p = [gen stringByAppendingPathComponent:@"corrupt_bitflip.zip"];
            printf("corrupt_bitflip.zip\n");
            COArchive *ar = [[[COArchive alloc] initWithPath:p] autorelease];
            check([ar isKindOfClass:[COZipArchive class]], @"bitflip: not on libzip path");
            check([ar itemCount] == 4,
                  [NSString stringWithFormat:@"bitflip: expected 4 listed entries, got %d",
                   [ar itemCount]]);
            int i;
            for (i = 0; i < [ar itemCount] && i < 4; i++) {
                COArchiveEntry *e = [[ar contents] objectAtIndex:i];
                check([[e path] isEqualToString:[asciiNames objectAtIndex:i]],
                      [NSString stringWithFormat:@"bitflip name #%d = %@", i, [e path]]);
                if (i == 0) {	// the fixture flips bytes in the first entry's deflate stream
                    check([e data] == nil, @"bitflip: corrupt entry must yield nil data");
                } else {
                    check([sha256([e data]) isEqualToString:[srcHashes objectAtIndex:i]],
                          [NSString stringWithFormat:@"bitflip sha #%d", i]);
                }
            }
        }

        // --- progress + cancellation (libarchive path; the zip lazy
        // path never invokes progress and cannot be cancelled) ---
        {
            NSString *p = [gen stringByAppendingPathComponent:@"test.tar"];
            printf("progress/cancel\n");
            __block int calls = 0;
            COArchive *ar = [[[COArchive alloc] initWithPath:p
                progress:^BOOL(long long done, long long total) {
                    calls++;
                    check(done > 0 && total > 0 && done <= total, @"progress bounds");
                    return YES;
                }] autorelease];
            check(calls > 0, @"progress callback never called");
            check([ar itemCount] == 4, @"progress run entry count");

            COArchive *ar2 = [[[COArchive alloc] initWithPath:p
                progress:^BOOL(long long done, long long total) {
                    return NO;	// cancel immediately
                }] autorelease];
            check([ar2 cancelled], @"cancel flag not set");
            check([ar2 itemCount] == 0, @"cancelled open must yield no entries");

            // zip path: open is near instant, cancel is a no-op
            COArchive *ar3 = [[[COArchive alloc]
                initWithPath:[gen stringByAppendingPathComponent:@"test.zip"]
                progress:^BOOL(long long done, long long total) {
                    return NO;
                }] autorelease];
            check(![ar3 cancelled], @"zip open must not be cancellable");
            check([ar3 itemCount] == 4, @"zip open with cancel-progress entry count");
        }

        printf(failures ? "\n%d FAILURE(S)\n" : "\nALL PASS\n", failures);
    }
    return failures;
}
