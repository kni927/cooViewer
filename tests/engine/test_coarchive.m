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

/* --- B2 test seams. The prefetch entry points are private to the readers;
   the read queue and the decoded-entry cache are reached through the
   runtime, so the readers need no test-only accessors. --- */
@interface CORarArchive (B2Testing)
- (void)prefetchAfterEntry:(CORarEntry *)entry;
@end
@interface COZipArchive (B2Testing)
- (void)prefetchAfterOrdinal:(NSUInteger)ordinal;
@end

static id ivarOf(id object, Class cls, const char *name)
{
    Ivar iv = class_getInstanceVariable(cls, name);
    return iv ? object_getIvar(object, iv) : nil;
}

/* Parks the prefetch that reaches the armed checkpoint until released. */
static dispatch_semaphore_t hookReached, hookRelease;
static NSUInteger hookOrdinal;
static BOOL hookDecoding;
static _Atomic int hookArmed;

static void parkingCheckpointHook(CORarArchive *archive, NSUInteger ordinal, BOOL decoding)
{
    (void)archive;
    if (ordinal != hookOrdinal || decoding != hookDecoding) return;
    int armed = 1;
    if (!atomic_compare_exchange_strong(&hookArmed, &armed, 0)) return;
    dispatch_semaphore_signal(hookReached);
    dispatch_semaphore_wait(hookRelease, DISPATCH_TIME_FOREVER);
}

/* Waits (up to 5 s) until a read on another thread has registered as
   cancelling a prefetch. */
static BOOL waitForCancelledCount(COArchive *ar, NSUInteger want)
{
    for (int i = 0; i < 500; i++) {
        if ([ar prefetchCancelledCount] >= want) return YES;
        usleep(10000);
    }
    return NO;
}

/* Reads `demand` on another thread while a prefetch is parked: either at the
   armed checkpoint (`ordinal`, `decoding`) after `trigger` started it, or —
   with a nil-ordinal "queued" mode — behind a blocker on `queue`, after
   `trigger` queued it. The parked prefetch is released once the read has
   cancelled it. Returns the read's data; *ok is NO on a timeout. */
static NSData *readWhilePrefetchParked(COArchive *ar, dispatch_queue_t queue,
                                       NSUInteger ordinal, BOOL decoding,
                                       void (^trigger)(void), COArchiveEntry *demand, BOOL *ok)
{
    *ok = YES;
    NSUInteger cancelledBefore = [ar prefetchCancelledCount];
    dispatch_semaphore_t release = dispatch_semaphore_create(0);
    if (queue) {
        dispatch_async(queue, ^{ dispatch_semaphore_wait(release, DISPATCH_TIME_FOREVER); });
        trigger();
    } else {
        hookReached = dispatch_semaphore_create(0);
        hookRelease = release;
        hookOrdinal = ordinal;
        hookDecoding = decoding;
        atomic_store(&hookArmed, 1);
        CORarPrefetchCheckpointHookForTesting = parkingCheckpointHook;
        trigger();
        if (dispatch_semaphore_wait(hookReached, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)) != 0) {
            atomic_store(&hookArmed, 0);
            CORarPrefetchCheckpointHookForTesting = NULL;
            *ok = NO;
            dispatch_release(hookReached);
            dispatch_release(release);
            return nil;
        }
    }
    __block NSData *result = nil;
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool { result = [[demand data] retain]; }
    });
    if (!waitForCancelledCount(ar, cancelledBefore + 1)) *ok = NO;
    dispatch_semaphore_signal(release);
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    CORarPrefetchCheckpointHookForTesting = NULL;
    if (!queue) dispatch_release(hookReached);
    dispatch_release(group);
    dispatch_release(release);
    return [result autorelease];
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

        // --- B1/B2: direct positioning for non-solid RAR whose stored
        // order is not page order (docs/cbr-performance-20261003.md cause
        // 2). Stored 003,001,004,002. Every read in page order, then
        // backwards, then a jump, must decode the right bytes without ever
        // walking the cursor from the start (rewindCount stays 0). The page
        // order hint makes the prefetch after page N fetch page N+1: once
        // the queue has drained, reading N+1 opens no stream. ---
        for (NSString *f in @[ @"test_rar4_unordered.cbr", @"test_rar5_unordered.cbr" ]) {
            NSString *p = [gen stringByAppendingPathComponent:f];
            if (![[NSFileManager defaultManager] fileExistsAtPath:p]) continue;
            printf("%s direct positioning\n", [f UTF8String]);
            COArchive *ar = [[[COArchive alloc] initWithPath:p] autorelease];
            check([ar isKindOfClass:[CORarArchive class]], [NSString stringWithFormat:@"%@: not CORarArchive", f]);
            if (![ar isKindOfClass:[CORarArchive class]] || [ar itemCount] != 4) {
                check(NO, [NSString stringWithFormat:@"%@: expected 4 entries", f]);
                continue;
            }
            CORarArchive *rar = (CORarArchive *)ar;
            check([rar usesDirectPositioning], [NSString stringWithFormat:@"%@: direct positioning not used", f]);
            NSArray *stored = @[ @"003.png", @"001.png", @"004.jpg", @"002.jpg" ];
            NSMutableArray *pages = [NSMutableArray array];	// page order
            for (NSString *name in asciiNames) {
                CORarEntry *e = rarEntryNamed(ar, name);
                check(e != nil, [NSString stringWithFormat:@"%@: %@ missing", f, name]);
                if (e) [pages addObject:e];
            }
            int i;
            for (i = 0; i < 4; i++)
                check([[[[ar contents] objectAtIndex:i] path] isEqualToString:[stored objectAtIndex:i]],
                      [NSString stringWithFormat:@"%@: stored order #%d", f, i]);
            if ([pages count] != 4) continue;
            [ar setPrefetchPageOrder:pages];

            int sequence[] = { 0, 1, 2, 3, 2, 0, 3, 1 };	// forward, back, jumps
            int k;
            for (k = 0; k < 8; k++) {
                int page = sequence[k];
                CORarEntry *e = [pages objectAtIndex:page];
                check([sha256([e data]) isEqualToString:[srcHashes objectAtIndex:page]],
                      [NSString stringWithFormat:@"%@: sha mismatch for page %d (step %d)", f, page + 1, k]);
            }
            check([rar rewindCount] == 0,
                  [NSString stringWithFormat:@"%@: cursor rewound %lu times", f, (unsigned long)[rar rewindCount]]);
            check([rar positionedOpenCount] > 0, [NSString stringWithFormat:@"%@: no positioned open", f]);

            // B2 on a fresh archive: read page 1, let the prefetch run,
            // then page 2 must come from the cache
            COArchive *fresh = [[[COArchive alloc] initWithPath:p] autorelease];
            CORarArchive *freshRar = (CORarArchive *)fresh;
            NSMutableArray *freshPages = [NSMutableArray array];
            for (NSString *name in asciiNames) {
                CORarEntry *e = rarEntryNamed(fresh, name);
                if (e) [freshPages addObject:e];
            }
            if ([freshPages count] == 4) {
                // two pages only, so reading page 2 prefetches nothing
                [fresh setPrefetchPageOrder:[freshPages subarrayWithRange:NSMakeRange(0, 2)]];
                [(CORarEntry *)[freshPages objectAtIndex:0] data];
                NSUInteger opensAfterPage1 = [freshRar positionedOpenCount];	// waits for the prefetch
                NSData *page2 = [(CORarEntry *)[freshPages objectAtIndex:1] data];
                check([sha256(page2) isEqualToString:[srcHashes objectAtIndex:1]],
                      [NSString stringWithFormat:@"%@: B2 page 2 sha mismatch", f]);
                check([freshRar positionedOpenCount] == opensAfterPage1,
                      [NSString stringWithFormat:@"%@: page 2 was not prefetched (opens %lu -> %lu)", f,
                       (unsigned long)opensAfterPage1, (unsigned long)[freshRar positionedOpenCount]]);
            }
        }

        // --- the paths that keep the fast-forward cursor: solid RAR5
        // (decoder state spans entries) and an archive that took the
        // libarchive fallback index pass (RAR4 Unicode names: no header
        // offsets). Both still decode every page, in any order. ---
        {
            printf("no direct positioning: solid and fallback\n");
            NSString *solid = [gen stringByAppendingPathComponent:@"test_solid.cbr"];
            if ([[NSFileManager defaultManager] fileExistsAtPath:solid]) {
                CORarArchive *ar = (CORarArchive *)[[[COArchive alloc] initWithPath:solid] autorelease];
                check([ar isKindOfClass:[CORarArchive class]] && ![ar usesDirectPositioning],
                      @"test_solid.cbr: solid RAR5 must not use direct positioning");
            }
            NSString *fallback = [gen stringByAppendingPathComponent:@"test_rar4_unordered_unicode.cbr"];
            CORarArchive *ar = (CORarArchive *)[[[COArchive alloc] initWithPath:fallback] autorelease];
            check([ar isKindOfClass:[CORarArchive class]] && [ar itemCount] == 4,
                  @"unordered Unicode RAR4: not opened on CORarArchive with 4 entries");
            if ([ar isKindOfClass:[CORarArchive class]] && [ar itemCount] == 4) {
                check(![ar usesDirectPositioning], @"fallback-indexed RAR4 must not use direct positioning");
                int sequence[] = { 3, 0, 2, 1 };
                int k;
                for (k = 0; k < 4; k++) {
                    COArchiveEntry *e = [[ar contents] objectAtIndex:sequence[k]];
                    NSUInteger want = [asciiNames indexOfObject:[e path]];
                    check(want != NSNotFound && [sha256([e data]) isEqualToString:[srcHashes objectAtIndex:want]],
                          [NSString stringWithFormat:@"fallback RAR4: sha mismatch at %d", sequence[k]]);
                }
                check([ar positionedOpenCount] == 0, @"fallback RAR4 opened a positioned stream");
            }
        }

        // --- L3: -disablePrefetch stops the read-ahead a read schedules
        // (the QuickLook cover extractor reads one entry and lets go) ---
        for (NSString *f in @[ @"test.cbz", @"test.cbr", @"test_rar4.cbr" ]) {
            NSString *p = [gen stringByAppendingPathComponent:f];
            if (![[NSFileManager defaultManager] fileExistsAtPath:p]) continue;
            printf("%s prefetch switch\n", [f UTF8String]);
            COArchive *normal = [[[COArchive alloc] initWithPath:p] autorelease];
            COArchive *single = [COArchive lazyArchiveWithPath:p];
            if ([normal itemCount] < 2 || [single itemCount] < 2) {
                check(NO, [NSString stringWithFormat:@"%@: expected several entries", f]);
                continue;
            }
            [[[normal contents] objectAtIndex:0] data];
            check([normal prefetchCount] > 0,
                  [NSString stringWithFormat:@"%@: a read schedules a prefetch", f]);
            [single disablePrefetch];
            NSData *d = [[[single contents] objectAtIndex:0] data];
            check([d length] > 0, [NSString stringWithFormat:@"%@: entry read with prefetch off", f]);
            check([single prefetchCount] == 0,
                  [NSString stringWithFormat:@"%@: no prefetch after -disablePrefetch (%lu)", f,
                   (unsigned long)[single prefetchCount]]);
        }

        // --- M6: link entries between pages are not pages, and do not
        // shift the pages after them. Each page is read in order (the
        // cursor continues from the previous page across the link), then
        // backwards. The RAR4 and RAR5 header-indexed ones use direct
        // positioning; the Unicode RAR4 takes the libarchive fallback. ---
        for (NSString *f in @[ @"test_rar4_links.cbr", @"test_rar4_links_unicode.cbr",
                               @"test_rar5_links.cbr" ]) {
            NSString *p = [gen stringByAppendingPathComponent:f];
            testArchive(p, asciiNames, srcHashes);
            if (![[NSFileManager defaultManager] fileExistsAtPath:p]) continue;
            COArchive *ar = [[[COArchive alloc] initWithPath:p] autorelease];
            if (![ar isKindOfClass:[CORarArchive class]] || [ar itemCount] != 4) continue;
            check([(CORarArchive *)ar usesDirectPositioning] == ![f containsString:@"unicode"],
                  [NSString stringWithFormat:@"%@: unexpected positioning mode", f]);
            int k;
            for (k = 3; k >= 0; k--) {
                COArchiveEntry *e = [[ar contents] objectAtIndex:k];
                check([sha256([e data]) isEqualToString:[srcHashes objectAtIndex:k]],
                      [NSString stringWithFormat:@"%@: backwards sha mismatch for page %d", f, k + 1]);
            }
        }

        // --- the RAR5 trailing-error recovery (KNOWN_ISSUES #37) on the
        // direct-positioning path, twice: the second read follows the
        // cursor invalidation the recovery does. ---
        {
            printf("RAR5 recovery on the direct-positioning path\n");
            CORarArchive *ar = (CORarArchive *)[[[COArchive alloc] initWithPath:rar5Final] autorelease];
            check([ar isKindOfClass:[CORarArchive class]] && [ar usesDirectPositioning],
                  @"RAR5 final-block fixture should use direct positioning");
            CORarEntry *entry = [ar isKindOfClass:[CORarArchive class]] ? rarEntryNamed(ar, @"synthetic_payload.bin") : nil;
            if (entry) {
                int k;
                for (k = 0; k < 2; k++) {
                    NSData *payload = [entry data];
                    check(CORarPayloadMatchesExpectedMetadata(payload,
                              entry->hasExpectedSize, entry->expectedSize,
                              entry->hasExpectedCRC, entry->expectedCRC),
                          [NSString stringWithFormat:@"positioned recovery read %d failed", k + 1]);
                }
                check([ar rewindCount] == 0 && [ar positionedOpenCount] >= 1,
                      @"RAR5 final-block fixture was not read by direct positioning");
            }
        }

        // --- B2 / survey C3: the decoded-entry cache budget scales with
        // physical memory, physicalMemory / 32 within 256 MB ... 1 GB, and
        // both lazy readers use it ---
        {
            printf("decoded-entry cache limit\n");
            const uint64_t MB = 1024ULL * 1024, GB = 1024 * MB;
            check(COArchiveDecodedCacheLimitForPhysicalMemory(0) == 256 * MB, @"cache limit: 0 bytes of RAM");
            check(COArchiveDecodedCacheLimitForPhysicalMemory(4 * GB) == 256 * MB, @"cache limit: 4 GB");
            check(COArchiveDecodedCacheLimitForPhysicalMemory(8 * GB) == 256 * MB, @"cache limit: 8 GB");
            check(COArchiveDecodedCacheLimitForPhysicalMemory(16 * GB) == 512 * MB, @"cache limit: 16 GB");
            check(COArchiveDecodedCacheLimitForPhysicalMemory(24 * GB) == 768 * MB, @"cache limit: 24 GB");
            check(COArchiveDecodedCacheLimitForPhysicalMemory(32 * GB) == 1 * GB, @"cache limit: 32 GB");
            check(COArchiveDecodedCacheLimitForPhysicalMemory(128 * GB) == 1 * GB, @"cache limit: 128 GB");
            check(COArchiveDecodedCacheLimitForPhysicalMemory(UINT64_MAX) == 1 * GB, @"cache limit: UINT64_MAX");
            NSUInteger limit = COArchiveDecodedCacheLimit();
            check(limit == COArchiveDecodedCacheLimitForPhysicalMemory([[NSProcessInfo processInfo] physicalMemory]),
                  @"cache limit: not taken from physicalMemory");
            COArchive *zip = [[[COArchive alloc] initWithPath:[gen stringByAppendingPathComponent:@"test.cbz"]] autorelease];
            NSCache *zipCache = ivarOf(zip, [COZipArchive class], "dataCache");
            check([zip isKindOfClass:[COZipArchive class]] && [zipCache totalCostLimit] == limit,
                  @"COZipArchive: cache limit not applied");
            COArchive *rar = [[[COArchive alloc] initWithPath:[gen stringByAppendingPathComponent:@"test_rar4.cbr"]] autorelease];
            NSCache *rarCache = ivarOf(rar, [CORarArchive class], "dataCache");
            check([rar isKindOfClass:[CORarArchive class]] && [rarCache totalCostLimit] == limit,
                  @"CORarArchive: cache limit not applied");
            printf("  (this machine: %llu MB RAM -> %lu MB)\n",
                   [[NSProcessInfo processInfo] physicalMemory] / MB, (unsigned long)(limit / MB));
        }

        // --- B2: reading pages in stored order continues on the open
        // cursor — one positioned open for the whole book, no rewinds —
        // with the prefetch off (every page read on demand) and on (every
        // page after the first read ahead, then served from the cache) ---
        NSString *largeSrc = [gen stringByAppendingPathComponent:@"rar4_large_src"];
        NSMutableArray *largeHashes = [NSMutableArray array];
        for (NSString *f in srcFiles) {
            NSData *d = [NSData dataWithContentsOfFile:[largeSrc stringByAppendingPathComponent:f]];
            if (d) [largeHashes addObject:sha256(d)];
        }
        check([largeHashes count] == 4, @"rar4_large_src not generated");
        for (NSString *f in @[ @"test_rar4.cbr", @"test.cbr", @"test_rar4_large.cbr" ]) {
            NSString *p = [gen stringByAppendingPathComponent:f];
            if (![[NSFileManager defaultManager] fileExistsAtPath:p]) continue;
            NSArray *hashes = [f isEqualToString:@"test_rar4_large.cbr"] ? largeHashes : srcHashes;
            if ([hashes count] != 4) continue;
            printf("%s cursor continuation\n", [f UTF8String]);
            int withPrefetch;
            for (withPrefetch = 0; withPrefetch < 2; withPrefetch++) {
                CORarArchive *ar = (CORarArchive *)[[[COArchive alloc] initWithPath:p] autorelease];
                if (![ar isKindOfClass:[CORarArchive class]] || [ar itemCount] != 4 || ![ar usesDirectPositioning]) {
                    check(NO, [NSString stringWithFormat:@"%@: expected 4 entries read by direct positioning", f]);
                    break;
                }
                if (withPrefetch)
                    [ar setPrefetchPageOrder:[ar contents]];
                else
                    [ar disablePrefetch];
                int k;
                for (k = 0; k < 4; k++) {
                    NSData *d = [[[ar contents] objectAtIndex:k] data];
                    check([sha256(d) isEqualToString:[hashes objectAtIndex:k]],
                          [NSString stringWithFormat:@"%@: sha mismatch for page %d", f, k + 1]);
                    [ar positionedOpenCount];	// let the prefetch finish
                }
                NSString *mode = withPrefetch ? @"prefetch on" : @"prefetch off";
                check([ar positionedOpenCount] == 1 && [ar rewindCount] == 0,
                      [NSString stringWithFormat:@"%@ (%@): %lu positioned opens, %lu rewinds", f, mode,
                       (unsigned long)[ar positionedOpenCount], (unsigned long)[ar rewindCount]]);
                check([ar cursorContinueCount] == 3,
                      [NSString stringWithFormat:@"%@ (%@): cursor continued %lu times, not 3", f, mode,
                       (unsigned long)[ar cursorContinueCount]]);
                check([ar prefetchCount] == (withPrefetch ? 3 : 0),
                      [NSString stringWithFormat:@"%@ (%@): %lu prefetches", f, mode,
                       (unsigned long)[ar prefetchCount]]);
                check([ar prefetchCancelledCount] == 0 && [ar prefetchSkippedCount] == 0 &&
                      [ar prefetchAbortedCount] == 0,
                      [NSString stringWithFormat:@"%@ (%@): a prefetch was cancelled", f, mode]);
            }
        }

        // --- B2: a read of another entry cancels a queued prefetch. The
        // read queue is held by a blocker; the prefetch of page 2 is queued
        // behind it; page 4 is then read on another thread. Once that read
        // has registered, the blocker goes: the prefetch must return
        // without reading, and only page 4's stream is opened. ---
        {
            NSString *p = [gen stringByAppendingPathComponent:@"test_rar4_unordered.cbr"];
            printf("test_rar4_unordered.cbr queued prefetch skipped\n");
            CORarArchive *ar = (CORarArchive *)[[[COArchive alloc] initWithPath:p] autorelease];
            NSMutableArray *pages = [NSMutableArray array];
            for (NSString *name in asciiNames) {
                CORarEntry *e = rarEntryNamed(ar, name);
                if (e) [pages addObject:e];
            }
            if ([pages count] == 4 && [ar usesDirectPositioning]) {
                [ar setPrefetchPageOrder:pages];
                CORarEntry *b = [pages objectAtIndex:1], *d = [pages objectAtIndex:3];
                BOOL ok;
                NSData *data = readWhilePrefetchParked(ar, ivarOf(ar, [CORarArchive class], "readQueue"), 0, NO,
                    ^{ [ar prefetchAfterEntry:[pages objectAtIndex:0]]; }, d, &ok);
                check(ok, @"queued RAR prefetch: timed out");
                check([sha256(data) isEqualToString:[srcHashes objectAtIndex:3]], @"queued RAR prefetch: page 4 sha");
                check([ar prefetchCount] == 1 && [ar prefetchCancelledCount] == 1 && [ar prefetchSkippedCount] == 1 &&
                      [ar prefetchAbortedCount] == 0,
                      [NSString stringWithFormat:@"queued RAR prefetch: scheduled %lu cancelled %lu skipped %lu aborted %lu",
                       (unsigned long)[ar prefetchCount], (unsigned long)[ar prefetchCancelledCount],
                       (unsigned long)[ar prefetchSkippedCount], (unsigned long)[ar prefetchAbortedCount]]);
                check([ivarOf(ar, [CORarArchive class], "dataCache")
                       objectForKey:[NSNumber numberWithUnsignedInteger:b->ordinal]] == nil,
                      @"queued RAR prefetch: page 2 was read anyway");
                check([ar positionedOpenCount] == 1 && [ar rewindCount] == 0,
                      [NSString stringWithFormat:@"queued RAR prefetch: %lu positioned opens (want 1)",
                       (unsigned long)[ar positionedOpenCount]]);
                check([sha256([b data]) isEqualToString:[srcHashes objectAtIndex:1]], @"queued RAR prefetch: page 2 afterwards");
            } else {
                check(NO, @"test_rar4_unordered.cbr: expected 4 positioned pages");
            }
        }
        {
            NSString *p = [gen stringByAppendingPathComponent:@"test.cbz"];
            printf("test.cbz queued prefetch skipped\n");
            COZipArchive *ar = (COZipArchive *)[[[COArchive alloc] initWithPath:p] autorelease];
            if ([ar isKindOfClass:[COZipArchive class]] && [ar itemCount] == 4) {
                COZipEntry *b = [[ar contents] objectAtIndex:1];
                COZipEntry *d = [[ar contents] objectAtIndex:3];
                BOOL ok;
                NSData *data = readWhilePrefetchParked(ar, ivarOf(ar, [COZipArchive class], "readQueue"), 0, NO,
                    ^{ [ar prefetchAfterOrdinal:0]; }, d, &ok);
                check(ok, @"queued ZIP prefetch: timed out");
                check([sha256(data) isEqualToString:[srcHashes objectAtIndex:3]], @"queued ZIP prefetch: entry 4 sha");
                check([ar prefetchCount] == 1 && [ar prefetchCancelledCount] == 1 && [ar prefetchSkippedCount] == 1 &&
                      [ar prefetchAbortedCount] == 0,
                      [NSString stringWithFormat:@"queued ZIP prefetch: scheduled %lu cancelled %lu skipped %lu aborted %lu",
                       (unsigned long)[ar prefetchCount], (unsigned long)[ar prefetchCancelledCount],
                       (unsigned long)[ar prefetchSkippedCount], (unsigned long)[ar prefetchAbortedCount]]);
                check([ivarOf(ar, [COZipArchive class], "dataCache")
                       objectForKey:[NSNumber numberWithUnsignedLongLong:b->zipIndex]] == nil,
                      @"queued ZIP prefetch: entry 2 was read anyway");
            } else {
                check(NO, @"test.cbz: expected 4 entries on COZipArchive");
            }
        }

        // --- B2: a running prefetch is stopped where that is cheap. Each
        // case parks the prefetch at a checkpoint, reads another page on a
        // second thread, then lets the prefetch go on. ---
        if ([largeHashes count] == 4) {
            // positioned cursor, mid-entry: page 2's prefetch (1 MB, past
            // the 256 KB chunk) stops after its first chunk for page 4
            NSString *p = [gen stringByAppendingPathComponent:@"test_rar4_large.cbr"];
            printf("test_rar4_large.cbr running prefetch aborted mid-entry\n");
            CORarArchive *ar = (CORarArchive *)[[[COArchive alloc] initWithPath:p] autorelease];
            if ([ar isKindOfClass:[CORarArchive class]] && [ar itemCount] == 4 && [ar usesDirectPositioning]) {
                NSArray *pages = [ar contents];
                [ar setPrefetchPageOrder:pages];
                CORarEntry *b = [pages objectAtIndex:1];
                BOOL ok;
                NSData *data = readWhilePrefetchParked(ar, nil, b->ordinal, YES,
                    ^{ [[pages objectAtIndex:0] data]; }, [pages objectAtIndex:3], &ok);
                check(ok, @"mid-entry abort: timed out");
                check([sha256(data) isEqualToString:[largeHashes objectAtIndex:3]], @"mid-entry abort: page 4 sha");
                check([ar prefetchAbortedCount] == 1 && [ar prefetchSkippedCount] == 0,
                      [NSString stringWithFormat:@"mid-entry abort: aborted %lu skipped %lu",
                       (unsigned long)[ar prefetchAbortedCount], (unsigned long)[ar prefetchSkippedCount]]);
                check([ivarOf(ar, [CORarArchive class], "dataCache")
                       objectForKey:[NSNumber numberWithUnsignedInteger:b->ordinal]] == nil,
                      @"mid-entry abort: the partial page 2 was cached");
                // page 1 opened, page 2 continued on it, page 4 opened anew
                check([ar positionedOpenCount] == 2 && [ar cursorContinueCount] == 1 && [ar rewindCount] == 0,
                      [NSString stringWithFormat:@"mid-entry abort: opens %lu continues %lu rewinds %lu",
                       (unsigned long)[ar positionedOpenCount], (unsigned long)[ar cursorContinueCount],
                       (unsigned long)[ar rewindCount]]);
                check([sha256([b data]) isEqualToString:[largeHashes objectAtIndex:1]], @"mid-entry abort: page 2 afterwards");
            } else {
                check(NO, @"test_rar4_large.cbr: expected 4 positioned entries");
            }
        }
        {
            // forward cursor (the fallback-indexed RAR4 has no offsets).
            // Stored and page order alike: 003, 001, 004, 002.
            NSString *p = [gen stringByAppendingPathComponent:@"test_rar4_unordered_unicode.cbr"];
            NSArray *storedSrc = @[ @2, @0, @3, @1 ];	// srcHashes index per stored entry
            printf("test_rar4_unordered_unicode.cbr running prefetch, forward cursor\n");

            // the wanted entry lies ahead: the prefetch must finish
            CORarArchive *ar = (CORarArchive *)[[[COArchive alloc] initWithPath:p] autorelease];
            if ([ar isKindOfClass:[CORarArchive class]] && [ar itemCount] == 4 && ![ar usesDirectPositioning]) {
                NSArray *e = [ar contents];
                [ar setPrefetchPageOrder:e];
                CORarEntry *b = [e objectAtIndex:1];
                BOOL ok;
                NSData *data = readWhilePrefetchParked(ar, nil, b->ordinal, YES,
                    ^{ [[e objectAtIndex:0] data]; }, [e objectAtIndex:3], &ok);
                check(ok, @"forward, wanted ahead: timed out");
                check([sha256(data) isEqualToString:[srcHashes objectAtIndex:[[storedSrc objectAtIndex:3] intValue]]],
                      @"forward, wanted ahead: sha");
                check([ar prefetchAbortedCount] == 0 && [ar prefetchSkippedCount] == 0,
                      @"forward, wanted ahead: the prefetch was stopped");
                check([ivarOf(ar, [CORarArchive class], "dataCache")
                       objectForKey:[NSNumber numberWithUnsignedInteger:b->ordinal]] != nil,
                      @"forward, wanted ahead: the prefetched entry is not cached");
                check([ar rewindCount] == 1 && [ar cursorContinueCount] == 2,
                      [NSString stringWithFormat:@"forward, wanted ahead: rewinds %lu continues %lu",
                       (unsigned long)[ar rewindCount], (unsigned long)[ar cursorContinueCount]]);
            } else {
                check(NO, @"test_rar4_unordered_unicode.cbr: expected 4 entries on the forward cursor");
            }

            // the wanted entry lies behind: the prefetch stops mid-entry
            ar = (CORarArchive *)[[[COArchive alloc] initWithPath:p] autorelease];
            if ([ar isKindOfClass:[CORarArchive class]] && [ar itemCount] == 4) {
                NSArray *e = [ar contents];
                [ar setPrefetchPageOrder:e];
                CORarEntry *c = [e objectAtIndex:2];
                BOOL ok;
                NSData *data = readWhilePrefetchParked(ar, nil, c->ordinal, YES,
                    ^{ [[e objectAtIndex:1] data]; }, [e objectAtIndex:0], &ok);
                check(ok, @"forward, wanted behind: timed out");
                check([sha256(data) isEqualToString:[srcHashes objectAtIndex:[[storedSrc objectAtIndex:0] intValue]]],
                      @"forward, wanted behind: sha");
                check([ar prefetchAbortedCount] == 1, @"forward, wanted behind: the prefetch was not stopped");
                check([ivarOf(ar, [CORarArchive class], "dataCache")
                       objectForKey:[NSNumber numberWithUnsignedInteger:c->ordinal]] == nil,
                      @"forward, wanted behind: the partial entry was cached");
                check([ar rewindCount] == 2,
                      [NSString stringWithFormat:@"forward, wanted behind: rewinds %lu (want 2)",
                       (unsigned long)[ar rewindCount]]);
                check([sha256([c data]) isEqualToString:[srcHashes objectAtIndex:[[storedSrc objectAtIndex:2] intValue]]],
                      @"forward, wanted behind: entry afterwards");
            }

            // the wanted entry lies behind but is already cached: a second
            // thread missed the cache for entry 2 just before its read
            // stored it, and registers its demand only once entry 3's
            // prefetch is decoding. That read needs no cursor, so the
            // prefetch must finish and keep the cursor for entry 4.
            ar = (CORarArchive *)[[[COArchive alloc] initWithPath:p] autorelease];
            if ([ar isKindOfClass:[CORarArchive class]] && [ar itemCount] == 4) {
                NSArray *e = [ar contents];
                [ar setPrefetchPageOrder:e];
                CORarEntry *b = [e objectAtIndex:1], *c = [e objectAtIndex:2];
                NSCache *cache = ivarOf(ar, [CORarArchive class], "dataCache");
                check(b->ordinal < c->ordinal, @"forward, wanted behind and cached: stored order");
                hookReached = dispatch_semaphore_create(0);
                hookRelease = dispatch_semaphore_create(0);
                hookOrdinal = c->ordinal;
                hookDecoding = YES;
                atomic_store(&hookArmed, 1);
                CORarPrefetchCheckpointHookForTesting = parkingCheckpointHook;
                NSData *first = [b data];	// rewind 1; schedules entry 3's prefetch
                BOOL parked = dispatch_semaphore_wait(hookReached,
                    dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)) == 0;
                check(parked, @"forward, wanted behind and cached: timed out");
                if (parked) {
                    check([cache objectForKey:[NSNumber numberWithUnsignedInteger:b->ordinal]] != nil,
                          @"forward, wanted behind and cached: entry 2 not cached");
                    // the racing read's registration, as -dataForEntry: makes it
                    // after its cache miss
                    [ar noteDemandReadOfKey:b->ordinal];
                    check([ar prefetchCancelledCount] == 1,
                          @"forward, wanted behind and cached: the demand did not cancel");
                } else {
                    atomic_store(&hookArmed, 0);
                }
                dispatch_semaphore_signal(hookRelease);
                [ar positionedOpenCount];	// let the prefetch finish
                CORarPrefetchCheckpointHookForTesting = NULL;
                check([cache objectForKey:[NSNumber numberWithUnsignedInteger:c->ordinal]] != nil,
                      @"forward, wanted behind and cached: the prefetch did not cache entry 3");
                NSData *again = [b data];	// the racing read, served from the cache
                NSString *bHash = [srcHashes objectAtIndex:[[storedSrc objectAtIndex:1] intValue]];
                check([sha256(first) isEqualToString:bHash] && [sha256(again) isEqualToString:bHash],
                      @"forward, wanted behind and cached: entry 2 sha");
                check([ar prefetchAbortedCount] == 0 && [ar prefetchSkippedCount] == 0,
                      [NSString stringWithFormat:@"forward, wanted behind and cached: aborted %lu skipped %lu",
                       (unsigned long)[ar prefetchAbortedCount], (unsigned long)[ar prefetchSkippedCount]]);
                check([ar rewindCount] == 1,
                      [NSString stringWithFormat:@"forward, wanted behind and cached: rewinds %lu (want 1)",
                       (unsigned long)[ar rewindCount]]);
                // entry 4 continues on the kept cursor
                check([sha256([[e objectAtIndex:3] data]) isEqualToString:
                       [srcHashes objectAtIndex:[[storedSrc objectAtIndex:3] intValue]]],
                      @"forward, wanted behind and cached: entry 4 sha");
                check([ar rewindCount] == 1 && [ar cursorContinueCount] == 2,
                      [NSString stringWithFormat:@"forward, wanted behind and cached: rewinds %lu continues %lu (want 1, 2)",
                       (unsigned long)[ar rewindCount], (unsigned long)[ar cursorContinueCount]]);
                dispatch_release(hookReached);
                dispatch_release(hookRelease);
            }

            // stopped between entries: the prefetch of entry 4 walks past
            // entry 2, which is then read; the cursor is kept, so that read
            // continues on it instead of starting over
            ar = (CORarArchive *)[[[COArchive alloc] initWithPath:p] autorelease];
            if ([ar isKindOfClass:[CORarArchive class]] && [ar itemCount] == 4) {
                NSArray *e = [ar contents];
                [ar setPrefetchPageOrder:@[ [e objectAtIndex:0], [e objectAtIndex:3], [e objectAtIndex:1] ]];
                CORarEntry *last = [e objectAtIndex:3];
                BOOL ok;
                NSData *data = readWhilePrefetchParked(ar, nil, last->ordinal, NO,
                    ^{ [[e objectAtIndex:0] data]; }, [e objectAtIndex:1], &ok);
                check(ok, @"forward, between entries: timed out");
                check([sha256(data) isEqualToString:[srcHashes objectAtIndex:[[storedSrc objectAtIndex:1] intValue]]],
                      @"forward, between entries: sha");
                check([ar prefetchAbortedCount] == 1, @"forward, between entries: the prefetch was not stopped");
                check([ar rewindCount] == 1 && [ar cursorContinueCount] == 2,
                      [NSString stringWithFormat:@"forward, between entries: rewinds %lu continues %lu (want 1, 2)",
                       (unsigned long)[ar rewindCount], (unsigned long)[ar cursorContinueCount]]);
                check([ivarOf(ar, [CORarArchive class], "dataCache")
                       objectForKey:[NSNumber numberWithUnsignedInteger:last->ordinal]] == nil,
                      @"forward, between entries: entry 4 was cached");
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
