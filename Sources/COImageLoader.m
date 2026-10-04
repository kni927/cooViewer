#import "COArchive.h"
#import "BookWindowController.h"
#import "COImageLoader.h"

@interface COImageLoader(private)
-(void)content;
-(COArchive *)newArchiveContainer;
-(void)finishArchiveOpen;
-(BOOL)checkArchiveContainer:(int)index;
-(NSString *)uncompressEntry:(NSUInteger)index named:(NSString *)fileName duplicate:(BOOL)duplicate;
-(NSString *)temporaryDirectory;
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
	return [self initWithPath:path displayPath:dispPath readSubFolder:boo controller:ctr
		  deferPasswordPrompt:defer deferArchiveRead:NO];
}

- (id)initWithPath:(NSString *)path displayPath:(NSString *)dispPath readSubFolder:(BOOL)boo controller:(id)ctr deferPasswordPrompt:(BOOL)defer deferArchiveRead:(BOOL)deferRead
{

	self = [super init];
    if (self) {
		controller = ctr;
		deferPasswordPrompt = defer;
		needsPassword = NO;
		deferArchiveRead = deferRead;
		needsArchiveRead = NO;
		atomic_store(&archiveReadCancelled, 0);
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
		entryIndicesByRawName = [[NSMutableDictionary alloc] init];
		duplicatePagePaths = nil;
		rawContentPathArray = [[NSMutableArray alloc] init];
		pdfRep = nil;
		
		[self content];
	}
	/* A book with nothing in it to list keeps an empty page list; it used
	   to get Resources/empty.png as a stand-in page, so it opened as a
	   one-page book. -pagesStatus says why it is empty (KNOWN_ISSUES #30). */
    return self;
}

- (id)initWithPath:(NSString *)path readSubFolder:(BOOL)boo controller:(id)ctr;
{
	return [self initWithPath:path displayPath:path readSubFolder:boo controller:ctr];
}

- (void)dealloc
{
	/* B3: the decode-ahead pass and its writes end, and its files go, before
	   the directory they are in is removed. */
	[archiveContainer stopDecodeAhead];
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
	[entryIndicesByRawName release];
	[duplicatePagePaths release];
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

/* How many pages before `index` have the same path: 0 unless the path is
   one of an archive's repeated entry names (code review L4). */
- (NSUInteger)occurrenceOfPageAtIndex:(int)index
{
	NSString *page = [contentPathArray objectAtIndex:index];
	if (![duplicatePagePaths containsObject:page]) return 0;
	NSUInteger occurrence = 0;
	int i;
	for (i = 0; i < index; i++) {
		if ([[contentPathArray objectAtIndex:i] isEqualToString:page]) occurrence++;
	}
	return occurrence;
}

- (id)itemAtIndex:(int)index
{
	NSUInteger occurrence = [self occurrenceOfPageAtIndex:index];
	if ([inArchiveArray count] > 0) {
		NSString *fileName = [contentPathArray objectAtIndex:index];
		int i;
		for (i=0; i<[inArchiveArray count]; i++) {
			COImageLoader *inLoader = [inArchiveArray objectAtIndex:i];
			NSArray *inPages = [inLoader pathArray];
			NSUInteger at = [inPages indexOfObject:fileName];
			while (at != NSNotFound) {
				if (occurrence == 0) return [inLoader itemAtIndex:(int)at];
				occurrence--;
				at = [inPages indexOfObject:fileName inRange:NSMakeRange(at + 1, [inPages count] - at - 1)];
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
		NSArray *sameName = rawName ? [entryIndicesByRawName objectForKey:rawName] : nil;
		if (occurrence < [sameName count]) {
			NSUInteger itemIndex = [[sameName objectAtIndex:occurrence] unsignedIntegerValue];
			if (itemIndex < [items count]) data = [[items objectAtIndex:itemIndex] data];
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

- (BOOL)isUnsupportedSolidRAR4
{
	return [archiveContainer refusedSolidRAR4];
}

- (COImageLoaderPagesStatus)pagesStatus
{
	if (mode < 0) return COImageLoaderNotOpened;
	if ([self itemCount] > 0) return COImageLoaderHasPages;
	if (mode == 2) {
		if ([archiveContainer crypted] &&
		    [archiveContainer cryptoStatus] == COArchiveCryptoUnsupported)
			return COImageLoaderEncryptionUnsupported;
		if (!archiveContainer ||
		    ([archiveContainer lastError] && [[archiveContainer contents] count] == 0))
			return COImageLoaderUnreadable;
	}
	if (mode == 4 && pdfRep == nil) return COImageLoaderUnreadable;
	return COImageLoaderNoImages;
}

/* One attempt from the host's sheet (KNOWN_ISSUES #33). On success this
 * finishes the work -content would have done had the password been known at
 * init time: the container re-scans itself and the entries are enumerated by
 * -checkArchiveContainer:. On a wrong password nothing changes, so the host
 * can simply ask again. */
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

	/* mode is put back to the archive mode -content had set before the open
	 * failed. An archive that turns out to hold no images keeps it, so the
	 * host reports it like any other book with no pages (KNOWN_ISSUES #30). */
	mode = 2;
	if (![self checkArchiveContainer:0]) {
		mode = -1;
	}
	return COArchiveCryptoOK;
}

- (void)setInTempDir:(BOOL)b
{
	inTempDir = b;
}

#pragma mark deferred archive read (KNOWN_ISSUES #33)

- (BOOL)needsArchiveRead
{
	return needsArchiveRead;
}

- (void)readArchive
{
	if (!needsArchiveRead || archiveContainer) return;
	/* A worker thread has no autorelease pool of its own to rely on for the
	   temporaries of a read that can hold the whole archive in memory. */
	@autoreleasepool {
		archiveContainer = [self newArchiveContainer];
	}
}

- (void)finishArchiveRead
{
	if (!needsArchiveRead) return;
	needsArchiveRead = NO;
	/* Back to the archive mode -content set before it deferred the read. */
	mode = 2;
	[self finishArchiveOpen];
	/* B3: a solid RAR book a window opens decodes ahead into this loader's
	   temporary directory (see COArchive.h). Nested archives, archives in a
	   folder or saved search, and the QuickLook extensions do not take this
	   path. */
	if (mode == 2 && [archiveContainer canDecodeAhead]) {
		NSString *dir = [self temporaryDirectory];
		if (dir) [archiveContainer setDecodeAheadDirectory:dir];
	}
}

- (void)cancelArchiveRead
{
	atomic_store(&archiveReadCancelled, 1);
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
		/* KNOWN_ISSUES #33: the host reads the archive itself, off the main
		 * thread and without a modal session (-readArchive, then
		 * -finishArchiveRead). Nothing has been read, so nothing is open. */
		if (deferArchiveRead) {
			needsArchiveRead = YES;
			mode = -1;
			return;
		}
		/* The read is the expensive part of opening a book and the only
		 * part that reports progress. Since MW-1 the host runs it off the
		 * main thread behind a progress sheet (see
		 * -[BookWindowController runArchiveLoadNamed:usingBlock:]) so it can no
		 * longer freeze the UI or consume unrelated events. Hosts with no
		 * controller — the QuickLook and Thumbnail extensions — keep the
		 * plain synchronous read. Since #33's loading half, the book a window
		 * opens takes the deferred path above instead; this one is left to
		 * nested archives and the archives inside a folder or saved search.
		 *
		 * Only the read moves. Everything after it, including
		 * -checkArchiveContainer: and its password prompt, still runs on
		 * the caller's (main) thread exactly as before. */
		__block COArchive *opened = nil;
		void (^readBlock)(void) = ^{
			opened = [self newArchiveContainer];
		};
		if (controller && [controller respondsToSelector:@selector(runArchiveLoadNamed:usingBlock:)]) {
			[controller runArchiveLoadNamed:[displayPath lastPathComponent]
			                     usingBlock:readBlock];
		} else {
			readBlock();
		}
		archiveContainer = opened;
		[self finishArchiveOpen];
		return;
		
	} else if([[filePath pathExtension] compare:@"savedSearch" options:NSCaseInsensitiveSearch] == NSOrderedSame){
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

/* The archive read itself, shared by the inline path in -content and the
 * deferred -readArchive. Returns a +1 COArchive (or nil). Reports progress to
 * the controller from whatever thread this runs on; this loader's own
 * -cancelArchiveRead stops it as well. */
- (COArchive *)newArchiveContainer
{
	COArchiveProgress progress = ^BOOL(long long done, long long total) {
		if (atomic_load(&archiveReadCancelled)) return NO;
		if (controller && [controller respondsToSelector:@selector(archiveReadProgress:total:)])
			return [controller archiveReadProgress:done total:total];
		return YES;
	};
	return [[COArchive alloc] initWithPath:filePath progress:progress];
}

/* What follows the read, on the main thread: `mode` is 2 on entry. */
- (void)finishArchiveOpen
{
	if (!archiveContainer || [archiveContainer cancelled] ||
	    [archiveContainer refusedSolidRAR4]) {
		mode = -1;
		return;
	}
	if ([archiveContainer lastError])
		NSLog(@"COImageLoader: %@: %@", filePath, [archiveContainer lastError]);
	[self checkArchiveContainer:0];
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
			/* A prompt that is pending, cancelled or cannot be shown ends
			   the open. An encryption the format cannot decrypt does not:
			   the archive is simply one with no readable pages, and
			   -pagesStatus says why (KNOWN_ISSUES #30). */
			if ([archiveContainer cryptoStatus] != COArchiveCryptoUnsupported)
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
	[entryIndicesByRawName removeAllObjects];

	NSMutableArray *pathArray = [NSMutableArray array];
	NSArray *items=[archiveContainer contents];
	NSEnumerator *enu = [items objectEnumerator];
	id object;
	NSUInteger itemIndex = 0;
	while (object = [enu nextObject]) {
		NSUInteger thisIndex = itemIndex++;
		NSString *path = [object path];
		if (path) {
			[rawContentPathArray addObject:path];
			NSMutableArray *sameName = [entryIndicesByRawName objectForKey:path];
			BOOL repeatedName = (sameName != nil);
			if (!sameName) {
				sameName = [NSMutableArray array];
				[entryIndicesByRawName setObject:sameName forKey:path];
			}
			[sameName addObject:[NSNumber numberWithUnsignedInteger:thisIndex]];
			if([[COImageLoader fileTypes] containsObject:[[path pathExtension] lowercaseString]]){
				/* Nested archives are written to disk under their entry name;
				   one that would land outside tempDir is skipped. */
				if (!COIsContainedEntryPath(path)) continue;
				/* One nested archive that cannot be written out (a damaged
				   entry, a full disk) is skipped like an unreadable page;
				   it used to abandon every other page of the book (code
				   review L2). */
				NSString *extracted = [self uncompressEntry:thisIndex named:path duplicate:repeatedName];
				if (!extracted) {
					NSLog(@"COImageLoader: %@: skipping unreadable nested archive %@", filePath, path);
					continue;
				}
				COImageLoader *inLoader = [[[COImageLoader alloc] initWithPath:extracted
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

	NSCountedSet *pageCounts = [[[NSCountedSet alloc] initWithArray:contentPathArray] autorelease];
	NSMutableSet *repeated = [NSMutableSet set];
	for (NSString *page in pageCounts) {
		if ([pageCounts countForObject:page] > 1) [repeated addObject:page];
	}
	[duplicatePagePaths release];
	duplicatePagePaths = [repeated count] > 0 ? [repeated copy] : nil;

	/* B2: the archive's own pages in the order they are shown, so a lazy
	   reader prefetches the next page rather than the next entry in
	   archive order. Resolved the way -itemAtIndex: does (the n-th page of
	   a name is the n-th entry with that raw name); pages from nested
	   archives have no entry here. */
	NSMutableDictionary *usedByRawName = [NSMutableDictionary dictionary];
	NSMutableArray *pageOrder = [NSMutableArray array];
	for (NSString *page in contentPathArray) {
		NSString *rawName = [contentPathDic objectForKey:page];
		if (!rawName) continue;
		NSUInteger used = [[usedByRawName objectForKey:rawName] unsignedIntegerValue];
		[usedByRawName setObject:[NSNumber numberWithUnsignedInteger:used + 1] forKey:rawName];
		NSArray *sameName = [entryIndicesByRawName objectForKey:rawName];
		if (used < [sameName count]) {
			NSUInteger entryIndex = [[sameName objectAtIndex:used] unsignedIntegerValue];
			if (entryIndex < [items count]) [pageOrder addObject:[items objectAtIndex:entryIndex]];
		}
	}
	[archiveContainer setPrefetchPageOrder:pageOrder];
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

/* Writes archive entry `index` (a nested archive named `fileName`) under
   tempDir and returns the path written, or nil. A later entry with a name
   already used gets a directory of its own instead of overwriting the
   first one's file (code review L4). */
- (NSString *)uncompressEntry:(NSUInteger)index named:(NSString *)fileName duplicate:(BOOL)duplicate
{
	if (!COIsContainedEntryPath(fileName)) return nil;
	if (mode != 2) return nil;
	if (![self temporaryDirectory]) return nil;

	NSString *dir = duplicate
		? [tempDir stringByAppendingPathComponent:[NSString stringWithFormat:@".dup-%lu", (unsigned long)index]]
		: tempDir;
	NSString *dest = [dir stringByAppendingPathComponent:fileName];
	[self createDir:[dest stringByDeletingLastPathComponent]];
	return [archiveContainer uncompress:(int)index as:dest] ? dest : nil;
}

/* This loader's temporary directory (nested archives, B3's decode-ahead),
   created on first use; removed by dealloc. nil if it cannot be created. */
- (NSString *)temporaryDirectory
{
	if (!tempDir) {
		/* mkdtemp() rewrites its argument, so it needs a buffer of our own,
		   not -fileSystemRepresentation's. */
		char buffer[PATH_MAX];
		NSString *template = [NSTemporaryDirectory() stringByAppendingPathComponent:@"cooViewer.XXXXXX"];
		if (![template getFileSystemRepresentation:buffer maxLength:sizeof(buffer)] || mkdtemp(buffer) == NULL) {
			return nil;
		}
		tempDir = [[[NSFileManager defaultManager] stringWithFileSystemRepresentation:buffer length:strlen(buffer)] retain];
	}
	return tempDir;
}
@end
