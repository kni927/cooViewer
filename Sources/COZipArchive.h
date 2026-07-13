//
//  COZipArchive.h
//  cooViewer
//
//  libzip-based lazy reader for zip/cbz archives (lazy-zip phase 2).
//
//  Design (docs/tasks/2026-07-13-01-vendor-libzip.md, TASK phase 2):
//  - Opening reads only the central directory; no entry data is
//    decoded at open time, so open cost is independent of archive
//    size. The zip_t* handle stays open for the document lifetime.
//  - Entry data is decoded on demand in -[COZipEntry data] via
//    zip_fopen_index/zip_fread, cached in an NSCache keyed by entry
//    index with a byte-cost limit, so peak memory stays bounded.
//    After a demand read, the next entry in archive order is
//    prefetched on the read queue.
//  - Thread safety: a zip_t* does not support concurrent reads. All
//    libzip calls after init are serialized on a private serial
//    dispatch queue; -data may be called from any thread.
//  - Filename encoding, same policy as COArchive: raw name bytes are
//    fetched with ZIP_FL_ENC_RAW (libzip performs no conversion),
//    uchardet runs ONCE over the concatenated names, and every name
//    is decoded with the detected encoding. Because libzip never
//    converts names, this path does not depend on the process locale
//    (the setlocale workaround in main.m is only needed by the
//    libarchive path).
//  - Skipped entries match COArchive: directories, zero-byte
//    entries, AppleDouble ("._*") sidecars; encrypted entries are
//    skipped with -crypted = YES (crypto is disabled in the vendored
//    libzip).
//  - Error model: a corrupt entry is detected at read time (-data
//    returns nil and the viewer shows the broken-image placeholder),
//    unlike the libarchive path which drops corrupt entries at open
//    time — detecting them eagerly would require decoding everything.
//    A zip_open failure (corrupt/partial central directory) makes
//    +[COArchive initWithPath:...] fall back to the libarchive path.
//  - The open-progress callback is never invoked (open is near
//    instant) and open cannot be cancelled; -cancelled is always NO.
//
//  Do not instantiate directly: COArchive's initializer dispatches
//  .zip/.cbz files here.
//

#import <Foundation/Foundation.h>
#import "COArchive.h"
#include <zip.h>

@class COZipArchive;

@interface COZipEntry : COArchiveEntry
{
@public
	COZipArchive *owner;	// non-retained; owner's contentArray retains us
	zip_uint64_t zipIndex;	// index in the central directory
	unsigned long long size;	// uncompressed size
	NSUInteger ordinal;	// position in the owner's contentArray
}
- (id)initWithPath:(NSString *)inPath owner:(COZipArchive *)inOwner
             index:(zip_uint64_t)inIndex size:(unsigned long long)inSize;
@end

@interface COZipArchive : COArchive
{
	zip_t *za;
	dispatch_queue_t readQueue;	// serializes every libzip call
	NSCache *dataCache;		// NSNumber(zipIndex) -> NSData
	BOOL zipOpened;			// zip_open succeeded (else caller falls back)
}
- (BOOL)zipOpened;
/* internal, used by COZipEntry */
- (NSData *)dataForEntry:(COZipEntry *)entry;
@end
