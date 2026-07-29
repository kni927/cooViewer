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

/* -[Controller validateMenuItem:] dispatches on 44 localized menu titles,
 * including ones for actions that now target AppController (Open, Open the
 * last page, Preferences, Clear Recent). Splitting it is MW-4's job, not
 * MW-3's; forwarding here preserves today's behaviour exactly (the method's
 * default case already returns YES for any title it does not special-case,
 * which covers Preferences/Clear Recent unchanged). */
- (BOOL)validateMenuItem:(NSMenuItem *)anItem;

@end
