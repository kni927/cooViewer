#import <Cocoa/Cocoa.h>
#import "COPDFImage.h"
#import "COPDFImageRep.h"
#import "COArchive.h"	/* COArchiveCryptoStatus, for -tryPassword: */

@interface COImageLoader : NSObject {
	BOOL inTempDir;

	NSMutableArray *thumbnailArray;

	id controller;

	NSString *tempDir;
	NSMutableArray *inArchiveArray;

	NSString *filePath;
	NSString *displayPath;
	NSMutableArray *contentPathArray;
	NSMutableArray *rawContentPathArray;
	NSMutableDictionary *contentPathDic;

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
 * -1 and the only "page" is the placeholder every failed open gets — so the
 * host must ask -tryPassword: before treating it as a failed open. */
- (BOOL)needsPassword;

/* One password attempt. Returns COArchiveCryptoOK once the archive is open —
 * the entries have been scanned and -pathArray/-itemCount are the real ones,
 * exactly as if the password had been known at init time — or
 * COArchiveCryptoWrongPassword to be asked again. Any other status means the
 * archive cannot be opened at all and the host should give up. Safe to call
 * only while -needsPassword is YES. */
- (COArchiveCryptoStatus)tryPassword:(NSString *)entered;
/*
- (NSStringEncoding)nameEncoding;
- (void)setNameEncoding:(NSStringEncoding)enc;
*/
@end
