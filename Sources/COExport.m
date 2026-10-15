//
//  COExport.m
//  cooViewer
//

#import "COExport.h"
#import "COArchive.h"	/* the reader methods, sent to `id` archives */
#import "NSString_Compare.h"
#include <zip.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#pragma mark COExportPage

@implementation COExportPage

/* The last path component, or "page" when that is not a usable name. */
static NSString *COExportFlattenedName(NSString *name)
{
	NSString *last = [[name stringByReplacingOccurrencesOfString:@"\\" withString:@"/"] lastPathComponent];
	if ([last length] == 0 || [last isEqualToString:@"."] || [last isEqualToString:@".."]
		|| [last isEqualToString:@"/"]) {
		return @"page";
	}
	return last;
}

+ (COExportPage *)pageWithFilePath:(NSString *)path
{
	COExportPage *page = [[[COExportPage alloc] init] autorelease];
	page->filePath = [path copy];
	page->name = [COExportFlattenedName(path) copy];
	return page;
}

+ (COExportPage *)pageWithEntry:(id)anEntry name:(NSString *)aName
                        archive:(id)anArchive order:(NSUInteger)anOrder
{
	COExportPage *page = [[[COExportPage alloc] init] autorelease];
	page->entry = [anEntry retain];
	page->archive = [anArchive retain];
	page->order = anOrder;
	page->name = [COExportFlattenedName(aName) copy];
	return page;
}

- (void)dealloc
{
	[name release];
	[filePath release];
	[entry release];
	[archive release];
	[super dealloc];
}

- (NSString *)name { return name; }
- (NSString *)filePath { return filePath; }
- (id)entry { return entry; }
- (id)archive { return archive; }
- (NSUInteger)order { return order; }

- (NSData *)readData
{
	if (filePath) {
		return [NSData dataWithContentsOfFile:filePath options:NSDataReadingMappedIfSafe error:NULL];
	}
	if ([entry respondsToSelector:@selector(data)]) {
		return [entry data];
	}
	return nil;
}

- (NSDate *)modificationDate
{
	if (filePath) {
		return [[[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:NULL] fileModificationDate];
	}
	if ([entry respondsToSelector:@selector(modificationDate)]) {
		id date = [entry modificationDate];
		return [date isKindOfClass:[NSDate class]] ? date : nil;
	}
	return nil;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<COExportPage %@ %@>", name, filePath ? filePath : @"(entry)"];
}
@end

#pragma mark page list

/* A run of ASCII digits; values past a billion are clamped there, which is
   past any book and so refused as out of range. */
static BOOL COExportScanNumber(NSString *s, NSUInteger *outValue)
{
	NSUInteger i, length = [s length];
	if (length == 0) return NO;
	unsigned long long value = 0;
	for (i = 0; i < length; i++) {
		unichar c = [s characterAtIndex:i];
		if (c < '0' || c > '9') return NO;
		if (value < 1000000000ULL) value = value * 10 + (c - '0');
	}
	*outValue = (NSUInteger)(value > 1000000000ULL ? 1000000000ULL : value);
	return YES;
}

NSString *COExportNormalizedPageList(NSString *text)
{
	if (!text) return @"";
	NSArray *parts = [text componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	return [parts componentsJoinedByString:@""];
}

NSIndexSet *COExportParsePageList(NSString *text, NSUInteger pageCount,
                                  COExportPageListError *error, NSString **badToken)
{
	COExportPageListError dummy;
	if (!error) error = &dummy;
	*error = COExportPageListOK;
	if (badToken) *badToken = nil;

	if (pageCount == 0) {
		*error = COExportPageListEmpty;
		return nil;
	}
	NSString *list = COExportNormalizedPageList(text);
	if ([list length] == 0) {
		return [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, pageCount)];
	}

	NSMutableIndexSet *result = [NSMutableIndexSet indexSet];
	for (NSString *token in [list componentsSeparatedByString:@","]) {
		NSArray *ends = [token componentsSeparatedByString:@"-"];
		NSUInteger first = 0, last = 0;
		if ([ends count] == 1) {
			if (!COExportScanNumber(token, &first)) goto syntax;
			last = first;
		} else if ([ends count] == 2) {
			if (!COExportScanNumber([ends objectAtIndex:0], &first)
				|| !COExportScanNumber([ends objectAtIndex:1], &last)) goto syntax;
		} else {
			goto syntax;
		}
		if (first < 1 || last < 1 || first > pageCount || last > pageCount) {
			*error = COExportPageListOutOfRange;
			if (badToken) *badToken = token;
			return nil;
		}
		if (first > last) {
			*error = COExportPageListReversed;
			if (badToken) *badToken = token;
			return nil;
		}
		[result addIndexesInRange:NSMakeRange(first - 1, last - first + 1)];
		continue;
	syntax:
		*error = COExportPageListSyntax;
		if (badToken) *badToken = token;
		return nil;
	}
	if ([result count] == 0) {
		*error = COExportPageListEmpty;
		return nil;
	}
	return result;
}

#pragma mark names

NSString *COExportSanitizedFileName(NSString *name)
{
	if (!name) return @"";
	NSMutableString *out = [NSMutableString stringWithCapacity:[name length]];
	NSCharacterSet *unsafe = [NSCharacterSet characterSetWithCharactersInString:@"/:\\,*?\"<>|"];
	NSCharacterSet *control = [NSCharacterSet controlCharacterSet];
	NSUInteger i;
	for (i = 0; i < [name length]; i++) {
		unichar c = [name characterAtIndex:i];
		if ([unsafe characterIsMember:c] || [control characterIsMember:c]) {
			[out appendString:@"_"];
		} else {
			[out appendFormat:@"%C", c];
		}
	}
	if ([out hasPrefix:@"."]) {
		[out replaceCharactersInRange:NSMakeRange(0, 1) withString:@"_"];
	}
	return out;
}

NSString *COExportDefaultFileName(NSString *bookName, NSString *pagesText)
{
	NSString *book = COExportSanitizedFileName(bookName ? bookName : @"");
	if ([book length] == 0) book = @"book";
	NSString *pages = COExportNormalizedPageList(pagesText);
	if ([pages length] == 0) {
		return [NSString stringWithFormat:@"%@-export.cbz", book];
	}
	return [NSString stringWithFormat:@"%@-export-%@.cbz", book, COExportSanitizedFileName(pages)];
}

static NSArray *COExportFlattenedNames(NSArray *originalNames)
{
	NSMutableArray *names = [NSMutableArray arrayWithCapacity:[originalNames count]];
	for (NSString *name in originalNames) {
		[names addObject:COExportFlattenedName(name)];
	}
	return names;
}

BOOL COExportNamesNeedSequencePrefix(NSArray *originalNames)
{
	NSArray *names = COExportFlattenedNames(originalNames);
	NSMutableSet *seen = [NSMutableSet setWithCapacity:[names count]];
	NSUInteger i;
	for (i = 0; i < [names count]; i++) {
		NSString *name = [names objectAtIndex:i];
		/* Same name ignoring case (and composition): such entries would
		   overwrite each other when extracted to a Mac's file system. */
		NSString *key = [[name precomposedStringWithCanonicalMapping] lowercaseString];
		if ([seen containsObject:key]) return YES;
		[seen addObject:key];
		if (i == 0) continue;
		NSString *previous = [names objectAtIndex:i - 1];
		/* finderCompareS: passes on UCCompareText's result, which is any
		   negative number for "before", not only NSOrderedAscending. */
		if ((long)[previous finderCompareS:name] >= 0) return YES;
		if (strcmp([previous UTF8String], [name UTF8String]) >= 0) return YES;
	}
	return NO;
}

NSArray *COExportEntryNames(NSArray *originalNames)
{
	NSArray *names = COExportFlattenedNames(originalNames);
	if (!COExportNamesNeedSequencePrefix(originalNames)) return names;

	int width = 4;
	NSUInteger limit = 10000;
	while ([names count] >= limit && width < 19) {
		width++;
		limit *= 10;
	}
	NSMutableArray *prefixed = [NSMutableArray arrayWithCapacity:[names count]];
	NSUInteger i;
	for (i = 0; i < [names count]; i++) {
		[prefixed addObject:[NSString stringWithFormat:@"%0*lu_%@", width,
							 (unsigned long)(i + 1), [names objectAtIndex:i]]];
	}
	return prefixed;
}

#pragma mark writing

typedef struct {
	BOOL (^cancelled)(void);
	void (^progress)(double);
} COExportZipCallbacks;

static int COExportZipCancel(zip_t *za, void *ud)
{
	(void)za;
	COExportZipCallbacks *callbacks = ud;
	return (callbacks->cancelled && callbacks->cancelled()) ? 1 : 0;
}

static void COExportZipProgress(zip_t *za, double fraction, void *ud)
{
	(void)za;
	COExportZipCallbacks *callbacks = ud;
	if (callbacks->progress) callbacks->progress(fraction);
}

static BOOL COExportWriteStoredZipWithProgress(NSString *zipPath, NSArray *names, NSArray *contents,
                                               NSArray *dates,
                                               BOOL (^cancelled)(void), void (^progress)(double),
                                               NSString **errorMessage)
{
	if (errorMessage) *errorMessage = nil;
	if ([names count] != [contents count] || [names count] == 0
		|| (dates && [dates count] != [names count])) {
		if (errorMessage) *errorMessage = @"nothing to write";
		return NO;
	}

	int zerr = 0;
	zip_t *za = zip_open([zipPath fileSystemRepresentation], ZIP_CREATE | ZIP_EXCL, &zerr);
	if (!za) {
		if (errorMessage) {
			zip_error_t error;
			zip_error_init_with_code(&error, zerr);
			*errorMessage = [NSString stringWithFormat:@"cannot create the archive: %s", zip_error_strerror(&error)];
			zip_error_fini(&error);
		}
		return NO;
	}

	COExportZipCallbacks callbacks = { cancelled, progress };
	zip_register_cancel_callback_with_state(za, COExportZipCancel, NULL, &callbacks);
	if (progress) zip_register_progress_callback_with_state(za, 0.01, COExportZipProgress, NULL, &callbacks);

	NSUInteger i;
	for (i = 0; i < [names count]; i++) {
		id content = [contents objectAtIndex:i];
		zip_source_t *source = NULL;
		if ([content isKindOfClass:[NSData class]]) {
			/* `contents` keeps the data alive until zip_close(). */
			source = zip_source_buffer(za, [content bytes], [content length], 0);
		} else if ([content isKindOfClass:[NSString class]]) {
			source = zip_source_file(za, [content fileSystemRepresentation], 0, ZIP_LENGTH_TO_END);
		}
		if (!source) goto failed;
		zip_int64_t index = zip_file_add(za, [[names objectAtIndex:i] UTF8String], source, ZIP_FL_ENC_UTF_8);
		if (index < 0) {
			zip_source_free(source);
			goto failed;
		}
		if (zip_set_file_compression(za, (zip_uint64_t)index, ZIP_CM_STORE, 0) < 0) goto failed;
		/* The original's time; without one libzip uses the source's (a
		   staged file's is the time it was staged). */
		id date = dates ? [dates objectAtIndex:i] : nil;
		if ([date isKindOfClass:[NSDate class]]) {
			time_t mtime = (time_t)floor([date timeIntervalSince1970]);
			if (zip_file_set_mtime(za, (zip_uint64_t)index, mtime, 0) < 0) goto failed;
		}
	}

	if (zip_close(za) == 0) {
		return YES;
	}
	if (cancelled && cancelled()) {
		zip_discard(za);
		[[NSFileManager defaultManager] removeItemAtPath:zipPath error:NULL];
		return NO;
	}
failed:
	if (errorMessage) *errorMessage = [NSString stringWithUTF8String:zip_strerror(za)];
	zip_discard(za);
	[[NSFileManager defaultManager] removeItemAtPath:zipPath error:NULL];
	return NO;
}

BOOL COExportWriteStoredZip(NSString *zipPath, NSArray *names, NSArray *contents,
                            BOOL (^cancelled)(void), NSString **errorMessage)
{
	return COExportWriteStoredZipWithProgress(zipPath, names, contents, nil, cancelled, nil, errorMessage);
}

BOOL COExportWriteStoredZipWithDates(NSString *zipPath, NSArray *names, NSArray *contents,
                                     NSArray *dates, BOOL (^cancelled)(void),
                                     NSString **errorMessage)
{
	return COExportWriteStoredZipWithProgress(zipPath, names, contents, dates, cancelled, nil, errorMessage);
}

/* A new directory for staging, on the destination's volume: the system's
   replacement directory for it, or failing that a hidden one beside it. */
static NSString *COExportCreateStagingDirectory(NSURL *destination)
{
	NSFileManager *fm = [NSFileManager defaultManager];
	NSURL *dir = [fm URLForDirectory:NSItemReplacementDirectory inDomain:NSUserDomainMask
	               appropriateForURL:destination create:YES error:NULL];
	if (dir && [fm isWritableFileAtPath:[dir path]]) {
		return [dir path];
	}
	if (dir) [fm removeItemAtURL:dir error:NULL];

	NSString *parent = [[destination path] stringByDeletingLastPathComponent];
	NSString *template = [parent stringByAppendingPathComponent:@".cooViewer-export.XXXXXX"];
	char buffer[PATH_MAX];
	if (![template getFileSystemRepresentation:buffer maxLength:sizeof(buffer)] || mkdtemp(buffer) == NULL) {
		return nil;
	}
	return [fm stringWithFileSystemRepresentation:buffer length:strlen(buffer)];
}

COExportResult COExportPages(NSArray *pages, NSURL *destination,
                             BOOL (^cancelled)(void),
                             void (^progress)(double fraction),
                             NSUInteger *failedPage, NSString **errorMessage)
{
	if (errorMessage) *errorMessage = nil;
	if (failedPage) *failedPage = NSNotFound;
	if ([pages count] == 0 || !destination) {
		if (errorMessage) *errorMessage = @"nothing to export";
		return COExportWriteFailed;
	}

	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *staging = COExportCreateStagingDirectory(destination);
	if (!staging) {
		if (errorMessage) *errorMessage = @"cannot create a staging directory";
		return COExportWriteFailed;
	}

	COExportResult result = COExportWriteFailed;
	NSUInteger count = [pages count];
	NSMutableArray *contents = [NSMutableArray arrayWithCapacity:count];
	NSMutableArray *originalNames = [NSMutableArray arrayWithCapacity:count];
	NSMutableArray *dates = [NSMutableArray arrayWithCapacity:count];
	NSUInteger i;
	for (i = 0; i < count; i++) {
		COExportPage *page = [pages objectAtIndex:i];
		[originalNames addObject:[page name]];
		NSDate *date = [page modificationDate];
		[dates addObject:date ? (id)date : (id)[NSNull null]];
		/* A file is copied straight from where it is; an entry is staged. */
		[contents addObject:[page filePath] ? (id)[page filePath] : (id)[NSNull null]];
	}

	/* Read order: the entries of each archive together, archives in the
	   order their first page comes, and each archive's entries in its own
	   entry order — stream order for a solid RAR, whose cursor only goes
	   forward. Then they are added to the ZIP in page order. */
	NSMutableArray *archives = [NSMutableArray array];
	NSMutableArray *readOrder = [NSMutableArray array];
	for (i = 0; i < count; i++) {
		COExportPage *page = [pages objectAtIndex:i];
		if ([page filePath]) continue;
		[readOrder addObject:[NSNumber numberWithUnsignedInteger:i]];
		if ([archives indexOfObjectIdenticalTo:[page archive]] == NSNotFound) {
			[archives addObject:[page archive] ? [page archive] : [NSNull null]];
		}
	}
	[readOrder sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(id a, id b) {
		COExportPage *pa = [pages objectAtIndex:[a unsignedIntegerValue]];
		COExportPage *pb = [pages objectAtIndex:[b unsignedIntegerValue]];
		id archiveA = [pa archive] ? [pa archive] : [NSNull null];
		id archiveB = [pb archive] ? [pb archive] : [NSNull null];
		NSUInteger ga = [archives indexOfObjectIdenticalTo:archiveA];
		NSUInteger gb = [archives indexOfObjectIdenticalTo:archiveB];
		if (ga != gb) return ga < gb ? NSOrderedAscending : NSOrderedDescending;
		if ([pa order] != [pb order]) return [pa order] < [pb order] ? NSOrderedAscending : NSOrderedDescending;
		return NSOrderedSame;
	}];

	/* Each archive is read through a second reader of its file when it has
	   one (a RAR): its own cursor, no prefetch, so the export neither waits
	   behind the viewer's reads nor moves the viewer's solid-RAR cursor,
	   and a cancel stops it part-way through a read. Opened lazily, on
	   this thread; released before returning. */
	NSMutableArray *readers = [NSMutableArray arrayWithCapacity:[archives count]];
	for (i = 0; i < [archives count]; i++) [readers addObject:[NSNull null]];
	NSMutableIndexSet *readersOpened = [NSMutableIndexSet indexSet];

	NSUInteger staged = 0;
	NSUInteger toStage = [readOrder count];
	double stageWeight = toStage > 0 ? 0.5 : 0.0;
	for (NSNumber *number in readOrder) {
		if (cancelled && cancelled()) {
			result = COExportCancelled;
			goto done;
		}
		NSUInteger pageIndex = [number unsignedIntegerValue];
		COExportResult step = COExportOK;
		NSString *stepError = nil;
		@autoreleasepool {
			COExportPage *page = [pages objectAtIndex:pageIndex];
			id archive = [page archive] ? [page archive] : [NSNull null];
			NSUInteger group = [archives indexOfObjectIdenticalTo:archive];
			id reader = archive;
			if (group != NSNotFound) {
				if (![readersOpened containsIndex:group]) {
					[readersOpened addIndex:group];
					if ([archive respondsToSelector:@selector(newIndependentReaderWithCancel:)]) {
						id own = [archive newIndependentReaderWithCancel:cancelled];
						if (own) {
							[readers replaceObjectAtIndex:group withObject:own];
							[own release];
						}
					}
				}
				if ([readers objectAtIndex:group] != [NSNull null]) reader = [readers objectAtIndex:group];
			}
			NSData *data;
			if ([page entry] && [reader respondsToSelector:@selector(dataForEntryAtIndex:cancelled:)]) {
				data = [reader dataForEntryAtIndex:[page order] cancelled:cancelled];
			} else {
				data = [page readData];
			}
			if (!data && cancelled && cancelled()) {
				step = COExportCancelled;
			} else
			if (!data) {
				step = COExportReadFailed;
			} else {
				NSString *stagedPath = [staging stringByAppendingPathComponent:
					[NSString stringWithFormat:@"%06lu.page", (unsigned long)pageIndex]];
				NSError *error = nil;
				if ([data writeToFile:stagedPath options:0 error:&error]) {
					[contents replaceObjectAtIndex:pageIndex withObject:stagedPath];
				} else {
					step = COExportWriteFailed;
					stepError = [[error localizedDescription] retain];
				}
			}
		}
		if (step != COExportOK) {
			if (step == COExportReadFailed && failedPage) *failedPage = pageIndex;
			if (errorMessage) *errorMessage = [[stepError retain] autorelease];
			[stepError release];
			result = step;
			goto done;
		}
		staged++;
		if (progress) progress(stageWeight * (double)staged / (double)toStage);
	}
	if (cancelled && cancelled()) {
		result = COExportCancelled;
		goto done;
	}

	{
		NSString *zipPath = [staging stringByAppendingPathComponent:@"export.cbz"];
		NSString *zipError = nil;
		void (^zipProgress)(double) = nil;
		if (progress) {
			zipProgress = ^(double fraction) {
				progress(stageWeight + (1.0 - stageWeight) * fraction);
			};
		}
		if (!COExportWriteStoredZipWithProgress(zipPath, COExportEntryNames(originalNames), contents,
		                                        dates, cancelled, zipProgress, &zipError)) {
			if (cancelled && cancelled()) {
				result = COExportCancelled;
			} else {
				if (errorMessage) *errorMessage = zipError;
				result = COExportWriteFailed;
			}
			goto done;
		}
		/* Past the last point a cancel is honoured: the file is complete. */
		NSURL *zipURL = [NSURL fileURLWithPath:zipPath];
		NSError *error = nil;
		BOOL moved;
		if ([fm fileExistsAtPath:[destination path]]) {
			moved = [fm replaceItemAtURL:destination withItemAtURL:zipURL backupItemName:nil
			                     options:0 resultingItemURL:NULL error:&error];
		} else {
			moved = [fm moveItemAtURL:zipURL toURL:destination error:&error];
		}
		if (!moved) {
			if (errorMessage) *errorMessage = [error localizedDescription];
			result = COExportWriteFailed;
			goto done;
		}
		result = COExportOK;
	}

done:
	[fm removeItemAtPath:staging error:NULL];
	return result;
}
