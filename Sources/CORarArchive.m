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
#include <pthread.h>
#include <time.h>
#include <sys/mount.h>
#include <mach/mach_time.h>
#include <pthread/qos.h>

CORarPrefetchCheckpointHook CORarPrefetchCheckpointHookForTesting = NULL;
unsigned long long CORarDecodeAheadByteBoundForTesting = 0;
BOOL CORarDecodeAheadPassDisabledForTesting = NO;
CORarDecodeAheadPassHook CORarDecodeAheadPassHookForTesting = NULL;

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

static struct archive *CORarOpenStream(NSString *filePath);
static BOOL CORarEntryCounts(struct archive_entry *entry);

#pragma mark - B3: decode-ahead disk cache

/* See "Decode-ahead" in CORarArchive.h. */
#define CO_RAR_DECODE_CHUNK (256 * 1024)
#define CO_RAR_DECODE_AHEAD_MAX_BOUND (2ULL * 1024 * 1024 * 1024)
#define CO_RAR_DECODE_AHEAD_QUIET_MS 100.0
#define CO_RAR_DECODE_AHEAD_SLEEP_US 5000
#define CO_RAR_SIZE_UNKNOWN ULLONG_MAX

static double CORarMillisecondsSince(uint64_t start)
{
	static mach_timebase_info_data_t tb;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ mach_timebase_info(&tb); });
	return (double)(mach_absolute_time() - start) * tb.numer / tb.denom / 1e6;
}

static BOOL CORarWriteAll(int fd, const void *bytes, size_t length)
{
	const char *p = bytes;
	while (length > 0) {
		ssize_t n = write(fd, p, length);
		if (n < 0) {
			if (errno == EINTR) continue;
			return NO;
		}
		p += n;
		length -= (size_t)n;
	}
	return YES;
}

@interface CORarDiskCache : NSObject
{
@public
	NSString *directory;		// created by us; removed by -stop
	NSString *archivePath;
	unsigned long long *expectedSizes;	// by ordinal, CO_RAR_SIZE_UNKNOWN if unknown
	NSUInteger ordinalLimit;	// highest wanted ordinal + 1
	NSIndexSet *wanted;		// ordinals of -contents' entries
	unsigned long long byteBound;
	pthread_mutex_t lock;
	/* guarded by lock */
	NSMutableIndexSet *onDisk;
	NSMutableIndexSet *claimed;	// being written
	unsigned long long bytesReserved;	// on disk + being written (expected sizes)
	unsigned long long bytesOnDisk;
	BOOL boundReached;
	BOOL stopped;			// no new writes; files are being or have been removed
	BOOL stopCompleted;
	NSUInteger passEntryCount;
	unsigned long long passByteCount;
	NSUInteger writeThroughCount;
	NSUInteger diskHitCount;
	double passWallMs, passCPUMs, passYieldMs;
	BOOL passEnded;
	BOOL passRunning;		// started and not yet ended
	NSUInteger passPosition;	// the counted entry the pass is at
	pthread_t passThread;		// valid while passRunning
	NSUInteger awaitCount;		// reads served by waiting for the pass or a write
	pthread_cond_t changed;		// on disk, claims, pass position, pass end, stop
	/* lock-free */
	_Atomic int passDemand;		// a read is waiting for the pass: no yielding
	_Atomic int cancelled;
	_Atomic int foregroundActive;
	_Atomic uint64_t lastForegroundEnd;	// mach_absolute_time, 0 = never
	dispatch_queue_t passQueue;
	dispatch_group_t passGroup;
	dispatch_queue_t writerQueue;
}
- (id)initWithArchivePath:(NSString *)path entries:(NSArray *)entries inDirectory:(NSString *)parent;
- (void)startPass;
- (void)stop;
- (BOOL)hasOrdinal:(NSUInteger)ordinal;
- (unsigned long long)expectedSizeOfOrdinal:(NSUInteger)ordinal;
- (NSData *)dataForOrdinal:(NSUInteger)ordinal;
- (BOOL)claimOrdinal:(NSUInteger)ordinal;
- (void)releaseClaimOfOrdinal:(NSUInteger)ordinal;
- (void)writeClaimedOrdinal:(NSUInteger)ordinal data:(NSData *)data;
- (void)foregroundBegin;
- (void)foregroundEnd;
- (NSData *)awaitOrdinal:(NSUInteger)ordinal cursorNext:(NSUInteger)cursorNext
                  giveUp:(BOOL (^)(void))giveUp gaveUp:(BOOL *)outGaveUp;
@end

/* Every cache that has not been stopped, so the files of books still open
   are removed when the process exits: the app quits without releasing its
   loaders (-[NSApplication terminate:] ends in exit()). Not retained; a cache
   leaves the set at the start of -stop, which runs before it can be freed. */
static pthread_mutex_t gLiveDiskCachesLock = PTHREAD_MUTEX_INITIALIZER;
static CFMutableSetRef gLiveDiskCaches = NULL;

static void CORarStopDiskCachesAtExit(void)
{
	pthread_mutex_lock(&gLiveDiskCachesLock);
	CFIndex count = gLiveDiskCaches ? CFSetGetCount(gLiveDiskCaches) : 0;
	const void **caches = count > 0 ? malloc(sizeof(void *) * (size_t)count) : NULL;
	if (caches) {
		CFSetGetValues(gLiveDiskCaches, caches);
		for (CFIndex i = 0; i < count; i++) [(id)caches[i] retain];
	}
	pthread_mutex_unlock(&gLiveDiskCachesLock);
	if (!caches) return;
	for (CFIndex i = 0; i < count; i++) {
		CORarDiskCache *cache = (CORarDiskCache *)caches[i];
		NSString *parent = [cache->directory stringByDeletingLastPathComponent];
		[cache stop];
		/* The directory it was given (COImageLoader's temporary directory,
		   which no loader removes at quit) goes too, but only if that left
		   it empty: rmdir() refuses a directory with anything in it. */
		if (parent) rmdir([parent fileSystemRepresentation]);
		[cache release];
	}
	free(caches);
}

static void CORarRegisterDiskCache(CORarDiskCache *cache, BOOL live)
{
	pthread_mutex_lock(&gLiveDiskCachesLock);
	if (!gLiveDiskCaches) {
		gLiveDiskCaches = CFSetCreateMutable(kCFAllocatorDefault, 0, NULL);
		atexit(CORarStopDiskCachesAtExit);
	}
	if (live) CFSetAddValue(gLiveDiskCaches, cache);
	else CFSetRemoveValue(gLiveDiskCaches, cache);
	pthread_mutex_unlock(&gLiveDiskCachesLock);
}

@implementation CORarDiskCache

- (id)initWithArchivePath:(NSString *)path entries:(NSArray *)entries inDirectory:(NSString *)parent
{
	self = [super init];
	if (!self) return nil;
	pthread_mutex_init(&lock, NULL);
	pthread_cond_init(&changed, NULL);
	atomic_init(&passDemand, 0);
	archivePath = [path copy];
	onDisk = [[NSMutableIndexSet alloc] init];
	claimed = [[NSMutableIndexSet alloc] init];
	atomic_init(&cancelled, 0);
	atomic_init(&foregroundActive, 0);
	atomic_init(&lastForegroundEnd, 0);

	NSMutableIndexSet *w = [NSMutableIndexSet indexSet];
	for (CORarEntry *e in entries) {
		[w addIndex:e->ordinal];
		if (e->ordinal + 1 > ordinalLimit) ordinalLimit = e->ordinal + 1;
	}
	wanted = [w copy];
	expectedSizes = malloc(sizeof(unsigned long long) * (ordinalLimit ? ordinalLimit : 1));
	for (NSUInteger i = 0; i < ordinalLimit; i++) expectedSizes[i] = CO_RAR_SIZE_UNKNOWN;
	for (CORarEntry *e in entries)
		if (e->hasExpectedSize) expectedSizes[e->ordinal] = e->expectedSize;

	/* mkdtemp() rewrites its argument, so it needs a buffer of our own. */
	char buffer[PATH_MAX];
	NSString *template = [parent stringByAppendingPathComponent:@"decode-ahead.XXXXXX"];
	if (![template getFileSystemRepresentation:buffer maxLength:sizeof(buffer)] || mkdtemp(buffer) == NULL) {
		NSLog(@"CORarArchive: no decode-ahead directory in %@", parent);
		[self release];
		return nil;
	}
	directory = [[[NSFileManager defaultManager] stringWithFileSystemRepresentation:buffer
	                                                                         length:strlen(buffer)] retain];

	if (CORarDecodeAheadByteBoundForTesting > 0) {
		byteBound = CORarDecodeAheadByteBoundForTesting;
	} else {
		struct statfs fs;
		unsigned long long freeBytes = 0;
		if (statfs(buffer, &fs) == 0)
			freeBytes = (unsigned long long)fs.f_bavail * (unsigned long long)fs.f_bsize;
		byteBound = freeBytes / 10;
		if (byteBound > CO_RAR_DECODE_AHEAD_MAX_BOUND) byteBound = CO_RAR_DECODE_AHEAD_MAX_BOUND;
	}

	/* User-initiated, not utility: a read can wait for one of its writes
	   (-awaitOrdinal:...), and it only writes bytes already decoded. */
	writerQueue = dispatch_queue_create("cooViewer.CORarArchive.decodeAheadWrite",
		dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0));
	CORarRegisterDiskCache(self, YES);
	return self;
}

- (void)dealloc
{
	/* -stop has run (CORarArchive calls it before releasing us, and nothing
	   else retains us past the pass and the writer blocks). */
	if (passQueue) dispatch_release(passQueue);
	if (passGroup) dispatch_release(passGroup);
	if (writerQueue) dispatch_release(writerQueue);
	pthread_cond_destroy(&changed);
	pthread_mutex_destroy(&lock);
	free(expectedSizes);
	[wanted release];
	[onDisk release];
	[claimed release];
	[directory release];
	[archivePath release];
	[super dealloc];
}

- (NSString *)pathForOrdinal:(NSUInteger)ordinal temporary:(BOOL)temporary
{
	return [directory stringByAppendingPathComponent:
	        [NSString stringWithFormat:temporary ? @"%lu.tmp" : @"%lu", (unsigned long)ordinal]];
}

- (unsigned long long)expectedSizeOfOrdinal:(NSUInteger)ordinal
{
	return ordinal < ordinalLimit ? expectedSizes[ordinal] : CO_RAR_SIZE_UNKNOWN;
}

- (BOOL)hasOrdinal:(NSUInteger)ordinal
{
	pthread_mutex_lock(&lock);
	BOOL has = !stopped && [onDisk containsIndex:ordinal];
	pthread_mutex_unlock(&lock);
	return has;
}

/* Any thread. The file's bytes, read into memory (not mapped: -stop removes
   the files). nil when the entry is not on disk or the file is unreadable. */
- (NSData *)dataForOrdinal:(NSUInteger)ordinal
{
	if (![self hasOrdinal:ordinal]) return nil;
	const char *path = [[self pathForOrdinal:ordinal temporary:NO] fileSystemRepresentation];
	int fd = open(path, O_RDONLY);
	if (fd < 0) return nil;
	struct stat st;
	unsigned long long expected = [self expectedSizeOfOrdinal:ordinal];
	if (fstat(fd, &st) != 0 || st.st_size <= 0 ||
	    (expected != CO_RAR_SIZE_UNKNOWN && (unsigned long long)st.st_size != expected)) {
		close(fd);
		return nil;
	}
	size_t length = (size_t)st.st_size;
	char *bytes = malloc(length);
	size_t done = 0;
	while (bytes && done < length) {
		ssize_t n = read(fd, bytes + done, length - done);
		if (n < 0 && errno == EINTR) continue;
		if (n <= 0) break;
		done += (size_t)n;
	}
	close(fd);
	if (!bytes || done != length) {
		free(bytes);
		return nil;
	}
	pthread_mutex_lock(&lock);
	diskHitCount++;
	pthread_mutex_unlock(&lock);
	return [NSData dataWithBytesNoCopy:bytes length:length freeWhenDone:YES];
}

/* YES when the caller should write `ordinal` and now owns it: it is an entry
   of -contents, not on disk or being written, the cache is not stopped, and
   its size fits the bound. A refusal for the bound marks the bound reached. */
- (BOOL)claimOrdinal:(NSUInteger)ordinal
{
	BOOL ok = NO;
	unsigned long long expected = [self expectedSizeOfOrdinal:ordinal];
	unsigned long long reserve = expected == CO_RAR_SIZE_UNKNOWN ? 0 : expected;
	pthread_mutex_lock(&lock);
	if (!stopped && [wanted containsIndex:ordinal] &&
	    ![onDisk containsIndex:ordinal] && ![claimed containsIndex:ordinal]) {
		if (boundReached || bytesReserved + reserve > byteBound) {
			boundReached = YES;
		} else {
			[claimed addIndex:ordinal];
			bytesReserved += reserve;
			ok = YES;
		}
	}
	pthread_mutex_unlock(&lock);
	return ok;
}

- (void)releaseClaimOfOrdinal:(NSUInteger)ordinal
{
	unsigned long long expected = [self expectedSizeOfOrdinal:ordinal];
	pthread_mutex_lock(&lock);
	if ([claimed containsIndex:ordinal]) {
		[claimed removeIndex:ordinal];
		if (expected != CO_RAR_SIZE_UNKNOWN) bytesReserved -= expected;
	}
	pthread_cond_broadcast(&changed);
	pthread_mutex_unlock(&lock);
}

/* The temporary file for a claimed ordinal, or -1 (stopped, or it cannot be
   created). */
- (int)openTemporaryForOrdinal:(NSUInteger)ordinal
{
	pthread_mutex_lock(&lock);
	BOOL isStopped = stopped;
	pthread_mutex_unlock(&lock);
	if (isStopped) return -1;
	return open([[self pathForOrdinal:ordinal temporary:YES] fileSystemRepresentation],
	            O_WRONLY | O_CREAT | O_TRUNC, 0600);
}

/* Ends a claimed write: on success the temporary file is renamed to its final
   name and the ordinal is on disk; otherwise it is removed. Holding the lock
   across the rename keeps -stop from removing the directory in between. */
- (BOOL)finishOrdinal:(NSUInteger)ordinal fd:(int)fd length:(unsigned long long)length
                   ok:(BOOL)ok byPass:(BOOL)byPass
{
	if (fd >= 0) close(fd);
	unsigned long long expected = [self expectedSizeOfOrdinal:ordinal];
	NSString *tmp = [self pathForOrdinal:ordinal temporary:YES];
	pthread_mutex_lock(&lock);
	BOOL stored = NO;
	/* An entry of unknown size reserved nothing when it was claimed; it is
	   checked against the bound now, and one that does not fit ends the
	   caching as a known-size refusal in -claimOrdinal: does. */
	BOOL fits = expected != CO_RAR_SIZE_UNKNOWN || bytesReserved + length <= byteBound;
	if (ok && fd >= 0 && !fits)
		boundReached = YES;
	if (ok && fd >= 0 && fits && !stopped && length > 0 &&
	    (expected == CO_RAR_SIZE_UNKNOWN || length == expected)) {
		stored = rename([tmp fileSystemRepresentation],
		                [[self pathForOrdinal:ordinal temporary:NO] fileSystemRepresentation]) == 0;
	}
	if (!stored && fd >= 0) unlink([tmp fileSystemRepresentation]);
	[claimed removeIndex:ordinal];
	if (expected != CO_RAR_SIZE_UNKNOWN) bytesReserved -= expected;
	if (stored) {
		[onDisk addIndex:ordinal];
		bytesReserved += length;
		bytesOnDisk += length;
		if (byPass) {
			passEntryCount++;
			passByteCount += length;
		} else {
			writeThroughCount++;
		}
	}
	pthread_cond_broadcast(&changed);
	pthread_mutex_unlock(&lock);
	return stored;
}

/* Write-through from the read queue: `data` is written on the writer queue,
   off the reading thread. The ordinal must have been claimed. */
- (void)writeClaimedOrdinal:(NSUInteger)ordinal data:(NSData *)data
{
	NSData *bytes = [data retain];
	dispatch_async(writerQueue, ^{	// the block retains self
		int fd = [self openTemporaryForOrdinal:ordinal];
		BOOL ok = fd >= 0 && CORarWriteAll(fd, [bytes bytes], [bytes length]);
		[self finishOrdinal:ordinal fd:fd length:[bytes length] ok:ok byPass:NO];
		[bytes release];
	});
}

- (void)foregroundBegin
{
	atomic_fetch_add(&foregroundActive, 1);
}

- (void)foregroundEnd
{
	atomic_store(&lastForegroundEnd, mach_absolute_time());
	atomic_fetch_sub(&foregroundActive, 1);
}

/* The pass's yield point: waits while a foreground read is running or ended
   less than CO_RAR_DECODE_AHEAD_QUIET_MS ago, unless a read is waiting for
   the pass (-awaitOrdinal:..., which signals `changed`). YES when the pass
   should stop. */
- (BOOL)passYield
{
	uint64_t start = 0;
	pthread_mutex_lock(&lock);
	for (;;) {
		if (atomic_load(&cancelled)) {
			pthread_mutex_unlock(&lock);
			return YES;
		}
		if (atomic_load(&passDemand) > 0) break;
		uint64_t last = atomic_load(&lastForegroundEnd);
		if (atomic_load(&foregroundActive) == 0 &&
		    (last == 0 || CORarMillisecondsSince(last) >= CO_RAR_DECODE_AHEAD_QUIET_MS))
			break;
		if (!start) start = mach_absolute_time();
		struct timespec ts;
		clock_gettime(CLOCK_REALTIME, &ts);
		ts.tv_nsec += CO_RAR_DECODE_AHEAD_SLEEP_US * 1000;
		if (ts.tv_nsec >= 1000000000) {
			ts.tv_sec += 1;
			ts.tv_nsec -= 1000000000;
		}
		pthread_cond_timedwait(&changed, &lock, &ts);
	}
	if (start) passYieldMs += CORarMillisecondsSince(start);
	pthread_mutex_unlock(&lock);
	return NO;
}

/* YES while some entry from `ordinal` on is neither on disk nor being
   written, and the bound has not been reached. */
- (BOOL)passHasWorkFromOrdinal:(NSUInteger)ordinal
{
	if (ordinal >= ordinalLimit) return NO;
	NSRange rest = NSMakeRange(ordinal, ordinalLimit - ordinal);
	pthread_mutex_lock(&lock);
	BOOL work = !boundReached && !stopped &&
		[wanted countOfIndexesInRange:rest] >
		[onDisk countOfIndexesInRange:rest] + [claimed countOfIndexesInRange:rest];
	pthread_mutex_unlock(&lock);
	return work;
}

- (void)runPass
{
	pthread_mutex_lock(&lock);
	passThread = pthread_self();
	pthread_mutex_unlock(&lock);
	uint64_t wallStart = mach_absolute_time();
	struct timespec cpuStart, cpuEnd;
	clock_gettime(CLOCK_THREAD_CPUTIME_ID, &cpuStart);

	struct archive *a = CORarOpenStream(archivePath);
	char *buf = malloc(CO_RAR_DECODE_CHUNK);
	NSUInteger ordinal = 0;
	BOOL stop = (a == NULL || buf == NULL);
	while (!stop) {
		if ([self passYield]) break;
		if (![self passHasWorkFromOrdinal:ordinal]) break;
		if (CORarDecodeAheadPassHookForTesting) CORarDecodeAheadPassHookForTesting(ordinal, NO, NO);
		struct archive_entry *entry;
		int r = archive_read_next_header(a, &entry);
		if (r == ARCHIVE_EOF || r < ARCHIVE_WARN) break;
		if (!CORarEntryCounts(entry)) {
			archive_read_data_skip(a);
			continue;
		}
		pthread_mutex_lock(&lock);
		passPosition = ordinal;
		pthread_cond_broadcast(&changed);
		pthread_mutex_unlock(&lock);
		BOOL keep = [self claimOrdinal:ordinal];
		int fd = -1;
		if (keep) {
			fd = [self openTemporaryForOrdinal:ordinal];
			if (fd < 0) {
				[self releaseClaimOfOrdinal:ordinal];
				keep = NO;
			}
		}
		if (CORarDecodeAheadPassHookForTesting) CORarDecodeAheadPassHookForTesting(ordinal, YES, keep);
		/* An entry that is on disk or being written is still decoded and
		   dropped: the solid stream has to pass through it. */
		unsigned long long length = 0;
		BOOL ok = YES;
		for (;;) {
			if ([self passYield]) {
				ok = NO;
				stop = YES;
				break;
			}
			la_ssize_t got = archive_read_data(a, buf, CO_RAR_DECODE_CHUNK);
			if (got == 0) break;
			if (got < 0) {
				/* The stream is unreliable after a decoder error; the
				   foreground cursor reads (and may recover) the rest. */
				ok = NO;
				stop = YES;
				break;
			}
			if (keep && !CORarWriteAll(fd, buf, (size_t)got)) {
				ok = NO;	// e.g. the disk is full: no point going on
				stop = YES;
				break;
			}
			length += (unsigned long long)got;
		}
		if (keep) [self finishOrdinal:ordinal fd:fd length:length ok:ok byPass:YES];
		ordinal++;
	}
	free(buf);
	if (a) archive_read_free(a);

	clock_gettime(CLOCK_THREAD_CPUTIME_ID, &cpuEnd);
	double cpuMs = (double)(cpuEnd.tv_sec - cpuStart.tv_sec) * 1e3 +
	               (double)(cpuEnd.tv_nsec - cpuStart.tv_nsec) / 1e6;
	pthread_mutex_lock(&lock);
	passWallMs = CORarMillisecondsSince(wallStart);
	passCPUMs = cpuMs;
	passEnded = YES;
	passRunning = NO;
	pthread_cond_broadcast(&changed);
	pthread_mutex_unlock(&lock);
}

/* On the read queue, before the cursor is used for `ordinal` (cursorNext:
   the cursor's position, NSNotFound without a cursor). Returns the entry from
   disk when it is there, or once it is: when it is being written (by the
   writer queue or the pass), and when the running pass is at or before it
   and nearer to it than the cursor — the cursor would have to decode from
   further back (from the start without a cursor, or after a rewind),
   repeating what the pass has already done. While a read waits for the pass,
   the pass does not yield and runs at the reader's QoS (user-initiated).
   nil means: use the cursor. `giveUp` (a prefetch's cancellation) is checked
   every 10 ms; *outGaveUp says it fired. */
- (NSData *)awaitOrdinal:(NSUInteger)ordinal cursorNext:(NSUInteger)cursorNext
                  giveUp:(BOOL (^)(void))giveUp gaveUp:(BOOL *)outGaveUp
{
	if (outGaveUp) *outGaveUp = NO;
	BOOL found = NO, waited = NO, demanding = NO;
	pthread_override_t boost = NULL;
	pthread_mutex_lock(&lock);
	for (;;) {
		if (stopped) break;
		if ([onDisk containsIndex:ordinal]) {
			found = YES;
			break;
		}
		BOOL writing = [claimed containsIndex:ordinal];
		BOOL passNearer = passRunning && !boundReached && passPosition <= ordinal &&
			(cursorNext == NSNotFound || cursorNext > ordinal || cursorNext < passPosition);
		if (!writing && !passNearer) break;
		/* Any wait while the pass runs demands it, not only a wait for the
		   pass to get here: the claim being waited for may be the pass's own
		   (the entry it is decoding), and this reader counts as busy, so a
		   pass that yielded to it would never finish that entry. */
		if (passRunning && !demanding) {
			demanding = YES;
			atomic_fetch_add(&passDemand, 1);
			pthread_cond_broadcast(&changed);	// wakes a yielding pass
		}
		// the pass thread is known once it has started running
		if (demanding && !boost && passRunning && passThread)
			boost = pthread_override_qos_class_start_np(passThread, QOS_CLASS_USER_INITIATED, 0);
		if (giveUp && giveUp()) {
			if (outGaveUp) *outGaveUp = YES;
			break;
		}
		waited = YES;
		struct timespec ts;
		clock_gettime(CLOCK_REALTIME, &ts);
		ts.tv_nsec += 10 * 1000 * 1000;
		if (ts.tv_nsec >= 1000000000) {
			ts.tv_sec += 1;
			ts.tv_nsec -= 1000000000;
		}
		pthread_cond_timedwait(&changed, &lock, &ts);
	}
	if (found && waited) awaitCount++;
	pthread_mutex_unlock(&lock);
	if (boost) pthread_override_qos_class_end_np(boost);
	if (demanding) atomic_fetch_sub(&passDemand, 1);
	return found ? [self dataForOrdinal:ordinal] : nil;
}

- (void)startPass
{
	passQueue = dispatch_queue_create("cooViewer.CORarArchive.decodeAhead",
		dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
	passGroup = dispatch_group_create();
	pthread_mutex_lock(&lock);
	passRunning = YES;	// before it runs, so a read right after the start waits for it
	passPosition = 0;
	pthread_mutex_unlock(&lock);
	dispatch_group_async(passGroup, passQueue, ^{	// the block retains self
		@autoreleasepool {
			[self runPass];
		}
	});
}

/* Any thread but the pass and the writer queue. Idempotent. */
- (void)stop
{
	CORarRegisterDiskCache(self, NO);
	atomic_store(&cancelled, 1);
	if (passGroup) dispatch_group_wait(passGroup, DISPATCH_TIME_FOREVER);
	pthread_mutex_lock(&lock);
	BOOL already = stopCompleted;
	stopped = YES;
	stopCompleted = YES;
	pthread_cond_broadcast(&changed);
	pthread_mutex_unlock(&lock);
	if (already) return;
	/* Writes queued before `stopped` was set may still be running; later
	   ones find it set and write nothing. */
	dispatch_sync(writerQueue, ^{});
	[[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
}

@end

@interface CORarArchive (private)
- (BOOL)indexArchiveViaHeaderParser;
- (void)indexArchiveViaLibarchiveWithProgress:(COArchiveProgress)progress;
- (NSData *)readEntryOnQueue:(CORarEntry *)entry prefetchGeneration:(const unsigned long *)generation
                     aborted:(BOOL *)outAborted;
- (void)prefetchAfterEntry:(CORarEntry *)entry;
- (void)invalidateCursor;
- (CORarDiskCache *)decodeAheadCache;
- (BOOL)writeThroughPassedEntryTo:(CORarDiskCache *)disk ordinal:(NSUInteger)passedOrdinal;
@end

@implementation CORarArchive

- (void)dealloc
{
	[diskCache stop];
	[diskCache release];
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

#pragma mark B3 decode-ahead

- (CORarDiskCache *)decodeAheadCache
{
	@synchronized(self) {
		return [[diskCache retain] autorelease];
	}
}

- (BOOL)canDecodeAhead
{
	return rarOpened && solidArchive && [contentArray count] > 1;
}

- (void)setDecodeAheadDirectory:(NSString *)directory
{
	if (![self canDecodeAhead] || !directory) return;
	@synchronized(self) {
		if (diskCache) return;	// set once
	}
	CORarDiskCache *cache = [[CORarDiskCache alloc] initWithArchivePath:filePath
	                                                            entries:contentArray
	                                                        inDirectory:directory];
	if (!cache) return;
	/* One check-and-set: of two concurrent callers, the one that loses stops
	   and releases its cache (no pass has started yet). */
	BOOL won = NO;
	@synchronized(self) {
		if (!diskCache) {
			diskCache = cache;
			won = YES;
		}
	}
	if (!won) {
		[cache stop];
		[cache release];
		return;
	}
	if (!CORarDecodeAheadPassDisabledForTesting)
		[cache startPass];
}

- (void)stopDecodeAhead
{
	[[self decodeAheadCache] stop];
}

- (NSString *)decodeAheadCacheDirectory
{
	CORarDiskCache *c = [self decodeAheadCache];
	return c ? [[c->directory retain] autorelease] : nil;
}

/* The counters, read under the cache's lock. */
#define CO_RAR_DISK_COUNTER(expr) do { \
		CORarDiskCache *c = [self decodeAheadCache]; \
		if (!c) return 0; \
		pthread_mutex_lock(&c->lock); \
		NSUInteger v = (NSUInteger)(expr); \
		pthread_mutex_unlock(&c->lock); \
		return v; \
	} while (0)

- (NSUInteger)decodeAheadEntryCount { CO_RAR_DISK_COUNTER(c->passEntryCount); }
- (NSUInteger)decodeAheadByteCount { CO_RAR_DISK_COUNTER(c->passByteCount); }
- (NSUInteger)decodeAheadWriteThroughCount { CO_RAR_DISK_COUNTER(c->writeThroughCount); }
- (NSUInteger)decodeAheadDiskHitCount { CO_RAR_DISK_COUNTER(c->diskHitCount); }
- (NSUInteger)decodeAheadAwaitCount { CO_RAR_DISK_COUNTER(c->awaitCount); }
- (NSUInteger)decodeAheadDiskByteCount { CO_RAR_DISK_COUNTER(c->bytesOnDisk); }
- (NSUInteger)decodeAheadByteBound { CO_RAR_DISK_COUNTER(c->byteBound); }
- (NSUInteger)decodeAheadPassMilliseconds { CO_RAR_DISK_COUNTER(c->passWallMs + 0.5); }
- (NSUInteger)decodeAheadPassCPUMilliseconds { CO_RAR_DISK_COUNTER(c->passCPUMs + 0.5); }
- (NSUInteger)decodeAheadPassYieldMilliseconds { CO_RAR_DISK_COUNTER(c->passYieldMs + 0.5); }
- (BOOL)decodeAheadPassEnded { CO_RAR_DISK_COUNTER(c->passEnded); }
#undef CO_RAR_DISK_COUNTER

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
	solidArchive = layout.solid;
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
	// B3: then the decode-ahead files, without the read queue
	CORarDiskCache *disk = cached ? nil : [self decodeAheadCache];
	if (!cached && disk) {
		cached = [disk dataForOrdinal:ordinal];
		if (cached)
			[dataCache setObject:cached forKey:key cost:[cached length]];
	}
	if (!cached) {
		// B2: whatever read-ahead is queued or running for another entry
		// should not keep this read waiting (see CORarArchive.h)
		[self noteDemandReadOfKey:ordinal];
		[disk foregroundBegin];	// B3: the pass yields meanwhile
		__block NSData *result = nil;
		dispatch_sync(readQueue, ^{
			NSData *d = [dataCache objectForKey:key];
			if (!d && disk)
				d = [disk dataForOrdinal:ordinal];	// stored while this waited
			if (!d)
				d = [self readEntryOnQueue:entry prefetchGeneration:NULL aborted:NULL];
			if (d && ![dataCache objectForKey:key])
				[dataCache setObject:d forKey:key cost:[d length]];
			result = [d retain];
		});
		[disk foregroundEnd];
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
	// B3: what the forward cursor decodes or walks past goes to disk too
	CORarDiskCache *disk = positioned ? nil : [self decodeAheadCache];
	if (disk) {
		// B3: rather than decode it again, wait for a write of it in progress,
		// or for the pass when the pass is nearer to it than the cursor
		BOOL gaveUp = NO;
		BOOL (^giveUp)(void) = nil;
		if (generation) {
			unsigned long g = *generation;
			giveUp = ^BOOL{ return [self prefetchOfKey:ordinal supersededSince:g demandKey:NULL]; };
		}
		NSData *d = [disk awaitOrdinal:ordinal cursorNext:(cursor ? cursorNext : NSNotFound)
		                         giveUp:giveUp gaveUp:&gaveUp];
		if (d) return d;
		if (gaveUp) {
			if (outAborted) *outAborted = YES;
			return nil;
		}
	}
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
		if (!(counts && disk && [disk claimOrdinal:cursorNext] &&
		      [self writeThroughPassedEntryTo:disk ordinal:cursorNext]))
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
		if (recovered && disk && [disk claimOrdinal:ordinal])
			[disk writeClaimedOrdinal:ordinal data:payload];
		return recovered ? payload : nil;
	}
	if (disk && [disk claimOrdinal:ordinal])
		[disk writeClaimedOrdinal:ordinal data:payload];
	return payload;
}

/* B3, on readQueue: the cursor is on the data of entry `passedOrdinal`, which
   the read walks past and `disk` has let us claim. Decodes it instead of
   skipping it (in a solid stream a skip decodes anyway) and hands it to the
   writer. NO, with the claim released, if the decode failed part-way; the
   walk then goes on as after a skip. */
- (BOOL)writeThroughPassedEntryTo:(CORarDiskCache *)disk ordinal:(NSUInteger)passedOrdinal
{
	/* Owned, not autoreleased: dispatch_sync runs this on the reading
	   thread, whose pool may not drain until a whole walk is done. The
	   payload is sized from the header index when it knows the size. */
	unsigned long long expected = [disk expectedSizeOfOrdinal:passedOrdinal];
	NSMutableData *payload = [[NSMutableData alloc] initWithCapacity:
	                          expected != CO_RAR_SIZE_UNKNOWN && expected < (1ULL << 31) ? (NSUInteger)expected : 0];
	char *buf = malloc(CO_RAR_DECODE_CHUNK);
	BOOL ok = buf != NULL;
	while (ok) {
		la_ssize_t got = archive_read_data(cursor, buf, CO_RAR_DECODE_CHUNK);
		if (got == 0) break;
		if (got < 0) ok = NO;
		else [payload appendBytes:buf length:(NSUInteger)got];
	}
	free(buf);
	if (ok)
		[disk writeClaimedOrdinal:passedOrdinal data:payload];
	else
		[disk releaseClaimOfOrdinal:passedOrdinal];
	[payload release];
	return ok;
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
	// B3: a page on disk is read from there when it is wanted
	CORarDiskCache *disk = [self decodeAheadCache];
	if ([disk hasOrdinal:next->ordinal]) return;
	unsigned long generation = [self beginPrefetchOfKey:next->ordinal];
	[disk foregroundBegin];	// B3: the pass yields to read-ahead too
	dispatch_async(readQueue, ^{	// block retains self (and disk) until it runs
		BOOL skipped = NO, aborted = NO;
		if ([dataCache objectForKey:key] || [disk hasOrdinal:next->ordinal]) {
			// already read
		} else if ([self prefetchOfKey:next->ordinal supersededSince:generation demandKey:NULL]) {
			skipped = YES;	// B2: a read of another entry came in meanwhile
		} else {
			NSData *d = [self readEntryOnQueue:next prefetchGeneration:&generation aborted:&aborted];
			if (d)
				[dataCache setObject:d forKey:key cost:[d length]];
		}
		[self endPrefetchOfKey:next->ordinal skipped:skipped aborted:aborted];
		[disk foregroundEnd];
	});
}

@end
