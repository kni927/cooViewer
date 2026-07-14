//
//  CORarArchive.m
//  cooViewer
//
//  See CORarArchive.h for the design notes.
//

#import "CORarArchive.h"
#include <archive_entry.h>
#include <uchardet.h>
#include <string.h>
#include <sys/stat.h>

/* decoded-entry cache budget; same policy as COZipArchive */
#define CO_RAR_CACHE_LIMIT (256 * 1024 * 1024)

/* implemented in COArchive.m (shared archive-level name decoding) */
@interface COArchive (COArchiveNameDecoding)
- (NSString *)decodeName:(NSData *)raw fallback:(NSString *)u8 charset:(NSString *)charset;
@end

/* raw name + stream position collected during the index pass, before
 * the archive-level encoding decision is made */
@interface CORarRawEntry : NSObject
{
@public
	NSData *rawName;	// header bytes as stored (may be nil)
	NSString *utf8Name;	// libarchive's UTF-8 conversion (may be nil)
	NSUInteger streamOrdinal;
}
@end

@implementation CORarRawEntry
- (void)dealloc
{
	[rawName release];
	[utf8Name release];
	[super dealloc];
}
@end

@implementation CORarEntry

- (id)initWithPath:(NSString *)inPath owner:(CORarArchive *)inOwner
           ordinal:(NSUInteger)inOrdinal
{
	self = [super initWithPath:inPath data:nil];
	if (self) {
		owner = inOwner;
		ordinal = inOrdinal;
		arrayIndex = 0;
	}
	return self;
}

- (NSData *)data
{
	return [owner dataForEntry:self];
}

@end

@interface CORarArchive (private)
- (void)indexArchiveWithProgress:(COArchiveProgress)progress;
- (NSData *)readEntryOnQueue:(NSUInteger)ordinal;
- (void)prefetchAfterArrayIndex:(NSUInteger)arrayIndex;
- (void)invalidateCursor;
@end

@implementation CORarArchive

- (void)dealloc
{
	[self invalidateCursor];
	if (readQueue) {
#if OS_OBJECT_USE_OBJC
		[readQueue release];
#else
		dispatch_release(readQueue);
#endif
	}
	[dataCache release];
	[super dealloc];
}

- (BOOL)rarOpened
{
	return rarOpened;
}

/* Called once from COArchive's designated initializer, on the
 * initializing (main) thread — see the Thread safety note in
 * CORarArchive.h for why this must not be dispatched to a background
 * queue. */
- (void)readArchiveWithProgress:(COArchiveProgress)progress
{
	readQueue = dispatch_queue_create("cooViewer.CORarArchive.read", DISPATCH_QUEUE_SERIAL);
	dataCache = [[NSCache alloc] init];
	[dataCache setName:@"CORarArchive.dataCache"];
	[dataCache setTotalCostLimit:CO_RAR_CACHE_LIMIT];
	[self indexArchiveWithProgress:progress];
}

static struct archive *CORarOpenStream(NSString *filePath)
{
	struct archive *a = archive_read_new();
	archive_read_support_filter_all(a);
	archive_read_support_format_rar(a);
	archive_read_support_format_rar5(a);
	if (archive_read_open_filename(a, [filePath fileSystemRepresentation],
	                               256 * 1024) != ARCHIVE_OK) {
		archive_read_free(a);
		return NULL;
	}
	return a;
}

/* Structural qualification shared by the index pass and the cursor
 * fast-forward: directories, zero-byte entries, and AppleDouble
 * ("._*") sidecars are never counted toward the stream ordinal, so
 * both passes must agree on exactly which headers count. Encrypted
 * entries are handled by the caller (only the index pass needs to
 * set -crypted). */
static BOOL CORarEntryIsAppleDouble(struct archive_entry *entry)
{
	const char *u8 = archive_entry_pathname_utf8(entry);
	const char *raw = archive_entry_pathname(entry);
	const char *nm = u8 ? u8 : raw;
	if (!nm) return NO;
	const char *base = strrchr(nm, '/');
	base = base ? base + 1 : nm;
	return strncmp(base, "._", 2) == 0;
}

- (void)indexArchiveWithProgress:(COArchiveProgress)progress
{
	struct stat st;
	long long fileSize = 0;
	if (stat([filePath fileSystemRepresentation], &st) == 0)
		fileSize = (long long)st.st_size;

	struct archive *a = CORarOpenStream(filePath);
	if (!a) {
		lastError = [@"cannot open archive" retain];
		return;		// rarOpened stays NO; no fallback (see CORarArchive.h)
	}
	rarOpened = YES;

	NSMutableArray *rawEntries = [NSMutableArray array];	// CORarRawEntry
	NSMutableData *allRaw = [NSMutableData data];
	BOOL allHaveUTF8 = YES;
	NSUInteger streamOrdinal = 0;

	for (;;) {
		struct archive_entry *entry;
		int r = archive_read_next_header(a, &entry);
		if (r == ARCHIVE_EOF) break;
		if (r < ARCHIVE_WARN) {
			const char *e = archive_error_string(a);
			[lastError release];
			lastError = [[NSString alloc] initWithFormat:@"%s", e ? e : "read error"];
			break;
		}
		if (archive_entry_filetype(entry) == AE_IFDIR) continue;
		if (archive_entry_size_is_set(entry) && archive_entry_size(entry) == 0) continue;
		if (archive_entry_is_encrypted(entry)) {
			crypted = YES;
			continue;
		}
		if (CORarEntryIsAppleDouble(entry)) {
			archive_read_data_skip(a);
			continue;
		}

		// this entry counts: skip its data (cheap) rather than
		// decoding it, and record its stream position
		archive_read_data_skip(a);

		const char *raw = archive_entry_pathname(entry);
		const char *u8 = archive_entry_pathname_utf8(entry);

		CORarRawEntry *re = [[[CORarRawEntry alloc] init] autorelease];
		re->streamOrdinal = streamOrdinal++;
		if (raw) {
			re->rawName = [[NSData alloc] initWithBytes:raw length:strlen(raw)];
			[allRaw appendBytes:raw length:strlen(raw)];
			[allRaw appendBytes:"\n" length:1];
		}
		if (u8) {
			re->utf8Name = [[NSString alloc] initWithUTF8String:u8];
		} else {
			allHaveUTF8 = NO;
		}
		[rawEntries addObject:re];

		if (progress && fileSize > 0) {
			long long done = (long long)archive_filter_bytes(a, -1);
			if (!progress(done, fileSize)) {
				cancelled = YES;
				break;
			}
		}
	}

	archive_read_free(a);

	if (cancelled) {
		[contentArray removeAllObjects];
		[lastError release];
		lastError = [@"cancelled" retain];
		return;
	}

	// archive-level encoding decision: uchardet once over every raw
	// name (same policy as COArchive/COZipArchive)
	NSString *charset = nil;
	if (!allHaveUTF8 && [allRaw length] > 0) {
		uchardet_t ud = uchardet_new();
		uchardet_handle_data(ud, [allRaw bytes], [allRaw length]);
		uchardet_data_end(ud);
		if (uchardet_get_n_candidates(ud) > 0) {
			const char *cs = uchardet_get_encoding(ud, 0);
			if (cs && *cs)
				charset = [NSString stringWithUTF8String:cs];
		}
		uchardet_delete(ud);
	}

	NSEnumerator *enu = [rawEntries objectEnumerator];
	CORarRawEntry *re;
	while ((re = [enu nextObject])) {
		NSString *name;
		if (allHaveUTF8) {
			name = re->utf8Name;	// fast path: whole archive is UTF-8/ASCII
		} else {
			name = [self decodeName:re->rawName fallback:re->utf8Name charset:charset];
		}
		if (!name) continue;	// stream ordinal still consumed; array index just skips it
		CORarEntry *e = [[[CORarEntry alloc] initWithPath:name
		                                             owner:self
		                                           ordinal:re->streamOrdinal] autorelease];
		e->arrayIndex = [contentArray count];
		[contentArray addObject:e];
	}

	if ([contentArray count] == 0 && lastError == nil) {
		if (crypted)
			lastError = [@"encrypted archives are not supported" retain];
		else
			lastError = [@"no readable entries" retain];
	}
}

#pragma mark -

- (NSData *)dataForEntry:(CORarEntry *)entry
{
	NSUInteger ordinal = entry->ordinal;
	NSNumber *key = [NSNumber numberWithUnsignedInteger:ordinal];
	NSData *cached = [dataCache objectForKey:key];
	if (!cached) {
		__block NSData *result = nil;
		dispatch_sync(readQueue, ^{
			NSData *d = [dataCache objectForKey:key];
			if (!d) {
				d = [self readEntryOnQueue:ordinal];
				if (d)
					[dataCache setObject:d forKey:key cost:[d length]];
			}
			result = [d retain];
		});
		cached = [result autorelease];
	}

	[self prefetchAfterArrayIndex:entry->arrayIndex];
	return cached;
}

/* must run on readQueue (a struct archive* stream is not safe for
 * concurrent use). Fast-forwards -cursor to the requested stream
 * ordinal, reopening from the start of the file when the cursor
 * doesn't exist yet or has already passed the target (i.e. the
 * viewer paged backwards). Returns nil (and invalidates the cursor)
 * on any read error, so the next call starts clean. */
- (NSData *)readEntryOnQueue:(NSUInteger)ordinal
{
	if (!cursor || ordinal < cursorNext) {
		[self invalidateCursor];
		cursor = CORarOpenStream(filePath);
		cursorNext = 0;
		if (!cursor) {
			NSLog(@"CORarArchive: cannot reopen %@ for entry #%lu",
			      filePath, (unsigned long)ordinal);
			return nil;
		}
	}

	while (cursorNext < ordinal) {
		struct archive_entry *entry;
		int r = archive_read_next_header(cursor, &entry);
		if (r == ARCHIVE_EOF || r < ARCHIVE_WARN) {
			NSLog(@"CORarArchive: stream ended before entry #%lu in %@",
			      (unsigned long)ordinal, filePath);
			[self invalidateCursor];
			return nil;
		}
		if (archive_entry_filetype(entry) == AE_IFDIR) continue;
		if (archive_entry_size_is_set(entry) && archive_entry_size(entry) == 0) continue;
		if (archive_entry_is_encrypted(entry)) continue;
		if (CORarEntryIsAppleDouble(entry)) {
			archive_read_data_skip(cursor);
			continue;
		}
		archive_read_data_skip(cursor);
		cursorNext++;
	}

	struct archive_entry *entry;
	int r = archive_read_next_header(cursor, &entry);
	if (r == ARCHIVE_EOF || r < ARCHIVE_WARN) {
		NSLog(@"CORarArchive: entry #%lu missing from stream in %@",
		      (unsigned long)ordinal, filePath);
		[self invalidateCursor];
		return nil;
	}
	// entry #ordinal is always structurally qualifying by construction
	// (the index pass only ever recorded qualifying entries), so no
	// re-check is needed here.

	NSMutableData *payload = [NSMutableData data];
	BOOL entryOK = YES;
	for (;;) {
		char buf[256 * 1024];
		la_ssize_t got = archive_read_data(cursor, buf, sizeof(buf));
		if (got == 0) break;
		if (got < 0) {
			NSLog(@"CORarArchive: corrupt entry #%lu in %@: %s",
			      (unsigned long)ordinal, filePath, archive_error_string(cursor));
			entryOK = NO;
			break;
		}
		[payload appendBytes:buf length:(NSUInteger)got];
	}
	cursorNext++;

	if (!entryOK) {
		// the stream position after a corrupt read is unreliable;
		// force a clean reopen on the next request
		[self invalidateCursor];
		return nil;
	}
	return payload;
}

- (void)invalidateCursor
{
	if (cursor) {
		archive_read_free(cursor);
		cursor = NULL;
	}
	cursorNext = 0;
}

- (void)prefetchAfterArrayIndex:(NSUInteger)arrayIndex
{
	if (arrayIndex + 1 >= [contentArray count]) return;
	CORarEntry *next = [contentArray objectAtIndex:arrayIndex + 1];
	NSNumber *key = [NSNumber numberWithUnsignedInteger:next->ordinal];
	if ([dataCache objectForKey:key]) return;
	NSUInteger ord = next->ordinal;
	dispatch_async(readQueue, ^{	// block retains self until it runs
		if ([dataCache objectForKey:key]) return;
		NSData *d = [self readEntryOnQueue:ord];
		if (d)
			[dataCache setObject:d forKey:key cost:[d length]];
	});
}

@end
