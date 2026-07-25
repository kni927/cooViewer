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

/* decoded-entry cache budget; NSCache evicts under pressure anyway */
#define CO_ZIP_CACHE_LIMIT (256 * 1024 * 1024)

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
- (COZipCryptoStatus)validatePasswordForIndex:(zip_uint64_t)index size:(unsigned long long)size;
- (NSData *)readEntryOnQueue:(zip_uint64_t)index size:(unsigned long long)size;
- (void)prefetchAfterOrdinal:(NSUInteger)ordinal;
@end

@implementation COZipArchive

- (void)dealloc
{
	if (za) zip_discard(za);
	if (readQueue) {
#if OS_OBJECT_USE_OBJC
		[readQueue release];
#else
		dispatch_release(readQueue);
#endif
	}
	[dataCache release];
	[password release];
	[super dealloc];
}

- (BOOL)zipOpened
{
	return zipOpened;
}

- (COZipCryptoStatus)cryptoStatus
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
	[dataCache setTotalCostLimit:CO_ZIP_CACHE_LIMIT];
	cryptoStatus = COZipCryptoNone;
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
	cryptoStatus = COZipCryptoNone;
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
		cryptoStatus = COZipCryptoNeedsPassword;
	else
		cryptoStatus = COZipCryptoNone;

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
		if ([[encFlags objectAtIndex:k] boolValue] && cryptoStatus != COZipCryptoOK)
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
		if (cryptoStatus == COZipCryptoNeedsPassword)
			lastError = [@"password required for encrypted archive" retain];
		else if (cryptoStatus == COZipCryptoWrongPassword)
			lastError = [@"wrong password" retain];
		else if ([contentArray count] == 0)
			lastError = crypted ? [@"encrypted archives are not supported" retain]
			                    : [@"no readable entries" retain];
	}
}

/* Test-read one encrypted entry to tell a correct password from a wrong
 * one. Traditional PKWARE rejects at open; WinZip AES fails its HMAC only
 * once the whole stream (plus EOF) is read, so the entry is read in full.
 * A non-password failure (e.g. a corrupt stream) is reported as OK here so
 * the normal read-time path handles it; only a genuine password error
 * downgrades to COZipCryptoWrongPassword. */
- (COZipCryptoStatus)validatePasswordForIndex:(zip_uint64_t)index size:(unsigned long long)size
{
	zip_file_t *zf = zip_fopen_index(za, index, 0);
	if (!zf) {
		int ze = zip_error_code_zip(zip_get_error(za));
		if (ze == ZIP_ER_WRONGPASSWD || ze == ZIP_ER_NOPASSWD)
			return COZipCryptoWrongPassword;
		return COZipCryptoOK;		// not a password problem
	}
	unsigned char buf[8192];
	unsigned long long got = 0;
	COZipCryptoStatus result = COZipCryptoOK;
	while (got < size) {
		zip_uint64_t want = (size - got) < sizeof(buf) ? (size - got) : sizeof(buf);
		zip_int64_t n = zip_fread(zf, buf, want);
		if (n < 0) {
			int ze = zip_error_code_zip(zip_file_get_error(zf));
			if (ze == ZIP_ER_WRONGPASSWD || ze == ZIP_ER_NOPASSWD)
				result = COZipCryptoWrongPassword;
			break;
		}
		if (n == 0) break;
		got += (unsigned long long)n;
	}
	// force EOF so WinZip AES verifies its authentication code
	if (result == COZipCryptoOK) {
		char tail;
		if (zip_fread(zf, &tail, 1) != 0) {
			int ze = zip_error_code_zip(zip_file_get_error(zf));
			if (ze == ZIP_ER_WRONGPASSWD || ze == ZIP_ER_NOPASSWD)
				result = COZipCryptoWrongPassword;
			// otherwise a CRC/corruption error: leave OK, read-time handles it
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
	if (ordinal + 1 >= [contentArray count]) return;
	COZipEntry *next = [contentArray objectAtIndex:ordinal + 1];
	NSNumber *key = [NSNumber numberWithUnsignedLongLong:next->zipIndex];
	if ([dataCache objectForKey:key]) return;
	zip_uint64_t idx = next->zipIndex;
	unsigned long long sz = next->size;
	dispatch_async(readQueue, ^{	// block retains self until it runs
		if ([dataCache objectForKey:key]) return;
		NSData *d = [self readEntryOnQueue:idx size:sz];
		if (d)
			[dataCache setObject:d forKey:key cost:[d length]];
	});
}

@end
