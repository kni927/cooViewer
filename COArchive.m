//
//  COArchive.m
//  cooViewer
//
//  See COArchive.h for the design notes.
//

#import "COArchive.h"
#import "COZipArchive.h"
#import <CoreFoundation/CoreFoundation.h>
#include <archive.h>
#include <archive_entry.h>
#include <uchardet.h>
#include <locale.h>
#include <sys/stat.h>

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

- (id)initWithPath:(NSString *)path progress:(COArchiveProgress)progress
{
	// format dispatch: zip/cbz go to the libzip lazy reader
	// (COZipArchive). If libzip cannot open the file (corrupt or
	// partial central directory), fall through to the libarchive
	// full-extraction path below.
	if ([self isMemberOfClass:[COArchive class]]) {
		NSString *ext = [[path pathExtension] lowercaseString];
		if ([ext isEqualToString:@"zip"] || [ext isEqualToString:@"cbz"]) {
			COZipArchive *z = [[COZipArchive alloc] initWithPath:path
			                                            progress:progress];
			if ([z zipOpened]) {
				[self release];
				return z;
			}
			NSLog(@"COArchive: libzip cannot open %@ (%@); falling back to libarchive",
			      path, [z lastError]);
			[z release];
		}
	}

	self = [super init];
	if (self) {
		filePath = [path retain];
		contentArray = [[NSMutableArray alloc] init];
		lastError = nil;
		crypted = NO;
		cancelled = NO;
		[self readArchiveWithProgress:progress];
	}
	return self;
}

- (void)dealloc
{
	[filePath release];
	[contentArray release];
	[lastError release];
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
			char buf[256 * 1024];
			la_ssize_t got = archive_read_data(a, buf, sizeof(buf));
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
