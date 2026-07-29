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

@interface AppController : NSObject
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
- (IBAction)preferences:(id)sender;
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

/* A registered window with no book open, preferring the front one, or nil.
   What a new book is opened into before a window is created for it. */
- (id)emptyWindowController;

/* Called by -[BookWindowController windowDidBecomeMain:]. */
- (void)windowControllerDidBecomeFront:(id)aController;
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
