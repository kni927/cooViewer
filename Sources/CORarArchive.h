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
//  - Decoded NSData is cached in an NSCache keyed by ordinal, with a
//    byte-cost limit, consistent with COZipArchive's cache policy.
//    After a successful on-demand decode, the entry immediately
//    following it in the stream is prefetched for free (the cursor
//    is already sitting right after the just-decoded entry).
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
//    as well as the main thread.
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
//    entries, AppleDouble ("._*") sidecars; encrypted entries set
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
}
- (BOOL)rarOpened;
/* internal, used by CORarEntry */
- (NSData *)dataForEntry:(CORarEntry *)entry;
@end
