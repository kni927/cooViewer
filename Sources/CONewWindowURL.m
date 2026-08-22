#import "CONewWindowURL.h"

NSString * const CooViewerNewWindowSchemeInfoKey = @"CooViewerNewWindowScheme";

NSURL *CooViewerNewWindowURLForFileURL(NSURL *fileURL, NSString *scheme)
{
	if (![fileURL isFileURL] || [scheme length] == 0) {
		return nil;
	}

	NSURLComponents *components = [[[NSURLComponents alloc] init] autorelease];
	[components setScheme:scheme];
	[components setHost:@"open"];
	NSURLQueryItem *item = [NSURLQueryItem queryItemWithName:@"url"
													value:[fileURL absoluteString]];
	[components setQueryItems:[NSArray arrayWithObject:item]];
	return [components URL];
}

NSURL *CooViewerFileURLFromNewWindowURL(NSURL *requestURL, NSString *scheme)
{
	if (!requestURL || [scheme length] == 0) {
		return nil;
	}

	NSURLComponents *components = [NSURLComponents componentsWithURL:requestURL
										 resolvingAgainstBaseURL:NO];
	if (![[[components scheme] lowercaseString] isEqualToString:[scheme lowercaseString]]
		|| ![[components host] isEqualToString:@"open"]
		|| [[components path] length] != 0
		|| [components user] || [components password] || [components port]
		|| [components fragment]) {
		return nil;
	}

	NSArray *items = [components queryItems];
	if ([items count] != 1 || ![[[items objectAtIndex:0] name] isEqualToString:@"url"]
		|| [[items objectAtIndex:0] value] == nil) {
		return nil;
	}

	NSURL *fileURL = [NSURL URLWithString:[[items objectAtIndex:0] value]];
	NSString *host = [fileURL host];
	if (![fileURL isFileURL]
		|| ([host length] > 0 && ![[host lowercaseString] isEqualToString:@"localhost"])) {
		return nil;
	}

	NSURL *standardizedURL = [fileURL URLByStandardizingPath];
	NSString *path = [standardizedURL path];
	if (![path isAbsolutePath]
		|| ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
		return nil;
	}
	return standardizedURL;
}
