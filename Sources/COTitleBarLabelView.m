//
//  COTitleBarLabelView.m
//  cooViewer
//

#import "COTitleBarLabelView.h"
#import "COPageLabel.h"
#import "AccessoryView.h"	/* +fontWithMonospacedDigits: */

/* Space before the name (after the window buttons), between the name and
   the position, and kept free at the window's right edge. */
static const CGFloat COTitleBarLeadingInset = 4;
static const CGFloat COTitleBarNumberGap = 12;
static const CGFloat COTitleBarTrailingInset = 8;

@implementation COTitleBarLabelView

- (void)dealloc
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[number release];
	[numberFont release];
	[super dealloc];
}

- (void)setNumber:(NSString *)string
{
	if (string != number) {
		[number release];
		number = [string copy];
	}
	[self setNeedsDisplay:YES];
}

/* Clicks, drags and double-clicks go to the title bar underneath, so the
   window still moves and zooms as usual. */
- (NSView *)hitTest:(NSPoint)point
{
	return nil;
}

- (BOOL)mouseDownCanMoveWindow
{
	return YES;
}

- (BOOL)isOpaque
{
	return NO;
}

- (void)setNumberFont:(NSFont *)font
{
	NSFont *newFont = [AccessoryView fontWithMonospacedDigits:font];
	if (newFont == numberFont || (newFont && [newFont isEqual:numberFont])) return;
	[numberFont release];
	numberFont = [newFont retain];
	[self setNeedsDisplay:YES];
}

#pragma mark width

/* The accessory places the view after the window buttons and takes its
   width from the view's frame (NSTitlebarAccessoryViewController observes
   it), so the width is kept at "to the window's right edge". */
- (void)fitToWindow
{
	NSWindow *window = [self window];
	if (!window) return;
	CGFloat originX = [self convertPoint:NSZeroPoint toView:nil].x;
	CGFloat width = NSWidth([window frame]) - originX;
	if (width < 0) width = 0;
	if (fabs(width - NSWidth([self frame])) > 0.5) {
		[self setFrameSize:NSMakeSize(width, NSHeight([self frame]))];
	}
	[self setNeedsDisplay:YES];
}

- (void)fitToWindowSoon
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(fitToWindow) object:nil];
	[self performSelector:@selector(fitToWindow) withObject:nil afterDelay:0];
}

- (void)setFrameOrigin:(NSPoint)newOrigin
{
	[super setFrameOrigin:newOrigin];
	[self fitToWindowSoon];
}

- (void)windowStateDidChange:(NSNotification *)notification
{
	[self setNeedsDisplay:YES];
}

- (void)windowDidResize:(NSNotification *)notification
{
	[self fitToWindowSoon];
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow
{
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	NSWindow *old = [self window];
	if (old) {
		[center removeObserver:self name:nil object:old];
	}
	[super viewWillMoveToWindow:newWindow];
}

- (void)viewDidMoveToWindow
{
	[super viewDidMoveToWindow];
	NSWindow *window = [self window];
	if (!window) {
		[NSObject cancelPreviousPerformRequestsWithTarget:self];
		return;
	}
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	[center addObserver:self selector:@selector(windowDidResize:)
				   name:NSWindowDidResizeNotification object:window];
	NSString *names[] = {
		NSWindowDidBecomeMainNotification, NSWindowDidResignMainNotification,
		NSWindowDidBecomeKeyNotification, NSWindowDidResignKeyNotification,
	};
	unsigned i;
	for (i = 0; i < sizeof(names)/sizeof(names[0]); i++) {
		[center addObserver:self selector:@selector(windowStateDidChange:) name:names[i] object:window];
	}
	/* An inactive app dims its titles too. Registered once per window move;
	   removed with everything else in -dealloc. */
	[center removeObserver:self name:NSApplicationDidBecomeActiveNotification object:nil];
	[center removeObserver:self name:NSApplicationDidResignActiveNotification object:nil];
	[center addObserver:self selector:@selector(windowStateDidChange:)
				   name:NSApplicationDidBecomeActiveNotification object:nil];
	[center addObserver:self selector:@selector(windowStateDidChange:)
				   name:NSApplicationDidResignActiveNotification object:nil];
	[self fitToWindowSoon];
}

#pragma mark drawing

- (void)drawRect:(NSRect)dirtyRect
{
	NSWindow *window = [self window];
	NSString *title = [window title];
	if (!window || ([title length] == 0 && [number length] == 0)) return;

	BOOL active = [NSApp isActive] && ([window isMainWindow] || [window isKeyWindow]);
	NSFont *font = [NSFont titleBarFontOfSize:0];
	NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle alloc] init] autorelease];
	[style setLineBreakMode:NSLineBreakByTruncatingMiddle];
	NSDictionary *nameAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
		font, NSFontAttributeName,
		active ? [NSColor windowFrameTextColor] : [NSColor tertiaryLabelColor], NSForegroundColorAttributeName,
		style, NSParagraphStyleAttributeName,
		nil];
	NSDictionary *numberAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
		numberFont ? numberFont : [NSFont monospacedDigitSystemFontOfSize:[font pointSize] weight:NSFontWeightRegular], NSFontAttributeName,
		active ? [NSColor secondaryLabelColor] : [NSColor tertiaryLabelColor], NSForegroundColorAttributeName,
		nil];

	NSSize nameSize = [title length] ? [title sizeWithAttributes:nameAttributes] : NSZeroSize;
	NSSize numberSize = [number length] ? [number sizeWithAttributes:numberAttributes] : NSZeroSize;

	/* In this view's coordinates: the window's centre, and the width up
	   to a little short of the window's right edge. The name is
	   left-aligned and the position centred on the window; a long name is
	   shortened in the middle to end before the position. */
	CGFloat originX = [self convertPoint:NSZeroPoint toView:nil].x;
	CGFloat centreX = NSWidth([window frame])/2 - originX;
	CGFloat available = MIN(NSWidth([self bounds]), NSWidth([window frame]) - originX) - COTitleBarTrailingInset;
	COTitleBarLayout layout = COTitleBarLayoutMake(available, centreX, COTitleBarLeadingInset,
												   ceil(nameSize.width), COTitleBarNumberGap,
												   ceil(numberSize.width));

	CGFloat height = NSHeight([self bounds]);
	if ([title length] && layout.nameWidth > 0) {
		CGFloat h = ceil(nameSize.height);
		NSRect nameRect = NSMakeRect(layout.nameX, floor((height - h)/2), layout.nameWidth, h);
		[title drawInRect:nameRect withAttributes:nameAttributes];
	}
	if ([number length]) {
		CGFloat h = ceil(numberSize.height);
		[number drawAtPoint:NSMakePoint(layout.numberX, floor((height - h)/2)) withAttributes:numberAttributes];
	}
}

@end
