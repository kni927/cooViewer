//
//  COArchive.h
//  cooViewer
//
//  libarchive-based archive engine (replaces XADWrapper/XADMaster).
//
//  Design (docs/spike-libarchive-20260711.md, TASK v1.4.0):
//  - Format dispatch: initWithPath: returns a COZipArchive (libzip
//    lazy per-entry reader, see COZipArchive.h) for ZIP files whose
//    central directory is readable, and a CORarArchive
//    (libarchive-based partial-lazy reader, see CORarArchive.h) for
//    RAR files. The file's signature decides; the extension
//    (.zip/.cbz, .rar/.cbr) only when the signature names neither.
//    Everything below describes the libarchive full-extraction path
//    used for 7z/tar (and as the fallback when a lazy reader cannot
//    open the file).
//  - Opening an archive reads it sequentially and extracts every
//    usable entry into memory (NSData per entry). This matches how
//    COImageLoader consumes pages (-[entry data] -> NSImage
//    initWithData:) and libarchive has no random access. Nested
//    archives are written back to disk via -uncompress:as:.
//  - Entry order is archive order.
//  - Filename decoding: raw header bytes are collected for all
//    entries, uchardet runs ONCE over the concatenated names, and
//    every raw name is decoded with the detected encoding.
//    archive_entry_pathname_utf8() is used as the fast path when it
//    succeeds for every entry.
//  - Skipped entries: directories, zero-byte entries, AppleDouble
//    ("._*") sidecars.
//  - Error model: a corrupt entry is skipped with a log message and
//    the remaining entries stay readable. An unreadable archive
//    yields zero entries and -lastError.
//  - Encryption: -crypted reports whether encrypted entries were seen
//    and -cryptoStatus says what can be done about it. Encrypted ZIP
//    is supported — supply a password with -setPassword: and the
//    entries become readable (COZipArchive). Every other format
//    (RAR via CORarArchive, and this libarchive path) reports
//    COArchiveCryptoUnsupported and skips encrypted entries.
//
//  IMPORTANT: the process must run under a UTF-8 locale before any
//  COArchive use (see main.m); the C locale corrupts CP932 raw
//  names inside libarchive's zip reader. +initialize applies a
//  defensive fallback but the app-level setlocale is authoritative.
//

#import <Foundation/Foundation.h>

@interface COArchiveEntry : NSObject
{
	NSString *path;
	NSData *data;
}
- (id)initWithPath:(NSString *)inPath data:(NSData *)inData;
- (NSString *)path;
- (NSData *)data;
@end

/* Progress callback: bytesRead/bytesTotal are positions in the
 * compressed input file (monotone for every format, incl. solid).
 * Return NO to cancel; a cancelled open yields zero entries and
 * lastError = "cancelled". Called on the opening thread. */
typedef BOOL (^COArchiveProgress)(long long bytesRead, long long bytesTotal);

/* Encryption state of an opened archive. Kept separate from -lastError
 * so callers (COImageLoader's open flow and the password prompt) can
 * tell "needs a password" from "password was wrong" from "this format
 * cannot be decrypted at all". */
typedef enum {
	COArchiveCryptoNone = 0,	// no encrypted entries were seen
	COArchiveCryptoNeedsPassword,	// encrypted, no password supplied yet
	COArchiveCryptoWrongPassword,	// a password was supplied but rejected
	COArchiveCryptoOK,		// encrypted entries decrypted successfully
	COArchiveCryptoUnsupported	// encrypted, but this format cannot decrypt
} COArchiveCryptoStatus;

@interface COArchive : NSObject
{
	NSString *filePath;
	NSMutableArray *contentArray;	// COArchiveEntry, archive order
	NSString *lastError;
	BOOL crypted;
	BOOL cancelled;
	BOOL refusedSolidRAR4;
	BOOL prefetchDisabled;
	NSUInteger prefetchCount;	// prefetches scheduled (lazy readers)
}
- (id)initWithPath:(NSString *)path;
- (id)initWithPath:(NSString *)path progress:(COArchiveProgress)progress;

/* Only the lazy readers (COZipArchive, CORarArchive), chosen by the file's
 * signature and then its extension; nil instead of the full-extraction
 * fallback, which decodes every entry into memory. For callers with a
 * tight memory budget (the QuickLook extensions). nil for a solid RAR4
 * too (see -refusedSolidRAR4). */
+ (COArchive *)lazyArchiveWithPath:(NSString *)path;

- (NSString *)filePath;
- (int)itemCount;
- (NSArray *)contents;		// COArchiveEntry objects
- (NSString *)lastError;	// nil when fully OK
- (BOOL)crypted;		// encrypted entries were encountered
- (BOOL)cancelled;
/* The file is a solid RAR4 archive, which no reader here can decode past
 * its first entry (KNOWN_ISSUES #39). It is refused before either RAR
 * path is tried: no entries, and -lastError says why. */
- (BOOL)refusedSolidRAR4;

/* Encrypted-archive support. The base implementation (libarchive path)
 * cannot decrypt: -setPassword: is a no-op and -cryptoStatus reports
 * Unsupported whenever encrypted entries were seen. COZipArchive
 * overrides both; CORarArchive keeps the base behaviour. */
- (void)setPassword:(NSString *)pw;
- (COArchiveCryptoStatus)cryptoStatus;

/* write entry #index's data to fileName (for nested archives) */
- (BOOL)uncompress:(int)index as:(NSString *)fileName;

/* The entries of -contents that are pages, in page order (the order the
 * viewer shows them, which need not be archive order). A hint for a lazy
 * reader's prefetch; the base implementation ignores it, and so does
 * COZipArchive. CORarArchive prefetches the next page by it (B2). */
- (void)setPrefetchPageOrder:(NSArray *)entries;

/* No read-ahead from now on: reading an entry no longer schedules a read
 * of the next one. For a caller that needs one entry and then lets the
 * archive go — the QuickLook extensions' cover — where a prefetch would
 * keep decoding after the result has been returned (code review L3).
 * -prefetchCount says how many prefetches the lazy readers scheduled
 * (for tests). */
- (void)disablePrefetch;
- (NSUInteger)prefetchCount;
@end

/* YES when an entry path, appended to a directory, stays inside it: not
 * absolute and without a ".." component. Entry names come from archive
 * headers unchanged, so this must hold before one is used as a file name
 * on disk (COImageLoader's nested-archive extraction). */
BOOL COIsContainedEntryPath(NSString *path);
