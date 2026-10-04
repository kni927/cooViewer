//
//  COZipArchive.m
//  cooViewer
//
//  See COZipArchive.h for the design notes.
//

#import "COZipArchive.h"
#import <CoreFoundation/CoreFoundation.h>
#include <uchardet.h>
#include <string.h>

/* An entry's buffer is sized from the size the archive declares for it,
   which a crafted file chooses freely (and a decompression bomb states
   truthfully). Larger entries are refused, and only smaller ones are read
   ahead unasked, so that opening a book — or a QuickLook extension taking
   its cover — cannot be made to allocate without bound. */
#define CO_ZIP_MAX_ENTRY_SIZE (512ULL * 1024 * 1024)
#define CO_ZIP_MAX_PREFETCH_SIZE (64ULL * 1024 * 1024)

/* implemented in COArchive.m (shared archive-level name decoding) */
@interface COArchive (COArchiveNameDecoding)
- (NSString *)decodeName:(NSData *)raw fallback:(NSString *)u8 charset:(NSString *)charset;
@end

@implementation COZipEntry

- (id)initWithPath:(NSString *)inPath owner:(COZipArchive *)inOwner
             index:(zip_uint64_t)inIndex size:(unsigned long long)inSize
{
	self = [super initWithPath:inPath data:nil];
	if (self) {
		owner = inOwner;
		zipIndex = inIndex;
		size = inSize;
		ordinal = 0;
	}
	return self;
}

- (NSData *)data
{
	return [owner dataForEntry:self];
}

@end

@interface COZipArchive (private)
- (void)readCentralDirectory;
- (void)scanEntriesAndClassify;
- (COArchiveCryptoStatus)validatePasswordForIndex:(zip_uint64_t)index size:(unsigned long long)size;
- (NSData *)readEntryOnQueue:(zip_uint64_t)index size:(unsigned long long)size;
- (void)prefetchAfterOrdinal:(NSUInteger)ordinal;
@end

@implementation COZipArchive

- (void)dealloc
{
	if (za) zip_discard(za);
	if (readQueue) {
		[readQueue release];
	}
	[dataCache release];
	[password release];
	[super dealloc];
}

- (BOOL)zipOpened
{
	return zipOpened;
}

- (COArchiveCryptoStatus)cryptoStatus
{
	return cryptoStatus;
}

/* Called once from COArchive's designated initializer. The progress
 * callback is unused: only the central directory is read, so opening
 * is near instant and cannot be cancelled. */
- (void)readArchiveWithProgress:(COArchiveProgress)progress
{
	readQueue = dispatch_queue_create("cooViewer.COZipArchive.read", DISPATCH_QUEUE_SERIAL);
	dataCache = [[NSCache alloc] init];
	[dataCache setName:@"COZipArchive.dataCache"];
	// decoded-entry budget scaled with RAM; NSCache evicts under pressure anyway
	[dataCache setTotalCostLimit:COArchiveDecodedCacheLimit()];
	cryptoStatus = COArchiveCryptoNone;
	firstEncIndex = -1;
	[self readCentralDirectory];
}

- (void)readCentralDirectory
{
	int zerr = 0;
	za = zip_open([filePath fileSystemRepresentation], ZIP_RDONLY, &zerr);
	if (za == NULL) {
		zip_error_t error;
		zip_error_init_with_code(&error, zerr);
		lastError = [[NSString alloc] initWithFormat:@"%s", zip_error_strerror(&error)];
		zip_error_fini(&error);
		return;		// zipOpened stays NO; COArchive falls back to libarchive
	}
	zipOpened = YES;
	if (password)
		zip_set_default_password(za, [password UTF8String]);
	[self scanEntriesAndClassify];
}

/* (Re)build contentArray from the central directory. Non-encrypted
 * archives are read exactly as before. Encrypted entries set -crypted and
 * are included only once a password has been supplied and validated
 * against the first encrypted entry; -cryptoStatus / -lastError record
 * whether a password is missing or wrong. Re-runnable from -setPassword:. */
- (void)scanEntriesAndClassify
{
	[contentArray removeAllObjects];
	[lastError release];
	lastError = nil;
	crypted = NO;
	cryptoStatus = COArchiveCryptoNone;
	firstEncIndex = -1;
	firstEncSize = 0;
	BOOL havePassword = (password != nil);

	// pass 1: collect raw names (ZIP_FL_ENC_RAW: stored bytes, no
	// conversion by libzip), sizes, and a per-entry encryption flag for
	// the usable entries. Encrypted names join the encoding sample only
	// when a password is present (they will only be shown in that case),
	// so the non-encrypted path is byte-for-byte unchanged.
	zip_int64_t count = zip_get_num_entries(za, 0);
	NSMutableArray *rawNames = [NSMutableArray array];	// NSData
	NSMutableArray *indexes = [NSMutableArray array];	// NSNumber zip index
	NSMutableArray *sizes = [NSMutableArray array];		// NSNumber uncompressed
	NSMutableArray *encFlags = [NSMutableArray array];	// NSNumber BOOL
	NSMutableData *allRaw = [NSMutableData data];
	zip_uint64_t i;
	for (i = 0; i < (zip_uint64_t)count; i++) {
		zip_stat_t st;
		zip_stat_init(&st);
		if (zip_stat_index(za, i, 0, &st) != 0) continue;
		const char *raw = zip_get_name(za, i, ZIP_FL_ENC_RAW);
		if (!raw) continue;
		size_t len = strlen(raw);
		if (len == 0 || raw[len - 1] == '/') continue;			// directory
		if (!(st.valid & ZIP_STAT_SIZE) || st.size == 0) continue;	// zero-byte
		BOOL enc = ((st.valid & ZIP_STAT_ENCRYPTION_METHOD) &&
		            st.encryption_method != ZIP_EM_NONE);
		if (enc) {
			crypted = YES;
			if (firstEncIndex < 0) {
				firstEncIndex = (zip_int64_t)i;
				firstEncSize = st.size;
			}
			if (!havePassword) continue;	// unreadable without a password
		}
		// AppleDouble sidecars ("._name") are metadata, not pages
		{
			const char *base = strrchr(raw, '/');
			base = base ? base + 1 : raw;
			if (strncmp(base, "._", 2) == 0) continue;
		}
		[rawNames addObject:[NSData dataWithBytes:raw length:len]];
		[indexes addObject:[NSNumber numberWithUnsignedLongLong:i]];
		[sizes addObject:[NSNumber numberWithUnsignedLongLong:st.size]];
		[encFlags addObject:[NSNumber numberWithBool:enc]];
		[allRaw appendBytes:raw length:len];
		[allRaw appendBytes:"\n" length:1];
	}

	// classify the password state before deciding whether to trust the
	// encrypted entries collected above
	if (crypted && havePassword && firstEncIndex >= 0)
		cryptoStatus = [self validatePasswordForIndex:(zip_uint64_t)firstEncIndex
		                                         size:firstEncSize];
	else if (crypted)
		cryptoStatus = COArchiveCryptoNeedsPassword;
	else
		cryptoStatus = COArchiveCryptoNone;

	// archive-level encoding decision: uchardet once over every raw
	// name (per-filename detection mis-detects CP932 unacceptably
	// often; same policy as the libarchive path)
	NSString *charset = nil;
	if ([allRaw length] > 0) {
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

	NSUInteger k;
	for (k = 0; k < [rawNames count]; k++) {
		// keep encrypted entries only when the password checked out
		if ([[encFlags objectAtIndex:k] boolValue] && cryptoStatus != COArchiveCryptoOK)
			continue;
		NSString *name = [self decodeName:[rawNames objectAtIndex:k]
		                         fallback:nil charset:charset];
		if (!name) continue;
		COZipEntry *e = [[[COZipEntry alloc]
			initWithPath:name
			       owner:self
			       index:[[indexes objectAtIndex:k] unsignedLongLongValue]
			        size:[[sizes objectAtIndex:k] unsignedLongLongValue]]
			autorelease];
		e->ordinal = [contentArray count];
		[contentArray addObject:e];
	}

	if (lastError == nil) {
		if (cryptoStatus == COArchiveCryptoNeedsPassword)
			lastError = [@"password required for encrypted archive" retain];
		else if (cryptoStatus == COArchiveCryptoWrongPassword)
			lastError = [@"wrong password" retain];
		else if ([contentArray count] == 0)
			lastError = crypted ? [@"encrypted archives are not supported" retain]
			                    : [@"no readable entries" retain];
	}
}

/* Errors a wrong key leaves in the decrypted stream of the validation
 * entry. Traditional PKWARE checks the key with one header byte, which
 * about 2 wrong passwords in 256 pass; the garbage they decrypt then fails
 * the CRC, the decompressor or the length check. WinZip AES reports its
 * authentication code mismatch as a CRC error too. These used to count as
 * "not a password problem", so such a password opened the book with every
 * page broken and no new prompt (code review M9). The cost: a correct
 * password on an archive whose first encrypted entry is itself damaged is
 * now reported as wrong; the prompt's Cancel is the way out. Read errors
 * stay outside this list. */
static BOOL COZipErrorMeansWrongPassword(int ze)
{
	switch (ze) {
		case ZIP_ER_WRONGPASSWD:
		case ZIP_ER_NOPASSWD:
		case ZIP_ER_CRC:
		case ZIP_ER_ZLIB:
		case ZIP_ER_COMPRESSED_DATA:
		case ZIP_ER_INCONS:
		case ZIP_ER_DATA_LENGTH:
			return YES;
		default:
			return NO;
	}
}

/* Test-read one encrypted entry to tell a correct password from a wrong
 * one. Traditional PKWARE rejects most wrong passwords at open; WinZip AES
 * fails its HMAC only once the whole stream (plus EOF) is read, so the
 * entry is read in full, and the data errors a wrong key causes count as a
 * wrong password (see COZipErrorMeansWrongPassword). Any other failure
 * (e.g. a read error) is reported as OK here so the normal read-time path
 * handles it. */
- (COArchiveCryptoStatus)validatePasswordForIndex:(zip_uint64_t)index size:(unsigned long long)size
{
	zip_file_t *zf = zip_fopen_index(za, index, 0);
	if (!zf) {
		int ze = zip_error_code_zip(zip_get_error(za));
		if (ze == ZIP_ER_WRONGPASSWD || ze == ZIP_ER_NOPASSWD)
			return COArchiveCryptoWrongPassword;
		return COArchiveCryptoOK;		// not a password problem
	}
	unsigned char buf[8192];
	unsigned long long got = 0;
	COArchiveCryptoStatus result = COArchiveCryptoOK;
	while (got < size) {
		zip_uint64_t want = (size - got) < sizeof(buf) ? (size - got) : sizeof(buf);
		zip_int64_t n = zip_fread(zf, buf, want);
		if (n < 0) {
			int ze = zip_error_code_zip(zip_file_get_error(zf));
			if (COZipErrorMeansWrongPassword(ze))
				result = COArchiveCryptoWrongPassword;
			break;
		}
		if (n == 0) break;
		got += (unsigned long long)n;
	}
	// force EOF so WinZip AES verifies its authentication code
	if (result == COArchiveCryptoOK) {
		char tail;
		if (zip_fread(zf, &tail, 1) != 0) {
			int ze = zip_error_code_zip(zip_file_get_error(zf));
			if (COZipErrorMeansWrongPassword(ze))
				result = COArchiveCryptoWrongPassword;
			// otherwise a read error: leave OK, read-time handles it
		}
	}
	zip_fclose(zf);
	return result;
}

- (void)setPassword:(NSString *)pw
{
	NSString *old = password;
	password = [pw copy];	// UTF-8 is conveyed via -UTF8String at the libzip boundary
	[old release];
	if (za) {
		zip_set_default_password(za, password ? [password UTF8String] : NULL);
		[self scanEntriesAndClassify];
	}
}

#pragma mark -

- (NSData *)dataForEntry:(COZipEntry *)entry
{
	zip_uint64_t index = entry->zipIndex;
	unsigned long long size = entry->size;
	NSNumber *key = [NSNumber numberWithUnsignedLongLong:index];
	NSData *cached = [dataCache objectForKey:key];
	if (!cached) {
		// B2: a queued prefetch of another entry does not make this wait
		[self noteDemandReadOfKey:(unsigned long)index];
		__block NSData *result = nil;
		dispatch_sync(readQueue, ^{
			NSData *d = [dataCache objectForKey:key];
			if (!d) {
				d = [self readEntryOnQueue:index size:size];
				if (d)
					[dataCache setObject:d forKey:key cost:[d length]];
			}
			result = [d retain];
		});
		cached = [result autorelease];
	}

	// prefetch the next entry in archive order on the read queue
	[self prefetchAfterOrdinal:entry->ordinal];
	return cached;
}

/* must run on readQueue (zip_t* is not safe for concurrent reads) */
- (NSData *)readEntryOnQueue:(zip_uint64_t)index size:(unsigned long long)size
{
	if (size > CO_ZIP_MAX_ENTRY_SIZE) {
		NSLog(@"COZipArchive: entry #%llu in %@ declares %llu bytes; refused",
		      (unsigned long long)index, filePath, size);
		return nil;
	}
	zip_file_t *zf = zip_fopen_index(za, index, 0);
	if (!zf) {
		NSLog(@"COZipArchive: cannot open entry #%llu in %@: %s",
		      (unsigned long long)index, filePath, zip_strerror(za));
		return nil;
	}
	NSMutableData *buf = [NSMutableData dataWithLength:(NSUInteger)size];
	unsigned long long got = 0;
	BOOL ok = YES;
	while (got < size) {
		zip_int64_t n = zip_fread(zf, (char *)[buf mutableBytes] + got,
		                          size - got);
		if (n <= 0) {
			ok = NO;
			break;
		}
		got += (unsigned long long)n;
	}
	if (ok) {
		// hit EOF so libzip verifies the entry's CRC
		char tail;
		if (zip_fread(zf, &tail, 1) != 0) ok = NO;
	}
	if (!ok)
		NSLog(@"COZipArchive: corrupt entry #%llu in %@: %s",
		      (unsigned long long)index, filePath, zip_file_strerror(zf));
	zip_fclose(zf);
	return ok ? buf : nil;
}

- (void)prefetchAfterOrdinal:(NSUInteger)ordinal
{
	@synchronized(self) { if (prefetchDisabled) return; }
	if (ordinal + 1 >= [contentArray count]) return;
	COZipEntry *next = [contentArray objectAtIndex:ordinal + 1];
	NSNumber *key = [NSNumber numberWithUnsignedLongLong:next->zipIndex];
	if ([dataCache objectForKey:key]) return;
	zip_uint64_t idx = next->zipIndex;
	unsigned long long sz = next->size;
	if (sz > CO_ZIP_MAX_PREFETCH_SIZE) return;
	unsigned long generation = [self beginPrefetchOfKey:(unsigned long)idx];
	dispatch_async(readQueue, ^{	// block retains self until it runs
		BOOL skipped = NO;
		if ([dataCache objectForKey:key]) {
			// already read
		} else if ([self prefetchOfKey:(unsigned long)idx supersededSince:generation demandKey:NULL]) {
			skipped = YES;	// B2: a read of another entry came in meanwhile
		} else {
			NSData *d = [self readEntryOnQueue:idx size:sz];
			if (d)
				[dataCache setObject:d forKey:key cost:[d length]];
		}
		[self endPrefetchOfKey:(unsigned long)idx skipped:skipped aborted:NO];
	});
}

@end
