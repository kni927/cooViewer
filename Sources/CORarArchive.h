//
//  CORarArchive.h
//  cooViewer
//
//  libarchive-based partial-lazy reader for rar/cbr archives
//  (RAR-partial-lazy phase 4; index pass replaced in phase 6).
//
//  Design (docs/tasks/... phase 4 TASK, phase 6 TASK):
//  - Phase 4: libarchive's RAR reader is a streaming API: it cannot
//    seek to an arbitrary entry the way libzip can. What it can do
//    cheaply is archive_read_data_skip(), which advances past an
//    entry's compressed data without fully decoding it — except,
//    phase 5's investigation found, for *solid* RAR5 archives, where
//    libarchive's skip is implemented by actually running the
//    decompressor and discarding the output (see
//    docs/tasks/2026-07-14-03-solid-rar-investigation.md).
//  - Phase 6 (see CORarHeaderIndex.h) replaced the open-time index
//    pass with a fast, header-only parser (raw file-offset seeks,
//    informed by XADMaster's pre-libarchive strategy) that never
//    invokes a decompressor, solid or not. That parser is a pure
//    optional fast path in front of the still-present libarchive
//    scan below, which now serves only as the fallback when the fast
//    parser declines (wrong signature, header encryption,
//    multi-volume, malformed data, or an untested RAR4 name
//    encoding — see CORarHeaderIndex.h for the exact list). The text
//    below still describes that fallback path accurately; it is
//    otherwise unchanged from phase 4.
//  - The libarchive-based fallback: open performs one skip-only pass
//    over the whole stream (archive_read_next_header +
//    archive_read_data_skip for every entry) to build the entry
//    index (name, ordinal) without decoding any entry data. This is
//    RAR's equivalent of reading zip's central directory, at the
//    cost of one skip pass instead of a free lookup (and, for solid
//    archives, at the cost phase 5 diagnosed — which is exactly why
//    phase 6 exists).
//  - Entry data is decoded on demand through a second, independent
//    "cursor" archive_read stream. The cursor tracks the ordinal of
//    the next qualifying entry it will encounter (-cursorNext).
//    Reading entry N:
//      - N < cursorNext (or no cursor yet): close any existing
//        cursor and reopen the file from the start.
//      - Fast-forward: read headers, skip each qualifying entry's
//        data via archive_read_data_skip until cursorNext == N.
//      - Decode entry N via archive_read_data() into NSData.
//    Because the cursor is reused across sequential forward reads
//    (the common case — reading pages in order), most page turns
//    only pay for one header read + one decode, not a full re-scan.
//    Backward page turns pay for a fresh fast-forward from the
//    start; see the phase 4 task doc for why this was accepted
//    rather than adding another dependency.
//  - Direct positioning (B1, docs/cbr-performance-20261003.md): for a
//    non-solid archive indexed by the header parser, every entry
//    carries its header's file offset, and the cursor is never walked
//    from the start. A read that the cursor is not already positioned
//    for opens a fresh stream through a read callback that presents the
//    signature and main header and then continues at that entry's
//    header (CORarPositionedStream below), so libarchive sees it as the
//    archive's first entry. Sequential reads then continue on that
//    cursor exactly as before. Solid archives (whose decoder state
//    depends on every earlier entry) and archives that took the
//    libarchive fallback index pass (header encryption, multi-volume,
//    RAR4 Unicode names, ...) have no offsets and keep the
//    fast-forward-from-the-start cursor described above.
//  - Decoded NSData is cached in an NSCache keyed by ordinal, with a
//    byte-cost limit that scales with physical memory
//    (COArchiveDecodedCacheLimit), consistent with COZipArchive's cache
//    policy. After an on-demand read, the next *page* is
//    prefetched (B2): COImageLoader hands over the page order with
//    -setPrefetchPageOrder:, and without one the next entry in stream order is
//    used. When page order and stream order agree, the cursor is
//    already sitting right after the just-decoded entry and the read
//    continues on it (-cursorContinueCount); when they do not, direct
//    positioning makes the prefetch a cheap reposition.
//  - Prefetch cancellation (B2, docs/cbr-performance-20261003.md): a read
//    that misses the cache (a jump, or a page the prefetch has not
//    reached) cancels every prefetch scheduled before it, except one of
//    the same entry (COArchive's -noteDemandReadOfKey:). A cancelled
//    prefetch that has not started returns at once
//    (-prefetchSkippedCount). One that is running stops
//    (-prefetchAbortedCount), returning nil and caching nothing:
//      - before any header of its walk to the entry, always — the
//        cursor is between entries there and stays valid, so the read
//        that cancelled it continues from it or replaces it as it would
//        have anyway;
//      - after any decoded 256 KB chunk, only when finishing the entry
//        is not worth it: the cursor is a positioned one (a new
//        positioned open is cheap), or the wanted entry lies behind this
//        one and is not in the decoded cache (that read reopens from the
//        start anyway). The cursor is invalidated. A forward cursor whose
//        wanted entry lies further ahead keeps decoding, since stopping it
//        would make that read start over from the beginning of the file —
//        in a solid archive, decoding everything again. So does one whose
//        wanted entry lies behind but is already cached (a read that
//        missed the cache just before the entry was stored): that read
//        needs no cursor, and stopping would only make the next page
//        rewind.
//    The wanted entry's own prefetch is never cancelled; the read waits
//    for it and then finds it in the cache.
//  - Decode-ahead (B3, survey C1 in docs/cbr-performance-20261003.md;
//    KNOWN_ISSUES #46): for a solid archive read through the header index,
//    -setDecodeAheadDirectory: (COImageLoader, for the book a window opens)
//    creates a directory of its own inside the given one and starts a pass
//    on a serial queue of utility QoS. The pass opens its own libarchive
//    stream (the foreground cursor is untouched), decodes every entry in
//    stream order and writes each one counted in -contents to "<ordinal>"
//    (streamed through "<ordinal>.tmp" and renamed, so a file under its
//    final name is always complete; its length must match the header
//    index's size). The foreground cursor writes through: the entry it
//    reads, and every counted entry it walks past on the way (decoded
//    instead of skipped — in a solid stream a skip decodes anyway), are
//    handed to a serial writer queue of utility QoS. A read then tries
//    the NSCache, then these files (on the calling thread, without the read
//    queue), then the cursor; a page the NSCache lost is read back from
//    disk instead of by rewinding. Which ordinals are on disk, being
//    written, and the byte totals are guarded by one mutex.
//    Yield: every read and prefetch that goes to the read queue counts
//    itself busy for its duration; the pass checks before every header and
//    every 256 KB chunk, and waits (in 5 ms steps) while anything is busy or
//    until 100 ms after the last such read ended. It also ends as soon as
//    every entry from its position on is on disk or being written (a
//    read-through by the cursor has already stored them).
//    No double decoding: before the cursor is used, a read waits for the
//    entry when it is being written (the writer queue, or the pass), and
//    when the running pass is at or before it and nearer to it than the
//    cursor (no cursor, a cursor that would rewind, or one behind the
//    pass). Without this the cursor would decode again what the pass has
//    decoded, and a page the NSCache dropped just before its write-through
//    finished would rewind the stream. While a read waits, the pass does not
//    yield and its thread runs at user-initiated QoS
//    (pthread_override_qos_class_start_np). A prefetch gives up the wait
//    when it is cancelled (B2). The pass is then the decoder at the front
//    of the stream; the cursor is used for entries the pass will not store
//    (bound, decode error, stopped).
//    Bound: min(2 GB, a tenth of the free space of the directory's volume
//    when it is set) per open book. An entry that would pass it is not
//    stored; the pass ends there. 2 GB holds every ordinary book (decoded
//    size is about the archive size for JPEG pages; the 400-page generated
//    book is 560 MB), and a tenth of free space keeps a nearly full disk
//    from being filled by a cache.
//    Stop: -stopDecodeAhead (COImageLoader's dealloc, before it removes its
//    temporary directory, and this class's dealloc) cancels the pass,
//    waits for it to return (it checks every chunk, so within one 256 KB
//    decode), refuses further writes, waits for queued writes, and removes
//    the directory it created. The pass and the writer retain only the
//    cache object (CORarDiskCache), never the archive. The app quits
//    without releasing its loaders, so every cache not yet stopped is also
//    stopped, and its files removed, by an atexit() handler, which then also
//    removes the directory it was given if that is left empty (the loader's
//    temporary directory; one holding nested archives stays). A crash still
//    leaves them in the per-user temporary directory.
//    Any read that waits in -awaitOrdinal: while the pass runs demands the
//    pass (no yielding, QoS override), also when it waits for the pass's
//    own claim: the reader counts as busy, so a pass yielding to it would
//    never finish that entry. The writer queue is user-initiated for the
//    same reason (a read can wait for its writes).
//    Not used for non-solid archives (direct positioning makes a jump
//    cheap), for the libarchive fallback index (solidity unknown; a rewind
//    over non-solid entries skips without decoding), for 7z (decoded into
//    memory at open), or by the QuickLook extensions (never set).
//  - Thread safety: a single struct archive* stream is not safe for
//    concurrent use. The index pass runs synchronously, entirely on
//    whichever single thread initializes the object, exactly like the
//    base COArchive full-extraction path. Since MW-1 that is normally
//    a background thread, not the main thread: the host runs the read
//    off-main behind a progress sheet (see -[BookWindowController
//    runArchiveLoadNamed:usingBlock:]). This is safe because the pass
//    is still confined to one thread — what must never happen is two
//    threads touching the stream at once.
//    (Before MW-1 this comment required the main thread, because the
//    progress callback dequeued NSApp's event queue directly. That was
//    a consequence of the old -archiveReadProgress:total:, which no
//    longer touches AppKit at all; the requirement went with it.)
//    Once the index pass finishes, every cursor operation for entry
//    decode is serialized on a private dispatch queue instead, since
//    -data is called from COImageLoader's lookahead/prefetch threads
//    as well as the main thread. Prefetches are blocks on that same
//    queue. Cancellation never touches the stream from outside it: the
//    reading thread only moves an atomic generation counter (and records
//    the entry it wants) before it waits on the queue, and the prefetch
//    on the queue reads that counter at its checkpoints and stops
//    itself.
//  - Filename encoding (libarchive fallback path): same policy as
//    COArchive/COZipArchive — raw header bytes
//    (archive_entry_pathname) and libarchive's UTF-8 conversion
//    (archive_entry_pathname_utf8) are collected for every entry
//    during the index pass; if any entry lacks a UTF-8 conversion,
//    uchardet runs ONCE over every entry's concatenated raw bytes
//    and the shared COArchive decodeName:fallback:charset: routine
//    picks the final name. This path still depends on the process
//    locale exactly as before (see main.m) — libarchive's RAR reader
//    (unlike libzip) performs its own raw-to-UTF8 conversion
//    internally, so the setlocale workaround remains required here.
//    The phase 6 header-only parser reuses the same
//    decodeName:fallback:charset: routine and uchardet policy, but
//    supplies its own raw bytes / UTF-8 names directly from the
//    parsed headers — see CORarHeaderIndex.h.
//  - Skipped entries match COArchive: directories, zero-byte
//    entries, AppleDouble ("._*") sidecars, and symbolic and hard
//    links (CORarEntryCounts, shared with the cursor); encrypted entries set
//    -crypted = YES and are skipped (unrar decryption was never
//    supported, consistent with v1.4.0).
//  - Error model: corrupt entries are detected at read time (-data
//    returns nil, viewer shows the broken-image placeholder) rather
//    than being dropped at open time — same tradeoff COZipArchive
//    made, and for the same reason (detecting corruption eagerly
//    would require decoding everything up front, defeating the
//    point). If archive_read_open_filename itself fails (e.g. a
//    mislabeled non-RAR file with a .cbr extension, or an
//    unreadable file), -rarOpened is NO and COArchive's initializer
//    falls back to the libarchive full-extraction path, mirroring
//    zip's corrupt-central-directory fallback — this turned out to
//    be trivial to add once CORarArchive existed, so the phase 4
//    task's "skip unless trivial" fallback was implemented. Failures
//    that happen mid-scan, after the stream opened successfully
//    (e.g. a truncated file), are NOT retried through the fallback:
//    -rarOpened is already YES by then, so whatever entries the
//    index pass collected before hitting the error are kept, same
//    partial-results philosophy as the base COArchive path. The one
//    narrow recovery case is a decoder error after the complete
//    payload was returned: trusted header size and file CRC must both
//    match, and the cursor is still invalidated before returning data.
//    This is a compatibility fallback for libarchive/libarchive#3352
//    and libarchive/libarchive#3361. Reassess it after the vendored
//    libarchive contains the upstream RAR5 end-of-entry correction.
//  - The open-progress callback is only invoked when the libarchive
//    fallback index pass runs (open can be cancelled in that case,
//    same as phase 4); the phase 6 header-only fast path never calls
//    it and cannot be cancelled, matching COZipArchive's precedent —
//    it is expected to finish in well under a second regardless of
//    archive size.
//
//  Do not instantiate directly: COArchive's initializer dispatches
//  .rar/.cbr files here.
//

#import <Foundation/Foundation.h>
#import "COArchive.h"
#include <archive.h>

@class CORarArchive;

@interface CORarEntry : COArchiveEntry
{
@public
	CORarArchive *owner;	// non-retained; owner's contentArray retains us
	NSUInteger ordinal;	// position among qualifying entries in stream
				// order; what the cursor fast-forwards to
	NSUInteger arrayIndex;	// position in the owner's contentArray (may
				// differ from ordinal if a qualifying entry
				// somewhere earlier in the stream had no
				// decodable name and was skipped)
	BOOL hasExpectedSize;
	unsigned long long expectedSize;
	BOOL hasExpectedCRC;
	uint32_t expectedCRC;
	BOOL hasHeaderOffset;	// direct positioning available (see above)
	unsigned long long headerOffset;
}
- (id)initWithPath:(NSString *)inPath owner:(CORarArchive *)inOwner
           ordinal:(NSUInteger)inOrdinal
   hasExpectedSize:(BOOL)inHasExpectedSize
       expectedSize:(unsigned long long)inExpectedSize
    hasExpectedCRC:(BOOL)inHasExpectedCRC
        expectedCRC:(uint32_t)inExpectedCRC;
@end

/* Integrity gate used only after libarchive returns an entry read error. */
BOOL CORarPayloadMatchesExpectedMetadata(NSData *payload,
                                         BOOL hasExpectedSize,
                                         unsigned long long expectedSize,
                                         BOOL hasExpectedCRC,
                                         uint32_t expectedCRC);

@interface CORarArchive : COArchive
{
	struct archive *cursor;	// decode cursor stream, or NULL when unopened
	NSUInteger cursorNext;	// ordinal the cursor will read next
	dispatch_queue_t readQueue;	// serializes every libarchive call
	NSCache *dataCache;		// NSNumber(ordinal) -> NSData
	BOOL rarOpened;			// index pass succeeded (else caller falls back)
	/* Non-zero only when entries can be read by direct positioning: the
	   length of the signature + main header prefix (CORarArchiveLayout). */
	unsigned long long positioningPrefixLength;
	/* B2: NSNumber(ordinal) -> CORarEntry of the next page, from
	   -setPrefetchPageOrder:. Guarded by @synchronized(self). */
	NSDictionary *nextPageByOrdinal;
	/* Diagnostics for tests and tools/cbr_bench: cursor streams opened
	   from the start of the file, and by direct positioning. readQueue
	   only. */
	NSUInteger rewindCount;
	NSUInteger positionedOpenCount;
	/* Reads that used the open cursor without opening a stream (readQueue
	   only). */
	NSUInteger cursorContinueCount;
	/* B3: the header index found a solid archive. */
	BOOL solidArchive;
	/* B3: the decode-ahead disk cache (CORarDiskCache, private to
	   CORarArchive.m), or nil. Set once; guarded by @synchronized(self). */
	id diskCache;
}
- (BOOL)rarOpened;
- (BOOL)usesDirectPositioning;
/* Diagnostics; each waits for the reads queued before it. */
- (NSUInteger)rewindCount;
- (NSUInteger)positionedOpenCount;
- (NSUInteger)cursorContinueCount;
/* B3 diagnostics (0 without decode-ahead): entries and bytes the pass
 * stored; entries the foreground cursor stored (write-through); reads served
 * from disk; bytes on disk now; the bound; the pass's wall-clock, thread-CPU
 * and yielding time in ms, set when it has ended; whether it has ended. */
- (NSUInteger)decodeAheadEntryCount;
- (NSUInteger)decodeAheadByteCount;
- (NSUInteger)decodeAheadWriteThroughCount;
- (NSUInteger)decodeAheadDiskHitCount;
/* B3: reads served from disk after waiting for a write or for the pass. */
- (NSUInteger)decodeAheadAwaitCount;
- (NSUInteger)decodeAheadDiskByteCount;
- (NSUInteger)decodeAheadByteBound;
- (NSUInteger)decodeAheadPassMilliseconds;
- (NSUInteger)decodeAheadPassCPUMilliseconds;
- (NSUInteger)decodeAheadPassYieldMilliseconds;
- (BOOL)decodeAheadPassEnded;
/* The directory the cache files are in, or nil. */
- (NSString *)decodeAheadCacheDirectory;
/* internal, used by CORarEntry */
- (NSData *)dataForEntry:(CORarEntry *)entry;
@end

/* Tests only (tests/engine): when set, called on the read queue by a
 * prefetch at each cancellation checkpoint, just before it checks —
 * `decoding` NO before a header of its walk, YES after a decoded chunk of
 * entry `ordinal`. NULL in the app. */
typedef void (*CORarPrefetchCheckpointHook)(CORarArchive *archive, NSUInteger ordinal, BOOL decoding);
extern CORarPrefetchCheckpointHook CORarPrefetchCheckpointHookForTesting;

/* Tests only (tests/engine), NULL / 0 / NO in the app:
 * - CORarDecodeAheadByteBoundForTesting: the bound in bytes instead of the
 *   computed one, when non-zero;
 * - CORarDecodeAheadPassDisabledForTesting: no pass is started, so only the
 *   foreground cursor's write-through stores entries;
 * - CORarDecodeAheadPassHookForTesting: called by the pass before each
 *   header it reads, with the ordinal it is at (`afterClaim` NO), and again
 *   for a counted entry once it has tried to claim it, before decoding it
 *   (`afterClaim` YES; `claimed` says whether it will store it). */
extern unsigned long long CORarDecodeAheadByteBoundForTesting;
extern BOOL CORarDecodeAheadPassDisabledForTesting;
typedef void (*CORarDecodeAheadPassHook)(NSUInteger ordinal, BOOL afterClaim, BOOL claimed);
extern CORarDecodeAheadPassHook CORarDecodeAheadPassHookForTesting;
