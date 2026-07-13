//
//  COArchive.h
//  cooViewer
//
//  libarchive-based archive engine (replaces XADWrapper/XADMaster).
//
//  Design (docs/spike-libarchive-20260711.md, TASK v1.4.0):
//  - Format dispatch: initWithPath: returns a COZipArchive (libzip
//    lazy per-entry reader, see COZipArchive.h) for .zip/.cbz files
//    whose central directory is readable; everything below describes
//    the libarchive full-extraction path used for all other formats
//    (and as the fallback when zip_open fails).
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
//    yields zero entries and -lastError. Encrypted archives are
//    unsupported (password support dropped in v1.4.0): -crypted
//    reports YES and encrypted entries are skipped.
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

@interface COArchive : NSObject
{
	NSString *filePath;
	NSMutableArray *contentArray;	// COArchiveEntry, archive order
	NSString *lastError;
	BOOL crypted;
	BOOL cancelled;
}
- (id)initWithPath:(NSString *)path;
- (id)initWithPath:(NSString *)path progress:(COArchiveProgress)progress;

- (NSString *)filePath;
- (int)itemCount;
- (NSArray *)contents;		// COArchiveEntry objects
- (NSString *)lastError;	// nil when fully OK
- (BOOL)crypted;		// encrypted entries were encountered (unsupported)
- (BOOL)cancelled;

/* write entry #index's data to fileName (for nested archives) */
- (BOOL)uncompress:(int)index as:(NSString *)fileName;
@end
