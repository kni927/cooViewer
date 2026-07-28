#import "ThumbnailPanel.h"

@implementation ThumbnailPanel
//-(BOOL)canBecomeKeyWindow{return YES;}
-(void)awakeFromNib
{
	[self setAcceptsMouseMovedEvents:YES];
	[self makeFirstResponder:matrix];
}

- (void)setTarget:(ThumbnailController *)tar
{
	target = tar;
}

- (void)setAction:(SEL)sel
{
	selector = sel;
}
/*
- (void)mouseMoved:(NSEvent *)theEvent
{
	[super mouseMoved:theEvent];
	NSLog(@"kita0");
}
*/
-(void)becomeKeyWindow
{
	[super becomeKeyWindow];

	/* MW-2: this hid the menu bar process-wide whenever the thumbnail
	   panel became key, gated on the DontHideMenuBar default. Both the
	   default and the hand-managed menu bar are gone — native full screen
	   owns menu-bar visibility. */
}

-(void)resignKeyWindow
{
	//[self performClose:self];
	[super resignKeyWindow];
}


/* The thumbnail panel fills the usable area of the screen it is on.
 *
 * MW-2: this used to branch on [NSMenu menuBarVisible] — the legacy
 * fullscreen implementation's process-wide menu-bar flag — and force
 * [[NSScreen mainScreen] frame] with hand-tuned -6/+16 fudges to
 * compensate for the menu bar it was managing itself. Native full screen
 * owns the menu bar, so -visibleFrame gives the correct rect in both
 * states without the fudges, and on the right screen. */
-(NSRect)constrainFrameRect:(NSRect)frameRect toScreen:(NSScreen *)aScreen
{
	NSScreen *screen = aScreen;
	if (!screen) screen = [self screen];
	if (!screen) screen = [NSScreen mainScreen];
	return [screen visibleFrame];
}



- (void)performClose:(id)sender
{
	[super performClose:sender];
	[target performSelector:@selector(clearCell)];
}

- (void)sendEvent:(NSEvent *)theEvent
{
	if ([theEvent type] == NSKeyDown) {
		[target performSelector:@selector(action:) withObject:theEvent];
	} else {
		[super sendEvent:theEvent];
	}
}
/*
- (void)keyDown:(NSEvent *)theEvent
{
	NSLog(@"kita");
	[target performSelector:@selector(action:) withObject:theEvent];
}*/



- (void)scrollWheel:(NSEvent *)theEvent
{
	if (setting == 0) {
		return;
	}
	[target performSelector:@selector(wheelAction:) withObject:theEvent];
}

-(void)wheelSetting:(float)set
{
	setting = set;
}

@end
