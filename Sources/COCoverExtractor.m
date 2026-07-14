//
//  COCoverExtractor.m
//  cooViewer
//
//  Design (phase 7, docs/tasks/... QuickLook extension TASK):
//  - Reuses COArchive as-is: initWithPath: dispatches to COZipArchive
//    (libzip, phase 2) or CORarArchive (libarchive cursor pass +
//    CORarHeaderIndex header-only fast path, phases 4/6) exactly like
//    the main app, so opening is fast regardless of archive size or
//    solid/non-solid status — the whole point of those phases was to
//    make this kind of on-demand, single-entry access cheap enough
//    for QuickLook's time budget.
//  - Page ordering reuses NSString's -finderCompareS: category
//    (NSString_Compare.m), the exact comparator COImageLoader's
//    -checkArchiveContainer: sorts entries with. Not reimplemented:
//    same method, same behavior.
//  - Unlike COImageLoader, this does not handle nested archives
//    (an archive-inside-an-archive as the "first entry") or the
//    non-image document types (pdf, cvbdl) COImageLoader's fuller
//    fileTypes list covers — out of scope for a cover/thumbnail
//    extension per the task's "cover/first-page only" scope. If the
//    sorted-first image entry can't be decoded, this returns nil
//    rather than trying further entries, so the extension can fail
//    gracefully (no preview) instead of guessing.
//

#import "COCoverExtractor.h"
#import "COArchive.h"
#import "NSString_Compare.h"
#import <AppKit/AppKit.h>

NSData *COExtractCoverImageData(NSString *path)
{
	COArchive *archive = [[COArchive alloc] initWithPath:path];
	if ([archive lastError] || [archive itemCount] == 0) {
		[archive release];
		return nil;
	}

	NSArray *imageTypes = [NSImage imageFileTypes];
	NSMutableArray *imageEntries = [NSMutableArray array];
	for (COArchiveEntry *e in [archive contents]) {
		NSString *ext = [[[e path] pathExtension] lowercaseString];
		if ([ext length] > 0 && [imageTypes containsObject:ext])
			[imageEntries addObject:e];
	}
	if ([imageEntries count] == 0) {
		[archive release];
		return nil;
	}

	[imageEntries sortUsingComparator:^NSComparisonResult(COArchiveEntry *a, COArchiveEntry *b) {
		return [[a path] finderCompareS:[b path]];
	}];

	COArchiveEntry *cover = [imageEntries objectAtIndex:0];
	NSData *data = [[[cover data] retain] autorelease];
	[archive release];
	return data;
}
