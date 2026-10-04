#import <Cocoa/Cocoa.h>
#import "COPDFImage.h"
#import "COPDFImageRep.h"
#import "COArchive.h"	/* COArchiveCryptoStatus, for -tryPassword: */

/* Whether a loader has pages, and if not, why (KNOWN_ISSUES #30). A page that
 * fails to decode is still a page — -itemAtIndex: shows a placeholder for it —
 * so only a book with nothing in it to list ever reports anything else. */
typedef enum {
	COImageLoaderHasPages = 0,
	/* The open did not run to the end: the archive read was cancelled, a
	 * password is still needed or was not given, the file is a refused solid
	 * RAR4 (-isUnsupportedSolidRAR4), or the path is not a book at all. `mode`
	 * is -1. Nothing for the host to report beyond what it already knows. */
	COImageLoaderNotOpened,
	/* Read without trouble, but nothing in it is an image: an empty folder,
	 * an archive of other files, a saved search with no image results. */
	COImageLoaderNoImages,
	/* The archive or PDF could not be read at all (damaged, truncated, or not
	 * what its extension says). */
	COImageLoaderUnreadable,
	/* Encrypted with something this format cannot decrypt (encrypted RAR or
	 * 7z; docs/DECISIONS.md, "Encrypted RAR support: declined"). */
	COImageLoaderEncryptionUnsupported
} COImageLoaderPagesStatus;

@interface COImageLoader : NSObject {
	BOOL inTempDir;


	id controller;

	NSString *tempDir;
	NSMutableArray *inArchiveArray;

	NSString *filePath;
	NSString *displayPath;
	NSMutableArray *contentPathArray;
	NSMutableArray *rawContentPathArray;
	NSMutableDictionary *contentPathDic;
	/* Archive books: raw entry name -> indices of every entry with that
	 * name, in archive order; and the page paths that occur more than once
	 * (nil when none do). An archive can hold several entries of one name;
	 * the n-th page of a repeated name is the n-th such entry, not the
	 * first one again (code review L4). */
	NSMutableDictionary *entryIndicesByRawName;
	NSSet *duplicatePagePaths;

	id archiveContainer;
	id subArchiveContainer;
	NSArray *filterArray;
	NSString *password;	// for encrypted ZIP; nil until one is accepted

	/* Encrypted-archive prompting. A host that can present a window-modal
	 * sheet asks for `deferPasswordPrompt`, and this loader then never blocks
	 * to ask: it reports `needsPassword` instead and the host drives the
	 * prompt, calling -tryPassword: for each attempt (KNOWN_ISSUES #33). Every
	 * other caller — nested archives, the QuickLook/Thumbnail extractors —
	 * keeps the original synchronous behaviour. */
	BOOL deferPasswordPrompt;
	BOOL needsPassword;

	BOOL readSubFolder;
	int mode;
	
	
	COPDFImageRep	*pdfRep;
}
+(NSArray *)fileTypes;
+(NSArray *)archiveTypes;

- (id)initWithPath:(NSString *)path readSubFolder:(BOOL)boo controller:(id)ctr;
- (id)initWithPath:(NSString *)path displayPath:(NSString *)dispPath readSubFolder:(BOOL)boo controller:(id)ctr;
/* The designated initializer. `defer` = YES means "do not block to ask for a
 * password; tell me you need one" — see -needsPassword / -tryPassword:. The
 * two initializers above pass NO, so nothing but an explicit opt-in changes
 * behaviour. */
- (id)initWithPath:(NSString *)path displayPath:(NSString *)dispPath readSubFolder:(BOOL)boo controller:(id)ctr deferPasswordPrompt:(BOOL)defer;
//- (id)initWithPath:(NSString *)path readSubFolder:(BOOL)boo;
//- (id)initWithPath:(NSString *)path displayPath:(NSString *)dispPath readSubFolder:(BOOL)boo;

- (NSString*)filePath;
- (NSString*)displayPath;
- (NSString*)itemPathAtIndex:(int)index;
- (NSString*)itemNameAtIndex:(int)index;
- (BOOL)canSortByDate;

- (int)itemCount;

//NSImageを返す
- (id)itemAtIndex:(int)index;

//file名のsort済みarray
- (NSMutableArray*)pathArray;

//(-1=err),0=dir,1=zip,2=rar,3=savedSearch,4=pdf
- (int)mode;

- (int)nextFolder:(int)now;
- (int)prevFolder:(int)now;

- (BOOL)isInTempDir;
- (void)setInTempDir:(BOOL)b;

/* Password accepted for an encrypted ZIP, or nil. Set during opening by
 * the password prompt (see -[BookWindowController askArchivePassword:wrongPassword:]);
 * kept so nested archives and reopens can reuse it. */
- (NSString *)password;

/* YES when this loader was opened with `deferPasswordPrompt` and the archive
 * turned out to be an encrypted one it can unlock, but no password has been
 * supplied yet. The loader holds nothing readable in that state — `mode` is
 * -1 and it has no pages — so the host must ask -tryPassword: before treating
 * it as a failed open. */
- (BOOL)needsPassword;

/* One password attempt. Returns COArchiveCryptoOK once the archive is open —
 * the entries have been scanned and -pathArray/-itemCount are the real ones,
 * exactly as if the password had been known at init time — or
 * COArchiveCryptoWrongPassword to be asked again. Any other status means the
 * archive cannot be opened at all and the host should give up. Safe to call
 * only while -needsPassword is YES. */
- (COArchiveCryptoStatus)tryPassword:(NSString *)entered;

/* The book is a solid RAR4 archive, refused at open (KNOWN_ISSUES #39):
 * `mode` is -1, as for any failed open, and the host can tell the user why. */
- (BOOL)isUnsupportedSolidRAR4;

/* Whether this book has anything to show (KNOWN_ISSUES #30). A loader with
 * no pages has an -itemCount of 0; the host treats anything but
 * COImageLoaderHasPages as a failed open, and reports the last three
 * statuses to the user. */
- (COImageLoaderPagesStatus)pagesStatus;
/*
- (NSStringEncoding)nameEncoding;
- (void)setNameEncoding:(NSStringEncoding)enc;
*/
@end
