/* AppController
 *
 * MW-3 (docs/multiwindow-plan.md): the application delegate, split out of
 * BookWindowController so that BookWindowController can become a purely
 * per-window object in later MW steps.
 *
 * MW-7: the registry is a real list now. `windowControllers` holds every
 * live BookWindowController in creation order, `frontWindowController` is
 * whichever of them last became main, and -controller — the accessor every
 * app-level caller has always used — answers "the front window" rather than
 * "the window".
 */

#import <Cocoa/Cocoa.h>

#import "AppleRemote.h"
#import "GlobalKeyboardDevice.h"
#import "KeyspanFrontRowControl.h"
#import "MultiClickRemoteBehavior.h"

@class RemoteControl;
@class MultiClickRemoteBehavior;

/* MW-8 / Step-0 decision 5. The NSWindow identifier every book window
   carries, and therefore the identifier AppKit hands back to
   +restoreWindowWithIdentifier:state:completionHandler:. It is one shared
   identifier rather than one per window: the saved state already keeps a
   separate record per window, and which book each record describes comes
   from the coder, not from the identifier. */
extern NSString * const CooViewerBookWindowRestorationIdentifier;

@interface AppController : NSObject <NSWindowRestoration>
{
	RemoteControl *remoteControl;
	MultiClickRemoteBehavior *remoteControlBehavior;
	BOOL appleRemoteHoldDown;

	NSTimer *dontSleepTimer;

	/* The window registry (MW-7). Every live BookWindowController, in
	   creation order; it owns them, and each one is released when its
	   window closes. Never empty while the app runs — see
	   -retireWindowController:. */
	NSMutableArray *windowControllers;

	/* The window that last became main. Not retained: `windowControllers`
	   owns the objects, and this is cleared when the front window is
	   retired. */
	id frontWindowController;

	/* Whether any window has shown a book yet in this session. It is what
	   -applicationShouldTerminateAfterLastWindowClosed: answers with — see
	   the .m for why the question has to be about the session rather than
	   about the window that just closed. */
	BOOL didShowBook;

	/* MW-8: how many windows the system asked to have restored this launch.
	   Counted in +restoreWindowWithIdentifier:state:completionHandler:. */
	int restoredWindowCount;

	/* KNOWN_ISSUES #32. Finder open requests that arrive while restoration is
	   still in flight are held here instead of being acted on, then drained
	   through -openBookInNewWindow: once every restored window has its book —
	   at which point de-duplication can actually see those books. Empty and
	   unused once the launch has settled: after that, -application:openFiles:
	   takes the immediate path it always did. */
	NSMutableArray *pendingLaunchOpenPaths;

	/* NO until the launch's restoration has finished (or the drain deadline
	   has passed). While NO, -application:openFiles: queues; once YES it never
	   goes back, so the post-launch path is unchanged. */
	BOOL launchSettled;

	/* Whether -applicationDidFinishLaunching: has run. -settleLaunch waits for
	   it so the OpenLastFolder fallback still runs at the moment it always
	   has, rather than one run-loop pass earlier because the restoration
	   notification happened to come first. */
	BOOL launchDidFinish;

	/* Absolute time after which -settleLaunch stops waiting for restoration
	   and drains anyway, so a restoration that never completes cannot strand
	   a file the user double-clicked. */
	CFAbsoluteTime launchDrainDeadline;

	/* Whether a Finder request was serviced for this launch. It is what gives
	   an explicit request precedence over the OpenLastFolder fallback. */
	BOOL launchOpenRequestServiced;

	/* -applicationDidFinishLaunching:'s notification, held so -settleLaunch
	   can still hand it to -applicationDidFinishLaunchingSetup: a run-loop
	   pass later. That method does not read it today; passing it on keeps the
	   fallback's signature honest rather than making a future reader wonder
	   why it receives nil. */
	NSNotification *launchNotification;

	/* The app-wide All Bookmark browser (MW-5 item 5). */
	IBOutlet id allBookmarkController;

	IBOutlet id prefController;
	IBOutlet id openRecentMenuItem;
	IBOutlet id openSameFolderMenuItem;
	IBOutlet id bookmarkMenuItem;
}

- (void)setupRemoteControl;

/* Exposed so BookWindowController_input.m's -timeredRemoteButtonEvent: (which stays
 * window-side) can read the hold state that -remoteButton:pressedDown:clickCount:
 * (which moved here) maintains. This used to be a file-scope static in
 * BookWindowController_input.m; it cannot stay one now that the two halves of the
 * Apple Remote path live in different .m files. */
- (BOOL)appleRemoteHoldDown;

/* Prevents display sleep while any window's slideshow runs. Started/stopped
 * by BookWindowController's -slideshow: (window-side); owned here because the timer
 * must not be tied to one window controller's lifetime. */
- (void)dontSleepTimerStart;
- (void)dontSleepTimerStop;

- (IBAction)open:(id)sender;
/* MW-7 / decision A1: the only in-app route to a second window. File ▸ Open
 * still replaces the front window's book (Step-0 decision 3). */
- (IBAction)openInNewWindow:(id)sender;
- (IBAction)openTheLastPage:(id)sender;
/* KNOWN_ISSUES #24: opens the app-wide All Bookmark browser. Targeted here
 * rather than at First Responder — see the .m. */
- (IBAction)allBookmarks:(id)sender;
- (IBAction)preferences:(id)sender;
/* Takes down every window's archive password prompt, answering whether there
 * was one. Called from -[COApplication terminate:], which has to clear them
 * before AppKit's -terminate: runs: AppKit refuses to terminate while a sheet
 * is attached, and never reaches -applicationShouldTerminate:. */
- (BOOL)cancelPasswordPrompts;
- (IBAction)clearRecent:(id)sender;

/* MW-5: the Preferences window's OK/Cancel. Moved off BookWindowController
   when Preferences stayed in MainMenu.xib and that class became the File's
   Owner of BookWindow.xib. */
- (IBAction)sheetOk:(id)sender;
- (IBAction)sheetCancel:(id)sender;

- (id)openRecentMenuItem;
- (id)openSameFolderMenuItem;
- (id)bookmarkMenuItem;

/* The front book window controller, and the app-wide All Bookmark browser.
   MW-5 item 5: the browser is reached through here rather than from a window
   controller, since it outlives any one window. */
- (id)controller;
- (id)allBookmarkController;

#pragma mark window registry (MW-7)

/* Every live window controller, in creation order. */
- (NSArray *)windowControllers;
/* The window controller app-level commands act on: the one whose window last
   became main, falling back to the most recently created. Never nil. */
- (id)frontController;
/* Creates, registers and nib-loads a window controller. The window itself is
   not shown until a book is opened in it. */
- (id)newWindowController;
/* Brings the window already showing `bookPath` to the front, or opens the
   book in a new window. `path` is what the user chose; the "already open"
   test is on the *resolved* book path (Step-0 decision 2). */
- (void)openBookInNewWindow:(NSString *)path;
/* The window showing that book, or nil. `bookPath` must already be resolved
   (+[BookWindowController resolvedBookPath:]) — this is the "already open"
   test itself, not the whole open. Declared for the All Bookmark browser,
   which does the two halves separately (KNOWN_ISSUES #24). */
- (id)windowControllerShowingBook:(NSString *)bookPath;

/* A registered window with no book open, preferring the front one, or nil.
   What a new book is opened into before a window is created for it. MW-8:
   a window the system is in the middle of restoring a book into is not
   empty — its book simply has not been read yet — so it is skipped here, and
   KNOWN_ISSUES #33 adds the window whose open is waiting on a password. */
- (id)emptyWindowController;
- (BOOL)isWindowControllerEmpty:(id)aController;

#pragma mark window restoration (MW-8)

/* How many windows the system asked to have restored this launch. Final
   from -applicationDidFinishLaunching: onwards, and counted by
   +restoreWindowWithIdentifier:state:completionHandler: through the
   method below. */
- (void)noteWindowRestorationRequested;
- (int)restoredWindowCount;

/* KNOWN_ISSUES #32. The one point at which the launch's restoration is known
   to be over: it drains any Finder request held by -application:openFiles:
   and then runs the OpenLastFolder fallback if nothing else opened a book.
   Idempotent and self-rescheduling; kicked from
   -applicationDidFinishRestoringWindows: and -applicationDidFinishLaunching:,
   either of which may come first. */
- (void)settleLaunch;

/* Called by -[BookWindowController windowDidBecomeMain:]. */
- (void)windowControllerDidBecomeFront:(id)aController;
/* Called by -[BookWindowController openPage:last:] once a load has
   completed, which is what arms Step-0 decision 4. */
- (void)windowControllerDidOpenBook:(id)aController;
/* Called by -[BookWindowController windowWillClose:]. Unregisters and
   releases the controller, and returns YES when it did. Returns NO for the
   last remaining window: the app keeps running with no book open (as it
   always has), and that window controller is what File ▸ Open, the dock menu
   and Open the last page reuse. */
- (BOOL)retireWindowController:(id)aController;

/* MW-4: validates AppController's own items only (Open, Open the last page,
 * Preferences, Clear Recent) — see the .m for why. The book/view actions'
 * titles stay in -[BookWindowController validateMenuItem:], reached via First
 * Responder resolution now that those actions target it, not AppController.
 */
- (BOOL)validateMenuItem:(NSMenuItem *)anItem;

#pragma mark persistence (MW-3 cont.)
/* Single-writer API for the RecentItems/LastPages/BookSettings defaults
 * keys: BookWindowController no longer touches these keys directly, only through the
 * methods below. The three read helpers moved here bodily from BookWindowController;
 * -pathFromAliasData:/-aliasDataFromPath: stay window-side (Alias Manager
 * helpers, out of this task's scope), so these call back through the
 * `controller` outlet for path<->alias resolution.
 *
 * The two write methods are intentionally NOT unified even though their
 * bodies are almost identical, because -[BookWindowController openPage:last:] and
 * -[BookWindowController windowWillClose:] have small pre-existing behavioural
 * differences that predate this refactor and are preserved as-is:
 * -windowWillClose:'s RecentItems/LastPages removal loop compares
 * -pathFromAliasData: results directly instead of going through
 * -searchFromRecentItems:/-searchFromLastPages:, and only
 * -windowWillClose: honours `rememberBookSettings`. Reconciling those is
 * out of scope here. */

- (id)searchFromBookSettings:(NSString *)path key:(NSString **)key;
- (id)searchFromBookSettings:(NSString *)path key:(NSString **)key more:(BOOL)more;
- (id)searchFromRecentItems:(NSString *)path index:(int *)index;
- (id)searchFromLastPages:(NSString *)path index:(int *)index;

/* Persists the book being replaced by a newly-opened one — the
 * "oldBookPath" side of -[BookWindowController openPage:last:]. `page` is the
 * already-decremented page number to store; BookWindowController keeps the nowPage
 * ivar and its secondImage-dependent decrement to itself and only passes
 * the resulting value in. */
- (void)recordClosingBookSettings:(NSString *)path
                              name:(NSString *)name
                             alias:(NSData *)aliasData
                         bookmarks:(NSArray *)bookmarks
                       bookSetting:(NSMutableDictionary *)bookSetting
                              page:(int)page
                   openRecentLimit:(int)openRecentLimit
            alwaysRememberLastPage:(BOOL)alwaysRememberLastPage;

/* Persists the book still open in the window being closed —
 * -[BookWindowController windowWillClose:]. */
- (void)recordBookSettingsOnWindowClose:(NSString *)path
                                    name:(NSString *)name
                                   alias:(NSData *)aliasData
                               bookmarks:(NSArray *)bookmarks
                             bookSetting:(NSMutableDictionary *)bookSetting
                                    page:(int)page
                         openRecentLimit:(int)openRecentLimit
                  alwaysRememberLastPage:(BOOL)alwaysRememberLastPage
                   rememberBookSettings:(BOOL)rememberBookSettings;

@end
