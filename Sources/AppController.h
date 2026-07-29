/* AppController
 *
 * MW-3 (docs/multiwindow-plan.md): the application delegate, split out of
 * Controller so that Controller can become a purely per-window object in
 * later MW steps. Single window today — `controller` is the window
 * registry, with exactly one entry, per MW-3's scope.
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

	/* The window registry (MW-3: still exactly one entry). */
	IBOutlet id controller;

	IBOutlet id prefController;
	IBOutlet id openRecentMenuItem;
	IBOutlet id openSameFolderMenuItem;
	IBOutlet id bookmarkMenuItem;
}

- (void)setupRemoteControl;

/* Exposed so Controller_input.m's -timeredRemoteButtonEvent: (which stays
 * window-side) can read the hold state that -remoteButton:pressedDown:clickCount:
 * (which moved here) maintains. This used to be a file-scope static in
 * Controller_input.m; it cannot stay one now that the two halves of the
 * Apple Remote path live in different .m files. */
- (BOOL)appleRemoteHoldDown;

/* Prevents display sleep while any window's slideshow runs. Started/stopped
 * by Controller's -slideshow: (window-side); owned here because the timer
 * must not be tied to one window controller's lifetime. */
- (void)dontSleepTimerStart;
- (void)dontSleepTimerStop;

- (IBAction)open:(id)sender;
- (IBAction)openTheLastPage:(id)sender;
- (IBAction)preferences:(id)sender;
- (IBAction)clearRecent:(id)sender;

- (id)openRecentMenuItem;
- (id)openSameFolderMenuItem;
- (id)bookmarkMenuItem;

/* MW-4: validates AppController's own items only (Open, Open the last page,
 * Preferences, Clear Recent) — see the .m for why. The book/view actions'
 * titles stay in -[Controller validateMenuItem:], reached via First
 * Responder resolution now that those actions target it, not AppController.
 */
- (BOOL)validateMenuItem:(NSMenuItem *)anItem;

#pragma mark persistence (MW-3 cont.)
/* Single-writer API for the RecentItems/LastPages/BookSettings defaults
 * keys: Controller no longer touches these keys directly, only through the
 * methods below. The three read helpers moved here bodily from Controller;
 * -pathFromAliasData:/-aliasDataFromPath: stay window-side (Alias Manager
 * helpers, out of this task's scope), so these call back through the
 * `controller` outlet for path<->alias resolution.
 *
 * The two write methods are intentionally NOT unified even though their
 * bodies are almost identical, because -[Controller openPage:last:] and
 * -[Controller windowWillClose:] have small pre-existing behavioural
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
 * "oldBookPath" side of -[Controller openPage:last:]. `page` is the
 * already-decremented page number to store; Controller keeps the nowPage
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
 * -[Controller windowWillClose:]. */
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
