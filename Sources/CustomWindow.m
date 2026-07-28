#import "CustomWindow.h"
#import "Controller.h"

@implementation CustomWindow

- (BOOL)isInFullScreen
{
	return ([self styleMask] & NSWindowStyleMaskFullScreen) != 0;
}

-(void)awakeFromNib
{
	[self setLevel:NSNormalWindowLevel];
	[self setAcceptsMouseMovedEvents:YES];
	[self setShowsResizeIndicator:NO];

	/* Native full screen: gives the window the standard green-button
	   control, its own Space, and menu-bar reveal-on-hover. */
	[self setCollectionBehavior:[self collectionBehavior] |
	                            NSWindowCollectionBehaviorFullScreenPrimary];

	/* AppKit persists and restores the windowed frame, and correctly
	   ignores frames taken while full screen — which is what the old
	   manual saveFrameUsingName:/setFrameUsingName: pair in -awakeFromNib
	   and -[Controller windowDidMove:/windowDidResize:] was doing by hand.
	   MW-6 revisits this name when there is more than one window. */
	[self setFrameAutosaveName:@"NormalWindow"];
}

- (void)setFrame:(NSRect)windowFrame display:(BOOL)displayViews
{
	[super setFrame:windowFrame display:displayViews];
	[view setAccessoryWindowFrame];
}

- (void)setTarget:(id)tar
{
	target = tar;
}

- (void)setAction:(SEL)sel
{
	selector = sel;
}

- (void)keyDown:(NSEvent *)theEvent
{
	if ([self isInFullScreen]) [NSCursor setHiddenUntilMouseMoves:YES];
	[controller keyAction:theEvent];
}

- (void)cursorHide
{
	if ([self isInFullScreen] && [self isKeyWindow]) {
		[NSCursor setHiddenUntilMouseMoves:YES];
	}
	cursorTimer = nil;
}

- (void)mouseMoved:(NSEvent *)theEvent
{
	if ([self isInFullScreen] && !cursorTimer) {
		cursorTimer = [NSTimer scheduledTimerWithTimeInterval:3
													   target:self
													 selector:@selector(cursorHide)
													 userInfo:NULL
													  repeats:NO];
	}
	[view mouseMoved:theEvent];
}

@end
