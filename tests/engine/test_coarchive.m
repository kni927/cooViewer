/*
 * test_coarchive — engine gate harness for
 * COArchive/COZipArchive/CORarArchive.
 *
 * Runs COArchive against every fixture archive and verifies:
 *   - entry count and entry order (archive order)
 *   - decoded entry names against the baseline in
 *     tests/fixtures/README.md (ASCII and Japanese UTF-8/CP932)
 *   - SHA-256 of every entry payload against tests/fixtures/src
 *   - zip/cbz dispatch to the libzip lazy reader (COZipArchive) and
 *     rar/cbr dispatch to the partial-lazy reader (CORarArchive), by
 *     signature first (mislabeled files); 7z/tar stay on the
 *     full-extraction libarchive path
 *   - hostile metadata: ~5000-character entry names, a "../" nested
 *     archive name, a RAR4 size past the end of the file
 *   - the libzip path is locale-independent (CP932 names survive a
 *     forced C locale; the libarchive zip reader needed the UTF-8
 *     locale workaround in main.m)
 *   - solid RAR archives decode correctly (in their own, re-ordered
 *     stream order — solid compression reorders entries for a better
 *     ratio)
 *   - RAR backward page navigation (the cursor can only skip forward,
 *     so paging backwards must reopen and fast-forward from the start)
 *   - graceful handling of truncated and bit-flipped zip/rar archives
 *
 * usage: test_coarchive <fixtures-generated-dir> <fixtures-src-dir>
 *                       <rar5-final-block-fixture>
 * exit code: number of failed checks (0 = all pass)
 */
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#include <locale.h>
#include <objc/runtime.h>
#import "COArchive.h"
#import "COZipArchive.h"
#import "CORarArchive.h"
#import "CORarHeaderIndex.h"
#import "NSString_Compare.h"

static int failures = 0;
static int checks = 0;

static void check(BOOL ok, NSString *what)
{
    checks++;
    if (!ok) {
        failures++;
        printf("  FAIL: %s\n", [what UTF8String]);
    }
}

static CORarEntry *rarEntryNamed(COArchive *archive, NSString *name)
{
    for (COArchiveEntry *entry in [archive contents]) {
        if ([[entry path] isEqualToString:name] &&
            [entry isKindOfClass:[CORarEntry class]])
            return (CORarEntry *)entry;
    }
    return nil;
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

    // dispatch check: zip/cbz -> COZipArchive, rar/cbr -> CORarArchive,
    // everything else stays on the base libarchive full-extraction path
    NSString *ext = [[path pathExtension] lowercaseString];
    BOOL wantZip = [ext isEqualToString:@"zip"] || [ext isEqualToString:@"cbz"];
    BOOL wantRar = [ext isEqualToString:@"rar"] || [ext isEqualToString:@"cbr"];
    check([ar isKindOfClass:[COZipArchive class]] == wantZip,
          [NSString stringWithFormat:@"dispatch: %@ opened as %s",
           [path lastPathComponent], class_getName([ar class])]);
    check([ar isKindOfClass:[CORarArchive class]] == wantRar,
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
    if (argc != 4) {
        fprintf(stderr, "usage: %s <generated-dir> <src-dir> "
                        "<rar5-final-block-fixture>\n", argv[0]);
        return 64;
    }
    @autoreleasepool {
        NSString *gen = [NSString stringWithUTF8String:argv[1]];
        NSString *src = [NSString stringWithUTF8String:argv[2]];
        NSString *rar5Final = [NSString stringWithUTF8String:argv[3]];

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

        // --- trailing-error recovery predicate. "123456789" is the
        // standard CRC32 check vector (IEEE CRC32 = CBF43926). The
        // normal-success archive matrix below does not call this gate;
        // it remains confined to CORarArchive's read-error branch. ---
        {
            printf("RAR trailing-error recovery predicate\n");
            NSData *complete = [@"123456789" dataUsingEncoding:NSASCIIStringEncoding];
            NSData *shortPayload = [@"12345678" dataUsingEncoding:NSASCIIStringEncoding];
            check(CORarPayloadMatchesExpectedMetadata(complete, YES, 9, YES, 0xcbf43926U),
                  @"exact size and CRC should recover");
            check(!CORarPayloadMatchesExpectedMetadata(complete, YES, 9, YES, 0xcbf43927U),
                  @"wrong CRC must not recover");
            check(!CORarPayloadMatchesExpectedMetadata(shortPayload, YES, 9, YES, 0x9ae0daafU),
                  @"short payload must not recover");
            check(!CORarPayloadMatchesExpectedMetadata(complete, YES, 9, NO, 0),
                  @"missing CRC must not recover");
            check(!CORarPayloadMatchesExpectedMetadata(complete, NO, 0, YES, 0xcbf43926U),
                  @"missing size must not recover");
        }

        // --- positive matrix ---
        for (NSString *f in @[ @"test.zip", @"test.cbz", @"test.tar",
                               @"test.7z", @"test.cbr", @"test_rar4.cbr" ])
            testArchive([gen stringByAppendingPathComponent:f], asciiNames, srcHashes);

        // --- RAR4 (legacy) via the phase 6 header-only fast path:
        // hand-written fixture (no generator tool available for this
        // format), STORE method. Confirms the from-scratch RAR4
        // parser in CORarHeaderIndex.m — informed by XADRARParser.m
        // but unverified against any real-world RAR4 archive — at
        // least gets the basic single-volume, non-Unicode,
        // non-encrypted case right, cross-checked against
        // libarchive's own RAR4 reader for the decode side. ---
        {
            NSString *p = [gen stringByAppendingPathComponent:@"test_rar4.cbr"];
            printf("test_rar4.cbr fast-path check\n");
            __block int calls = 0;
            COArchive *ar = [[[COArchive alloc] initWithPath:p
                progress:^BOOL(long long done, long long total) {
                    calls++;
                    return YES;
                }] autorelease];
            check(calls == 0, @"RAR4 header-parser fast path should not invoke progress");
            check([ar isKindOfClass:[CORarArchive class]], @"test_rar4.cbr not on CORarArchive path");
            check([ar itemCount] == 4, @"RAR4 fast-path entry count");
            if ([ar itemCount] > 0) {
                CORarEntry *entry = [[ar contents] objectAtIndex:0];
                check(entry->hasExpectedSize, @"RAR4 declared size metadata missing");
                check(entry->hasExpectedCRC, @"RAR4 file CRC metadata missing");
                check(CORarPayloadMatchesExpectedMetadata([entry data],
                          entry->hasExpectedSize, entry->expectedSize,
                          entry->hasExpectedCRC, entry->expectedCRC),
                      @"RAR4 propagated metadata does not match payload");
            }
        }

        // --- solid RAR4 is refused at open (KNOWN_ISSUES #39): neither
        // the header index nor the libarchive fallback (taken for
        // LHD_UNICODE names) gets to list it, so the book cannot open as
        // one readable page followed by broken ones. Hand-written fixtures
        // (STORE data, MHD_SOLID/LHD_SOLID flags); rar 7.x cannot write
        // RAR4. Solid RAR5 is unaffected. ---
        for (NSString *f in @[ @"test_rar4_solid.cbr", @"test_rar4_solid_unicode.cbr" ]) {
            NSString *p = [gen stringByAppendingPathComponent:f];
            printf("%s (solid RAR4)\n", [f UTF8String]);
            check(CORarIsSolidRAR4AtPath(p), [NSString stringWithFormat:@"%@: not detected as solid RAR4", f]);
            __block int calls = 0;
            COArchive *ar = [[[COArchive alloc] initWithPath:p
                progress:^BOOL(long long done, long long total) {
                    calls++;
                    return YES;
                }] autorelease];
            check([ar refusedSolidRAR4], [NSString stringWithFormat:@"%@: not refused", f]);
            check([ar isMemberOfClass:[COArchive class]] && [ar itemCount] == 0,
                  [NSString stringWithFormat:@"%@: opened as %s with %d entries", f,
                   class_getName([ar class]), [ar itemCount]]);
            check([ar lastError] != nil, [NSString stringWithFormat:@"%@: no lastError", f]);
            check(calls == 0, [NSString stringWithFormat:@"%@: archive was read", f]);
            check([COArchive lazyArchiveWithPath:p] == nil,
                  [NSString stringWithFormat:@"%@: lazy-only open (QuickLook) not refused", f]);
        }
        {
            printf("solid RAR4 detection negatives\n");
            for (NSString *f in @[ @"test_rar4.cbr", @"test.zip", @"test.cbr", @"test_solid.cbr" ]) {
                NSString *p = [gen stringByAppendingPathComponent:f];
                if (![[NSFileManager defaultManager] fileExistsAtPath:p]) continue;
                check(!CORarIsSolidRAR4AtPath(p), [NSString stringWithFormat:@"%@ detected as solid RAR4", f]);
                COArchive *ar = [[[COArchive alloc] initWithPath:p] autorelease];
                check(![ar refusedSolidRAR4] && [ar itemCount] == 4,
                      [NSString stringWithFormat:@"%@ refused or short (%d entries)", f, [ar itemCount]]);
            }
        }

        for (NSString *f in @[ @"test_utf8.zip", @"test_utf8.7z",
                               @"test_utf8.cbr", @"test_sjis.zip" ])
            testArchive([gen stringByAppendingPathComponent:f], jpNames, srcHashes);

        // --- solid RAR: entries come back in the archive's own
        // (reordered) stream order, not source order — rar -s picked
        // 002,004,001,003 for this fixture's compression ratio
        {
            NSArray *solidOrder = @[ @1, @3, @0, @2 ];
            NSMutableArray *solidNames = [NSMutableArray array];
            NSMutableArray *solidHashes = [NSMutableArray array];
            for (NSNumber *i in solidOrder) {
                [solidNames addObject:[asciiNames objectAtIndex:[i unsignedIntegerValue]]];
                [solidHashes addObject:[srcHashes objectAtIndex:[i unsignedIntegerValue]]];
            }
            testArchive([gen stringByAppendingPathComponent:@"test_solid.cbr"],
                        solidNames, solidHashes);
        }

        // --- committed synthetic RAR5 regression. Bundled libarchive
        // returns the complete payload and then reports a trailing block
        // header error. The recovery path must accept only the payload whose
        // declared size and CRC both match. The same test remains valid after
        // a future libarchive update makes the read end normally. ---
        {
            printf("RAR5 output-empty final-block regression\n");
            COArchive *ar = [[[COArchive alloc] initWithPath:rar5Final] autorelease];
            check([ar isKindOfClass:[CORarArchive class]],
                  @"RAR5 final-block fixture not on CORarArchive path");
            check([ar itemCount] == 1,
                  [NSString stringWithFormat:@"RAR5 final-block fixture expected 1 entry, got %d",
                   [ar itemCount]]);

            CORarEntry *entry = rarEntryNamed(ar, @"synthetic_payload.bin");
            check(entry != nil, @"RAR5 final-block fixture entry missing");
            if (entry) {
                check(entry->hasExpectedSize && entry->expectedSize == 16635,
                      @"RAR5 final-block fixture size metadata mismatch");
                check(entry->hasExpectedCRC && entry->expectedCRC == 0x7a5e9eafU,
                      @"RAR5 final-block fixture CRC metadata mismatch");

                NSData *payload = [entry data];
                check(payload != nil, @"RAR5 final-block fixture recovery failed");
                check([payload length] == 16635,
                      @"RAR5 final-block fixture payload length mismatch");
                check(CORarPayloadMatchesExpectedMetadata(payload,
                          entry->hasExpectedSize, entry->expectedSize,
                          entry->hasExpectedCRC, entry->expectedCRC),
                      @"RAR5 final-block fixture payload failed size/CRC validation");
            }
        }

        // --- RAR backward page navigation: the cursor can only skip
        // forward through the stream, so requesting an earlier entry
        // than the cursor's current position must reopen and
        // fast-forward from the start. Exercise both the "continue
        // forward" and "reopen" paths on both non-solid and solid. ---
        for (NSString *f in @[ @"test.cbr", @"test_solid.cbr" ]) {
            NSString *p = [gen stringByAppendingPathComponent:f];
            if (![[NSFileManager defaultManager] fileExistsAtPath:p]) continue;
            printf("%s backward navigation\n", [f UTF8String]);
            COArchive *ar = [[[COArchive alloc] initWithPath:p] autorelease];
            if ([ar itemCount] != 4) {
                check(NO, [NSString stringWithFormat:@"%@: expected 4 entries for nav test", f]);
                continue;
            }
            NSArray *srcByName = [asciiNames count] == 4 ? asciiNames : nil;
            int order[] = { 3, 0, 2, 1 };
            int k;
            for (k = 0; k < 4; k++) {
                COArchiveEntry *e = [[ar contents] objectAtIndex:order[k]];
                NSUInteger want = [srcByName indexOfObject:[e path]];
                check(want != NSNotFound,
                      [NSString stringWithFormat:@"%@: unexpected name %@", f, [e path]]);
                if (want == NSNotFound) continue;
                check([sha256([e data]) isEqualToString:[srcHashes objectAtIndex:want]],
                      [NSString stringWithFormat:@"%@: nav sha mismatch at array index %d",
                       f, order[k]]);
            }
        }

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

        // --- mislabeled files (M7): the reader is chosen by the file's
        // signature, so a zip renamed to .cbr gets the libzip lazy
        // reader (it used to fall back to full extraction into memory),
        // and a rar renamed to .cbz the RAR reader. A 7z renamed to .cbr
        // names neither, so it still goes to the full-extraction path,
        // which +lazyArchiveWithPath: (the QuickLook extensions) refuses ---
        {
            NSFileManager *fm = [NSFileManager defaultManager];
            NSString *src = [gen stringByAppendingPathComponent:@"test.zip"];
            NSString *p = [gen stringByAppendingPathComponent:@"mislabeled.cbr"];
            [fm removeItemAtPath:p error:nil];
            if ([fm copyItemAtPath:src toPath:p error:nil]) {
                printf("mislabeled.cbr (zip renamed to .cbr)\n");
                COArchive *ar = [[[COArchive alloc] initWithPath:p] autorelease];
                check([ar isKindOfClass:[COZipArchive class]],
                      [NSString stringWithFormat:@"mislabeled zip-as-cbr opened as %s",
                       class_getName([ar class])]);
                check([ar itemCount] == 4,
                      [NSString stringWithFormat:@"mislabeled.cbr entry count %d (lastError=%@)",
                       [ar itemCount], [ar lastError]]);
                check([[COArchive lazyArchiveWithPath:p] isKindOfClass:[COZipArchive class]],
                      @"mislabeled.cbr: no lazy reader");
            } else {
                check(NO, @"could not create mislabeled.cbr fixture");
            }

            NSString *rsrc = [gen stringByAppendingPathComponent:@"test.cbr"];
            NSString *rp = [gen stringByAppendingPathComponent:@"mislabeled_rar.cbz"];
            [fm removeItemAtPath:rp error:nil];
            if ([fm fileExistsAtPath:rsrc] && [fm copyItemAtPath:rsrc toPath:rp error:nil]) {
                printf("mislabeled_rar.cbz (rar renamed to .cbz)\n");
                COArchive *ar = [[[COArchive alloc] initWithPath:rp] autorelease];
                check([ar isKindOfClass:[CORarArchive class]],
                      [NSString stringWithFormat:@"mislabeled rar-as-cbz opened as %s",
                       class_getName([ar class])]);
                check([ar itemCount] == 4, @"mislabeled_rar.cbz entry count");
            } else {
                printf("mislabeled_rar.cbz: SKIP (rar not installed)\n");
            }

            NSString *zsrc = [gen stringByAppendingPathComponent:@"test.7z"];
            NSString *zp = [gen stringByAppendingPathComponent:@"mislabeled_7z.cbr"];
            [fm removeItemAtPath:zp error:nil];
            if ([fm fileExistsAtPath:zsrc] && [fm copyItemAtPath:zsrc toPath:zp error:nil]) {
                printf("mislabeled_7z.cbr (7z renamed to .cbr)\n");
                COArchive *ar = [[[COArchive alloc] initWithPath:zp] autorelease];
                check([ar isMemberOfClass:[COArchive class]] && [ar itemCount] == 4,
                      @"mislabeled_7z.cbr: full-extraction fallback");
                check([COArchive lazyArchiveWithPath:zp] == nil,
                      @"mislabeled_7z.cbr: lazy-only open must refuse the full-extraction path");
            } else {
                printf("mislabeled_7z.cbr: SKIP (7zz not installed)\n");
            }
        }

        // --- long entry names (H2): ~5000-character paths, past the
        // 1024-unit stack buffers -finderCompareS: used to copy into.
        // Sorted exactly as COImageLoader/COCoverExtractor sort them ---
        {
            NSString *p = [gen stringByAppendingPathComponent:@"long_name.cbz"];
            printf("long_name.cbz\n");
            COArchive *ar = [[[COArchive alloc] initWithPath:p] autorelease];
            check([ar itemCount] == 2, @"long_name.cbz entry count");
            if ([ar itemCount] == 2) {
                NSMutableArray *names = [NSMutableArray array];
                for (COArchiveEntry *e in [ar contents]) {
                    check([[e path] length] > 4000, @"long_name.cbz: name shorter than expected");
                    [names addObject:[e path]];
                }
                [names sortUsingSelector:@selector(finderCompareS:)];
                check([[names objectAtIndex:0] hasSuffix:@"/001.jpg"] &&
                      [[names objectAtIndex:1] hasSuffix:@"/002.jpg"],
                      @"long_name.cbz: finderCompareS order");
            }
            // UCCompareTextDefault's result is signed, not just -1/0/1
            check([@"page2.jpg" finderCompareS:@"page10.jpg"] < 0,
                  @"finderCompareS: digits compare as numbers");
        }

        // --- "../" nested archive (H3): the name comes back from the
        // archive unchanged; COIsContainedEntryPath is what keeps
        // COImageLoader from writing it outside its temp directory ---
        {
            NSString *p = [gen stringByAppendingPathComponent:@"dotdot.cbz"];
            printf("dotdot.cbz\n");
            COArchive *ar = [[[COArchive alloc] initWithPath:p] autorelease];
            check([ar itemCount] == 2, @"dotdot.cbz entry count");
            BOOL sawEscape = NO;
            for (COArchiveEntry *e in [ar contents]) {
                if ([[e path] isEqualToString:@"../../escape.zip"]) {
                    sawEscape = YES;
                    check(!COIsContainedEntryPath([e path]), @"dotdot.cbz: ../ entry accepted");
                } else {
                    check(COIsContainedEntryPath([e path]), @"dotdot.cbz: page entry rejected");
                }
            }
            check(sawEscape, @"dotdot.cbz: ../ entry not listed");
            check(!COIsContainedEntryPath(@"/tmp/abs.zip"), @"absolute entry path accepted");
            check(!COIsContainedEntryPath(@"a/../../b.zip"), @"inner .. component accepted");
            check(!COIsContainedEntryPath(@".."), @"bare .. accepted");
            check(!COIsContainedEntryPath(@""), @"empty entry path accepted");
            check(COIsContainedEntryPath(@"a/b..c/..x.zip"), @"dots inside names rejected");
            check(COIsContainedEntryPath(@"sub/inner.cbz"), @"plain nested path rejected");
        }

        // --- RAR4 64-bit packed size past the end of the file (L9): the
        // header index declines (the fallback reader takes over) rather
        // than doing pointer arithmetic with it ---
        {
            NSString *p = [gen stringByAppendingPathComponent:@"rar4_huge_size.cbr"];
            printf("rar4_huge_size.cbr\n");
            BOOL crypted = NO;
            check(CORarParseHeadersAtPath(p, &crypted) == nil,
                  @"rar4_huge_size.cbr: header index accepted a size past the file");
            COArchive *ar = [[[COArchive alloc] initWithPath:p] autorelease];
            check([ar itemCount] <= 1, @"rar4_huge_size.cbr: too many entries");
        }

        // --- corruption: truncated rar (RAR5 signature intact, rest
        // cut off). The index pass opens the stream fine (the
        // signature is at the very start) but the skip-only header
        // scan hits truncated data partway through the first entry,
        // so at most one (unreadable) entry is listed and lastError
        // is set. Unlike zip, CORarArchive has no fallback path. ---
        {
            NSString *p = [gen stringByAppendingPathComponent:@"corrupt_truncated.cbr"];
            if ([[NSFileManager defaultManager] fileExistsAtPath:p]) {
                printf("corrupt_truncated.cbr\n");
                COArchive *ar = [[[COArchive alloc] initWithPath:p] autorelease];
                check([ar isKindOfClass:[CORarArchive class]],
                      @"truncated rar did not open on the CORarArchive path");
                check([ar itemCount] <= 1, @"truncated rar yielded too many entries");
                check([ar lastError] != nil, @"truncated rar should set lastError");
            } else {
                printf("corrupt_truncated.cbr: SKIP (rar not installed)\n");
            }
        }

        // --- corruption: bit-flipped entry #1 (002.jpg) payload
        // inside test.cbr's compressed stream. The index pass only
        // skips entry data (never decodes it), so all 4 entries are
        // still listed correctly; the corrupt entry is detected at
        // read time (-data == nil) and the surrounding entries stay
        // readable — fast-forwarding past a corrupt entry only needs
        // to skip it, not decode it. ---
        {
            NSString *p = [gen stringByAppendingPathComponent:@"corrupt_bitflip.cbr"];
            if ([[NSFileManager defaultManager] fileExistsAtPath:p]) {
                printf("corrupt_bitflip.cbr\n");
                COArchive *ar = [[[COArchive alloc] initWithPath:p] autorelease];
                check([ar isKindOfClass:[CORarArchive class]],
                      @"bitflip rar did not open on the CORarArchive path");
                check([ar itemCount] == 4,
                      [NSString stringWithFormat:@"bitflip rar: expected 4 listed entries, got %d",
                       [ar itemCount]]);
                int i;
                for (i = 0; i < [ar itemCount] && i < 4; i++) {
                    COArchiveEntry *e = [[ar contents] objectAtIndex:i];
                    check([[e path] isEqualToString:[asciiNames objectAtIndex:i]],
                          [NSString stringWithFormat:@"bitflip rar name #%d = %@", i, [e path]]);
                    if (i == 1) {	// the fixture flips bytes inside 002.jpg's compressed stream
                        check([e data] == nil, @"bitflip rar: corrupt entry must yield nil data");
                    } else {
                        check([sha256([e data]) isEqualToString:[srcHashes objectAtIndex:i]],
                              [NSString stringWithFormat:@"bitflip rar sha #%d", i]);
                    }
                }
            } else {
                printf("corrupt_bitflip.cbr: SKIP (rar not installed)\n");
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

            // rar path (phase 6): the header-only fast path is
            // expected to win for a plain single-volume RAR5 fixture
            // like test.cbr, so — like zip's instant open — progress
            // never fires and cancel is a no-op. (The libarchive
            // fallback this path replaces *did* support progress/
            // cancel, same as test.tar above; that fallback code is
            // unchanged and still exercised whenever the header
            // parser declines — see the rar4_huge_size.cbr test above.)
            NSString *rp = [gen stringByAppendingPathComponent:@"test.cbr"];
            if ([[NSFileManager defaultManager] fileExistsAtPath:rp]) {
                __block int rcalls = 0;
                COArchive *ar4 = [[[COArchive alloc] initWithPath:rp
                    progress:^BOOL(long long done, long long total) {
                        rcalls++;
                        return YES;
                    }] autorelease];
                check(rcalls == 0, @"rar header-parser fast path should not invoke progress");
                check([ar4 itemCount] == 4, @"rar fast-path entry count");

                COArchive *ar5 = [[[COArchive alloc] initWithPath:rp
                    progress:^BOOL(long long done, long long total) {
                        return NO;	// would cancel, but the fast path can't be cancelled
                    }] autorelease];
                check(![ar5 cancelled], @"rar fast-path open must not be cancellable");
                check([ar5 itemCount] == 4, @"rar fast-path open with cancel-progress entry count");
            }
        }

        if (failures)
            printf("\n%d FAILURE(S) IN %d CHECKS\n", failures, checks);
        else
            printf("\nALL PASS (%d checks)\n", checks);
    }
    return failures;
}
