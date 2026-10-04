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
//   open   open, list and sort; page 1 data, then a full ImageIO decode
//   seq    every page in page order, back to back
//   paced  the first 30 pages, one every 300 ms
//   jump   page 1, the middle page, the last page, page 1, the page ¼ in
// Prints one JSON object on stdout.

#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#include <mach/mach_time.h>
#include <sys/resource.h>
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
/* CORarArchive.m is compiled with -Darchive_read_open_filename=...: every
   stream it opens, from the start or (current build) positioned, is counted
   here. */
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

static NSString *jsonNumbers(NSArray *values)
{
    return [NSString stringWithFormat:@"[%@]", [values componentsJoinedByString:@","]];
}

int main(int argc, char **argv)
{
    if (argc != 3) {
        fprintf(stderr, "usage: %s open|seq|paced|jump <archive>\n", argv[0]);
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
        unsigned long opensAtOpen = gStreamOpens;
#endif
        double openMs = nowMs() - t0;
        NSUInteger count = [pages count];
        if (count == 0) {
            fprintf(stderr, "no pages in %s\n", argv[2]);
            return 1;
        }

        NSMutableArray *indices = [NSMutableArray array];
        if ([scenario isEqualToString:@"open"]) {
            [indices addObject:@0];
        } else if ([scenario isEqualToString:@"seq"]) {
            for (NSUInteger i = 0; i < count; i++) [indices addObject:@(i)];
        } else if ([scenario isEqualToString:@"paced"]) {
            for (NSUInteger i = 0; i < count && i < 30; i++) [indices addObject:@(i)];
        } else if ([scenario isEqualToString:@"jump"]) {
            for (NSNumber *n in @[ @0, @(count / 2), @(count - 1), @0, @(count / 4) ])
                [indices addObject:n];
        } else {
            fprintf(stderr, "unknown scenario %s\n", argv[1]);
            return 64;
        }

        NSMutableArray *latencies = [NSMutableArray array];
        unsigned long failures = 0;
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
#ifdef BENCH_XAD
        printf("\"stream_opens\":null,");
#else
        printf("\"stream_opens\":%lu,", gStreamOpens - opensAtOpen);
#endif
        struct rusage usage;
        getrusage(RUSAGE_SELF, &usage);	// ru_maxrss is in bytes on macOS
        printf("\"rss_bytes\":%ld,", (long)usage.ru_maxrss);
        printf("\"latencies_ms\":%s}\n", [jsonNumbers(latencies) UTF8String]);
        [archive release];
    }
    return 0;
}
