#import "COArchive.h"
#import "BookWindowController.h"
#import "COImageLoader.h"

@interface COImageLoader(private)
-(void)content;
-(BOOL)checkArchiveContainer:(int)index;
-(BOOL)uncompressToTempDir:(NSString*)file;
-(BOOL)unlockEncryptedArchive;
//-(BOOL)uncompressAllFileToTempDir;
@end
static NSArray *_COImageLoader_fileTypes=nil;
static NSArray *_COImageLoader_archiveTypes=nil;
@implementation COImageLoader
+(NSArray *)fileTypes
{
	//COImageLoaderで読み込める種類(スマートフォルダとフォルダ以外)
	if (!_COImageLoader_fileTypes) {
		id types = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDocumentTypes"];
		id object,inner;
		NSMutableArray *array = [NSMutableArray array];
		NSEnumerator *enu = [types objectEnumerator];
		while (object=[enu nextObject]) {
            if ((inner = [object objectForKey:@"CFBundleTypeExtensions"])) {
				[array addObjectsFromArray:inner];
			}
		}
		[array removeObjectsInArray:[NSImage imageFileTypes]];
		[array removeObjectsInArray:[NSArray arrayWithObjects:@"savedSearch",nil]];
		[array addObject:@"pdf"];
		_COImageLoader_fileTypes = [[NSArray arrayWithArray:array] retain];
		//NSLog(@"%@",_COImageLoader_fileTypes);
	}
	return _COImageLoader_fileTypes;
	//return [NSArray arrayWithObjects:@"zip",@"cbz",@"rar",@"cbr",@"lzh",@"lha",@"7z",@"sit",@"pdf",@"cvbdl",nil];
}
+(NSArray *)archiveTypes
{
	//COImageLoaderで読み込めるアーカイブ
	if (!_COImageLoader_archiveTypes) {
		NSMutableArray *temp = [NSMutableArray arrayWithArray:[COImageLoader fileTypes]];
		[temp removeObjectsInArray:[NSArray arrayWithObjects:@"cvbdl",@"pdf",nil]];
		_COImageLoader_archiveTypes = [[NSArray arrayWithArray:temp] retain];
		//NSLog(@"%@",_COImageLoader_archiveTypes);
	}
	return _COImageLoader_archiveTypes;
	//return [NSArray arrayWithObjects:@"zip",@"cbz",@"rar",@"cbr",@"lzh",@"lha",@"7z",@"sit",nil];
}

- (NSString*)displayPath
{
	return displayPath;
}

- (id)initWithPath:(NSString *)path displayPath:(NSString *)dispPath readSubFolder:(BOOL)boo controller:(id)ctr;
{
	return [self initWithPath:path displayPath:dispPath readSubFolder:boo controller:ctr
		  deferPasswordPrompt:NO];
}

- (id)initWithPath:(NSString *)path displayPath:(NSString *)dispPath readSubFolder:(BOOL)boo controller:(id)ctr deferPasswordPrompt:(BOOL)defer;
{

	self = [super init];
    if (self) {
		controller = ctr;
		deferPasswordPrompt = defer;
		needsPassword = NO;
		tempDir = nil;
		inTempDir = NO;
		inArchiveArray = [[NSMutableArray alloc] init];

		NSMutableArray *tempArray = [NSMutableArray arrayWithArray:[COImageLoader fileTypes]];
		[tempArray addObjectsFromArray:[NSImage imageFileTypes]];

		filterArray = [[NSArray arrayWithArray:tempArray] retain];
		readSubFolder=boo;
		mode=-1;
		filePath=[path retain];
		displayPath = [dispPath retain];
		archiveContainer = nil;
		subArchiveContainer = nil;
		password = nil;
		contentPathArray = [[NSMutableArray alloc] init];
		contentPathDic = [[NSMutableDictionary alloc] init];
		rawContentPathArray = [[NSMutableArray alloc] init];
		pdfRep = nil;
		
		[self content];
	}
	if ([self itemCount]==0) {
		[contentPathArray addObject:[[NSBundle mainBundle] pathForResource:@"empty" ofType:@"png"]];
	}
    return self;	
}

- (id)initWithPath:(NSString *)path readSubFolder:(BOOL)boo controller:(id)ctr;
{
	return [self initWithPath:path displayPath:path readSubFolder:boo controller:ctr];
}

- (void)dealloc
{
	if(tempDir) {
        [[NSFileManager defaultManager] removeItemAtURL:[NSURL fileURLWithPath:tempDir] error:nil];
		[tempDir release];
	}
	
	if(rawContentPathArray)[rawContentPathArray release];
	if(inArchiveArray)[inArchiveArray release];
	if(filePath)[filePath release];
	if(displayPath)[displayPath release];
	if(archiveContainer)[archiveContainer release];
	if(subArchiveContainer)[subArchiveContainer release];
	if(contentPathArray)[contentPathArray release];
	if(contentPathDic)[contentPathDic release];
	if(filterArray)[filterArray release];
	if(password)[password release];
	if(pdfRep)[pdfRep release];
	//if(mode==4)CGPDFDocumentRelease(pdfDocument);
	
	[super dealloc];
}

#pragma mark -
- (NSString *)filePath
{
	return filePath;
}

- (int)itemCount
{
	if(contentPathArray)	return (int)[contentPathArray count];
	return 0;
}
- (int)mode
{
	//0:fold 1:hetimazip=>disable 2:xad 3:savedSearch 4:pdf 5:dummy
	return mode;
}

- (NSString*)itemPathAtIndex:(int)index
{
	if ([inArchiveArray count] > 0) {
		NSString *fileName = [contentPathArray objectAtIndex:index];
		int i;
		for (i=0; i<[inArchiveArray count]; i++) {
			COImageLoader *inLoader = [inArchiveArray objectAtIndex:i];
			if (![inLoader isInTempDir] && [[inLoader pathArray] indexOfObject:fileName] != NSNotFound) {
				return [inLoader filePath];
			}
		}
	}
	if (mode==0 || mode==3 || mode==5) {
		return [contentPathArray objectAtIndex:index];
	} else {
		return filePath;
	}
}

- (NSString*)itemNameAtIndex:(int)index
{
	return [contentPathArray objectAtIndex:index];
}

- (BOOL)canSortByDate
{
	if ([inArchiveArray count]>0) {
		return NO;
	}
	if (mode==0 || mode==3) {
		return YES;
	}
	return NO;
}

- (NSMutableArray*)pathArray
{
	return contentPathArray;
}
#pragma mark -

- (id)itemAtIndex:(int)index
{
	if ([inArchiveArray count] > 0) {
		NSString *fileName = [contentPathArray objectAtIndex:index];
		int i;
		for (i=0; i<[inArchiveArray count]; i++) {
			COImageLoader *inLoader = [inArchiveArray objectAtIndex:i];
			if ([[inLoader pathArray] indexOfObject:fileName] != NSNotFound) {
				return [inLoader itemAtIndex:(int)[[inLoader pathArray] indexOfObject:fileName]];
			}
		}
	}
	if (mode==4) {
		return [[[COPDFImage alloc] initWithPDFRep:pdfRep page:index] autorelease];
	} else if(mode==2) {
		NSString *rawName = [contentPathDic objectForKey:[contentPathArray objectAtIndex:index]];
		NSArray*    items=[archiveContainer contents];
		
		NSData *data = nil;
		NSImage *image = nil;
		if ([rawContentPathArray indexOfObject:rawName] != NSNotFound) {
			data =[[items objectAtIndex:[rawContentPathArray indexOfObject:rawName]] data];
		}
		
		if(data && [data length]>0){
			image = [[[NSImage allocWithZone:NULL] initWithData:data] autorelease];	
			if(image && [image isValid] && [image representations]) {
				return image;
			}
		}
	} else {
		NSImage *image = [[[NSImage allocWithZone:NULL] initWithContentsOfFile:[contentPathArray objectAtIndex:index]] autorelease];
		if(image && [image isValid] && [image representations]){
			return image;
		}
	}
	return [NSImage imageNamed:@"broken"];
	return nil;
}

#pragma mark -
- (int)nextFolder:(int)now
{
	int i = now-1;
	//NSLog(@"next startAt  %@",[contentPathArray objectAtIndex:now-1]);
	NSString *currentFolder = [[contentPathArray objectAtIndex:i] stringByDeletingLastPathComponent];
	for (i+=1;i<[contentPathArray count];i++) {
		NSString *nextFolder = [[contentPathArray objectAtIndex:i] stringByDeletingLastPathComponent];
		//NSLog(@"%@",[contentPathArray objectAtIndex:i]);
		if (![currentFolder isEqualToString:nextFolder]) {
			//NSLog(@"found1");
			return i;
		}
	}
	for (i=0;i<[contentPathArray count];i++) {
		if (i==now-1) {
			//NSLog(@"notFound");
			return 0;
		}
		NSString *nextFolder = [[contentPathArray objectAtIndex:i] stringByDeletingLastPathComponent];
		//NSLog(@"%@",[contentPathArray objectAtIndex:i]);
		if (![currentFolder isEqualToString:nextFolder]) {
			//NSLog(@"found2");
			return i;
		}
	}
	return 0;
	//NSLog(@"next end");
}
- (int)prevFolder:(int)now
{
	//NSLog(@"prev startAt %@",[contentPathArray objectAtIndex:now-1]);
	NSString *currentFolder = [[contentPathArray objectAtIndex:now-1] stringByDeletingLastPathComponent];
	if (now-2>0 && [currentFolder isEqualToString:[[contentPathArray objectAtIndex:now-2] stringByDeletingLastPathComponent]]) {
		//1つ前も同じフォルダだったらこのフォルダの先頭を検索
		NSString *prevFolder;
		int i = now-1;
		for (i;i>=0;i--) {
			if (i == 0) return 0;
			prevFolder = [[contentPathArray objectAtIndex:i] stringByDeletingLastPathComponent];
			if (![currentFolder isEqualToString:prevFolder]) {
				return i+1;
			}
		}
	} else {
		//1つ前が違うフォルダだったらそっちの先頭を検索
		NSString *prevFolder,*prevFolderHead;
		int i = now-1;
		for (i;i>=0;i--) {
			prevFolder = [[contentPathArray objectAtIndex:i] stringByDeletingLastPathComponent];
			//NSLog(@"%@ %i",[contentPathArray objectAtIndex:i],i);
			if (![currentFolder isEqualToString:prevFolder]) {
				int ii;
				for (ii=i;ii>=0;ii--) {
					if (ii == 0) return 0;
					prevFolderHead = [[contentPathArray objectAtIndex:ii] stringByDeletingLastPathComponent];
					//NSLog(@"%@",[contentPathArray objectAtIndex:ii]);
					if (![prevFolder isEqualToString:prevFolderHead]) {
						//NSLog(@"found1 %i",ii+1);
						return ii+1;
					}
				}
			}
		}
		i=(int)[contentPathArray count]-1;
		for (i;i>=0;i--) {
			if (i==now) {
				//NSLog(@"notFound");
				return now-1;
			}
			prevFolder = [[contentPathArray objectAtIndex:i] stringByDeletingLastPathComponent];
			//NSLog(@"%@",[contentPathArray objectAtIndex:i]);
			if (![currentFolder isEqualToString:prevFolder]) {
				int ii;
				for (ii=i;ii>=0;ii--) {
					if (ii == 0) return 0;
					prevFolderHead = [[contentPathArray objectAtIndex:ii] stringByDeletingLastPathComponent];
					if (![prevFolder isEqualToString:prevFolderHead]) {
						//NSLog(@"found2 %i",ii+1);
						return ii+1;
					}
				}
			}
		}
	}
	//NSLog(@"prev end");
	return now-1;
}
#pragma mark -

- (BOOL)isInTempDir
{
	if (inTempDir) return YES;
	return NO;
}

- (NSString *)password
{
	return password;
}

- (BOOL)needsPassword
{
	return needsPassword;
}

/* One attempt from the host's sheet (KNOWN_ISSUES #33). On success this
 * finishes the work -content would have done had the password been known at
 * init time: the container re-scans itself, the entries are enumerated by
 * -checkArchiveContainer:, and the placeholder page that every failed open
 * gets is dropped. On a wrong password nothing changes, so the host can
 * simply ask again. */
- (COArchiveCryptoStatus)tryPassword:(NSString *)entered
{
	if (!needsPassword || entered == nil) {
		return COArchiveCryptoWrongPassword;
	}

	[archiveContainer setPassword:entered];
	COArchiveCryptoStatus status = [archiveContainer cryptoStatus];
	if (status != COArchiveCryptoOK) {
		/* Anything other than "try again" leaves the archive unopenable; the
		 * host stops asking and the loader stays in its failed state. */
		if (status != COArchiveCryptoWrongPassword) {
			needsPassword = NO;
		}
		return status;
	}

	NSString *old = password;
	password = [entered copy];
	[old release];
	needsPassword = NO;

	/* -checkArchiveContainer: empties the three content collections itself, so
	 * the placeholder inserted by the initializer goes with them. mode is put
	 * back to the archive mode -content had set before the open failed. */
	mode = 2;
	if (![self checkArchiveContainer:0]) {
		mode = -1;
	}
	if ([self itemCount] == 0) {
		[contentPathArray addObject:[[NSBundle mainBundle] pathForResource:@"empty" ofType:@"png"]];
		mode = -1;
	}
	return COArchiveCryptoOK;
}

- (void)setInTempDir:(BOOL)b
{
	inTempDir = b;
}
@end

@implementation COImageLoader(private)
- (void)content
{
	if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) return;
	
	NSMutableArray *pathArray = [NSMutableArray array];
	if ([[filePath pathExtension] compare:@"pdf" options:NSCaseInsensitiveSearch] == NSOrderedSame) {
		mode=4;
		pdfRep = [(COPDFImageRep *)[COPDFImageRep imageRepWithContentsOfFile:filePath] retain];
		int pages = (int)[pdfRep pageCount];
		
		int i;
		for (i=0;pages>i;i++) {
			[contentPathArray addObject:[NSString stringWithFormat:@"%@/%i.pdf",filePath,i+1]];
		}
		return;
		
	} else if([[COImageLoader archiveTypes] containsObject:[[filePath pathExtension] lowercaseString]]) {
		mode=2;
		COArchiveProgress progress = ^BOOL(long long done, long long total) {
			if (controller && [controller respondsToSelector:@selector(archiveReadProgress:total:)])
				return [controller archiveReadProgress:done total:total];
			return YES;
		};
		/* The read is the expensive part of opening a book and the only
		 * part that reports progress. Since MW-1 the host runs it off the
		 * main thread behind a progress sheet (see
		 * -[BookWindowController runArchiveLoadNamed:usingBlock:]) so it can no
		 * longer freeze the UI or consume unrelated events. Hosts with no
		 * controller — the QuickLook and Thumbnail extensions — keep the
		 * plain synchronous read.
		 *
		 * Only the read moves. Everything after it, including
		 * -checkArchiveContainer: and its password prompt, still runs on
		 * the caller's (main) thread exactly as before. */
		__block COArchive *opened = nil;
		void (^readBlock)(void) = ^{
			opened = [[COArchive alloc] initWithPath:filePath progress:progress];
		};
		if (controller && [controller respondsToSelector:@selector(runArchiveLoadNamed:usingBlock:)]) {
			[controller runArchiveLoadNamed:[displayPath lastPathComponent]
			                     usingBlock:readBlock];
		} else {
			readBlock();
		}
		archiveContainer = opened;
		if (!archiveContainer || [archiveContainer cancelled]) {
			mode = -1;
			return;
		}
		if ([archiveContainer lastError])
			NSLog(@"COImageLoader: %@: %@", filePath, [archiveContainer lastError]);
		[self checkArchiveContainer:0];
		return;
		
	} else if([[filePath pathExtension] compare:@"savedSearch" options:NSCaseInsensitiveSearch] == NSOrderedSame){
		mode=-1;
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 1040
		if([NSObject respondsToSelector:@selector(finalize)]){
			mode=3;
			NSDictionary *doc = [NSDictionary dictionaryWithContentsOfFile:filePath];
			NSString *raw = [doc objectForKey:@"RawQuery"];
			NSArray *scope = [[doc objectForKey:@"SearchCriteria"] objectForKey:@"FXScopeArrayOfPaths"];
			
			MDQueryRef query = MDQueryCreate(kCFAllocatorDefault, (CFStringRef)raw, NULL, NULL);
			MDQuerySetSearchScope (query,(CFArrayRef)scope,0);
			
			MDQueryExecute(query, kMDQuerySynchronous);
			
			CFIndex count = MDQueryGetResultCount(query);
			int i;
			NSMutableArray *temp = [NSMutableArray array];
			for (i = 0; i < count; i++) {
				MDItemRef item = (MDItemRef)MDQueryGetResultAtIndex(query,i);
				CFStringRef itemPath = MDItemCopyAttribute(item,kMDItemPath);
				
				BOOL isDir;
				[[NSFileManager defaultManager] fileExistsAtPath:((NSString *) itemPath) isDirectory:&isDir];
				if (isDir && readSubFolder) {
					NSArray *ar = [[NSFileManager defaultManager] subpathsAtPath:((NSString *) itemPath)];
					int ii;
					for (ii=0; ii<[ar count]; ii++) {
						[temp addObject:[((NSString *) itemPath) stringByAppendingPathComponent:[ar objectAtIndex:ii]]];
					}
				} else {
					[temp addObject:((NSString *) itemPath)];
				} 
				CFRelease(itemPath);
			}
			CFRelease(query);
			NSArray *completeArray;
			completeArray = [temp pathsMatchingExtensions:filterArray];
			
			NSEnumerator *enu=[completeArray objectEnumerator];
			id path;
			while (path = [enu nextObject]) {
				if([[COImageLoader fileTypes] containsObject:[[path pathExtension] lowercaseString]]){
					COImageLoader *inLoader = [[[COImageLoader alloc] initWithPath:path readSubFolder:NO controller:controller] autorelease];
					[pathArray addObjectsFromArray:[inLoader pathArray]];
					[inArchiveArray addObject:inLoader];
				} else if (path) {
					[pathArray addObject:path];
				}
			}
			[contentPathArray addObjectsFromArray:pathArray];
		}
#endif
	} else {
		mode=0;
		BOOL isDir;
		[[NSFileManager defaultManager] fileExistsAtPath:filePath isDirectory:&isDir];
		if (isDir) {
			NSArray *completeArray;
			if (readSubFolder) {
				completeArray = [NSArray arrayWithArray:[[NSFileManager defaultManager] subpathsAtPath:filePath]];
			} else {
                completeArray = [NSArray arrayWithArray:[[NSFileManager defaultManager] contentsOfDirectoryAtPath:filePath error:nil]];
			}
			completeArray = [completeArray pathsMatchingExtensions:filterArray];
			
			NSEnumerator *enu=[completeArray objectEnumerator];
			id path;
			while (path = [enu nextObject]) {
				path = [filePath stringByAppendingPathComponent:path];
				if([[COImageLoader fileTypes] containsObject:[[path pathExtension] lowercaseString]]){
					COImageLoader *inLoader = [[[COImageLoader alloc] initWithPath:path readSubFolder:NO controller:controller] autorelease];
					[pathArray addObjectsFromArray:[inLoader pathArray]];
					[inArchiveArray addObject:inLoader];
				} else if (path) {
					[pathArray addObject:path];
				}
			}
			[contentPathArray addObjectsFromArray:pathArray];
		} else {
			mode=-1;
		}
	}
	[contentPathArray sortUsingSelector:@selector(finderCompareS:)];
}

/* Encrypted archive: try to make it readable.
 *
 * Returns YES once a password has been accepted (the container re-scanned
 * itself and its entries are now readable), NO when the archive stays
 * closed: an unsupported format (encrypted RAR — fails closed exactly as
 * before), a host that cannot ask (the QuickLook extensions never reach
 * here; they use COCoverExtractor, which has no controller), the host having
 * asked to drive the prompt itself (`deferPasswordPrompt`), or the user
 * cancelling.
 *
 * The retry loop always has an exit: Cancel makes the prompt return nil,
 * and any status other than WrongPassword also ends the loop. */
- (BOOL)unlockEncryptedArchive
{
	if (![archiveContainer respondsToSelector:@selector(cryptoStatus)])
		return NO;
	if ([archiveContainer cryptoStatus] != COArchiveCryptoNeedsPassword)
		return NO;	// Unsupported (encrypted RAR/7z): fail closed

	// a password already accepted for this loader (reopen/retry)
	if (password) {
		[archiveContainer setPassword:password];
		if ([archiveContainer cryptoStatus] == COArchiveCryptoOK)
			return YES;
	}

	/* KNOWN_ISSUES #33: the host wants to ask for the password itself, with a
	 * sheet that does not block its other windows. Report the need and stop —
	 * -tryPassword: is how the answers come back. */
	if (deferPasswordPrompt) {
		needsPassword = YES;
		return NO;
	}

	if (!controller ||
	    ![controller respondsToSelector:@selector(askArchivePassword:wrongPassword:)])
		return NO;	// non-interactive host

	BOOL previousWasWrong = NO;
	for (;;) {
		NSString *entered = [controller askArchivePassword:self
		                                    wrongPassword:previousWasWrong];
		if (entered == nil)
			return NO;				// cancelled
		[archiveContainer setPassword:entered];
		COArchiveCryptoStatus status = [archiveContainer cryptoStatus];
		if (status == COArchiveCryptoOK) {
			NSString *old = password;
			password = [entered copy];
			[old release];
			return YES;
		}
		if (status != COArchiveCryptoWrongPassword)
			return NO;				// not a password problem
		previousWasWrong = YES;
	}
}

- (BOOL)checkArchiveContainer:(int)index
{
	if ([archiveContainer crypted] && [[archiveContainer contents] count] == 0) {
		// Encrypted archive. ZIP can be unlocked by asking the user for a
		// password (v1.5.0 restores what v1.4.0 dropped); every other
		// format reports Unsupported and fails closed exactly as before,
		// as does a cancelled prompt.
		if (![self unlockEncryptedArchive]) {
			mode = -1;
			return NO;
		}
	}
	if ([[archiveContainer contents] count] == 0) {
        return NO;
	}

	[rawContentPathArray removeAllObjects];
	[contentPathArray removeAllObjects];
	[contentPathDic removeAllObjects];

	NSMutableArray *pathArray = [NSMutableArray array];
	NSArray *items=[archiveContainer contents];
	NSEnumerator *enu = [items objectEnumerator];
	id object;
	while (object = [enu nextObject]) {
		NSString *path = [object path];
		if (path) {
			[rawContentPathArray addObject:path];
			if([[COImageLoader fileTypes] containsObject:[[path pathExtension] lowercaseString]]){
				if (![self uncompressToTempDir:path]) {
					return NO;
				}
				COImageLoader *inLoader = [[[COImageLoader alloc] initWithPath:[tempDir stringByAppendingPathComponent:path]
																   displayPath:[displayPath stringByAppendingPathComponent:path]
																 readSubFolder:NO
																	controller:controller] autorelease];
				[inLoader setInTempDir:YES];
				[pathArray addObjectsFromArray:[inLoader pathArray]];
				[inArchiveArray addObject:inLoader];
			} else {
				NSString *inPath = [NSString stringWithFormat:@"%@/%@",displayPath,path];
				[pathArray addObject:inPath];
				[contentPathDic setObject:path forKey:inPath];
			}
		}
	}

	[contentPathArray addObjectsFromArray:[pathArray pathsMatchingExtensions:filterArray]];
	[contentPathArray sortUsingSelector:@selector(finderCompareS:)];
	//NSLog(@"%@",contentPathDic);
	return YES;
}

- (void)createDir:(NSString*)dir
{
	NSFileManager *manager = [NSFileManager defaultManager];
	if (![manager fileExistsAtPath:dir]) {
		if (![manager fileExistsAtPath:[dir stringByDeletingLastPathComponent]]) {
			[self createDir:[dir stringByDeletingLastPathComponent]];
		}
        [manager createDirectoryAtPath:dir withIntermediateDirectories:NO attributes:nil error:nil];
	}
}

- (BOOL)uncompressToTempDir:(NSString*)fileName
{
	if (!tempDir) {
        const char *buffer = [[NSString stringWithFormat:@"%@/%@",NSTemporaryDirectory(),@"cooViewer.XXXXXX"] fileSystemRepresentation];
        mkdtemp((char *)buffer);
        tempDir = [[NSString stringWithFormat:@"%s", buffer] retain];
	}
	
	if ([rawContentPathArray indexOfObject:fileName] != NSNotFound) {
		[self createDir:[[tempDir stringByAppendingPathComponent:fileName] stringByDeletingLastPathComponent]];
		
		if (mode == 2) {
			return [archiveContainer uncompress:(int)[rawContentPathArray indexOfObject:fileName] as:[tempDir stringByAppendingPathComponent:fileName]];
		}
	} else {
		//NSLog(@"notFound");
	}
	return YES;
}
@end
