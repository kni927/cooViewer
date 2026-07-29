#import "AppController.h"
#import "Controller.h"
#import "PreferenceController.h"

@implementation AppController

/* Same timing as before MW-3: Controller's own -awakeFromNib called
   -setupRemoteControl as its last step, during nib load rather than at
   applicationDidFinishLaunching: time. AppController is a nib object too
   now (wired as NSApplication's delegate), so its own -awakeFromNib
   preserves that timing. */
- (void)awakeFromNib
{
	[self setupRemoteControl];
}

#pragma mark NSApplicationDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
	/* Almost the entire body is window-level (pushes keyArray/mouseArray
	   into the window's outlets, then the OpenLastFolder gate) — see the
	   MW-3 pre-implementation inventory in docs/multiwindow-plan.md. */
	[controller applicationDidFinishLaunchingSetup:notification];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
	[[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)applicationWillBecomeActive:(NSNotification *)aNotification
{
	[remoteControl startListening:self];
}
- (void)applicationWillResignActive:(NSNotification *)aNotification
{
	[remoteControl stopListening:self];
}
- (void)applicationDidBecomeActive:(NSNotification *)aNotification
{
	/* checkCurrentFolderUpdated stats the parent folder of the current book
	   (and may re-enumerate it via setSameFolderMenu:). Doing that every time
	   the app regains focus hits the parent folder constantly and can trigger
	   macOS folder-access permission prompts repeatedly. It's now run lazily,
	   right before the "Open from same folder" submenu is actually shown —
	   see -[Controller menuNeedsUpdate:]. */
}

- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename
{
	return [controller application:theApplication openFile:filename];
}

- (NSMenu *)applicationDockMenu:(NSApplication *)sender
{
	/* MW-3 finding: this used to read the per-window [imageView image]
	   directly; with exactly one window it now asks that window controller
	   whether a book is open. "The front window" (plural) is MW-7's job. */
	NSMenu *menu = [[[NSMenu alloc] init] autorelease];

	if (![controller hasBookOpen]) {
		NSMenuItem *menuItem;
		menuItem = [[NSMenuItem alloc] init];
		[menuItem setTitle:NSLocalizedString(@"Open the last page", @"")];
		[menuItem setAction:@selector(openTheLastPage:)];
		[menu addItem:menuItem];
		[menuItem release];
	}
	return menu;
}

#pragma mark appleRemote

- (void)setupRemoteControl
{
	remoteControl = [[AppleRemote alloc] initWithDelegate:self];
	[remoteControl setDelegate:self];

	// OPTIONAL CODE
	// The MultiClickRemoteBehavior adds extra functionality.
	// It works like a middle man between the delegate and the remote control
	remoteControlBehavior = [MultiClickRemoteBehavior new];
	[remoteControlBehavior setDelegate:self];
	[remoteControlBehavior setSimulateHoldEvent:YES];
	[remoteControl setOpenInExclusiveMode:YES];
	[remoteControl setDelegate:remoteControlBehavior];
	[remoteControl startListening:self];
}

- (BOOL)appleRemoteHoldDown
{
	return appleRemoteHoldDown;
}

#pragma mark action

/* Moved from Controller_input.m together with setupRemoteControl (MW-3
   finding #4). The body still needs window-side state (the window's
   visible/key state, the thumbnail panel, and the actual key dispatch in
   -timeredRemoteButtonEvent:), which stays on Controller and is reached
   through it — there is exactly one controller to route to until MW-7. */
- (void)remoteButton:(RemoteControlEventIdentifier)buttonIdentifier pressedDown:(BOOL)pressedDown clickCount:(unsigned int)clickCount
{
	appleRemoteHoldDown = NO;
	if (!pressedDown) {
		return;
	}
	UpdateSystemActivity( OverallAct );
	//UpdateSystemActivity(UsrActivity);

    unichar character = buttonIdentifier;
	switch(buttonIdentifier) {
		case kRemoteButtonRight_Hold:
			appleRemoteHoldDown = YES;
			character = kRemoteButtonRight;
			break;
		case kRemoteButtonLeft_Hold:
			appleRemoteHoldDown = YES;
			character = kRemoteButtonLeft;
			break;
		case kRemoteButtonPlus_Hold:
			appleRemoteHoldDown = YES;
			character = kRemoteButtonPlus;
			break;
		case kRemoteButtonMinus_Hold:
			appleRemoteHoldDown = YES;
			character = kRemoteButtonMinus;
			break;
		case kRemoteButtonPlay_Hold:
			appleRemoteHoldDown = YES;
			character = kRemoteButtonPlay;
			break;
		case kRemoteButtonMenu_Hold:
			appleRemoteHoldDown = YES;
			character = kRemoteButtonMenu;
			break;
		default:
			break;
	}
	NSString *characters = [NSString stringWithCharacters:&character length:1];

	NSWindow *bookWindow = [controller sheetParentWindow];
	if (![bookWindow isVisible] || ![bookWindow isKeyWindow]) {
		if ([prefController inKeyEdit]) {
			[prefController setKeyCharacters:characters];
			appleRemoteHoldDown = NO;
			return;
		}
		if (![[controller thumController] isVisible]) {
			appleRemoteHoldDown = NO;
			return;
		}
	}
	[controller timeredRemoteButtonEvent:characters];
}

#pragma mark dontSleep

- (void)dontSleepTimerStart
{
	if (dontSleepTimer == nil) {
		dontSleepTimer = [NSTimer scheduledTimerWithTimeInterval:25.0
														  target:self
														selector:@selector(dontSleep)
														userInfo:NULL
														 repeats:YES];
	}
}
- (void)dontSleepTimerStop
{
	[dontSleepTimer invalidate];
	dontSleepTimer = nil;
}
- (void)dontSleep
{
	UpdateSystemActivity( OverallAct );
	//UpdateSystemActivity( UsrActivity );
}

#pragma mark openFromAny

- (IBAction)open:(id)sender
{
	[controller open:sender];
}
- (IBAction)openTheLastPage:(id)sender
{
	[controller openTheLastPage:sender];
}

#pragma mark preferences

- (IBAction)preferences:(id)sender
{
	[prefController preferences];
}
- (IBAction)clearRecent:(id)sender
{
	[[NSUserDefaults standardUserDefaults] removeObjectForKey:@"RecentItems"];
	[[NSUserDefaults standardUserDefaults] synchronize];
	[controller setOpenRecentMenu];
}

#pragma mark menu outlet accessors
/* Builder methods for these menus stay on Controller (they read per-window
   book state); Controller reaches the items through these accessors. */

- (id)openRecentMenuItem
{
	return openRecentMenuItem;
}
- (id)openSameFolderMenuItem
{
	return openSameFolderMenuItem;
}
- (id)bookmarkMenuItem
{
	return bookmarkMenuItem;
}

#pragma mark validation

- (BOOL)validateMenuItem:(NSMenuItem *)anItem
{
	return [controller validateMenuItem:anItem];
}

@end
