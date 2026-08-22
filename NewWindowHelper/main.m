#import <Cocoa/Cocoa.h>

#import "CONewWindowURL.h"

@interface CooViewerNewWindowHelperDelegate : NSObject <NSApplicationDelegate>
{
	BOOL receivedOpenRequest;
}
@end

@implementation CooViewerNewWindowHelperDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
	/* A direct launch has nothing to forward. Keep one short run-loop window
	   so a document event arriving just after launch is not lost. */
	[self performSelector:@selector(terminateIfIdle) withObject:nil afterDelay:1.0];
}

- (void)application:(NSApplication *)application openFiles:(NSArray *)filenames
{
	receivedOpenRequest = YES;
	NSString *scheme = [[NSBundle mainBundle]
		objectForInfoDictionaryKey:CooViewerNewWindowSchemeInfoKey];
	BOOL forwardedAll = ([filenames count] > 0);

	NSEnumerator *enumerator = [filenames objectEnumerator];
	NSString *filename;
	while (filename = [enumerator nextObject]) {
		NSURL *fileURL = [NSURL fileURLWithPath:filename];
		NSURL *requestURL = CooViewerNewWindowURLForFileURL(fileURL, scheme);
		if (!requestURL || ![[NSWorkspace sharedWorkspace] openURL:requestURL]) {
			forwardedAll = NO;
		}
	}

	[application replyToOpenOrPrint:(forwardedAll
		? NSApplicationDelegateReplySuccess
		: NSApplicationDelegateReplyFailure)];
	[application performSelector:@selector(terminate:) withObject:self afterDelay:0.0];
}

- (void)terminateIfIdle
{
	if (!receivedOpenRequest) {
		[NSApp terminate:self];
	}
}

@end

int main(int argc, const char *argv[])
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSApplication *application = [NSApplication sharedApplication];
	[application setActivationPolicy:NSApplicationActivationPolicyProhibited];
	CooViewerNewWindowHelperDelegate *delegate =
		[[CooViewerNewWindowHelperDelegate alloc] init];
	[application setDelegate:delegate];
	[application run];
	[delegate release];
	[pool drain];
	return 0;
}
