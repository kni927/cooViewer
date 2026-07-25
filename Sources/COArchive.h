//
//  COArchive.h
//  cooViewer
//
//  libarchive-based archive engine (replaces XADWrapper/XADMaster).
//
//  Design (docs/spike-libarchive-20260711.md, TASK v1.4.0):
//  - Format dispatch: initWithPath: returns a COZipArchive (libzip
//    lazy per-entry reader, see COZipArchive.h) for .zip/.cbz files
//    whose central directory is readable, and a CORarArchive
//    (libarchive-based partial-lazy reader, see CORarArchive.h) for
//    .rar/.cbr files; everything below describes the libarchive
//    full-extraction path used for 7z/tar (and as the fallback when
//    zip_open fails).
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
}
- (id)initWithPath:(NSString *)path;
- (id)initWithPath:(NSString *)path progress:(COArchiveProgress)progress;

- (NSString *)filePath;
- (int)itemCount;
- (NSArray *)contents;		// COArchiveEntry objects
- (NSString *)lastError;	// nil when fully OK
- (BOOL)crypted;		// encrypted entries were encountered
- (BOOL)cancelled;

/* Encrypted-archive support. The base implementation (libarchive path)
 * cannot decrypt: -setPassword: is a no-op and -cryptoStatus reports
 * Unsupported whenever encrypted entries were seen. COZipArchive
 * overrides both; CORarArchive keeps the base behaviour. */
- (void)setPassword:(NSString *)pw;
- (COArchiveCryptoStatus)cryptoStatus;

/* write entry #index's data to fileName (for nested archives) */
- (BOOL)uncompress:(int)index as:(NSString *)fileName;
@end
