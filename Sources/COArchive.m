//
//  COArchive.m
//  cooViewer
//
//  See COArchive.h for the design notes.
//

#import "COArchive.h"
#import "COZipArchive.h"
#import "CORarArchive.h"
#import "CORarHeaderIndex.h"
#import <CoreFoundation/CoreFoundation.h>
#include <archive.h>
#include <archive_entry.h>
#include <uchardet.h>
#include <locale.h>
#include <sys/stat.h>
#ifdef COVIEWER_REPRO_46
/* KNOWN_ISSUES #46 reproduction switch (TASK 2026-10-05); compiled out unless COVIEWER_REPRO_46 is defined. */
#include <os/log.h>
#endif

@implementation COArchiveEntry

- (id)initWithPath:(NSString *)inPath data:(NSData *)inData
{
	self = [super init];
	if (self) {
		path = [inPath retain];
		data = [inData retain];
	}
	return self;
}

- (void)dealloc
{
	[path release];
	[data release];
	[super dealloc];
}

- (NSString *)path
{
	return path;
}

- (NSData *)data
{
	return data;
}

@end

BOOL COIsContainedEntryPath(NSString *path)
{
	if ([path length] == 0 || [path hasPrefix:@"/"]) return NO;
	for (NSString *component in [path componentsSeparatedByString:@"/"]) {
		if ([component isEqualToString:@".."]) return NO;
	}
	return YES;
}

/* raw name + payload collected during the sequential read, before the
 * archive-level encoding decision is made */
@interface COArchiveRawEntry : NSObject
{
@public
	NSData *rawName;	// header bytes as stored (may be nil)
	NSString *utf8Name;	// libarchive's UTF-8 conversion (may be nil)
	NSData *payload;
}
@end

@implementation COArchiveRawEntry
- (void)dealloc
{
	[rawName release];
	[utf8Name release];
	[payload release];
	[super dealloc];
}
@end

@interface COArchive (private)
- (void)readArchiveWithProgress:(COArchiveProgress)progress;
- (NSString *)decodeName:(NSData *)raw fallback:(NSString *)u8 charset:(NSString *)charset;
@end

@implementation COArchive

+ (void)initialize
{
	if (self != [COArchive class]) return;
	// Defensive: the zip reader corrupts CP932 raw names under the C
	// locale (backslash normalization eats 0x5C trail bytes). main()
	// sets the locale properly; this catches other entry points.
	const char *ctype = setlocale(LC_CTYPE, NULL);
	if (ctype == NULL || strcmp(ctype, "C") == 0 || strcmp(ctype, "POSIX") == 0) {
		setlocale(LC_CTYPE, "en_US.UTF-8");
	}
}

- (id)initWithPath:(NSString *)path
{
	return [self initWithPath:path progress:nil];
}

typedef enum {
	COArchiveKindOther = 0,
	COArchiveKindZip,
	COArchiveKindRar
} COArchiveKind;

/* What the file's first bytes say it is; COArchiveKindOther when they name
   neither ZIP nor RAR (7z, tar, an SFX stub, unreadable). */
static COArchiveKind COSniffArchiveKind(NSString *path)
{
	unsigned char head[7];
	size_t got = 0;
	FILE *f = fopen([path fileSystemRepresentation], "rb");
	if (f) {
		got = fread(head, 1, sizeof(head), f);
		fclose(f);
	}
	if (got >= 4 && head[0] == 'P' && head[1] == 'K' &&
	    ((head[2] == 3 && head[3] == 4) || (head[2] == 5 && head[3] == 6) ||
	     (head[2] == 7 && head[3] == 8)))
		return COArchiveKindZip;
	if (got >= 7 && memcmp(head, "Rar!\x1a\x07", 6) == 0 && (head[6] == 0 || head[6] == 1))
		return COArchiveKindRar;
	return COArchiveKindOther;
}

/* Format dispatch: ZIP goes to the libzip lazy reader (COZipArchive), RAR
   to the libarchive-based partial-lazy reader (CORarArchive). The file's
   own signature decides, so a .cbr that is really a ZIP (or a .cbz that is
   a RAR) still gets a lazy reader; the extension is used only when the
   signature names neither. Returns nil when neither applies or the reader
   cannot open the file (corrupt/partial zip central directory, a RAR the
   header checks reject). */
static COArchive *COOpenLazyArchive(NSString *path, COArchiveProgress progress)
{
	COArchiveKind kind = COSniffArchiveKind(path);
	if (kind == COArchiveKindOther) {
		NSString *ext = [[path pathExtension] lowercaseString];
		if ([ext isEqualToString:@"zip"] || [ext isEqualToString:@"cbz"])
			kind = COArchiveKindZip;
		else if ([ext isEqualToString:@"rar"] || [ext isEqualToString:@"cbr"])
			kind = COArchiveKindRar;
	}
	if (kind == COArchiveKindZip) {
		COZipArchive *z = [[COZipArchive alloc] initWithPath:path
		                                            progress:progress];
		if ([z zipOpened])
			return z;
		NSLog(@"COArchive: libzip cannot open %@ (%@)", path, [z lastError]);
		[z release];
	} else if (kind == COArchiveKindRar) {
		CORarArchive *r = [[CORarArchive alloc] initWithPath:path
		                                            progress:progress];
		if ([r rarOpened])
			return r;
		NSLog(@"COArchive: CORarArchive cannot open %@ (%@)", path, [r lastError]);
		[r release];
	}
	return nil;
}

+ (COArchive *)lazyArchiveWithPath:(NSString *)path
{
	if (CORarIsSolidRAR4AtPath(path)) return nil;
	return [COOpenLazyArchive(path, nil) autorelease];
}

- (id)initWithPath:(NSString *)path progress:(COArchiveProgress)progress
{
	// A solid RAR4 is refused outright: CORarArchive would list every
	// entry and decode only the first, and the full-extraction path stops
	// after the first. Otherwise a lazy reader if one applies (see
	// COOpenLazyArchive); otherwise, or if it fails to open, the
	// libarchive full-extraction path below, which supports every format
	// and will succeed if the file is readable at all.
	BOOL solidRAR4 = NO;
	if ([self isMemberOfClass:[COArchive class]]) {
		solidRAR4 = CORarIsSolidRAR4AtPath(path);
		COArchive *lazy = solidRAR4 ? nil : COOpenLazyArchive(path, progress);
		if (lazy) {
			[self release];
			return lazy;
		}
	}

	self = [super init];
	if (self) {
		filePath = [path retain];
		contentArray = [[NSMutableArray alloc] init];
		lastError = nil;
		crypted = NO;
		cancelled = NO;
		atomic_init(&prefetchGeneration, 0);
		atomic_init(&demandKey, ULONG_MAX);
		refusedSolidRAR4 = solidRAR4;
		if (solidRAR4)
			lastError = [@"solid RAR4 archives are not supported" retain];
		else
			[self readArchiveWithProgress:progress];
	}
	return self;
}

- (void)dealloc
{
	[filePath release];
	[contentArray release];
	[lastError release];
	[outstandingPrefetchKeys release];
	[super dealloc];
}

#pragma mark -

- (NSString *)filePath
{
	return filePath;
}

- (int)itemCount
{
	return (int)[contentArray count];
}

- (NSArray *)contents
{
	return contentArray;
}

- (NSString *)lastError
{
	return lastError;
}

- (BOOL)crypted
{
	return crypted;
}

- (BOOL)cancelled
{
	return cancelled;
}

- (BOOL)refusedSolidRAR4
{
	return refusedSolidRAR4;
}

/* Base (libarchive) path: no decryption. COZipArchive overrides both;
 * CORarArchive intentionally inherits these — encrypted RAR stays
 * unsupported and fails closed. */
- (void)setPassword:(NSString *)pw
{
	(void)pw;
}

- (COArchiveCryptoStatus)cryptoStatus
{
	return crypted ? COArchiveCryptoUnsupported : COArchiveCryptoNone;
}

- (void)setPrefetchPageOrder:(NSArray *)entries
{
}

- (void)disablePrefetch
{
	@synchronized(self) { prefetchDisabled = YES; }
}

- (NSUInteger)prefetchCount
{
	@synchronized(self) { return prefetchCount; }
}

- (NSUInteger)prefetchCancelledCount
{
	@synchronized(self) { return prefetchCancelledCount; }
}

- (NSUInteger)prefetchSkippedCount
{
	@synchronized(self) { return prefetchSkippedCount; }
}

- (NSUInteger)prefetchAbortedCount
{
	@synchronized(self) { return prefetchAbortedCount; }
}

/* B3: only CORarArchive decodes ahead (see COArchive.h). */
- (BOOL)canDecodeAhead
{
	return NO;
}

- (void)setDecodeAheadDirectory:(NSString *)directory
{
	(void)directory;
}

- (void)stopDecodeAhead
{
}

- (BOOL)uncompress:(int)index as:(NSString *)fileName
{
	if (index < 0 || index >= (int)[contentArray count]) return NO;
	NSData *data = [[contentArray objectAtIndex:index] data];
	return [data writeToFile:fileName atomically:NO];
}

#pragma mark -

- (NSString *)decodeName:(NSData *)raw fallback:(NSString *)u8 charset:(NSString *)charset
{
	if (raw && charset) {
		CFStringEncoding enc = CFStringConvertIANACharSetNameToEncoding((CFStringRef)charset);
		if (enc != kCFStringEncodingInvalidId) {
			NSString *s = [(NSString *)CFStringCreateWithBytes(NULL,
				[raw bytes], (CFIndex)[raw length], enc, false) autorelease];
			if (s) return s;
		}
	}
	if (u8) return u8;
	if (raw) {
		// last resort: Latin-1 is byte-transparent, never fails
		NSString *s = [[[NSString alloc] initWithData:raw
			encoding:NSISOLatin1StringEncoding] autorelease];
		if (s) return s;
	}
	return nil;
}

- (void)readArchiveWithProgress:(COArchiveProgress)progress
{
	struct stat st;
	long long fileSize = 0;
	if (stat([filePath fileSystemRepresentation], &st) == 0)
		fileSize = (long long)st.st_size;

	struct archive *a = archive_read_new();
	archive_read_support_filter_all(a);
	archive_read_support_format_zip(a);
	archive_read_support_format_rar(a);
	archive_read_support_format_rar5(a);
	archive_read_support_format_7zip(a);
	archive_read_support_format_tar(a);

	if (archive_read_open_filename(a, [filePath fileSystemRepresentation],
	                               256 * 1024) != ARCHIVE_OK) {
		const char *e = archive_error_string(a);
		lastError = [[NSString alloc] initWithFormat:@"%s", e ? e : "cannot open archive"];
		archive_read_free(a);
		return;
	}

	NSMutableArray *rawEntries = [NSMutableArray array];
	NSMutableData *allRaw = [NSMutableData data];
	/* The read buffer lives on the heap: this runs on worker threads whose
	   stacks are 512 KB (code review L11). */
	NSMutableData *chunk = [NSMutableData dataWithLength:256 * 1024];
	char *buf = [chunk mutableBytes];
	BOOL allHaveUTF8 = YES;

	for (;;) {
		struct archive_entry *entry;
		int r = archive_read_next_header(a, &entry);
		if (r == ARCHIVE_EOF) break;
		if (r < ARCHIVE_WARN) {
			// keep whatever was read so far (truncated archive)
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

		const char *raw = archive_entry_pathname(entry);
		const char *u8 = archive_entry_pathname_utf8(entry);

		// AppleDouble sidecars ("._name") are metadata, not pages
		{
			const char *nm = u8 ? u8 : raw;
			if (nm) {
				const char *base = strrchr(nm, '/');
				base = base ? base + 1 : nm;
				if (strncmp(base, "._", 2) == 0) {
					archive_read_data_skip(a);
					continue;
				}
			}
		}

		// payload (chunked; entry size may be unset for some formats)
		NSMutableData *payload = [NSMutableData data];
		BOOL entryOK = YES;
		for (;;) {
			la_ssize_t got = archive_read_data(a, buf, [chunk length]);
			if (got == 0) break;
			if (got < 0) {
				NSLog(@"COArchive: skipping corrupt entry '%s' in %@: %s",
				      raw ? raw : "?", filePath, archive_error_string(a));
				entryOK = NO;
				break;
			}
			[payload appendBytes:buf length:(NSUInteger)got];

			if (progress && fileSize > 0) {
				long long done = (long long)archive_filter_bytes(a, -1);
				if (!progress(done, fileSize)) {
					cancelled = YES;
					goto out;
				}
			}
		}
		if (!entryOK || [payload length] == 0) continue;

		COArchiveRawEntry *re = [[[COArchiveRawEntry alloc] init] autorelease];
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
		re->payload = [[NSData alloc] initWithData:payload];
		[rawEntries addObject:re];
	}
out:

	archive_read_free(a);

	if (cancelled) {
		[contentArray removeAllObjects];
		[lastError release];
		lastError = [@"cancelled" retain];
		return;
	}

	// archive-level encoding decision
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
	COArchiveRawEntry *re;
	while ((re = [enu nextObject])) {
		NSString *name;
		if (allHaveUTF8) {
			name = re->utf8Name;	// fast path: whole archive is UTF-8/ASCII
		} else {
			name = [self decodeName:re->rawName fallback:re->utf8Name charset:charset];
		}
		if (!name) continue;
		COArchiveEntry *e = [[[COArchiveEntry alloc] initWithPath:name
		                                                     data:re->payload] autorelease];
		[contentArray addObject:e];
	}

	if ([contentArray count] == 0 && lastError == nil) {
		if (crypted)
			lastError = [@"encrypted archives are not supported" retain];
		else
			lastError = [@"no readable entries" retain];
	}
}

@end

@implementation COArchive (COLazyReaderPrefetch)

- (void)noteDemandReadOfKey:(unsigned long)key
{
	/* demandKey first: a prefetch that sees the new generation then also
	   sees the key that moved it on (both sequentially consistent). */
	atomic_store(&demandKey, key);
	atomic_fetch_add(&prefetchGeneration, 1);
	@synchronized(self) {
		NSUInteger same = [outstandingPrefetchKeys countForObject:
		                   [NSNumber numberWithUnsignedLong:key]];
		if ([outstandingPrefetchKeys count] > (same > 0 ? 1 : 0))
			prefetchCancelledCount++;
	}
}

- (unsigned long)beginPrefetchOfKey:(unsigned long)key
{
	@synchronized(self) {
		if (!outstandingPrefetchKeys)
			outstandingPrefetchKeys = [[NSCountedSet alloc] init];
		[outstandingPrefetchKeys addObject:[NSNumber numberWithUnsignedLong:key]];
		prefetchCount++;
	}
	return atomic_load(&prefetchGeneration);
}

- (BOOL)prefetchOfKey:(unsigned long)key supersededSince:(unsigned long)generation
            demandKey:(unsigned long *)outDemandKey
{
	if (atomic_load(&prefetchGeneration) == generation) return NO;
	unsigned long wanted = atomic_load(&demandKey);
	if (outDemandKey) *outDemandKey = wanted;
	return wanted != key;
}

- (void)endPrefetchOfKey:(unsigned long)key skipped:(BOOL)skipped aborted:(BOOL)aborted
{
	@synchronized(self) {
		[outstandingPrefetchKeys removeObject:[NSNumber numberWithUnsignedLong:key]];
		if (skipped) prefetchSkippedCount++;
		if (aborted) prefetchAbortedCount++;
	}
}

@end

uint64_t COArchiveDecodedCacheLimitForPhysicalMemory(uint64_t physicalMemory)
{
	const uint64_t lowest = 256ULL * 1024 * 1024;
	const uint64_t highest = 1024ULL * 1024 * 1024;
	uint64_t limit = physicalMemory / 32;
	if (limit < lowest) return lowest;
	if (limit > highest) return highest;
	return limit;
}

NSUInteger COArchiveDecodedCacheLimit(void)
{
#ifdef COVIEWER_REPRO_46
	/* KNOWN_ISSUES #46 reproduction switch (TASK 2026-10-05); compiled out unless COVIEWER_REPRO_46 is defined. */
	static dispatch_once_t repro46Once;
	dispatch_once(&repro46Once, ^{
		os_log(os_log_create("jp.coo.cooViewer", "Repro46"),
			   "COVIEWER_REPRO_46 repro switch active: decoded cache 8 MB, no decode-ahead");
	});
	return 8 * 1024 * 1024;
#else
	return (NSUInteger)COArchiveDecodedCacheLimitForPhysicalMemory(
		[[NSProcessInfo processInfo] physicalMemory]);
#endif
}
