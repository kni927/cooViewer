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

	/* KNOWN_ISSUES #47: the overlay (AccessoryWindow, a child window) has to
	   follow every frame change. Not every change goes through
	   -setFrame:display: below: macOS window tiling (Window > Fill, Move &
	   Resize, drag to a screen edge) sets the frame without calling it, and
	   the overlay kept the old frame. These notifications are posted for
	   every resize and move, whoever makes it. */
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	[center addObserver:self selector:@selector(frameDidChange:)
				   name:NSWindowDidResizeNotification object:self];
	[center addObserver:self selector:@selector(frameDidChange:)
				   name:NSWindowDidMoveNotification object:self];

	/* MW-6 item 1: the frame autosave name moved to
	   -[BookWindowController windowDidLoad]. AppKit still persists and
	   restores the windowed frame (and still correctly ignores frames taken
	   while full screen) — but *which* name a window uses, and whether it
	   restores a saved frame at all or cascades off the previous window, is
	   a per-window decision the window controller makes, not something this
	   class can know. */
}

/* MW-7 item 2 (KNOWN_ISSUES #26). This class owns no object ivars —
   `target`, `controller` and `view` are all borrowed — so the only thing to
   undo is the cursor-hide timer. It is scheduled with target:self and so
   retains this window; being repeats:NO it can only do so for its 3 s
   interval, which means invalidating it here guards a future repeating timer
   rather than making -dealloc reachable. */
- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[cursorTimer invalidate];
	cursorTimer = nil;

	[super dealloc];
}

- (void)setFrame:(NSRect)windowFrame display:(BOOL)displayViews
{
	[super setFrame:windowFrame display:displayViews];
	[view setAccessoryWindowFrame];
}

- (void)frameDidChange:(NSNotification *)notification
{
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
