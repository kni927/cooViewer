/* CustomWindow */

#import <Cocoa/Cocoa.h>
#import "CustomImageView.h"

/* The viewer window.
 *
 * Full screen is AppKit's own (MW-2): the window declares
 * NSWindowCollectionBehaviorFullScreenPrimary and everything goes through
 * -toggleFullScreen:. Ask -[NSWindow styleMask] for the current state; this
 * class no longer keeps its own flag.
 *
 * Before MW-2 this implemented full screen by hand — resizing to
 * [[NSScreen mainScreen] frame] regardless of which screen the window was
 * on, forcing that rect from -constrainFrameRect:toScreen:, toggling
 * process-wide [NSMenu setMenuBarVisible:] from half a dozen overrides, and
 * storing the state in a "Fullscreen" user default. All of that is gone. */
@interface CustomWindow : NSWindow
{
	id target;
	SEL selector;

	IBOutlet id controller;
	NSTimer *cursorTimer;
	CustomImageView *view;		/* wired in MainMenu.xib */
}
- (void)keyDown:(NSEvent *)theEvent;

@end
