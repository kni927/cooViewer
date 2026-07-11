/*
 * test_coarchive — phase-2 gate harness for COArchive.
 *
 * Runs COArchive against every fixture archive and verifies:
 *   - entry count and entry order (archive order)
 *   - decoded entry names against the baseline in
 *     tests/fixtures/README.md (ASCII and Japanese UTF-8/CP932)
 *   - SHA-256 of every entry payload against tests/fixtures/src
 *   - graceful handling of truncated and bit-flipped archives
 *
 * usage: test_coarchive <fixtures-generated-dir> <fixtures-src-dir>
 * exit code: number of failed checks (0 = all pass)
 */
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#import "COArchive.h"

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
    printf("%s\n", [[path lastPathComponent] UTF8String]);
    COArchive *ar = [[[COArchive alloc] initWithPath:path] autorelease];
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

        // --- corruption: truncated zip (headers cut off mid-file) ---
        {
            NSString *p = [gen stringByAppendingPathComponent:@"corrupt_truncated.zip"];
            printf("corrupt_truncated.zip\n");
            COArchive *ar = [[[COArchive alloc] initWithPath:p] autorelease];
            check([ar itemCount] <= 1, @"truncated zip yielded too many entries");
            check([ar lastError] != nil, @"truncated zip should set lastError");
        }

        // --- corruption: bit-flipped first entry, rest must survive ---
        {
            NSString *p = [gen stringByAppendingPathComponent:@"corrupt_bitflip.zip"];
            printf("corrupt_bitflip.zip\n");
            COArchive *ar = [[[COArchive alloc] initWithPath:p] autorelease];
            check([ar itemCount] == 3,
                  [NSString stringWithFormat:@"bitflip: expected 3 surviving entries, got %d",
                   [ar itemCount]]);
            int i;
            for (i = 0; i < [ar itemCount] && i < 3; i++) {
                COArchiveEntry *e = [[ar contents] objectAtIndex:i];
                check([[e path] isEqualToString:[asciiNames objectAtIndex:i + 1]],
                      [NSString stringWithFormat:@"bitflip name #%d = %@", i, [e path]]);
                check([sha256([e data]) isEqualToString:[srcHashes objectAtIndex:i + 1]],
                      [NSString stringWithFormat:@"bitflip sha #%d", i]);
            }
        }

        // --- progress + cancellation ---
        {
            NSString *p = [gen stringByAppendingPathComponent:@"test.zip"];
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
        }

        printf(failures ? "\n%d FAILURE(S)\n" : "\nALL PASS\n", failures);
    }
    return failures;
}
