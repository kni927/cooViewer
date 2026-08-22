#import <Foundation/Foundation.h>
#import <fcntl.h>
#import <unistd.h>

#import "CONewWindowURL.h"

static int failures = 0;
static int checks = 0;

static void check(BOOL condition, NSString *message)
{
	checks++;
	if (!condition) {
		failures++;
		NSLog(@"FAIL: %@", message);
	}
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSString *scheme = @"cooviewer-new-window-test";
	NSString *fixtureRoot = [[[NSProcessInfo processInfo] environment]
		objectForKey:@"COOVIEWER_TEST_TMPDIR"];
	if ([fixtureRoot length] == 0) {
		fixtureRoot = NSTemporaryDirectory();
	}
	NSString *directory = [fixtureRoot
		stringByAppendingPathComponent:@"cooViewer URL codec 日本語 #?%"];
	NSError *directoryError = nil;
	BOOL createdDirectory = [[NSFileManager defaultManager] createDirectoryAtPath:directory
									 withIntermediateDirectories:YES
												  attributes:nil
													   error:&directoryError];
	check(createdDirectory, [NSString stringWithFormat:@"creates fixture directory: %@", directoryError]);
	NSString *path = [directory stringByAppendingPathComponent:@"book 空 白 #?%.cbz"];
	int descriptor = open([path fileSystemRepresentation], O_CREAT | O_WRONLY, 0600);
	BOOL createdFile = descriptor >= 0;
	if (createdFile) {
		write(descriptor, "test", 4);
		close(descriptor);
	}
	check(createdFile, [NSString stringWithFormat:@"creates the special-character fixture at %@", path]);
	NSURL *fileURL = [NSURL fileURLWithPath:path];

	NSURL *requestURL = CooViewerNewWindowURLForFileURL(fileURL, scheme);
	check(requestURL != nil, @"encodes an existing local file URL");
	check([[requestURL scheme] isEqualToString:scheme], @"uses the expected scheme");
	check([[requestURL absoluteString] rangeOfString:@"#?%"].location == NSNotFound,
		@"reserved filename characters are percent-encoded");
	NSURL *decodedURL = CooViewerFileURLFromNewWindowURL(requestURL, scheme);
	check(decodedURL != nil, @"decodes a valid request");
	check([[decodedURL path] isEqualToString:[[fileURL URLByStandardizingPath] path]],
		@"round-trips spaces, Unicode, and reserved characters");

	check(CooViewerNewWindowURLForFileURL([NSURL URLWithString:@"https://example.com"], scheme) == nil,
		@"encoder rejects non-file URLs");
	check(CooViewerFileURLFromNewWindowURL(requestURL, @"wrong-scheme") == nil,
		@"decoder rejects an unexpected scheme");
	check(CooViewerFileURLFromNewWindowURL(
		[NSURL URLWithString:@"cooviewer-new-window-test://wrong?url=file%3A%2F%2F%2Ftmp"], scheme) == nil,
		@"decoder rejects an unexpected action");
	check(CooViewerFileURLFromNewWindowURL(
		[NSURL URLWithString:@"cooviewer-new-window-test://open?url=https%3A%2F%2Fexample.com"], scheme) == nil,
		@"decoder rejects a non-file payload");
	check(CooViewerFileURLFromNewWindowURL(
		[NSURL URLWithString:@"cooviewer-new-window-test://open?url=file%3A%2F%2F%2Fdefinitely%2Fmissing&extra=1"], scheme) == nil,
		@"decoder rejects extra query items");
	check(CooViewerFileURLFromNewWindowURL(
		[NSURL URLWithString:@"cooviewer-new-window-test://open?url=file%3A%2F%2F%2Fdefinitely%2Fmissing"], scheme) == nil,
		@"decoder rejects a missing local path");

	[[NSFileManager defaultManager] removeItemAtPath:directory error:nil];
	NSLog(@"%d checks, %d failures", checks, failures);
	[pool drain];
	return failures == 0 ? 0 : 1;
}
