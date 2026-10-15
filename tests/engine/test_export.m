// File ▸ Export… harness: the page list, file and entry names, the store-only
// ZIP writer (COExport.m), and whole exports of fixture books through
// COImageLoader -exportPageAtIndex: and COExportPages, read back with libzip
// and re-opened by cooViewer's own loader. Built and run by run_tests.sh.
//
// Usage: test_export <generated-fixtures-dir> <src-dir> <output-dir>

#import <Cocoa/Cocoa.h>
#import "COImageLoader.h"
#import "COExport.h"
#import "CORarArchive.h"
#include <mach/mach_time.h>
#include <zip.h>
#include <archive.h>
#include <archive_entry.h>

// As in test_imageloader.m: nested archives go under $TMPDIR, which a
// sandboxed run can write, rather than the per-user temporary directory.
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

static NSString *indexString(NSIndexSet *set)
{
    if (!set) return @"nil";
    NSMutableArray *parts = [NSMutableArray array];
    [set enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) {
        [parts addObject:[NSString stringWithFormat:@"%lu", (unsigned long)i]];
    }];
    return [parts componentsJoinedByString:@","];
}

#pragma mark page list

static void parseOK(NSString *text, NSUInteger count, NSString *want)
{
    COExportPageListError error = COExportPageListOK;
    NSIndexSet *got = COExportParsePageList(text, count, &error, NULL);
    check(got != nil && error == COExportPageListOK && [indexString(got) isEqualToString:want],
          [NSString stringWithFormat:@"parse \"%@\" of %lu: got %@ (error %d), want %@",
           text, (unsigned long)count, indexString(got), (int)error, want]);
}

static void parseBad(NSString *text, NSUInteger count, COExportPageListError want, NSString *wantToken)
{
    COExportPageListError error = COExportPageListOK;
    NSString *bad = nil;
    NSIndexSet *got = COExportParsePageList(text, count, &error, &bad);
    BOOL tokenOK = wantToken == nil || [bad isEqualToString:wantToken];
    check(got == nil && error == want && tokenOK,
          [NSString stringWithFormat:@"parse \"%@\" of %lu: got %@ (error %d, token \"%@\"), want error %d \"%@\"",
           text, (unsigned long)count, indexString(got), (int)error, bad, (int)want, wantToken]);
}

static void testPageList(void)
{
    printf("page list\n");
    parseOK(@"", 4, @"0,1,2,3");
    parseOK(@"   ", 4, @"0,1,2,3");
    parseOK(nil, 3, @"0,1,2");
    parseOK(@"5", 40, @"4");
    parseOK(@"20-30", 40, @"19,20,21,22,23,24,25,26,27,28,29");
    parseOK(@"1-3,7,10-12", 40, @"0,1,2,6,9,10,11");
    parseOK(@" 1 - 3 , 7 ", 40, @"0,1,2,6");
    parseOK(@"7,1-3", 40, @"0,1,2,6");          // book order, not typed order
    parseOK(@"1-3,2-4,3", 40, @"0,1,2,3");      // overlaps once
    parseOK(@"4-4", 4, @"3");
    parseOK(@"1-4", 4, @"0,1,2,3");

    parseBad(@"0", 4, COExportPageListOutOfRange, @"0");
    parseBad(@"5", 4, COExportPageListOutOfRange, @"5");
    parseBad(@"1,3-5", 4, COExportPageListOutOfRange, @"3-5");
    parseBad(@"99999999999999", 4, COExportPageListOutOfRange, nil);
    parseBad(@"3-1", 4, COExportPageListReversed, @"3-1");
    parseBad(@"a", 4, COExportPageListSyntax, @"a");
    parseBad(@"1,,2", 4, COExportPageListSyntax, @"");
    parseBad(@",", 4, COExportPageListSyntax, nil);
    parseBad(@"1,", 4, COExportPageListSyntax, nil);
    parseBad(@"1-", 4, COExportPageListSyntax, @"1-");
    parseBad(@"-3", 4, COExportPageListSyntax, @"-3");
    parseBad(@"1-2-3", 4, COExportPageListSyntax, @"1-2-3");
    parseBad(@"1.5", 4, COExportPageListSyntax, @"1.5");
    parseBad(@"+2", 4, COExportPageListSyntax, @"+2");
    parseBad(@"１", 4, COExportPageListSyntax, nil);     // full-width digit
    parseBad(@"1;2", 4, COExportPageListSyntax, nil);
    parseBad(@"", 0, COExportPageListEmpty, nil);
}

#pragma mark names

static void checkString(NSString *got, NSString *want, NSString *what)
{
    check([got isEqualToString:want],
          [NSString stringWithFormat:@"%@: got \"%@\", want \"%@\"", what, got, want]);
}

static void testNames(void)
{
    printf("file and entry names\n");
    checkString(COExportSanitizedFileName(@"a,b/c:d\\e*f?g\"h<i>j|k"), @"a_b_c_d_e_f_g_h_i_j_k", @"sanitize unsafe");
    checkString(COExportSanitizedFileName(@".hidden"), @"_hidden", @"sanitize leading dot");
    checkString(COExportSanitizedFileName(@"tab\there"), @"tab_here", @"sanitize control");
    checkString(COExportSanitizedFileName(@"日本語 1"), @"日本語 1", @"sanitize keeps others");

    checkString(COExportDefaultFileName(@"Book", @""), @"Book-export.cbz", @"default name, all pages");
    checkString(COExportDefaultFileName(@"Book", @"  "), @"Book-export.cbz", @"default name, blank");
    checkString(COExportDefaultFileName(@"Book", @"20-30"), @"Book-export-20-30.cbz", @"default name, range");
    checkString(COExportDefaultFileName(@"Book", @"1-3,7,10-12"), @"Book-export-1-3_7_10-12.cbz", @"default name, list");
    checkString(COExportDefaultFileName(@"Book", @" 1 - 3 , 7 "), @"Book-export-1-3_7.cbz", @"default name, spaces");
    checkString(COExportDefaultFileName(@"A/B:C", @"5"), @"A_B_C-export-5.cbz", @"default name, unsafe book name");
    checkString(COExportDefaultFileName(@"", @""), @"book-export.cbz", @"default name, no book name");

    NSArray *normal = @[@"001.png", @"002.jpg", @"003.png", @"004.jpg"];
    check([COExportEntryNames(normal) isEqualToArray:normal], @"entry names: in order, kept");
    check(!COExportNamesNeedSequencePrefix(normal), @"entry names: in order, no prefix");

    NSArray *nested = @[@"book/001.png", @"book/sub/002.jpg"];
    check([COExportEntryNames(nested) isEqualToArray:(@[@"001.png", @"002.jpg"])], @"entry names: flattened");

    NSArray *collide = @[@"a/001.png", @"b/001.png"];
    check([COExportEntryNames(collide) isEqualToArray:(@[@"0001_001.png", @"0002_001.png"])],
          [NSString stringWithFormat:@"entry names: collision prefixed, got %@", COExportEntryNames(collide)]);
    check(COExportNamesNeedSequencePrefix(@[@"A.jpg", @"a.jpg"]), @"entry names: case-only collision");
    NSArray *reversed = @[@"002.jpg", @"001.png"];
    check([COExportEntryNames(reversed) isEqualToArray:(@[@"0001_002.jpg", @"0002_001.png"])],
          @"entry names: out of order prefixed");
    // Finder order agrees, byte order does not: many readers sort by bytes
    check(COExportNamesNeedSequencePrefix(@[@"1.jpg", @"2.jpg", @"10.jpg"]), @"entry names: numeric names prefixed");
    // byte order agrees, Finder order does not
    check(COExportNamesNeedSequencePrefix(@[@"a10.jpg", @"a9.jpg"]), @"entry names: Finder misorder prefixed");
    check(!COExportNamesNeedSequencePrefix(@[@"a01.jpg", @"a02.jpg", @"b01.jpg"]), @"entry names: ordered both ways");
    check([COExportEntryNames(@[@"x.png"]) isEqualToArray:(@[@"x.png"])], @"entry names: one page");

    NSMutableArray *many = [NSMutableArray array];
    int i;
    for (i = 0; i < 10000; i++) [many addObject:@"p.png"];
    NSArray *manyNames = COExportEntryNames(many);
    checkString([manyNames objectAtIndex:0], @"00001_p.png", @"entry names: width grows past 9999 pages");
    checkString([manyNames lastObject], @"10000_p.png", @"entry names: last of 10000");
}

#pragma mark reading back

static NSData *zipEntryData(zip_t *za, zip_uint64_t index)
{
    zip_stat_t st;
    zip_stat_init(&st);
    if (zip_stat_index(za, index, 0, &st) != 0) return nil;
    zip_file_t *zf = zip_fopen_index(za, index, 0);
    if (!zf) return nil;
    NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)st.size];
    zip_int64_t n = zip_fread(zf, [data mutableBytes], st.size);
    zip_fclose(zf);
    return (n == (zip_int64_t)st.size) ? data : nil;
}

/* Checks the exported file: entry names, every entry stored, bytes equal to
   `expected` (NSData per page). */
static void checkZip(NSString *label, NSString *path, NSArray *wantNames, NSArray *expected)
{
    int err = 0;
    zip_t *za = zip_open([path fileSystemRepresentation], ZIP_RDONLY | ZIP_CHECKCONS, &err);
    check(za != NULL, [NSString stringWithFormat:@"%@: opens as a ZIP (error %d)", label, err]);
    if (!za) return;
    zip_int64_t n = zip_get_num_entries(za, 0);
    check(n == (zip_int64_t)[wantNames count],
          [NSString stringWithFormat:@"%@: %lld entries, want %lu", label, n, (unsigned long)[wantNames count]]);
    zip_int64_t i;
    for (i = 0; i < n && i < (zip_int64_t)[wantNames count]; i++) {
        zip_stat_t st;
        zip_stat_init(&st);
        zip_stat_index(za, (zip_uint64_t)i, 0, &st);
        NSString *name = [NSString stringWithUTF8String:st.name];
        check([name isEqualToString:[wantNames objectAtIndex:(NSUInteger)i]],
              [NSString stringWithFormat:@"%@: entry %lld is %@, want %@", label, i, name, [wantNames objectAtIndex:(NSUInteger)i]]);
        check(st.comp_method == ZIP_CM_STORE,
              [NSString stringWithFormat:@"%@: entry %lld stored (method %d)", label, i, (int)st.comp_method]);
        check(st.encryption_method == ZIP_EM_NONE,
              [NSString stringWithFormat:@"%@: entry %lld not encrypted", label, i]);
        NSData *data = zipEntryData(za, (zip_uint64_t)i);
        check([data isEqualToData:[expected objectAtIndex:(NSUInteger)i]],
              [NSString stringWithFormat:@"%@: entry %lld byte-identical (%lu vs %lu bytes)", label, i,
               (unsigned long)[data length], (unsigned long)[[expected objectAtIndex:(NSUInteger)i] length]]);
    }
    zip_close(za);
}

#pragma mark modification times

/* An archive's entry times as libarchive reads them, by entry path: the
   reference the export is compared with, read apart from cooViewer's own
   readers (libzip for ZIP, the RAR header index). */
static NSDictionary *referenceMTimes(NSString *archivePath)
{
    static NSMutableDictionary *cache = nil;
    if (!cache) cache = [[NSMutableDictionary alloc] init];
    NSDictionary *cached = [cache objectForKey:archivePath];
    if (cached) return cached;
    NSMutableDictionary *times = [NSMutableDictionary dictionary];
    struct archive *a = archive_read_new();
    archive_read_support_format_all(a);
    archive_read_support_filter_all(a);
    if (archive_read_open_filename(a, [archivePath fileSystemRepresentation], 65536) == ARCHIVE_OK) {
        struct archive_entry *entry;
        while (archive_read_next_header(a, &entry) == ARCHIVE_OK) {
            const char *name = archive_entry_pathname_utf8(entry);
            if (!name) name = archive_entry_pathname(entry);
            if (name && archive_entry_mtime_is_set(entry)) {
                [times setObject:[NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)archive_entry_mtime(entry)]
                          forKey:[NSString stringWithUTF8String:name]];
            }
            archive_read_data_skip(a);
        }
    }
    archive_read_free(a);
    [cache setObject:times forKey:archivePath];
    return times;
}

/* The time the export should keep for a page: the file's, or the entry's
   in its archive (nil when there is none). */
static NSDate *referenceMTime(COExportPage *page)
{
    if ([page filePath]) {
        return [[[NSFileManager defaultManager] attributesOfItemAtPath:[page filePath] error:NULL] fileModificationDate];
    }
    id archive = [page archive];
    if (![archive respondsToSelector:@selector(filePath)] || ![[page entry] respondsToSelector:@selector(path)]) return nil;
    return [referenceMTimes([archive filePath]) objectForKey:[[page entry] path]];
}

/* Every exported entry keeps its original's time, as ZIP stores it: a
   local DOS time, to 2 seconds. The reference can be up to 2 s off that
   either way: a ZIP book's DOS time is what the export keeps, and its
   writer may have rounded it up, while libarchive reports the book's
   extended timestamp when it has one (enc_pages.cbz: DOS :32, extended
   :31). Pages with no time, or one before 1980 that DOS cannot hold, are
   not compared. */
static void checkMTimes(NSString *label, NSString *path, NSArray *pages)
{
    int err = 0;
    zip_t *za = zip_open([path fileSystemRepresentation], ZIP_RDONLY, &err);
    if (!za) return;	/* checkZip reports it */
    NSUInteger compared = 0;
    NSUInteger i;
    for (i = 0; i < [pages count] && (zip_int64_t)i < zip_get_num_entries(za, 0); i++) {
        NSDate *want = referenceMTime([pages objectAtIndex:i]);
        if (!want || [want timeIntervalSince1970] < 315532800.0 + 86400.0) continue;
        zip_stat_t st;
        zip_stat_init(&st);
        if (zip_stat_index(za, (zip_uint64_t)i, 0, &st) != 0 || !(st.valid & ZIP_STAT_MTIME)) {
            check(NO, [NSString stringWithFormat:@"%@: entry %lu has a time", label, (unsigned long)i]);
            continue;
        }
        long long wantSeconds = (long long)floor([want timeIntervalSince1970]);
        long long got = (long long)st.mtime;
        check(llabs(got - wantSeconds) <= 2,
              [NSString stringWithFormat:@"%@: entry %lu keeps the original's time (%lld, want %lld)",
               label, (unsigned long)i, got, wantSeconds]);
        compared++;
    }
    zip_close(za);
    check(compared > 0, [NSString stringWithFormat:@"%@: entry times compared (%lu)", label, (unsigned long)compared]);
}

/* cooViewer's own loader re-opens the export, with the pages in the same
   order. */
static void checkReopen(NSString *label, NSString *path, NSArray *wantNames)
{
    COImageLoader *again = [[[COImageLoader alloc] initWithPath:path readSubFolder:NO controller:nil] autorelease];
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *page in [again pathArray]) [names addObject:[page lastPathComponent]];
    check([again mode] == 2 && [names isEqualToArray:wantNames],
          [NSString stringWithFormat:@"%@: re-opened in order (mode %d): %@", label, [again mode],
           [names componentsJoinedByString:@" "]]);
}

static NSArray *pagesOf(COImageLoader *loader, NSIndexSet *indexes)
{
    NSMutableArray *pages = [NSMutableArray array];
    NSUInteger i = [indexes firstIndex];
    while (i != NSNotFound) {
        COExportPage *page = [loader exportPageAtIndex:(int)i];
        if (!page) return nil;
        [pages addObject:page];
        i = [indexes indexGreaterThanIndex:i];
    }
    return pages;
}

/* No staging directory or temporary ZIP is left beside the output. */
static void checkNoLeftovers(NSString *label, NSString *dir)
{
    for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL]) {
        check(![name hasPrefix:@".cooViewer-export"] && ![name hasPrefix:@".zip"] && [name rangeOfString:@".cbz."].location == NSNotFound,
              [NSString stringWithFormat:@"%@: leftover %@", label, name]);
    }
}

/* Exports `pagesText` of `loader` to out/<file>, then checks it against the
   files in `src` named like each page. */
static void exportAndCheck(NSString *label, COImageLoader *loader, NSString *pagesText,
                           NSString *outDir, NSString *file, NSString *src,
                           NSArray *wantNames)
{
    printf("%s\n", [label UTF8String]);
    NSIndexSet *indexes = COExportParsePageList(pagesText, (NSUInteger)[loader itemCount], NULL, NULL);
    check(indexes != nil, [NSString stringWithFormat:@"%@: pages \"%@\" parse", label, pagesText]);
    NSArray *pages = pagesOf(loader, indexes);
    check(pages != nil, [NSString stringWithFormat:@"%@: every page has bytes", label]);
    if (!pages) return;

    NSString *dest = [outDir stringByAppendingPathComponent:file];
    [[NSFileManager defaultManager] removeItemAtPath:dest error:NULL];
    NSString *message = nil;
    __block double lastProgress = -1.0;
    __block BOOL progressMonotone = YES;
    COExportResult result = COExportPages(pages, [NSURL fileURLWithPath:dest], ^BOOL(void) { return NO; },
        ^(double f) { if (f < lastProgress) progressMonotone = NO; lastProgress = f; },
        NULL, &message);
    check(result == COExportOK, [NSString stringWithFormat:@"%@: exported (result %d, %@)", label, (int)result, message]);
    check(progressMonotone && lastProgress > 0.99,
          [NSString stringWithFormat:@"%@: progress rises to 1 (last %.3f)", label, lastProgress]);

    NSMutableArray *expected = [NSMutableArray array];
    for (COExportPage *page in pages) {
        NSData *original = [NSData dataWithContentsOfFile:[src stringByAppendingPathComponent:[page name]]];
        [expected addObject:original ? original : [NSData data]];
    }
    checkZip(label, dest, wantNames, expected);
    checkMTimes(label, dest, pages);
    checkReopen(label, dest, wantNames);
    checkNoLeftovers(label, outDir);
}

#pragma mark failure paths

@interface UnreadableEntry : NSObject
- (NSData *)data;
@end
@implementation UnreadableEntry
- (NSData *)data { return nil; }
@end

static void testFailures(NSString *outDir, NSString *src)
{
    printf("cancel and read failure\n");
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dest = [outDir stringByAppendingPathComponent:@"existing.cbz"];
    NSData *old = [@"previous contents" dataUsingEncoding:NSUTF8StringEncoding];
    [old writeToFile:dest atomically:NO];

    NSArray *pages = @[[COExportPage pageWithFilePath:[src stringByAppendingPathComponent:@"001.png"]],
                       [COExportPage pageWithEntry:[[[UnreadableEntry alloc] init] autorelease] name:@"x/002.jpg"
                                           archive:@"archive" order:0]];
    NSUInteger failed = 99;
    COExportResult result = COExportPages(pages, [NSURL fileURLWithPath:dest], nil, nil, &failed, NULL);
    check(result == COExportReadFailed && failed == 1,
          [NSString stringWithFormat:@"unreadable page: result %d, page %lu", (int)result, (unsigned long)failed]);
    check([[NSData dataWithContentsOfFile:dest] isEqualToData:old], @"unreadable page: existing file untouched");

    // cancelled before the first page, between pages, and inside the ZIP write
    NSArray *filePages = @[[COExportPage pageWithFilePath:[src stringByAppendingPathComponent:@"001.png"]],
                           [COExportPage pageWithFilePath:[src stringByAppendingPathComponent:@"002.jpg"]]];
    result = COExportPages(filePages, [NSURL fileURLWithPath:dest], ^BOOL(void) { return YES; }, nil, NULL, NULL);
    check(result == COExportCancelled, @"cancel at once: cancelled");
    check([[NSData dataWithContentsOfFile:dest] isEqualToData:old], @"cancel at once: existing file untouched");

    // the first poll is the one after staging; every later one is libzip's
    __block int polls = 0;
    result = COExportPages(filePages, [NSURL fileURLWithPath:dest], ^BOOL(void) { return ++polls > 1; }, nil, NULL, NULL);
    check(result == COExportCancelled, [NSString stringWithFormat:@"cancel while writing: cancelled (result %d after %d polls)", (int)result, polls]);
    check([[NSData dataWithContentsOfFile:dest] isEqualToData:old], @"cancel while writing: existing file untouched");

    NSString *fresh = [outDir stringByAppendingPathComponent:@"never.cbz"];
    [fm removeItemAtPath:fresh error:NULL];
    polls = 0;
    result = COExportPages(filePages, [NSURL fileURLWithPath:fresh], ^BOOL(void) { return ++polls > 1; }, nil, NULL, NULL);
    check(result == COExportCancelled && ![fm fileExistsAtPath:fresh], @"cancel: no file at a new destination");

    // success replaces the file the save panel agreed to replace
    result = COExportPages(filePages, [NSURL fileURLWithPath:dest], nil, nil, NULL, NULL);
    check(result == COExportOK, @"replace: exported");
    checkZip(@"replace", dest, @[@"001.png", @"002.jpg"],
             @[[NSData dataWithContentsOfFile:[src stringByAppendingPathComponent:@"001.png"]],
               [NSData dataWithContentsOfFile:[src stringByAppendingPathComponent:@"002.jpg"]]]);
    checkNoLeftovers(@"failure paths", outDir);
    [fm removeItemAtPath:dest error:NULL];

    // the writer alone, with data and file contents
    NSString *direct = [outDir stringByAppendingPathComponent:@"direct.zip"];
    [fm removeItemAtPath:direct error:NULL];
    NSData *bytes = [@"hello" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *message = nil;
    BOOL ok = COExportWriteStoredZip(direct, @[@"a.txt", @"001.png"],
                                     @[bytes, [src stringByAppendingPathComponent:@"001.png"]], nil, &message);
    check(ok, [NSString stringWithFormat:@"writer: wrote (%@)", message]);
    checkZip(@"writer", direct, @[@"a.txt", @"001.png"],
             @[bytes, [NSData dataWithContentsOfFile:[src stringByAppendingPathComponent:@"001.png"]]]);
    [fm removeItemAtPath:direct error:NULL];
    ok = COExportWriteStoredZip(direct, @[@"a.txt"], @[bytes], ^BOOL(void) { return YES; }, &message);
    check(!ok && ![fm fileExistsAtPath:direct], @"writer: cancelled leaves nothing");
}

#pragma mark folder books

/* A one-page PDF, drawn with Quartz. */
static BOOL writePDF(NSString *path)
{
    CGRect box = CGRectMake(0, 0, 200, 300);
    CGContextRef ctx = CGPDFContextCreateWithURL((CFURLRef)[NSURL fileURLWithPath:path], &box, NULL);
    if (!ctx) return NO;
    CGPDFContextBeginPage(ctx, NULL);
    CGContextSetRGBFillColor(ctx, 1, 0, 0, 1);
    CGContextFillRect(ctx, CGRectMake(20, 20, 100, 100));
    CGPDFContextEndPage(ctx);
    CGPDFContextClose(ctx);
    CGContextRelease(ctx);
    return YES;
}

static void testFolders(NSString *gen, NSString *src, NSString *outDir)
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *four = @[@"001.png", @"002.jpg", @"003.png", @"004.jpg"];

    COImageLoader *folder = [[[COImageLoader alloc] initWithPath:src readSubFolder:NO controller:nil] autorelease];
    check([folder mode] == 0 && [folder itemCount] == 4, @"folder book: four pages");
    exportAndCheck(@"folder book, all pages", folder, @"", outDir, @"folder-export.cbz", src, four);

    // a folder with an archive in it: names collide, so every entry is prefixed
    NSString *mixed = [outDir stringByAppendingPathComponent:@"mixed_folder"];
    [fm removeItemAtPath:mixed error:NULL];
    [fm createDirectoryAtPath:mixed withIntermediateDirectories:YES attributes:nil error:NULL];
    [fm copyItemAtPath:[src stringByAppendingPathComponent:@"001.png"] toPath:[mixed stringByAppendingPathComponent:@"001.png"] error:NULL];
    [fm copyItemAtPath:[src stringByAppendingPathComponent:@"002.jpg"] toPath:[mixed stringByAppendingPathComponent:@"002.jpg"] error:NULL];
    [fm copyItemAtPath:[gen stringByAppendingPathComponent:@"test.cbz"] toPath:[mixed stringByAppendingPathComponent:@"zz.cbz"] error:NULL];
    // fixed times, years before the run, so a kept time cannot pass for "now"
    [fm setAttributes:@{NSFileModificationDate: [NSDate dateWithTimeIntervalSince1970:981173106]}	// 2001-02-03
         ofItemAtPath:[mixed stringByAppendingPathComponent:@"001.png"] error:NULL];
    [fm setAttributes:@{NSFileModificationDate: [NSDate dateWithTimeIntervalSince1970:1118131751]}	// 2005-06-07, odd second
         ofItemAtPath:[mixed stringByAppendingPathComponent:@"002.jpg"] error:NULL];
    COImageLoader *mixedLoader = [[[COImageLoader alloc] initWithPath:mixed readSubFolder:NO controller:nil] autorelease];
    check([mixedLoader itemCount] == 6, [NSString stringWithFormat:@"folder with archive: %d pages", [mixedLoader itemCount]]);
    exportAndCheck(@"folder with an archive inside (colliding names)", mixedLoader, @"", outDir, @"mixed-export.cbz", src,
                   @[@"0001_001.png", @"0002_002.jpg", @"0003_001.png", @"0004_002.jpg", @"0005_003.png", @"0006_004.jpg"]);
    exportAndCheck(@"folder with an archive inside, nested pages only", mixedLoader, @"4-6", outDir, @"mixed-export-4-6.cbz", src,
                   @[@"002.jpg", @"003.png", @"004.jpg"]);

    // a PDF inside a folder: its pages have no bytes of their own
    NSString *withPDF = [outDir stringByAppendingPathComponent:@"pdf_folder"];
    [fm removeItemAtPath:withPDF error:NULL];
    [fm createDirectoryAtPath:withPDF withIntermediateDirectories:YES attributes:nil error:NULL];
    [fm copyItemAtPath:[src stringByAppendingPathComponent:@"001.png"] toPath:[withPDF stringByAppendingPathComponent:@"001.png"] error:NULL];
    if (writePDF([withPDF stringByAppendingPathComponent:@"002.pdf"])) {
        printf("folder with a PDF inside\n");
        COImageLoader *pdfLoader = [[[COImageLoader alloc] initWithPath:withPDF readSubFolder:NO controller:nil] autorelease];
        check([pdfLoader itemCount] == 2, [NSString stringWithFormat:@"folder with PDF: %d pages", [pdfLoader itemCount]]);
        check([pdfLoader exportPageAtIndex:0] != nil, @"folder with PDF: image page has bytes");
        check([pdfLoader exportPageAtIndex:1] == nil, @"folder with PDF: PDF page has none");
        COImageLoader *pdfBook = [[[COImageLoader alloc] initWithPath:[withPDF stringByAppendingPathComponent:@"002.pdf"]
                                                        readSubFolder:NO controller:nil] autorelease];
        check([pdfBook mode] == 4 && [pdfBook exportPageAtIndex:0] == nil, @"PDF book: no page has bytes");
    }
    check([folder exportPageAtIndex:-1] == nil && [folder exportPageAtIndex:4] == nil, @"index outside the book");
    [fm removeItemAtPath:mixed error:NULL];
    [fm removeItemAtPath:withPDF error:NULL];
}

#pragma mark modification times, known values

static time_t zipEntryMTime(NSString *path, zip_uint64_t index)
{
    int err = 0;
    zip_t *za = zip_open([path fileSystemRepresentation], ZIP_RDONLY, &err);
    if (!za) return (time_t)-1;
    zip_stat_t st;
    zip_stat_init(&st);
    time_t t = (zip_stat_index(za, index, 0, &st) == 0 && (st.valid & ZIP_STAT_MTIME)) ? st.mtime : (time_t)-1;
    zip_close(za);
    return t;
}

static void testKnownMTimes(NSString *src, NSString *outDir)
{
    printf("modification times kept, known values\n");
    NSFileManager *fm = [NSFileManager defaultManager];
    const time_t t1 = 1000000000, t2 = 1234567890;	/* 2001-09-09, 2009-02-13; both even */

    // a ZIP book whose entries carry fixed times (written with libzip)
    NSString *book = [outDir stringByAppendingPathComponent:@"dated.cbz"];
    [fm removeItemAtPath:book error:NULL];
    int err = 0;
    zip_t *za = zip_open([book fileSystemRepresentation], ZIP_CREATE | ZIP_EXCL, &err);
    check(za != NULL, @"dated book: created");
    if (!za) return;
    NSArray *names = @[@"001.png", @"002.jpg"];
    time_t times[2] = { t1, t2 };
    NSUInteger i;
    for (i = 0; i < 2; i++) {
        NSString *file = [src stringByAppendingPathComponent:[names objectAtIndex:i]];
        zip_source_t *s = zip_source_file(za, [file fileSystemRepresentation], 0, ZIP_LENGTH_TO_END);
        zip_int64_t index = zip_file_add(za, [[names objectAtIndex:i] UTF8String], s, ZIP_FL_ENC_UTF_8);
        zip_file_set_mtime(za, (zip_uint64_t)index, times[i], 0);
    }
    check(zip_close(za) == 0, @"dated book: written");
    check(zipEntryMTime(book, 0) == t1 && zipEntryMTime(book, 1) == t2, @"dated book: times as set");

    COImageLoader *loader = [[[COImageLoader alloc] initWithPath:book readSubFolder:NO controller:nil] autorelease];
    NSArray *pages = pagesOf(loader, [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)]);
    check([pages count] == 2, @"dated book: two pages");
    if ([pages count] != 2) return;
    check([[[pages objectAtIndex:0] modificationDate] timeIntervalSince1970] == (NSTimeInterval)t1,
          @"dated book: entry time read (libzip)");
    NSString *dest = [outDir stringByAppendingPathComponent:@"dated-export.cbz"];
    [fm removeItemAtPath:dest error:NULL];
    COExportResult result = COExportPages(pages, [NSURL fileURLWithPath:dest], nil, nil, NULL, NULL);
    check(result == COExportOK, @"dated book: exported");
    check(zipEntryMTime(dest, 0) == t1, [NSString stringWithFormat:@"dated book: page 1 keeps its time (%ld)", (long)zipEntryMTime(dest, 0)]);
    check(zipEntryMTime(dest, 1) == t2, [NSString stringWithFormat:@"dated book: page 2 keeps its time (%ld)", (long)zipEntryMTime(dest, 1)]);

    // the writer: a date per entry, NSNull for "now"
    NSString *direct = [outDir stringByAppendingPathComponent:@"dated-direct.zip"];
    [fm removeItemAtPath:direct error:NULL];
    NSData *bytes = [@"hello" dataUsingEncoding:NSUTF8StringEncoding];
    time_t before = time(NULL);
    BOOL ok = COExportWriteStoredZipWithDates(direct, @[@"a.txt", @"b.txt"], @[bytes, bytes],
                                              @[[NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)t2 + 1], [NSNull null]],
                                              nil, NULL);
    check(ok, @"writer with dates: wrote");
    check(zipEntryMTime(direct, 0) == t2, @"writer with dates: odd second rounded down to DOS time");
    time_t now = zipEntryMTime(direct, 1);
    check(now >= before - 2 && now <= time(NULL) + 2, @"writer with dates: no date, the time of writing");
    ok = COExportWriteStoredZipWithDates(direct, @[@"a.txt"], @[bytes], @[], nil, NULL);
    check(!ok, @"writer with dates: count mismatch refused");
    [fm removeItemAtPath:direct error:NULL];
    [fm removeItemAtPath:dest error:NULL];
    [fm removeItemAtPath:book error:NULL];
}

#pragma mark solid RAR: own reader, prompt cancel

static double nowSeconds(void)
{
    static mach_timebase_info_data_t tb;
    if (tb.denom == 0) mach_timebase_info(&tb);
    return (double)mach_absolute_time() * tb.numer / tb.denom / 1e9;
}

/* The export reads a RAR through a second reader of the file, so the
   viewer's archive (and its solid cursor) is not touched; and a cancel while
   that reader walks the solid stream returns within a decode chunk, not
   after the walk. */
static void testSolidReader(NSString *gen, NSString *outDir)
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *solid = [gen stringByAppendingPathComponent:@"test_solid.cbr"];
    if ([fm fileExistsAtPath:solid]) {
        printf("test_solid.cbr: the viewer's reader is not used\n");
        COImageLoader *loader = [[[COImageLoader alloc] initWithPath:solid readSubFolder:NO controller:nil] autorelease];
        NSArray *pages = pagesOf(loader, [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 4)]);
        CORarArchive *viewer = (CORarArchive *)[[pages objectAtIndex:0] archive];
        NSString *dest = [outDir stringByAppendingPathComponent:@"solid-own-reader.cbz"];
        [fm removeItemAtPath:dest error:NULL];
        COExportResult r = COExportPages(pages, [NSURL fileURLWithPath:dest], nil, nil, NULL, NULL);
        check(r == COExportOK, @"own reader: exported");
        check([viewer isKindOfClass:[CORarArchive class]] && [viewer rewindCount] == 0 &&
              [viewer cursorContinueCount] == 0 && [viewer positionedOpenCount] == 0,
              [NSString stringWithFormat:@"own reader: viewer's cursor untouched (rewinds %lu, continues %lu)",
               (unsigned long)[viewer rewindCount], (unsigned long)[viewer cursorContinueCount]]);
        [fm removeItemAtPath:dest error:NULL];
    }

    NSString *walk = [gen stringByAppendingPathComponent:@"test_rar5_solid_walk.cbr"];
    if (![fm fileExistsAtPath:walk]) {
        printf("test_rar5_solid_walk.cbr (skipped: not generated)\n");
        return;
    }
    printf("test_rar5_solid_walk.cbr: cancel during the walk\n");
    COImageLoader *loader = [[[COImageLoader alloc] initWithPath:walk readSubFolder:NO controller:nil] autorelease];
    int count = [loader itemCount];
    check(count == 40, [NSString stringWithFormat:@"walk book: %d pages", count]);
    if (count < 2) return;

    // the last page alone: the reader walks every entry before it
    NSArray *last = pagesOf(loader, [NSIndexSet indexSetWithIndex:(NSUInteger)count - 1]);
    NSString *dest = [outDir stringByAppendingPathComponent:@"walk-last.cbz"];
    [fm removeItemAtPath:dest error:NULL];
    double t0 = nowSeconds();
    COExportResult r = COExportPages(last, [NSURL fileURLWithPath:dest], nil, nil, NULL, NULL);
    double full = nowSeconds() - t0;
    check(r == COExportOK, @"walk book: last page exported");
    printf("  uncancelled export of the last page: %.3f s\n", full);
    NSData *want = [[[(COArchive *)[[last objectAtIndex:0] archive] contents] objectAtIndex:[[last objectAtIndex:0] order]] data];
    checkZip(@"walk book, last page", dest, @[@"040.jpg"], @[want ? want : [NSData data]]);
    [fm removeItemAtPath:dest error:NULL];

    // cancel 50 ms in, while the walk is under way
    __block double cancelAt = 0;
    double start = nowSeconds();
    r = COExportPages(last, [NSURL fileURLWithPath:dest], ^BOOL(void) {
        if (cancelAt == 0 && nowSeconds() - start >= 0.05) cancelAt = nowSeconds();
        return cancelAt != 0;
    }, nil, NULL, NULL);
    double latency = cancelAt > 0 ? nowSeconds() - cancelAt : -1;
    printf("  cancel latency during the walk: %.3f s\n", latency);
    check(r == COExportCancelled && ![fm fileExistsAtPath:dest],
          [NSString stringWithFormat:@"walk book: cancelled, no file (result %d)", (int)r]);
    check(latency >= 0 && latency < 0.25,
          [NSString stringWithFormat:@"walk book: cancel returned in %.3f s (walk takes %.3f s)", latency, full]);
    checkNoLeftovers(@"walk book", outDir);
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        if (argc < 4) {
            fprintf(stderr, "usage: test_export <generated-fixtures-dir> <src-dir> <output-dir>\n");
            return 2;
        }
        NSString *gen = [NSString stringWithUTF8String:argv[1]];
        NSString *src = [NSString stringWithUTF8String:argv[2]];
        NSString *outDir = [NSString stringWithUTF8String:argv[3]];
        [[NSFileManager defaultManager] createDirectoryAtPath:outDir withIntermediateDirectories:YES attributes:nil error:NULL];

        testPageList();
        testNames();

        NSArray *four = @[@"001.png", @"002.jpg", @"003.png", @"004.jpg"];
        COImageLoader *cbz = [[[COImageLoader alloc] initWithPath:[gen stringByAppendingPathComponent:@"test.cbz"]
                                                    readSubFolder:NO controller:nil] autorelease];
        exportAndCheck(@"test.cbz, all pages", cbz, @"", outDir, @"test-export.cbz", src, four);
        exportAndCheck(@"test.cbz, pages 2-3,4", cbz, @"2-3,4", outDir, @"test-export-2-3_4.cbz", src,
                       @[@"002.jpg", @"003.png", @"004.jpg"]);
        exportAndCheck(@"test.cbz, page 3", cbz, @"3", outDir, @"test-export-3.cbz", src, @[@"003.png"]);

        NSArray *rars = @[@"test.cbr", @"test_rar5_unordered.cbr", @"test_solid.cbr"];
        for (NSString *name in rars) {
            NSString *path = [gen stringByAppendingPathComponent:name];
            if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
                printf("%s (skipped: not generated)\n", [name UTF8String]);
                continue;
            }
            COImageLoader *rar = [[[COImageLoader alloc] initWithPath:path readSubFolder:NO controller:nil] autorelease];
            NSString *base = [name stringByDeletingPathExtension];
            exportAndCheck([NSString stringWithFormat:@"%@, all pages", name], rar, @"", outDir,
                           [base stringByAppendingString:@"-export.cbz"], src, four);
            exportAndCheck([NSString stringWithFormat:@"%@, pages 2-3", name], rar, @"2-3", outDir,
                           [base stringByAppendingString:@"-export-2-3.cbz"], src, @[@"002.jpg", @"003.png"]);
        }

        // a password-protected ZIP: the export holds the decrypted pages
        for (NSString *name in @[@"enc_pages.cbz", @"enc_pages_aes.cbz"]) {
            NSString *path = [gen stringByAppendingPathComponent:name];
            if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
                printf("%s (skipped: not generated)\n", [name UTF8String]);
                continue;
            }
            COImageLoader *enc = [[[COImageLoader alloc] initWithPath:path displayPath:path readSubFolder:NO
                                                           controller:nil deferPasswordPrompt:YES] autorelease];
            check([enc needsPassword] && [enc tryPassword:@"SECRET"] == COArchiveCryptoOK,
                  [NSString stringWithFormat:@"%@: unlocked", name]);
            exportAndCheck([NSString stringWithFormat:@"%@ (encrypted), all pages", name], enc, @"", outDir,
                           [[name stringByDeletingPathExtension] stringByAppendingString:@"-export.cbz"], src, four);
        }

        testFolders(gen, src, outDir);
        testFailures(outDir, src);
        testKnownMTimes(src, outDir);
        testSolidReader(gen, outDir);

        if (failures == 0) {
            printf("\nALL PASS (%d checks)\n", checks);
            return 0;
        }
        printf("\n%d FAILED of %d checks\n", failures, checks);
        return 1;
    }
}
