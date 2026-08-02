#import "AppController.h"
#import "BookWindowController.h"
#import "PreferenceController.h"
#import "COImageLoader.h"	/* +fileTypes, for the Open in New Window panel */
#import "AllBookmarkController.h"	/* -editAllBookmark:, for the All Bookmarks menu item */

NSString * const CooViewerBookWindowRestorationIdentifier = @"cooViewerBookWindow";

@implementation AppController

static const int DIALOG_OK		= 128;
static const int DIALOG_CANCEL	= 129;

/* KNOWN_ISSUES #32. How long -settleLaunch will wait for restoration to
   finish before draining a held Finder request anyway. Measured ordering on
   macOS 26 (see the comment on -settleLaunch) puts the last restored book
   about 0.3 s after the open request arrives, so this is roughly ten times
   the expected wait: long enough that a slow archive is not cut short,
   short enough that a restoration which never completes cannot leave a
   double-clicked file unopened. */
static const CFAbsoluteTime kLaunchDrainTimeout = 3.0;
/* How often -settleLaunch re-checks while it is still waiting. */
static const NSTimeInterval kLaunchDrainPollInterval = 0.05;

/* Same timing as before MW-3: BookWindowController's own -awakeFromNib called
   -setupRemoteControl as its last step, during nib load rather than at
   applicationDidFinishLaunching: time. AppController is a nib object too
   now (wired as NSApplication's delegate), so its own -awakeFromNib
   preserves that timing. */
- (void)awakeFromNib
{
	/* MW-5 item 6: BookWindowControllers are created here rather than
	   instantiated from MainMenu.xib. The first one is created at the same
	   launch-time moment at which MainMenu.xib used to instantiate this
	   object and run its -awakeFromNib. Its window is still not shown until
	   a book is opened. */
	windowControllers = [[NSMutableArray alloc] init];
	[self newWindowController];

	/* KNOWN_ISSUES #32: created here because this runs during the MainMenu.xib
	   load, which is before both the restoration pass and the launch's
	   -application:openFiles:. */
	pendingLaunchOpenPaths = [[NSMutableArray alloc] init];
	launchDrainDeadline = CFAbsoluteTimeGetCurrent() + kLaunchDrainTimeout;

	/* MW-8: the backstop that ends any restoration a window never got a
	   -restoreStateWithCoder: for. Registered here because this runs during
	   the MainMenu.xib load, which is before the restoration pass. */
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(applicationDidFinishRestoringWindows:)
												 name:NSApplicationDidFinishRestoringWindowsNotification
											   object:nil];

	[self setupRemoteControl];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(settleLaunch)
											   object:nil];
	[pendingLaunchOpenPaths release];
	[launchNotification release];
	[windowControllers release];
	[super dealloc];
}

#pragma mark NSApplicationDelegate

/* MW-8 / Step-0 decision 5 put the OpenLastFolder fallback here, gated on
   "did the system restore any windows". KNOWN_ISSUES #32 moved the fallback
   itself into -settleLaunch: a Finder request that arrives during launch is
   now held rather than acted on, so this method is too early to know whether
   anything is going to open a book. Both the gate and the queue drain happen
   at the one point where that is knowable, and this method only kicks it —
   -settleLaunch is idempotent, and -applicationDidFinishRestoringWindows:
   may kick it first (on macOS 26 it does). */
- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
	/* Installed here rather than in -awakeFromNib: NSApplication registers its
	   own handler for this event during launch and the last registration wins.
	   See -handleQuitAppleEvent:withReplyEvent:. */
	[[NSAppleEventManager sharedAppleEventManager]
		setEventHandler:self
			andSelector:@selector(handleQuitAppleEvent:withReplyEvent:)
		  forEventClass:kCoreEventClass
			 andEventID:kAEQuitApplication];

	launchNotification = [notification retain];
	launchDidFinish = YES;
	[self performSelector:@selector(settleLaunch) withObject:nil afterDelay:0.0];
}

/* macOS 12 and later. Restorable state is archived with secure coding when
   this answers YES, which is what the two -encodeRestorableStateWithCoder:
   participants here already assume: BookWindowController encodes NSData and
   two ints, and decodes the NSData with -decodeObjectOfClass:forKey:. */
- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app
{
	return YES;
}

/* The application could not be quit while an archive password prompt was up —
   Cmd+Q, the Quit menu item and an AppleEvent quit were all discarded rather
   than deferred. Not a regression from making the prompt window-modal
   (measured identically on the app-modal build), but an unresponsive Cmd+Q is
   breakage all the same.

   **The obvious fix does not work, and this was measured rather than assumed:**
   this delegate method is never reached while a sheet is attached.
   Instrumenting it showed it firing for an ordinary quit and not firing at all
   for a quit attempted with a password prompt up — AppKit's -terminate: refuses
   before it consults the delegate. The prompts therefore have to come down
   inside -terminate: itself, which is what COApplication does; this method
   stays as the backstop for any route that does reach the delegate. */
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
	[self cancelPasswordPrompts];
	return NSTerminateNow;
}

/* Takes down every window's password prompt, and answers whether there was one
   to take down — COApplication uses that to decide whether the quit has to wait
   a run-loop pass for AppKit to finish dismissing the sheets. Each prompt ends
   as a cancel, by the rule the prompt already follows: a window that had a book
   keeps it, a bookless window stays bookless. Nothing about the abandoned book
   is persisted — RecentItems, LastPages and the restorable state are written by
   the second half of the open, which a cancelled prompt never reaches — so an
   archive whose password was never entered leaves no trace to come back on at
   the next launch. */
- (BOOL)cancelPasswordPrompts
{
	BOOL dismissedAny = NO;
	NSEnumerator *enu = [windowControllers objectEnumerator];
	id aController;
	while (aController = [enu nextObject]) {
		if ([aController cancelPasswordPromptForTermination]) {
			dismissedAny = YES;
		}
	}
	return dismissedAny;
}

/* The AppleEvent quit — `osascript -e 'quit app "cooViewer"'`, the Dock menu's
   Quit, and the quit every application is sent at logout — needs its own hook
   even with -[COApplication terminate:] in place. Measured: with a password
   prompt up, Cmd+Q and the Quit menu item reach -terminate: (and so are fixed
   by the override), while the AppleEvent route does not — AppKit's own handler
   for it declines earlier. Taking the prompts down here and then calling
   -terminate: puts that route back on the same footing. */
- (void)handleQuitAppleEvent:(NSAppleEventDescriptor *)event
              withReplyEvent:(NSAppleEventDescriptor *)replyEvent
{
	[self cancelPasswordPrompts];
	[NSApp performSelector:@selector(terminate:) withObject:self afterDelay:0.0];
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
	   see -[BookWindowController menuNeedsUpdate:]. */
}

/* Finder "Open With", a drag onto the Dock icon, and the launch document
   event all arrive here. MW-7 forwarded the singular -application:openFile:
   straight to the front window, so a book opened from the Finder replaced
   whatever that window was showing; MW-7's multi-window pass then routed it
   through -openBookInNewWindow: like ⌥⌘O instead, so it always opened a new
   window. v1.6.2 (this task) restores the original "replace the front
   window's book" behavior — but per-file, and only for the first file that
   doesn't already have a window: de-duplicate first (unchanged, still wins),
   then if a book window exists, load the first not-already-open file into
   *its own front controller* via the same -openBookAtPath: File ▸ Open uses
   (Step-0 decision 3), rather than opening a new one. Only the first
   otherwise-unhandled file gets this treatment per call, since the front
   window can only hold one book — every file after it, and everything when
   no book window exists yet, still goes through -openBookInNewWindow:
   unchanged (dedup, empty-window reuse, or a new cascaded window).

   AppKit prefers this over -application:openFile: when both exist, so the
   singular one is gone rather than left as an unreachable second path.

   KNOWN_ISSUES #32: during launch the request is *held* rather than acted on.
   De-duplication asks which window is showing a book, and at this point in
   the launch a window being restored has decoded its book but not opened it
   yet — so acting now would find nothing to de-duplicate against and open a
   second window on a book that is already coming back. -settleLaunch drains
   the queue through this same -openBookInNewWindow: once every restored
   window has its book — the front-window-replace behavior below does not
   apply to the drain, matching Step-0 decision 2's existing comment on
   -openBookInNewWindow: (an explicit request for a book a restored window
   is already showing brings that window forward, never doubles it). Once
   the launch has settled this method is unchanged: immediate, no queue. */
- (void)application:(NSApplication *)sender openFiles:(NSArray *)filenames
{
	if (!launchSettled) {
		[pendingLaunchOpenPaths addObjectsFromArray:filenames];
		/* Reply now: the files *will* be opened, and holding the reply until
		   the drain would leave the Finder waiting on a run-loop pass that
		   -openPage:last: can turn into a much longer one. */
		[sender replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
		[self performSelector:@selector(settleLaunch) withObject:nil afterDelay:0.0];
		return;
	}

	/* Only the first file in this call gets to replace the front window —
	   every file after it finds that slot already taken and falls through to
	   -openBookInNewWindow: like today. The dedup lookup below is a read-only
	   query (already shared with -openBookInNewWindow: and the bookmark
	   browsers), not a second copy of that method's own logic: it decides
	   whether *this* file is a front-window-replace candidate, and
	   -openBookInNewWindow: still runs its own copy of the same check for
	   every file this loop does route to it, unchanged. */
	BOOL frontWindowReplaced = NO;
	NSEnumerator *enu = [filenames objectEnumerator];
	NSString *filename;
	while (filename = [enu nextObject]) {
		id front = [self frontController];
		/* v1.6.x: -isBookLoadInFlight guards against replacing a window
		   whose *own* front-window-replace (or restoration) is still
		   running — -hasBookOpen alone stays YES for the old book
		   throughout a replace's load, so two Finder-opens landing on the
		   same occupied front window in quick succession could otherwise
		   both pass this gate and race into -openBookAtPath: together.
		   See docs/tasks/2026-08-02-02-investigate-empty-window-race.md. */
		if (!frontWindowReplaced && front && [front hasBookOpen] && ![front isBookLoadInFlight]
			&& ![self windowControllerShowingBook:[BookWindowController resolvedBookPath:filename]]) {
			[front openBookAtPath:filename];
			frontWindowReplaced = YES;
			continue;
		}
		[self openBookInNewWindow:filename];
	}
	[sender replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
}

/* Step-0 decision 4. Deferred by MW-7 because -[BookWindowController
   openPage:last:] closes the window it has just ordered front when a load
   fails and the window had no book to fall back on — so a flat YES would
   quit the app the moment someone opened a corrupt file as the first thing
   in a session.

   The discriminator is the session, not the close: this returns YES only
   once some window has actually shown a book. A failed first open therefore
   cannot quit the app, because nothing has been read yet; and once a book
   has been read, "no windows left" really is the user having closed the
   last one. The state that would otherwise need distinguishing — app alive,
   a book already read, no window open — is unreachable, since reaching it
   is precisely what now terminates. */
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
	return didShowBook;
}

/* Called by -[BookWindowController openPage:last:] when a load completes. */
- (void)windowControllerDidOpenBook:(id)aController
{
	didShowBook = YES;
}

- (NSMenu *)applicationDockMenu:(NSApplication *)sender
{
	/* MW-3 finding: this used to read the per-window [imageView image]
	   directly; it asks the front window controller whether a book is open. */
	NSMenu *menu = [[[NSMenu alloc] init] autorelease];

	if (![[self frontController] hasBookOpen]) {
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

/* Moved from BookWindowController_input.m together with setupRemoteControl (MW-3
   finding #4). The body still needs window-side state (the window's
   visible/key state, the thumbnail panel, and the actual key dispatch in
   -timeredRemoteButtonEvent:), which stays on BookWindowController; MW-7
   routes it to the front window. */
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

	/* Resolved once: the remote acts on one window, and -frontController
	   must not be re-read part-way through this dispatch. */
	id controller = [self frontController];
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
	[[self frontController] open:sender];
}

/* MW-7 / decision A1. Deliberately targeted at AppController rather than
   First Responder (unlike the render-path and book actions MW-4 retargeted):
   creating a window is not something a window does, and the command must
   stay available when the front window has no book — or, later, when there
   is no key window at all. */
- (IBAction)openInNewWindow:(id)sender
{
	NSOpenPanel *openPanel = [NSOpenPanel openPanel];

	[openPanel setCanChooseDirectories:YES];
	[openPanel setAllowedFileTypes:[NSMutableArray arrayWithArray:[COImageLoader fileTypes]]];
	/* NSModalResponseOK, not the NSOKButton the older -[BookWindowController
	   open:] uses: the same value, but not deprecated, so this does not add
	   to the project's deprecation warning baseline. */
	if ([openPanel runModal] != NSModalResponseOK) {
		return;
	}
	[self openBookInNewWindow:[[openPanel URL] path]];
}

- (IBAction)openTheLastPage:(id)sender
{
	[[self frontController] openTheLastPage:sender];
}

/* KNOWN_ISSUES #24: the All Bookmark browser's entry. Deliberately targeted at
   AppController rather than First Responder, unlike the book/view actions MW-4
   swept onto the responder chain: there is one browser for the whole
   application (MW-5 item 5, which is also why MW-6 left its autosave name
   unsuffixed), and it must be reachable when no window has a book — the state
   the old route needed and could not survive. */
- (IBAction)allBookmarks:(id)sender
{
	[(AllBookmarkController *)allBookmarkController editAllBookmark:nil];
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
	[[self frontController] setOpenRecentMenu];
}

#pragma mark menu outlet accessors
/* Builder methods for these menus stay on BookWindowController (they read per-window
   book state); BookWindowController reaches the items through these accessors. */

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

#pragma mark window registry / app-wide panels (MW-5, MW-7)

/* The book window controller app-level code should act on. Every existing
   caller of this accessor meant "the window", which from MW-7 on means "the
   front window". */
- (id)controller
{
	return [self frontController];
}

- (NSArray *)windowControllers
{
	return windowControllers;
}

- (id)frontController
{
	if (frontWindowController) {
		return frontWindowController;
	}
	/* Before any window has become main — at launch, and after the front
	   window has been retired without another taking over yet. */
	return [windowControllers lastObject];
}

/* Slot 0 keeps the historical unsuffixed frame autosave names
   ("NormalWindow", "Bookmark", "FilterPanel") and therefore the frames users
   already have saved, so slots are handed out lowest-free-first rather than
   monotonically: close window 2 and reopen it and it is window 2 again,
   sitting on its own saved frames instead of accumulating new ones. */
- (int)firstFreeWindowIndex
{
	int index;
	for (index = 0; ; index++) {
		BOOL taken = NO;
		NSEnumerator *enu = [windowControllers objectEnumerator];
		id aController;
		while (aController = [enu nextObject]) {
			if ([aController windowIndex] == index) {
				taken = YES;
				break;
			}
		}
		if (!taken) {
			return index;
		}
	}
}

- (id)newWindowController
{
	BookWindowController *aController = [[BookWindowController alloc] initWithWindowNibName:@"BookWindow"];

	/* -setAppController: and -setWindowIndex: both have to happen before the
	   nib loads: -windowDidLoad reads the first, and the second is what the
	   per-window frame autosave names are keyed on, which the panels in
	   BookWindow.xib ask for during nib load (MW-6 items 1 and 2). */
	[aController setAppController:self];
	[aController setWindowIndex:[self firstFreeWindowIndex]];
	/* Registered before the nib loads, so anything that resolves the front
	   window during the load finds this one rather than the window it is
	   being opened from. */
	[windowControllers addObject:aController];
	[aController release];

	/* Forces BookWindow.xib to load now. The window is not shown until a
	   book is opened in it. */
	[aController window];
	return aController;
}

- (id)windowControllerShowingBook:(NSString *)bookPath
{
	NSEnumerator *enu = [windowControllers objectEnumerator];
	id aController;
	while (aController = [enu nextObject]) {
		if ([aController hasBookOpen]
			&& [[aController currentBookPath] isEqualToString:bookPath]) {
			return aController;
		}
	}
	return nil;
}

- (void)openBookInNewWindow:(NSString *)path
{
	/* Step-0 decision 2: keyed on the resolved book path, not the path the
	   user picked — a single image file opens its parent folder as the book,
	   which is exactly the case where de-duplication matters. */
	id existing = [self windowControllerShowingBook:[BookWindowController resolvedBookPath:path]];
	if (existing) {
		[[existing window] makeKeyAndOrderFront:self];
		return;
	}

	/* An empty window — the one at launch, or the last one left after its
	   book was closed — is used rather than adding a second window beside
	   it. It is what File ▸ Open would have used, and leaving it behind
	   bookless would be the empty-window state Step-0 decision 4 exists to
	   avoid. */
	id aController = [self emptyWindowController];
	if (!aController) {
		/* v1.6.2: a genuinely new window inherits the front book window's
		   size. Read before -newWindowController, which registers the new
		   controller immediately and would otherwise make -frontController
		   resolve to it instead of the window this one should inherit from
		   (see -newWindowController's own comment on registration order).
		   No inheritance if the front window has no book open — e.g. the
		   bookless window at launch — which leaves this case exactly as it
		   was: the nib default, placed by cascade. */
		id front = [self frontController];
		BOOL inheritSize = (front != nil && [front hasBookOpen]);
		NSSize inheritedSize = inheritSize ? [front currentWindowedSize] : NSZeroSize;

		aController = [self newWindowController];

		if (inheritSize) {
			NSWindow *newWindow = [aController window];
			NSRect frame = [newWindow frame];
			frame.size = inheritedSize;
			/* display:NO — this only changes the frame the window will
			   first draw into; the window is not shown until
			   -openBookAtPath: below opens a book into it. */
			[newWindow setFrame:frame display:NO];
		}
	}
	[aController openBookAtPath:path];
}

/* A registered window with no book in it, or nil. The front one wins, but
   the search does not stop there: -application:openFiles: opens a whole list
   in one pass, and -frontController only changes when AppKit sends
   -windowDidBecomeMain:, so relying on the front window alone would make the
   second file of a multi-file open depend on when that notification lands. */
- (id)emptyWindowController
{
	id front = [self frontController];
	if (front && [self isWindowControllerEmpty:front]) {
		return front;
	}
	NSEnumerator *enu = [windowControllers objectEnumerator];
	id aController;
	while (aController = [enu nextObject]) {
		if ([self isWindowControllerEmpty:aController]) {
			return aController;
		}
	}
	return nil;
}

/* "Empty" means no book *and* nothing on its way in. Three states are not
   empty even though -hasBookOpen says NO: a window the system is restoring
   a book into (MW-8), a window whose open is sitting on a password sheet
   (KNOWN_ISSUES #33), and a window with an ordinary (non-restored) load
   still running — -isBookLoadInFlight, added because -hasBookOpen alone
   only goes YES once a load *completes*, leaving every load's whole
   duration looking "empty" to this method. Handing any of the three to the
   next open would drop a second book on top of one already in flight, and
   in the password case would queue a second sheet behind the first on the
   same window. See
   docs/tasks/2026-08-02-02-investigate-empty-window-race.md for the
   measured race this closes. */
- (BOOL)isWindowControllerEmpty:(id)aController
{
	return (![aController hasBookOpen]
			&& ![aController isBookLoadInFlight]
			&& ![aController isAwaitingRestoredBook]
			&& ![aController isWaitingForUserInput]);
}

#pragma mark window restoration (MW-8)

/* Step-0 decision 5, the NSWindowRestoration half. AppKit calls this once
   per saved window, during the restoration pass between
   applicationWillFinishLaunching: and applicationDidFinishLaunching:. All it
   has to do is hand back a window; which book that window shows is decoded
   by -[BookWindowController restoreStateWithCoder:], out of the same coder
   that is passed in here.

   The window at launch is empty, so the first restored window is opened into
   it rather than beside it — the same reuse -openBookInNewWindow: does, and
   what keeps the "a window always has a book" invariant Step-0 decision 4
   rests on. -beginRestoration takes that window out of the empty pool
   immediately, so the second call does not pick the same one back up before
   the first has decoded its book. */
+ (void)restoreWindowWithIdentifier:(NSUserInterfaceItemIdentifier)identifier
							  state:(NSCoder *)state
				  completionHandler:(void (^)(NSWindow *, NSError *))completionHandler
{
	if (![identifier isEqualToString:CooViewerBookWindowRestorationIdentifier]) {
		completionHandler(nil, nil);
		return;
	}
	id appController = [NSApp delegate];
	if (![appController isKindOfClass:[AppController class]]) {
		completionHandler(nil, nil);
		return;
	}

	[appController noteWindowRestorationRequested];

	id aController = [appController emptyWindowController];
	if (!aController) {
		aController = [appController newWindowController];
	}
	[aController beginRestoration];
	completionHandler([aController window], nil);
}

/* The backstop for a window that was handed back above but never got a
   -restoreStateWithCoder: — nothing in AppKit's contract promises one, and a
   window left flagged "restoring" would never be reused as an empty window
   again. Restoration is over by the time this runs, so anything still
   flagged is not going to be restored. */
- (void)applicationDidFinishRestoringWindows:(NSNotification *)notification
{
	NSEnumerator *enu = [windowControllers objectEnumerator];
	id aController;
	while (aController = [enu nextObject]) {
		[aController endRestoration];
	}
	/* KNOWN_ISSUES #32. AppKit posts this even when there was nothing to
	   restore (measured), so it is the earliest reliable "restoration is over"
	   signal — but the restored books are opened a run-loop pass later still,
	   which is what -settleLaunch waits for. */
	[self performSelector:@selector(settleLaunch) withObject:nil afterDelay:0.0];
}

/* KNOWN_ISSUES #32. Ordering of the launch, measured on macOS 26 by
   instrumenting every hook (three windows to restore plus a Finder open):

     applicationWillFinishLaunching:
     +restoreWindowWithIdentifier:  x3
     -restoreStateWithCoder:        x3     <- the books are known here
     NSApplicationDidFinishRestoringWindows
     -application:openFiles:
     applicationDidFinishLaunching:
     -openRestoredBook              x3     <- ~0.3 s later; the books open here

   Two things in that trace decide this method. Restoration state is decoded
   *before* -applicationDidFinishLaunching:, not after it as the MW-8 comment
   assumed; and the restored books are opened after it, from the
   -performSelector:afterDelay:0.0 that -restoreStateWithCoder: schedules. So
   the launch is settled only once no window is still working through a
   restored book, and that is what is waited for here rather than any single
   notification. The wait is a poll with a deadline because AppKit promises no
   notification for "the restored books are open" — nothing in the trace above
   is that signal — and because a restoration that fails or never completes
   must not strand the user's file.

   -isRestoredBookUnfinished covers all three stages: AppKit still deciding,
   decoded but not yet opened, and mid-open. The last one matters because
   -openPage:last: spins the run loop (MW-1's modal session), so this
   -performSelector: can fire *inside* a restored book's open. */
- (void)settleLaunch
{
	if (launchSettled) {
		return;
	}

	/* KNOWN_ISSUES #33: a restored encrypted book waits on a password sheet,
	   and a person takes as long as they take. The deadline is there to bound
	   *machine* work that may never finish, so it is pushed forward for as long
	   as any window is waiting on input — otherwise it would expire while the
	   sheet is up and drain the queue early, which is exactly the duplicate
	   window #32 removed. */
	BOOL waitingForUser = NO;
	NSEnumerator *userEnu = [windowControllers objectEnumerator];
	id aWindowController;
	while (aWindowController = [userEnu nextObject]) {
		if ([aWindowController isWaitingForUserInput]) {
			waitingForUser = YES;
			break;
		}
	}
	if (waitingForUser) {
		launchDrainDeadline = CFAbsoluteTimeGetCurrent() + kLaunchDrainTimeout;
	}

	if (CFAbsoluteTimeGetCurrent() < launchDrainDeadline) {
		BOOL waiting = !launchDidFinish;
		NSEnumerator *enu = [windowControllers objectEnumerator];
		id aController;
		while (!waiting && (aController = [enu nextObject])) {
			waiting = [aController isRestoredBookUnfinished];
		}
		if (waiting) {
			[self performSelector:@selector(settleLaunch)
					   withObject:nil
					   afterDelay:kLaunchDrainPollInterval];
			return;
		}
	} else if ([pendingLaunchOpenPaths count] > 0) {
		NSLog(@"cooViewer: window restoration did not finish in time; "
			  @"opening the requested book(s) anyway");
	}

	launchSettled = YES;

	/* Drained through -openBookInNewWindow:, so an explicit request for a book
	   that a restored window is already showing brings that window forward at
	   its restored page instead of opening a second one — Step-0 decision 2,
	   which is the whole point of the queue. */
	if ([pendingLaunchOpenPaths count] > 0) {
		launchOpenRequestServiced = YES;
		NSArray *paths = [[pendingLaunchOpenPaths copy] autorelease];
		[pendingLaunchOpenPaths removeAllObjects];
		NSEnumerator *enu = [paths objectEnumerator];
		NSString *path;
		while (path = [enu nextObject]) {
			[self openBookInNewWindow:path];
		}
	}

	/* MW-8 / Step-0 decision 5, unchanged in intent: OpenLastFolder is the
	   fallback for "nothing else opened a book this launch". It now has two
	   things to stand down for rather than one. A restored window whose book
	   has since been deleted still suppresses it — the system did restore a
	   window, it just has nothing to show — and an explicit Finder request
	   takes precedence, because opening the last folder *and* the requested
	   book is the same duplicate-window outcome from the other direction. */
	if (restoredWindowCount > 0 || launchOpenRequestServiced) {
		[launchNotification release];
		launchNotification = nil;
		return;
	}

	/* The body is the OpenLastFolder gate, and window-level — see the MW-3
	   pre-implementation inventory in docs/multiwindow-plan.md. */
	[[self frontController] applicationDidFinishLaunchingSetup:launchNotification];
	[launchNotification release];
	launchNotification = nil;
}

- (void)noteWindowRestorationRequested
{
	restoredWindowCount++;
}

- (int)restoredWindowCount
{
	return restoredWindowCount;
}

- (void)windowControllerDidBecomeFront:(id)aController
{
	frontWindowController = aController;
}

- (BOOL)retireWindowController:(id)aController
{
	if ([windowControllers count] < 2) {
		/* The last window stays. Closing it leaves the app running with no
		   book open, as it always has, and this controller is what File ▸
		   Open, Open the last page and the dock menu reuse. Step-0 decision
		   4 (quit after the last window closes) is a separate change — see
		   docs/DECISIONS.md. */
		return NO;
	}
	if (frontWindowController == aController) {
		frontWindowController = nil;
	}
	/* -windowWillClose: is running inside this object; the release has to
	   outlive the rest of that call and AppKit's own close sequence. */
	[[aController retain] autorelease];
	[windowControllers removeObject:aController];
	return YES;
}

/* The All Bookmark browser (MW-5 item 5). App-wide, so it lives here rather
   than on a window controller. */
- (id)allBookmarkController
{
	return allBookmarkController;
}

#pragma mark shared modal helpers

/* MW-5: moved here from BookWindowController. The only users are the
   Preferences window's OK/Cancel buttons; Preferences is app-wide and stays
   in MainMenu.xib, while BookWindowController became the File's Owner of
   BookWindow.xib. Codes unchanged. */
- (IBAction)sheetOk:(id)sender{[NSApp stopModalWithCode:DIALOG_OK];}
- (IBAction)sheetCancel:(id)sender{[NSApp stopModalWithCode:DIALOG_CANCEL];}

#pragma mark validation

/* MW-4: this used to forward wholesale to -[BookWindowController validateMenuItem:],
 * which held all 44 title branches (including the AppController items,
 * since everything but BookWindowController itself was target="484" back then). Now
 * that the render-path/book actions target First Responder and resolve to
 * BookWindowController via the window's delegate, BookWindowController's method only needs to
 * validate items still explicitly targeted at it (the RightMenu
 * contextAction/sheet items) plus whatever the responder chain search finds
 * it for. This method now only needs to handle AppController's own items:
 * "Open the last page" keeps its original per-window check (moved to
 * -[BookWindowController validateOpenTheLastPageMenuItem]); Open/Preferences/Clear
 * Recent had no special-case branch before (they fell through BookWindowController's
 * default) and still don't. */
- (BOOL)validateMenuItem:(NSMenuItem *)anItem
{
	if ([[anItem title] isEqualToString:NSLocalizedString(@"Open the last page", @"")] == YES) {
		return [[self frontController] validateOpenTheLastPageMenuItem];
	}
	return YES;
}

#pragma mark persistence (MW-3 cont.)
/* Moved bodily from BookWindowController.m, unchanged apart from -pathFromAliasData:/
   -aliasDataFromPath: calls now going through the `controller` outlet
   (those helpers stayed window-side). */

- (id)searchFromBookSettings:(NSString *)path key:(NSString **)key
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	if ([defaults dictionaryForKey:@"BookSettings"]) {
		NSEnumerator *enu = [[defaults dictionaryForKey:@"BookSettings"] objectEnumerator];
		id object;
		while (object = [enu nextObject]) {
			if ([[object objectForKey:@"temppath"] isEqualToString:path]) {
				if ([[[self frontController] pathFromAliasData:[object objectForKey:@"alias"]] isEqualToString:path]) {
					if (key) {
						*key = [[[defaults dictionaryForKey:@"BookSettings"] allKeysForObject:object] objectAtIndex:0];
					}
					return [NSDictionary dictionaryWithDictionary:object];
				}
			}
		}

		NSMutableDictionary *newDic = [NSMutableDictionary dictionaryWithDictionary:[defaults dictionaryForKey:@"BookSettings"]];
		NSEnumerator *enuS = [newDic keyEnumerator];
		id tempKey;
		while (tempKey = [enuS nextObject]) {
			if ([[[self frontController] pathFromAliasData:[[newDic objectForKey:tempKey] objectForKey:@"alias"]] isEqualToString:path]) {
				NSMutableDictionary *newInnerDic = [NSMutableDictionary dictionaryWithDictionary:[newDic objectForKey:tempKey]];
				[newInnerDic setObject:path forKey:@"temppath"];
				[newDic setObject:newInnerDic forKey:tempKey];

				if (key) {
					*key = tempKey;
				}
				[defaults setObject:newDic forKey:@"BookSettings"];
				return [NSDictionary dictionaryWithDictionary:newInnerDic];
			}
		}
	}
	if (key) *key = nil;
	return nil;
}

- (id)searchFromRecentItems:(NSString *)path index:(int *)index
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	if ([defaults arrayForKey:@"RecentItems"]) {
		NSEnumerator *enu = [[defaults arrayForKey:@"RecentItems"] objectEnumerator];
		id object;
		while (object = [enu nextObject]) {
			if ([[object objectForKey:@"temppath"] isEqualToString:path]) {
				if ([[[self frontController] pathFromAliasData:[object objectForKey:@"alias"]] isEqualToString:path]) {
					if (index) {
						*index = (int)[[defaults arrayForKey:@"RecentItems"] indexOfObject:object];
					}
					return [NSDictionary dictionaryWithDictionary:object];
				}
			}
		}

		NSEnumerator *enuS = [[defaults arrayForKey:@"RecentItems"] objectEnumerator];
		while (object = [enuS nextObject]) {
			if ([[[self frontController] pathFromAliasData:[object objectForKey:@"alias"]] isEqualToString:path]) {
				NSMutableArray *newArray = [NSMutableArray arrayWithArray:[defaults arrayForKey:@"RecentItems"]];
				NSMutableDictionary *newInnerDic = [NSMutableDictionary dictionaryWithDictionary:object];
				int tempIndex = (int)[[defaults arrayForKey:@"RecentItems"] indexOfObject:object];
				[newArray removeObjectAtIndex:tempIndex];
				[newInnerDic setObject:path forKey:@"temppath"];
				[newArray insertObject:newInnerDic atIndex:tempIndex];

				if (index) {
					*index = tempIndex;
				}
				[defaults setObject:newArray forKey:@"RecentItems"];
				return [NSDictionary dictionaryWithDictionary:newInnerDic];
			}
		}
	}
	if (index) *index = -1;
	return nil;
}

- (id)searchFromLastPages:(NSString *)path index:(int *)index
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	if ([defaults arrayForKey:@"LastPages"]) {
		NSEnumerator *enu = [[defaults arrayForKey:@"LastPages"] objectEnumerator];
		id object;
		while (object = [enu nextObject]) {
			if ([[object objectForKey:@"temppath"] isEqualToString:path]) {
				if ([[[self frontController] pathFromAliasData:[object objectForKey:@"alias"]] isEqualToString:path]) {
					if (index) {
						*index = (int)[[defaults arrayForKey:@"LastPages"] indexOfObject:object];
					}
					return [NSDictionary dictionaryWithDictionary:object];
				}
			}
		}

		NSEnumerator *enuS = [[defaults arrayForKey:@"LastPages"] objectEnumerator];
		while (object = [enuS nextObject]) {
			if ([[[self frontController] pathFromAliasData:[object objectForKey:@"alias"]] isEqualToString:path]) {
				NSMutableArray *newArray = [NSMutableArray arrayWithArray:[defaults arrayForKey:@"LastPages"]];
				NSMutableDictionary *newInnerDic = [NSMutableDictionary dictionaryWithDictionary:object];
				int tempIndex = (int)[[defaults arrayForKey:@"LastPages"] indexOfObject:object];
				[newArray removeObjectAtIndex:tempIndex];
				[newInnerDic setObject:path forKey:@"temppath"];
				[newArray insertObject:newInnerDic atIndex:tempIndex];

				if (index) {
					*index = (int)[[defaults arrayForKey:@"LastPages"] indexOfObject:object];
				}
				[defaults setObject:newArray forKey:@"LastPages"];
				return [NSDictionary dictionaryWithDictionary:newInnerDic];
			}
		}
	}
	if (index) *index = -1;
	return nil;
}

- (id)searchFromBookSettings:(NSString *)path key:(NSString **)key more:(BOOL)b
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	id searched = [self searchFromBookSettings:path key:key];
	if (searched) {
		return searched;
	} else if (!searched && b && [defaults dictionaryForKey:@"BookSettings"]) {
		NSString *temp;

		NSMutableDictionary *newDic = [NSMutableDictionary dictionaryWithDictionary:[defaults dictionaryForKey:@"BookSettings"]];
		NSEnumerator *enuS = [newDic keyEnumerator];
		id tempKey;

		while (tempKey = [enuS nextObject]) {
			temp = [[self frontController] pathFromAliasData:[[newDic objectForKey:tempKey] objectForKey:@"alias"]];
			if ([[temp lastPathComponent] isEqualToString:[path lastPathComponent]] && ![[NSFileManager defaultManager] fileExistsAtPath:temp]) {

				NSAlert *alert = [[[NSAlert alloc] init] autorelease];
				[alert setMessageText:NSLocalizedString(@"Setting is not found",@"")];
				[alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"Setting of %@ is not found.\nDo you want to use a setting of %@ ?",@""),path,temp]];
				[alert addButtonWithTitle:NSLocalizedString(@"OK",@"")];
				[alert addButtonWithTitle:NSLocalizedString(@"Cancel",@"")];

				if([alert runModal] == NSAlertFirstButtonReturn) {
					/*LastPagesの修正*/
					int lastPagesIndex;
					id lastPage = [self searchFromLastPages:temp index:&lastPagesIndex];
					if (lastPage) {
						NSMutableDictionary *newLastPage = [NSMutableDictionary dictionaryWithDictionary:lastPage];
						NSMutableArray *newLastPagesArray = [NSMutableArray arrayWithArray:[defaults arrayForKey:@"LastPages"]];
						[newLastPage setObject:path forKey:@"temppath"];
						[newLastPage setObject:[[self frontController] aliasDataFromPath:path] forKey:@"alias"];
						[newLastPagesArray removeObjectAtIndex:lastPagesIndex];
						[newLastPagesArray insertObject:newLastPage atIndex:lastPagesIndex];
						[defaults setObject:newLastPagesArray forKey:@"LastPages"];
					}
					/*RecentItemsの修正*/
					int recentItemsIndex;
					id recentItem = [self searchFromRecentItems:temp index:&recentItemsIndex];
					if (recentItem) {
						NSMutableDictionary *newRecentItem = [NSMutableDictionary dictionaryWithDictionary:recentItem];
						NSMutableArray *newRecentItemsArray = [NSMutableArray arrayWithArray:[defaults arrayForKey:@"RecentItems"]];
						[newRecentItem setObject:path forKey:@"temppath"];
						[newRecentItem setObject:[[self frontController] aliasDataFromPath:path] forKey:@"alias"];
						[newRecentItemsArray removeObjectAtIndex:recentItemsIndex];
						[newRecentItemsArray insertObject:newRecentItem atIndex:recentItemsIndex];
						[defaults setObject:newRecentItemsArray forKey:@"RecentItems"];
					}
					/*BookSettingsの修正*/
					NSMutableDictionary *newInnerDic = [NSMutableDictionary dictionaryWithDictionary:[newDic objectForKey:tempKey]];
					[newInnerDic setObject:path forKey:@"temppath"];
					[newInnerDic setObject:[[self frontController] aliasDataFromPath:path] forKey:@"alias"];
					[newDic setObject:newInnerDic forKey:tempKey];

					if (key) {
						*key = tempKey;
					}
					[defaults setObject:newDic forKey:@"BookSettings"];
					return [NSDictionary dictionaryWithDictionary:newInnerDic];
				}
			}
		}
	}
	return nil;
}

- (void)recordClosingBookSettings:(NSString *)path
                              name:(NSString *)name
                             alias:(NSData *)aliasData
                         bookmarks:(NSArray *)bookmarks
                       bookSetting:(NSMutableDictionary *)bookSetting
                              page:(int)page
                   openRecentLimit:(int)openRecentLimit
            alwaysRememberLastPage:(BOOL)alwaysRememberLastPage
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	NSMutableDictionary *dic;
	if (![defaults dictionaryForKey:@"BookSettings"]) {
		dic = [NSMutableDictionary dictionary];
	} else {
		dic = [NSMutableDictionary dictionaryWithDictionary:[defaults dictionaryForKey:@"BookSettings"]];
	}
	id key;
	[self searchFromBookSettings:path key:&key];

	[bookSetting setObject:aliasData forKey:@"alias"];
	[bookSetting setObject:path forKey:@"temppath"];
	if ([bookmarks count]>0) {
		[bookSetting setObject:bookmarks forKey:@"bookmarks"];
	} else if ([bookmarks count]==0) {
		[bookSetting removeObjectForKey:@"bookmarks"];
	}
	if ([bookSetting count]>2) {
		if (!key) {
			key = name;
			int i = 2;
			while ([dic objectForKey:key]) {
				key = [NSString stringWithFormat:@"%@#%i",name,i];
				i++;
			}
			[dic setObject:bookSetting forKey:key];
		} else {
			[dic setObject:bookSetting forKey:key];
		}
		[defaults setObject:dic forKey:@"BookSettings"];
	}

	NSNumber *pageNumber = [NSNumber numberWithInt:page];
	if (openRecentLimit>0) {
		NSMutableArray *newRecentItems;
		if (![defaults arrayForKey:@"RecentItems"]) {
			newRecentItems = [NSMutableArray array];
		} else {
			newRecentItems = [NSMutableArray arrayWithArray:[defaults arrayForKey:@"RecentItems"]];
		}
		int index = 0;
		id object = [self searchFromRecentItems:path index:&index];
		if (object) {
			[newRecentItems removeObjectAtIndex:index];
		}
		while ([newRecentItems count] >= openRecentLimit) {
			[newRecentItems removeLastObject];
		}
		[newRecentItems insertObject:[NSDictionary dictionaryWithObjectsAndKeys:aliasData,@"alias",pageNumber,@"page",path,@"temppath",nil] atIndex:0];
		[defaults setObject:newRecentItems forKey:@"RecentItems"];
	} else {
		[defaults removeObjectForKey:@"RecentItems"];
	}

	if (alwaysRememberLastPage && page > 0) {
		NSMutableArray *lastPages;
		if (![defaults arrayForKey:@"LastPages"]) {
			lastPages = [NSMutableArray array];
		} else {
			lastPages = [NSMutableArray arrayWithArray:[defaults arrayForKey:@"LastPages"]];
		}
		int index;
		id object = [self searchFromLastPages:path index:&index];
		if (object) {
			[lastPages removeObjectAtIndex:index];
		}
		[lastPages addObject:[NSDictionary dictionaryWithObjectsAndKeys:aliasData,@"alias",pageNumber,@"page",path,@"temppath",nil]];
		[defaults setObject:lastPages forKey:@"LastPages"];
	} else if (!alwaysRememberLastPage || page == 0) {
		NSMutableArray *lastPages;
		if (![defaults arrayForKey:@"LastPages"]) {
			lastPages = [NSMutableArray array];
		} else {
			lastPages = [NSMutableArray arrayWithArray:[defaults arrayForKey:@"LastPages"]];
		}
		int index;
		id object = [self searchFromLastPages:path index:&index];
		if (object) {
			[lastPages removeObjectAtIndex:index];
		}
		[defaults setObject:lastPages forKey:@"LastPages"];
	}
}

/* This call site's RecentItems removal has always used a plain
   -pathFromAliasData: comparison instead of -searchFromRecentItems:
   (temppath+alias match) — see the divergence note in AppController.h.
   Kept as an independent, faithful port of
   -[BookWindowController windowWillClose:]'s original body rather than reconciled
   with -recordClosingBookSettings:...'s. */
- (void)recordBookSettingsOnWindowClose:(NSString *)path
                                    name:(NSString *)name
                                   alias:(NSData *)aliasData
                               bookmarks:(NSArray *)bookmarks
                             bookSetting:(NSMutableDictionary *)bookSetting
                                    page:(int)page
                         openRecentLimit:(int)openRecentLimit
                  alwaysRememberLastPage:(BOOL)alwaysRememberLastPage
                   rememberBookSettings:(BOOL)rememberBookSettings
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	NSMutableDictionary *dic;
	if (![defaults dictionaryForKey:@"BookSettings"]) {
		dic = [NSMutableDictionary dictionary];
	} else {
		dic = [NSMutableDictionary dictionaryWithDictionary:[defaults dictionaryForKey:@"BookSettings"]];
	}
	id key;
	[self searchFromBookSettings:path key:&key];

	if (!rememberBookSettings) {
		[bookSetting removeAllObjects];
	}

	[bookSetting setObject:aliasData forKey:@"alias"];
	[bookSetting setObject:path forKey:@"temppath"];
	if ([bookmarks count]>0) {
		[bookSetting setObject:bookmarks forKey:@"bookmarks"];
	} else if ([bookmarks count]==0) {
		[bookSetting removeObjectForKey:@"bookmarks"];
	}
	if ([bookSetting count]>2) {
		if (!key) {
			key = name;
			int i = 2;
			while ([dic objectForKey:key]) {
				key = [NSString stringWithFormat:@"%@#%i",name,i];
				i++;
			}
			[dic setObject:bookSetting forKey:key];
		} else {
			[dic setObject:bookSetting forKey:key];
		}
		[defaults setObject:dic forKey:@"BookSettings"];
	}

	NSNumber *pageNumber = [NSNumber numberWithInt:page];
	if (openRecentLimit>0) {
		NSMutableArray *array;
		if (![defaults arrayForKey:@"RecentItems"]) {
			array = [NSMutableArray array];
		} else {
			array = [NSMutableArray arrayWithArray:[defaults arrayForKey:@"RecentItems"]];
		}
		NSEnumerator *enu = [array objectEnumerator];
		id object;
		while (object = [enu nextObject]) {
			if ([[[self frontController] pathFromAliasData:[object objectForKey:@"alias"]] isEqualToString:path]) {
				[array removeObject:object];
				break;
			}
		}
		while ([array count] >= openRecentLimit) {
			[array removeLastObject];
		}
		[array insertObject:[NSDictionary dictionaryWithObjectsAndKeys:aliasData,@"alias",pageNumber,@"page",path,@"temppath",nil] atIndex:0];
		[defaults setObject:array forKey:@"RecentItems"];
	} else {
		[defaults removeObjectForKey:@"RecentItems"];
	}
	if (alwaysRememberLastPage && page > 0) {
		NSMutableArray *array;
		if (![defaults arrayForKey:@"LastPages"]) {
			array = [NSMutableArray array];
		} else {
			array = [NSMutableArray arrayWithArray:[defaults arrayForKey:@"LastPages"]];
		}
		NSEnumerator *enu = [array objectEnumerator];
		id object;
		while (object = [enu nextObject]) {
			if ([[[self frontController] pathFromAliasData:[object objectForKey:@"alias"]] isEqualToString:path]) {
				[array removeObject:object];
				break;
			}
		}
		[array addObject:[NSDictionary dictionaryWithObjectsAndKeys:aliasData,@"alias",pageNumber,@"page",path,@"temppath",nil]];
		[defaults setObject:array forKey:@"LastPages"];
	} else if (!alwaysRememberLastPage || page == 0) {
		NSMutableArray *lastPages;
		if (![defaults arrayForKey:@"LastPages"]) {
			lastPages = [NSMutableArray array];
		} else {
			lastPages = [NSMutableArray arrayWithArray:[defaults arrayForKey:@"LastPages"]];
		}
		int index;
		id object = [self searchFromLastPages:path index:&index];
		if (object) {
			[lastPages removeObjectAtIndex:index];
		}
		[defaults setObject:lastPages forKey:@"LastPages"];
	}
	[defaults synchronize];
}

@end
