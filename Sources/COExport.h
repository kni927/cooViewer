//
//  COExport.h
//  cooViewer
//
//  File ▸ Export…: writes a book's original page files, all or chosen pages,
//  into an uncompressed (store-only) ZIP. Foundation only, so the engine
//  tests can build it without AppKit. Nothing here decodes or draws a page:
//  the bytes written are the bytes the book holds (decrypted, for an
//  encrypted ZIP).
//
//  The window controller resolves the pages to export on the main thread
//  (-[COImageLoader exportPageAtIndex:]) and runs COExportPages() on a worker
//  thread.
//

#import <Foundation/Foundation.h>

/* One page to export: either a file on disk (a folder book's page) or an
   archive entry (anything with a -data method, a COArchiveEntry). */
@interface COExportPage : NSObject
{
	NSString *name;
	NSString *filePath;
	id entry;
	id archive;
	NSUInteger order;
}
/* A page that is a file; its name is the file's last path component. */
+ (COExportPage *)pageWithFilePath:(NSString *)path;
/* A page that is an entry of `archive`. `name` is the entry's own name
   (flattened to its last path component here), `order` its position in the
   archive's entry list: reading the entries of one archive in that order
   never makes a solid RAR's forward-only cursor go back. The page retains
   `archive`, which keeps `entry` alive. */
+ (COExportPage *)pageWithEntry:(id)entry name:(NSString *)name
                        archive:(id)archive order:(NSUInteger)order;
- (NSString *)name;		/* the original file name, flattened */
- (NSString *)filePath;		/* nil for an archive entry */
- (id)entry;
- (id)archive;
- (NSUInteger)order;
/* The page's original bytes, or nil if they cannot be read. */
- (NSData *)readData;
/* The original's modification time: the file's, or the entry's as its
   archive stores it (-[COArchiveEntry modificationDate]); nil when there
   is none. The exported entry keeps it. */
- (NSDate *)modificationDate;
@end

#pragma mark page list

typedef enum {
	COExportPageListOK = 0,
	COExportPageListSyntax,		/* not a page number or a range */
	COExportPageListOutOfRange,	/* 0, or past the last page */
	COExportPageListReversed,	/* "30-20" */
	COExportPageListEmpty		/* nothing to export (a book with no pages) */
} COExportPageListError;

/* Parses the "Pages" field: empty (or blank) means every page; otherwise a
   comma-separated list of page numbers and ranges, such as "20-30", "5" or
   "1-3,7,10-12". Spaces around numbers, dashes and commas are allowed.
   Numbers are 1-based, the numbers the page bar shows. Returns the 0-based
   page indices, ascending and without repeats (the export is always in book
   order), or nil with *error set and *badToken (optional) naming the part
   that was refused. */
NSIndexSet *COExportParsePageList(NSString *text, NSUInteger pageCount,
                                  COExportPageListError *error, NSString **badToken);

/* The page list as typed, without whitespace, or "" when blank. */
NSString *COExportNormalizedPageList(NSString *text);

#pragma mark names

/* `name` with every character that is unsafe in a file name, or awkward in
   one, replaced by "_": "/", ":", "\\", ",", "*", "?", "\"", "<", ">", "|"
   and control characters. A leading "." becomes "_" too, so the result is
   never a hidden file. */
NSString *COExportSanitizedFileName(NSString *name);

/* "<book name>-export.cbz" for every page; "<book name>-export-<pages>.cbz"
   with a page list ("1-3,7" gives "...-export-1-3_7.cbz"). `pagesText` is
   the field as typed; blank means every page. */
NSString *COExportDefaultFileName(NSString *bookName, NSString *pagesText);

/* The ZIP entry names for pages with these original names, in page order.
   Names are flattened to their last path component. They are kept as they
   are unless two of them are the same (ignoring case) or they would not sort
   in page order — by cooViewer's own sort (Finder order) or by plain byte
   order, which many readers use — and then every name gets a zero-padded
   sequence prefix instead: "0001_001.png". The width is 4 digits, or more
   when there are more pages than that holds. */
NSArray *COExportEntryNames(NSArray *originalNames);

/* YES when COExportEntryNames() would prefix these names. */
BOOL COExportNamesNeedSequencePrefix(NSArray *originalNames);

#pragma mark writing

/* Writes a store-only ZIP at `zipPath` (which must not exist): one entry per
   name, in the order given, holding the matching item of `contents` — an
   NSData, or an NSString path of a file to copy. Entries are stored, never
   compressed. `cancelled` (optional) is polled while writing; when it
   answers YES the write stops. On failure or cancel nothing is left at
   `zipPath` and *errorMessage (optional) says why (nil for a cancel). */
BOOL COExportWriteStoredZip(NSString *zipPath, NSArray *names, NSArray *contents,
                            BOOL (^cancelled)(void), NSString **errorMessage);
/* The same, with each entry's modification time: `dates` holds an NSDate
   per entry, or NSNull for "now" (as for every entry when `dates` is nil).
   ZIP stores it as a DOS time: local time, to 2 seconds. */
BOOL COExportWriteStoredZipWithDates(NSString *zipPath, NSArray *names, NSArray *contents,
                                     NSArray *dates, BOOL (^cancelled)(void),
                                     NSString **errorMessage);

typedef enum {
	COExportOK = 0,
	COExportCancelled,
	COExportReadFailed,	/* a page could not be read; *failedPage is its index in `pages` */
	COExportWriteFailed	/* staging, the ZIP or the final move failed */
} COExportResult;

/* The whole export, on any thread: reads every page's bytes — archive
   entries grouped by archive and in each archive's entry order, so a solid
   RAR is read in one forward pass — into a staging directory beside the
   destination, writes the store-only ZIP there in page order with
   COExportEntryNames() and each page's -modificationDate, and moves it to `destination`, replacing a file
   already there (the save panel has asked about that). On cancel or failure
   the destination is untouched and the staging directory is removed.
   `cancelled` is polled between pages and while the ZIP is written;
   `progress` (optional) gets 0...1. The caller keeps whatever owns the
   pages' archives (the book's loader) alive until this returns. */
COExportResult COExportPages(NSArray *pages, NSURL *destination,
                             BOOL (^cancelled)(void),
                             void (^progress)(double fraction),
                             NSUInteger *failedPage, NSString **errorMessage);
