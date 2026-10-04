//
//  CORarArchive.m
//  cooViewer
//
//  See CORarArchive.h for the design notes.
//

#import "CORarArchive.h"
#import "CORarHeaderIndex.h"
#include <archive_entry.h>
#include <uchardet.h>
#include <string.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <errno.h>

CORarPrefetchCheckpointHook CORarPrefetchCheckpointHookForTesting = NULL;

static uint32_t CORarCRC32(NSData *data)
{
	uint32_t crc = UINT32_MAX;
	const uint8_t *bytes = [data bytes];
	NSUInteger length = [data length];
	for (NSUInteger i = 0; i < length; i++) {
		crc ^= bytes[i];
		for (int bit = 0; bit < 8; bit++)
			crc = (crc >> 1) ^ (0xedb88320U & (uint32_t)-(int32_t)(crc & 1));
	}
	return crc ^ UINT32_MAX;
}

BOOL CORarPayloadMatchesExpectedMetadata(NSData *payload,
                                         BOOL hasExpectedSize,
                                         unsigned long long expectedSize,
                                         BOOL hasExpectedCRC,
                                         uint32_t expectedCRC)
{
	if (!payload || !hasExpectedSize || !hasExpectedCRC) return NO;
	if ((unsigned long long)[payload length] != expectedSize) return NO;
	return CORarCRC32(payload) == expectedCRC;
}

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
   hasExpectedSize:(BOOL)inHasExpectedSize
      expectedSize:(unsigned long long)inExpectedSize
    hasExpectedCRC:(BOOL)inHasExpectedCRC
       expectedCRC:(uint32_t)inExpectedCRC
{
	self = [super initWithPath:inPath data:nil];
	if (self) {
		owner = inOwner;
		ordinal = inOrdinal;
		arrayIndex = 0;
		hasExpectedSize = inHasExpectedSize;
		expectedSize = inExpectedSize;
		hasExpectedCRC = inHasExpectedCRC;
		expectedCRC = inExpectedCRC;
		hasHeaderOffset = NO;
		headerOffset = 0;
	}
	return self;
}

- (NSData *)data
{
	return [owner dataForEntry:self];
}

@end

@interface CORarArchive (private)
- (BOOL)indexArchiveViaHeaderParser;
- (void)indexArchiveViaLibarchiveWithProgress:(COArchiveProgress)progress;
- (NSData *)readEntryOnQueue:(CORarEntry *)entry prefetchGeneration:(const unsigned long *)generation
                     aborted:(BOOL *)outAborted;
- (void)prefetchAfterEntry:(CORarEntry *)entry;
- (void)invalidateCursor;
@end

@implementation CORarArchive

- (void)dealloc
{
	[self invalidateCursor];
	if (readQueue) {
		[readQueue release];
	}
	[dataCache release];
	[nextPageByOrdinal release];
	[super dealloc];
}

- (BOOL)rarOpened
{
	return rarOpened;
}

- (BOOL)usesDirectPositioning
{
	return positioningPrefixLength > 0;
}

- (NSUInteger)rewindCount
{
	__block NSUInteger n = 0;
	dispatch_sync(readQueue, ^{ n = rewindCount; });
	return n;
}

- (NSUInteger)positionedOpenCount
{
	__block NSUInteger n = 0;
	dispatch_sync(readQueue, ^{ n = positionedOpenCount; });
	return n;
}

- (NSUInteger)cursorContinueCount
{
	__block NSUInteger n = 0;
	dispatch_sync(readQueue, ^{ n = cursorContinueCount; });
	return n;
}

/* Called once from COArchive's designated initializer, on the
 * initializing (main) thread — see the Thread safety note in
 * CORarArchive.h for why this must not be dispatched to a background
 * queue. Tries the fast, header-only parser first (phase 6); falls
 * back to the libarchive-based scan (phase 4) if it declines to
 * handle this archive for any reason. */
- (void)readArchiveWithProgress:(COArchiveProgress)progress
{
	readQueue = dispatch_queue_create("cooViewer.CORarArchive.read", DISPATCH_QUEUE_SERIAL);
	dataCache = [[NSCache alloc] init];
	[dataCache setName:@"CORarArchive.dataCache"];
	[dataCache setTotalCostLimit:COArchiveDecodedCacheLimit()];	// same policy as COZipArchive

	if ([self indexArchiveViaHeaderParser]) {
		rarOpened = YES;
		return;
	}

	// clean slate: the header parser may have partially set crypted/
	// lastError before declining; the libarchive scan determines
	// these fresh and independently
	crypted = NO;
	[lastError release];
	lastError = nil;
	[contentArray removeAllObjects];

	[self indexArchiveViaLibarchiveWithProgress:progress];
}

/* Fast path (phase 6): enumerate entries via CORarParseHeadersAtPath
 * (raw file-offset seeks, no decompression — see CORarHeaderIndex.h)
 * instead of walking the archive through libarchive. Returns NO if
 * the header-only parser declined (wrong signature, encrypted
 * headers, multi-volume, malformed data, or zero usable entries),
 * in which case the caller falls back to the libarchive-based scan.
 * Never invokes progress or supports cancellation: like COZipArchive's
 * central-directory read, this is expected to complete in well under
 * a second regardless of archive size. */
- (BOOL)indexArchiveViaHeaderParser
{
	BOOL headerCrypted = NO;
	CORarArchiveLayout layout = { 0, NO };
	NSArray *headerEntries = CORarParseHeadersAtPathWithLayout(filePath, &headerCrypted, &layout);
	if (!headerEntries) return NO;
	BOOL positionable = (!layout.solid && layout.prefixLength > 0);

	NSMutableData *allRaw = [NSMutableData data];
	BOOL allHaveUTF8 = YES;
	for (CORarHeaderEntry *he in headerEntries) {
		if (he->utf8Name) continue;
		allHaveUTF8 = NO;
		if (he->rawName) {
			[allRaw appendData:he->rawName];
			[allRaw appendBytes:"\n" length:1];
		}
	}

	// archive-level encoding decision: uchardet once over every raw
	// name (same policy as the libarchive path and COZipArchive)
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

	NSUInteger streamOrdinal = 0;
	for (CORarHeaderEntry *he in headerEntries) {
		NSUInteger thisOrdinal = streamOrdinal++;
		NSString *name;
		if (allHaveUTF8) {
			name = he->utf8Name;
		} else {
			name = [self decodeName:he->rawName fallback:he->utf8Name charset:charset];
		}
		if (!name) continue;	// ordinal still consumed; matches the libarchive path's policy
		CORarEntry *e = [[[CORarEntry alloc] initWithPath:name
		                                             owner:self
		                                           ordinal:thisOrdinal
		                                   hasExpectedSize:he->hasUncompressedSize
		                                      expectedSize:he->uncompressedSize
		                                    hasExpectedCRC:he->hasFileCRC
		                                       expectedCRC:he->fileCRC] autorelease];
		e->arrayIndex = [contentArray count];
		if (positionable) {
			e->hasHeaderOffset = YES;
			e->headerOffset = he->headerOffset;
		}
		[contentArray addObject:e];
	}

	if ([contentArray count] == 0) {
		// nothing usable (e.g. every entry was encrypted): let the
		// libarchive fallback have a try too, on the off chance it
		// disagrees; harmless either way since this case is rare
		[contentArray removeAllObjects];
		return NO;
	}

	crypted = headerCrypted;
	if (positionable)
		positioningPrefixLength = layout.prefixLength;
	return YES;
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

/* B1: a libarchive input stream that is the file's first prefixLength
 * bytes (signature and main header) followed by the file from
 * entryOffset (an entry's header) to the end. Owned by the stream: freed
 * by the close callback, which libarchive calls exactly once, also when
 * the open fails after archive_read_open2 has been entered. */
typedef struct {
	int fd;
	unsigned long long prefixLength;
	unsigned long long entryOffset;
	unsigned long long virtualSize;
	unsigned long long position;	// in the virtual stream
	void *buffer;
} CORarPositionedStream;

#define CO_RAR_POSITIONED_BLOCK (256 * 1024)

static la_ssize_t CORarPositionedRead(struct archive *a, void *clientData, const void **outBuffer)
{
	CORarPositionedStream *s = clientData;
	*outBuffer = s->buffer;
	if (s->position >= s->virtualSize) return 0;
	unsigned long long fileOffset, available;
	if (s->position < s->prefixLength) {
		fileOffset = s->position;
		available = s->prefixLength - s->position;
	} else {
		fileOffset = s->entryOffset + (s->position - s->prefixLength);
		available = s->virtualSize - s->position;
	}
	size_t want = (size_t)(available < CO_RAR_POSITIONED_BLOCK ? available : CO_RAR_POSITIONED_BLOCK);
	ssize_t got = pread(s->fd, s->buffer, want, (off_t)fileOffset);
	if (got < 0) {
		archive_set_error(a, errno, "read error");
		return ARCHIVE_FATAL;
	}
	s->position += (unsigned long long)got;
	return got;
}

static la_int64_t CORarPositionedSkip(struct archive *a, void *clientData, la_int64_t request)
{
	CORarPositionedStream *s = clientData;
	if (request <= 0) return 0;
	unsigned long long remaining = s->virtualSize - s->position;
	unsigned long long skip = (unsigned long long)request < remaining ? (unsigned long long)request : remaining;
	s->position += skip;
	return (la_int64_t)skip;
}

static int CORarPositionedClose(struct archive *a, void *clientData)
{
	CORarPositionedStream *s = clientData;
	close(s->fd);
	free(s->buffer);
	free(s);
	return ARCHIVE_OK;
}

static struct archive *CORarOpenPositionedStream(NSString *filePath,
                                                 unsigned long long prefixLength,
                                                 unsigned long long entryOffset)
{
	int fd = open([filePath fileSystemRepresentation], O_RDONLY);
	if (fd < 0) return NULL;
	struct stat st;
	if (fstat(fd, &st) != 0 || entryOffset < prefixLength ||
	    entryOffset >= (unsigned long long)st.st_size) {
		close(fd);
		return NULL;
	}
	CORarPositionedStream *s = calloc(1, sizeof(*s));
	void *buffer = malloc(CO_RAR_POSITIONED_BLOCK);
	if (!s || !buffer) {
		free(s);
		free(buffer);
		close(fd);
		return NULL;
	}
	s->fd = fd;
	s->prefixLength = prefixLength;
	s->entryOffset = entryOffset;
	s->virtualSize = prefixLength + ((unsigned long long)st.st_size - entryOffset);
	s->position = 0;
	s->buffer = buffer;

	struct archive *a = archive_read_new();
	archive_read_support_format_rar(a);
	archive_read_support_format_rar5(a);
	if (archive_read_open2(a, s, NULL, CORarPositionedRead, CORarPositionedSkip,
	                       CORarPositionedClose) != ARCHIVE_OK) {
		archive_read_free(a);	// s was freed by the close callback
		return NULL;
	}
	return a;
}

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

/* Structural qualification shared by the libarchive index pass and the
 * cursor: directories, zero-byte entries, symbolic and hard links (RAR5
 * redirection records, RAR4 Unix links), encrypted entries and
 * AppleDouble ("._*") sidecars are never counted toward the stream
 * ordinal. CORarHeaderIndex applies the same rules to the raw headers, so
 * every pass agrees on exactly which headers count. Links used to be
 * counted by one pass and not the other, shifting every later page or
 * leaving an empty one (code review M6): libarchive leaves a RAR5 link's
 * size unset and gives a RAR4 link size 0. The index pass tests
 * encryption itself first, because it has to set -crypted. */
static BOOL CORarEntryCounts(struct archive_entry *entry)
{
	if (archive_entry_filetype(entry) == AE_IFDIR) return NO;
	if (archive_entry_filetype(entry) == AE_IFLNK) return NO;
	if (archive_entry_hardlink(entry) != NULL) return NO;
	if (archive_entry_size_is_set(entry) && archive_entry_size(entry) == 0) return NO;
	if (archive_entry_is_encrypted(entry)) return NO;
	if (CORarEntryIsAppleDouble(entry)) return NO;
	return YES;
}

- (void)indexArchiveViaLibarchiveWithProgress:(COArchiveProgress)progress
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
		if (archive_entry_filetype(entry) != AE_IFDIR &&
		    !(archive_entry_size_is_set(entry) && archive_entry_size(entry) == 0) &&
		    archive_entry_is_encrypted(entry))
			crypted = YES;
		BOOL counts = CORarEntryCounts(entry);

		// skip the data (cheap) rather than decoding it; an entry that
		// counts records its stream position
		archive_read_data_skip(a);
		if (!counts) continue;

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
		                                           ordinal:re->streamOrdinal
		                                   hasExpectedSize:NO
		                                      expectedSize:0
		                                    hasExpectedCRC:NO
		                                       expectedCRC:0] autorelease];
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
		// B2: whatever read-ahead is queued or running for another entry
		// should not keep this read waiting (see CORarArchive.h)
		[self noteDemandReadOfKey:ordinal];
		__block NSData *result = nil;
		dispatch_sync(readQueue, ^{
			NSData *d = [dataCache objectForKey:key];
			if (!d) {
				d = [self readEntryOnQueue:entry prefetchGeneration:NULL aborted:NULL];
				if (d)
					[dataCache setObject:d forKey:key cost:[d length]];
			}
			result = [d retain];
		});
		cached = [result autorelease];
	}

	[self prefetchAfterEntry:entry];
	return cached;
}

/* must run on readQueue (a struct archive* stream is not safe for
 * concurrent use). Brings -cursor to the requested stream ordinal. With
 * direct positioning (B1) any cursor that is not exactly there is
 * replaced by a stream positioned on the entry's header. Otherwise the
 * cursor is fast-forwarded, after reopening from the start of the file
 * when it doesn't exist yet or has already passed the target (i.e. the
 * viewer paged backwards). A read error can return the accumulated
 * payload only when trusted header size and CRC metadata both match;
 * the cursor is invalidated either way.
 *
 * `generation` is NULL for a read someone is waiting for. A prefetch passes
 * the generation it was scheduled in and stops, returning nil with
 * *outAborted = YES, once a cache-missing read of another entry has come in
 * since (B2): at any header boundary of the walk, where the cursor stays
 * valid for that read to continue from or replace; and after any decoded
 * chunk if the rest of the entry is not worth finishing, i.e. the cursor is
 * a positioned one (a new positioned open is cheap) or the wanted entry
 * lies behind this one and is not in the cache (that read reopens anyway).
 * A forward cursor keeps decoding otherwise: heading for an entry before
 * the wanted one, stopping it would force that read to start over from the
 * beginning of the file, which in a solid archive means decoding
 * everything again; and when the wanted entry is behind but already cached
 * (a read that missed the cache just before that entry was stored), that
 * read needs no cursor at all, so stopping would only throw this one away
 * and make the next page rewind. */
- (NSData *)readEntryOnQueue:(CORarEntry *)requestedEntry prefetchGeneration:(const unsigned long *)generation
                     aborted:(BOOL *)outAborted
{
	NSUInteger ordinal = requestedEntry->ordinal;
	BOOL positioned = (positioningPrefixLength > 0 && requestedEntry->hasHeaderOffset);
	if (outAborted) *outAborted = NO;
	if (positioned && cursor && ordinal == cursorNext) {
		// already there: continue on the cursor
		cursorContinueCount++;
	} else if (positioned) {
		[self invalidateCursor];
		cursor = CORarOpenPositionedStream(filePath, positioningPrefixLength,
		                                   requestedEntry->headerOffset);
		cursorNext = ordinal;
		positionedOpenCount++;
		if (!cursor) {
			NSLog(@"CORarArchive: cannot open %@ at entry #%lu",
			      filePath, (unsigned long)ordinal);
			return nil;
		}
	} else if (!cursor || ordinal < cursorNext) {
		[self invalidateCursor];
		cursor = CORarOpenStream(filePath);
		cursorNext = 0;
		rewindCount++;
		if (!cursor) {
			NSLog(@"CORarArchive: cannot reopen %@ for entry #%lu",
			      filePath, (unsigned long)ordinal);
			return nil;
		}
	} else {
		// forward from where the cursor is
		cursorContinueCount++;
	}

	// Walk to entry #ordinal. Headers that do not count (links, sidecars,
	// …) are skipped on the way *and* just before it: a cursor continued
	// from the previous page, or one positioned on a header, may still
	// have such a header in front of the page (code review M6).
	struct archive_entry *entry;
	for (;;) {
		if (generation) {
			if (CORarPrefetchCheckpointHookForTesting)
				CORarPrefetchCheckpointHookForTesting(self, ordinal, NO);
			if ([self prefetchOfKey:ordinal supersededSince:*generation demandKey:NULL]) {
				// between entries: cursor and cursorNext stay valid
				*outAborted = YES;
				return nil;
			}
		}
		int r = archive_read_next_header(cursor, &entry);
		if (r == ARCHIVE_EOF || r < ARCHIVE_WARN) {
			NSLog(@"CORarArchive: stream ended before entry #%lu in %@",
			      (unsigned long)ordinal, filePath);
			[self invalidateCursor];
			return nil;
		}
		BOOL counts = CORarEntryCounts(entry);
		if (counts && cursorNext == ordinal) break;
		archive_read_data_skip(cursor);
		if (counts) cursorNext++;
	}
	// The header index knows each entry's size; a header that disagrees
	// means the passes counted differently, and its data would be shown
	// as some other page. Fail closed instead.
	if (requestedEntry->hasExpectedSize && archive_entry_size_is_set(entry) &&
	    (unsigned long long)archive_entry_size(entry) != requestedEntry->expectedSize) {
		NSLog(@"CORarArchive: entry #%lu (%@) in %@ landed on a header of another size",
		      (unsigned long)ordinal, [requestedEntry path], filePath);
		[self invalidateCursor];
		return nil;
	}

	NSMutableData *payload = [NSMutableData data];
	BOOL entryOK = YES;
	NSString *entryError = nil;
	/* On the heap: readQueue's GCD threads have 512 KB stacks (code review
	   L11). */
	NSMutableData *chunk = [NSMutableData dataWithLength:256 * 1024];
	char *buf = [chunk mutableBytes];
	for (;;) {
		la_ssize_t got = archive_read_data(cursor, buf, [chunk length]);
		if (got == 0) break;
		if (got < 0) {
			const char *errorString = archive_error_string(cursor);
			entryError = [[NSString alloc] initWithUTF8String:
			              errorString ? errorString : "read error"];
			entryOK = NO;
			break;
		}
		[payload appendBytes:buf length:(NSUInteger)got];
		if (generation) {
			if (CORarPrefetchCheckpointHookForTesting)
				CORarPrefetchCheckpointHookForTesting(self, ordinal, YES);
			unsigned long wanted = 0;
			if ([self prefetchOfKey:ordinal supersededSince:*generation demandKey:&wanted] &&
			    (positioned ||
			     (wanted < ordinal &&
			      ![dataCache objectForKey:[NSNumber numberWithUnsignedInteger:(NSUInteger)wanted]]))) {
				// mid-entry: the cursor cannot be continued
				[self invalidateCursor];
				*outAborted = YES;
				return nil;
			}
		}
	}
	cursorNext++;

	if (!entryOK) {
		BOOL recovered = CORarPayloadMatchesExpectedMetadata(
			payload, requestedEntry->hasExpectedSize, requestedEntry->expectedSize,
			requestedEntry->hasExpectedCRC, requestedEntry->expectedCRC);
		// Even a recovered payload leaves the decoder position unreliable.
		[self invalidateCursor];
		if (recovered) {
			NSLog(@"CORarArchive: recovered complete CRC-valid entry #%lu (%@) after libarchive error: %@",
			      (unsigned long)ordinal, [requestedEntry path], entryError);
		} else {
			NSLog(@"CORarArchive: corrupt entry #%lu (%@) in %@: %@",
			      (unsigned long)ordinal, [requestedEntry path], filePath, entryError);
		}
		[entryError release];
		return recovered ? payload : nil;
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

/* B2: the page after `entry` in page order, as handed over by
 * -setPrefetchPageOrder:; nil after the last page. */
- (void)setPrefetchPageOrder:(NSArray *)entries
{
	NSMutableDictionary *next = [NSMutableDictionary dictionary];
	CORarEntry *previous = nil;
	for (id object in entries) {
		if (![object isKindOfClass:[CORarEntry class]]) continue;
		CORarEntry *e = object;
		if (e->owner != self) continue;
		if (previous)
			[next setObject:e forKey:[NSNumber numberWithUnsignedInteger:previous->ordinal]];
		previous = e;
	}
	NSDictionary *frozen = [next copy];
	@synchronized(self) {
		[nextPageByOrdinal release];
		nextPageByOrdinal = frozen;
	}
}

/* Prefetches the next page (B2), or without a page order the next entry
 * in stream order, as before. */
- (void)prefetchAfterEntry:(CORarEntry *)entry
{
	CORarEntry *next = nil;
	BOOL hasPageOrder = NO;
	@synchronized(self) {
		if (prefetchDisabled) return;
		if (nextPageByOrdinal) {
			hasPageOrder = YES;
			next = [[[nextPageByOrdinal objectForKey:
			          [NSNumber numberWithUnsignedInteger:entry->ordinal]] retain] autorelease];
		}
	}
	if (!hasPageOrder && entry->arrayIndex + 1 < [contentArray count])
		next = [contentArray objectAtIndex:entry->arrayIndex + 1];
	if (!next) return;
	NSNumber *key = [NSNumber numberWithUnsignedInteger:next->ordinal];
	if ([dataCache objectForKey:key]) return;
	unsigned long generation = [self beginPrefetchOfKey:next->ordinal];
	dispatch_async(readQueue, ^{	// block retains self until it runs
		BOOL skipped = NO, aborted = NO;
		if ([dataCache objectForKey:key]) {
			// already read
		} else if ([self prefetchOfKey:next->ordinal supersededSince:generation demandKey:NULL]) {
			skipped = YES;	// B2: a read of another entry came in meanwhile
		} else {
			NSData *d = [self readEntryOnQueue:next prefetchGeneration:&generation aborted:&aborted];
			if (d)
				[dataCache setObject:d forKey:key cost:[d length]];
		}
		[self endPrefetchOfKey:next->ordinal skipped:skipped aborted:aborted];
	});
}

@end
