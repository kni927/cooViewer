// bench.m — archive-layer timing harness for tools/cbr_bench (see README.md).
//
// Built three times from this one file by run_bench.sh:
//   current  — the working tree's Sources/COArchive.m, CORarArchive.m, ...
//   before   — the same files exported from a git ref (BEFORE_REF)
//   v137     — v1.3.7's XADWrapper.m / XADItem.m against XADMaster.framework
//              (compiled with -DBENCH_XAD)
// Each goes through the object COImageLoader uses: -contents, a sort with
// -finderCompareS:, then -[item data]. The current build also hands the
// page order to the archive (-setPrefetchPageOrder:), as COImageLoader does.
//
// usage: bench <scenario> <archive>
//   open      open, list and sort; page 1 data, then a full ImageIO decode
//   seq       every page in page order, back to back
//   paced     the first 30 pages, one every 300 ms
//   jump      page 1, the middle page, the last page, page 1, the page ¼ in
//   back      every page in page order (untimed), then N pages before the
//             last for N = 3, 10, 100, 200, 300 (those that exist), in turn
//   idlejump  open, wait BENCH_IDLE_MS (default 10000) without reading,
//             then the jump steps: for background work started at open
//             (decode-ahead) to finish or make progress first
// Prints one JSON object on stdout.
//
// Decode-ahead (B3): when the archive responds to -setDecodeAheadDirectory:,
// it gets a fresh directory under $TMPDIR right after the page order, inside
// the timed open (as COImageLoader sets it after the open), removed at the
// end. BENCH_DECODE_AHEAD=0 leaves it off.
//
// Diagnostic counters: after the timed reads, every zero-argument integer
// or BOOL method of the archive named in kCounterNames or in the
// BENCH_COUNTERS environment variable (comma or space separated) that the
// archive responds to is reported under "counters". respondsToSelector:
// keeps the harness building and running against a ref that lacks them.

#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <sys/resource.h>
#include <stdlib.h>
#include <unistd.h>

#ifdef BENCH_XAD
#import "XADWrapper.h"
#import "XADItem.h"
#else
#import "COArchive.h"
#include <archive.h>
#endif
#import "NSString_Compare.h"

static double nowMs(void)
{
    static mach_timebase_info_data_t tb;
    if (tb.denom == 0) mach_timebase_info(&tb);
    return (double)mach_absolute_time() * tb.numer / tb.denom / 1e6;
}

#ifndef BENCH_XAD
/* The libarchive-based sources (COArchive.m, CORarArchive.m, ...) are
   compiled with -Darchive_read_open_filename=...: every stream they open,
   from the start or (positioned) mid-file, is counted here. */
static unsigned long gStreamOpens = 0;
int cobench_open_filename(struct archive *a, const char *path, size_t block)
{
    gStreamOpens++;
    return archive_read_open_filename(a, path, block);
}
int cobench_open2(struct archive *a, void *data, archive_open_callback *o,
                  archive_read_callback *r, archive_skip_callback *s, archive_close_callback *c)
{
    gStreamOpens++;
    return archive_read_open2(a, data, o, r, s, c);
}
#endif

/* Counters read if the archive has them. The first three exist since the
   B1/B2 work of 2026-10-04 (COArchive -prefetchCount, CORarArchive
   -rewindCount / -positionedOpenCount); the rest are names later work may
   add. Others can be named in BENCH_COUNTERS. */
static NSString *const kCounterNames[] = {
    @"prefetchCount", @"rewindCount", @"positionedOpenCount",
    @"cursorContinueCount", @"prefetchSkippedCount", @"prefetchCancelledCount",
    @"prefetchAbortedCount", @"decodeAheadEntryCount", @"decodeAheadByteCount",
    @"decodeAheadWriteThroughCount", @"decodeAheadDiskHitCount", @"decodeAheadAwaitCount",
    @"decodeAheadDiskByteCount",
    @"decodeAheadByteBound", @"decodeAheadPassMilliseconds", @"decodeAheadPassCPUMilliseconds",
    @"decodeAheadPassYieldMilliseconds", @"decodeAheadPassEnded",
};

static NSString *jsonNumbers(NSArray *values)
{
    return [NSString stringWithFormat:@"[%@]", [values componentsJoinedByString:@","]];
}

static NSString *jsonStrings(NSArray *values)
{
    NSMutableArray *quoted = [NSMutableArray array];
    for (NSString *s in values) [quoted addObject:[NSString stringWithFormat:@"\"%@\"", s]];
    return jsonNumbers(quoted);
}

/* "counters":{...} for every counter the archive responds to. */
static NSString *countersJSON(id archive)
{
    NSMutableArray *names = [NSMutableArray array];
    for (size_t i = 0; i < sizeof kCounterNames / sizeof kCounterNames[0]; i++)
        [names addObject:kCounterNames[i]];
    const char *extra = getenv("BENCH_COUNTERS");
    if (extra) {
        NSCharacterSet *sep = [NSCharacterSet characterSetWithCharactersInString:@", "];
        for (NSString *n in [[NSString stringWithUTF8String:extra] componentsSeparatedByCharactersInSet:sep])
            if ([n length] > 0 && ![names containsObject:n]) [names addObject:n];
    }
    NSMutableArray *pairs = [NSMutableArray array];
    for (NSString *name in names) {
        SEL sel = NSSelectorFromString(name);
        if (![archive respondsToSelector:sel]) continue;
        NSMethodSignature *sig = [archive methodSignatureForSelector:sel];
        if ([sig numberOfArguments] != 2 || [sig methodReturnLength] > 8) continue;
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setSelector:sel];
        [inv invokeWithTarget:archive];
        unsigned char buf[8] = {0};
        [inv getReturnValue:buf];
        long long v;
        switch ([sig methodReturnType][0]) {
            case 'c': v = *(signed char *)buf; break;
            case 'B':
            case 'C': v = *(unsigned char *)buf; break;
            case 's': v = *(short *)buf; break;
            case 'S': v = *(unsigned short *)buf; break;
            case 'i': v = *(int *)buf; break;
            case 'I': v = *(unsigned int *)buf; break;
            case 'l':
            case 'q': v = *(long long *)buf; break;
            case 'L':
            case 'Q': v = (long long)*(unsigned long long *)buf; break;
            default: continue;	// not an integer: not a counter
        }
        [pairs addObject:[NSString stringWithFormat:@"\"%@\":%lld", name, v]];
    }
    return [NSString stringWithFormat:@"{%@}", [pairs componentsJoinedByString:@","]];
}

int main(int argc, char **argv)
{
    if (argc != 3) {
        fprintf(stderr, "usage: %s open|seq|paced|jump|back|idlejump <archive>\n", argv[0]);
        return 64;
    }
    @autoreleasepool {
        NSString *scenario = [NSString stringWithUTF8String:argv[1]];
        NSString *path = [NSString stringWithUTF8String:argv[2]];

        double t0 = nowMs();
#ifdef BENCH_XAD
        XADWrapper *archive = [[XADWrapper alloc] initWithPath:path];
#else
        COArchive *archive = [[COArchive alloc] initWithPath:path];
#endif
        NSArray *items = [archive contents];
        NSMutableArray *pages = [NSMutableArray arrayWithArray:items];
        [pages sortUsingComparator:^NSComparisonResult(id a, id b) {
            return [[a path] finderCompareS:[b path]];
        }];
#ifndef BENCH_XAD
        if ([archive respondsToSelector:@selector(setPrefetchPageOrder:)])
            [archive performSelector:@selector(setPrefetchPageOrder:) withObject:pages];
        NSString *decodeAheadDir = nil;
        const char *da = getenv("BENCH_DECODE_AHEAD");
        if ((!da || strcmp(da, "0") != 0) &&
            [archive respondsToSelector:@selector(setDecodeAheadDirectory:)]) {
            const char *tmp = getenv("TMPDIR");
            NSString *template = [[NSString stringWithUTF8String:tmp ? tmp : "/tmp"]
                                  stringByAppendingPathComponent:@"cbr_bench_da.XXXXXX"];
            char buffer[PATH_MAX];
            if ([template getFileSystemRepresentation:buffer maxLength:sizeof(buffer)] && mkdtemp(buffer)) {
                decodeAheadDir = [NSString stringWithUTF8String:buffer];
                [archive performSelector:@selector(setDecodeAheadDirectory:) withObject:decodeAheadDir];
            }
        }
        unsigned long opensAtOpen = gStreamOpens;
#endif
        double openMs = nowMs() - t0;
        NSUInteger count = [pages count];
        if (count == 0) {
            fprintf(stderr, "no pages in %s\n", argv[2]);
            return 1;
        }

        NSMutableArray *warmup = [NSMutableArray array];	// read untimed first
        NSMutableArray *indices = [NSMutableArray array];	// timed
        NSMutableArray *steps = [NSMutableArray array];		// labels (back)
        double idleMs = 0;
        if ([scenario isEqualToString:@"open"]) {
            [indices addObject:@0];
        } else if ([scenario isEqualToString:@"seq"]) {
            for (NSUInteger i = 0; i < count; i++) [indices addObject:@(i)];
        } else if ([scenario isEqualToString:@"paced"]) {
            for (NSUInteger i = 0; i < count && i < 30; i++) [indices addObject:@(i)];
        } else if ([scenario isEqualToString:@"jump"] || [scenario isEqualToString:@"idlejump"]) {
            for (NSNumber *n in @[ @0, @(count / 2), @(count - 1), @0, @(count / 4) ])
                [indices addObject:n];
            if ([scenario isEqualToString:@"idlejump"]) {
                const char *e = getenv("BENCH_IDLE_MS");
                idleMs = e ? atof(e) : 10000;
            }
        } else if ([scenario isEqualToString:@"back"]) {
            for (NSUInteger i = 0; i < count; i++) [warmup addObject:@(i)];
            for (NSNumber *n in @[ @3, @10, @100, @200, @300 ]) {
                NSUInteger back = [n unsignedIntegerValue];
                if (back >= count) continue;
                [indices addObject:@(count - 1 - back)];
                [steps addObject:[NSString stringWithFormat:@"-%lu", (unsigned long)back]];
            }
        } else {
            fprintf(stderr, "unknown scenario %s\n", argv[1]);
            return 64;
        }

        unsigned long failures = 0;
        double w0 = nowMs();
        for (NSNumber *n in warmup) {
            NSData *data = [[pages objectAtIndex:[n unsignedIntegerValue]] data];
            if ([data length] == 0) failures++;
        }
        double warmupMs = nowMs() - w0;
        if (idleMs > 0) usleep((useconds_t)(idleMs * 1000));

        NSMutableArray *latencies = [NSMutableArray array];
        double decodeMs = 0;
        double t1 = nowMs();
        for (NSNumber *n in indices) {
            if ([scenario isEqualToString:@"paced"] && [latencies count] > 0) usleep(300 * 1000);
            double s = nowMs();
            NSData *data = [[pages objectAtIndex:[n unsignedIntegerValue]] data];
            double ms = nowMs() - s;
            [latencies addObject:[NSString stringWithFormat:@"%.3f", ms]];
            if ([data length] == 0) failures++;
            if ([scenario isEqualToString:@"open"] && [data length] > 0) {
                double d0 = nowMs();
                CGImageSourceRef src = CGImageSourceCreateWithData((CFDataRef)data, NULL);
                CGImageRef image = src ? CGImageSourceCreateImageAtIndex(src, 0, NULL) : NULL;
                if (image) {
                    // force the decode
                    CFDataRef pixels = CGDataProviderCopyData(CGImageGetDataProvider(image));
                    if (pixels) CFRelease(pixels);
                    CGImageRelease(image);
                }
                if (src) CFRelease(src);
                decodeMs = nowMs() - d0;
            }
        }
        double totalMs = nowMs() - t1;

        printf("{\"scenario\":\"%s\",\"pages\":%lu,\"open_ms\":%.3f,\"total_ms\":%.3f,"
               "\"decode_ms\":%.3f,\"failures\":%lu,",
               argv[1], (unsigned long)count, openMs, totalMs, decodeMs, failures);
        if ([warmup count] > 0) printf("\"warmup_ms\":%.3f,", warmupMs);
        if (idleMs > 0) printf("\"idle_ms\":%.0f,", idleMs);
        if ([steps count] > 0) printf("\"steps\":%s,", [jsonStrings(steps) UTF8String]);
#ifdef BENCH_XAD
        printf("\"stream_opens\":null,\"counters\":{},");
#else
        // stream opens after the open (warm-up, idle and timed reads)
        printf("\"stream_opens\":%lu,", gStreamOpens - opensAtOpen);
        printf("\"counters\":%s,", [countersJSON(archive) UTF8String]);
#endif
        struct rusage usage;
        getrusage(RUSAGE_SELF, &usage);	// ru_maxrss is in bytes on macOS
        printf("\"rss_bytes\":%ld,", (long)usage.ru_maxrss);
        // The kernel's peak physical footprint (what Activity Monitor calls
        // Memory, compressed pages included); ru_maxrss can read far lower
        // when pages are compressed or swapped out.
        task_vm_info_data_t vm;
        mach_msg_type_number_t vmCount = TASK_VM_INFO_COUNT;
        if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&vm, &vmCount) == KERN_SUCCESS
            && vmCount >= TASK_VM_INFO_REV2_COUNT)
            printf("\"footprint_peak_bytes\":%lld,", (long long)vm.ledger_phys_footprint_peak);
        printf("\"latencies_ms\":%s}\n", [jsonNumbers(latencies) UTF8String]);
        [archive release];	// stops a decode-ahead pass and removes its files
#ifndef BENCH_XAD
        if (decodeAheadDir)
            [[NSFileManager defaultManager] removeItemAtPath:decodeAheadDir error:NULL];
#endif
    }
    return 0;
}
