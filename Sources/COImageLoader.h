#import <Cocoa/Cocoa.h>
#import "COPDFImage.h"
#import "COPDFImageRep.h"

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
	
	BOOL readSubFolder;
	int mode;
	
	
	COPDFImageRep	*pdfRep;
}
+(NSArray *)fileTypes;
+(NSArray *)archiveTypes;

- (id)initWithPath:(NSString *)path readSubFolder:(BOOL)boo controller:(id)ctr;
- (id)initWithPath:(NSString *)path displayPath:(NSString *)dispPath readSubFolder:(BOOL)boo controller:(id)ctr;
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
 * the password prompt (see -[Controller askArchivePassword:wrongPassword:]);
 * kept so nested archives and reopens can reuse it. */
- (NSString *)password;
/*
- (NSStringEncoding)nameEncoding;
- (void)setNameEncoding:(NSStringEncoding)enc;
*/
@end
