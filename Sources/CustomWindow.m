#import "CustomWindow.h"
#import "BookWindowController.h"

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

	/* MW-6 item 1: the frame autosave name moved to
	   -[BookWindowController windowDidLoad]. AppKit still persists and
	   restores the windowed frame (and still correctly ignores frames taken
	   while full screen) — but *which* name a window uses, and whether it
	   restores a saved frame at all or cascades off the previous window, is
	   a per-window decision the window controller makes, not something this
	   class can know. */
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
