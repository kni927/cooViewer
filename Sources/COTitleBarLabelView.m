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

- (void)setFillFraction:(double)fraction fromLeft:(BOOL)fromLeft
{
	if (isnan(fraction) || fraction < 0) fraction = 0;
	if (fraction > 1) fraction = 1;
	if (fraction == fillFraction && fromLeft == fillFromLeft) return;
	fillFraction = fraction;
	fillFromLeft = fromLeft;
	[self setNeedsDisplay:YES];
}

- (void)setCentresName:(BOOL)flag
{
	if (flag == centresName) return;
	centresName = flag;
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

/* Light and dark mode: the fill's colour is picked in -drawRect:. */
- (void)viewDidChangeEffectiveAppearance
{
	[super viewDidChangeEffectiveAppearance];
	[self setNeedsDisplay:YES];
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
		/* The fill is left out in full screen. */
		NSWindowWillEnterFullScreenNotification, NSWindowDidEnterFullScreenNotification,
		NSWindowDidExitFullScreenNotification,
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

/* The fill's colour: a light grey over the title bar's own background,
   as a translucent overlay so it works on any title bar material. Light
   mode darkens the bar a little, dark mode lightens it; an inactive window
   gets a lighter (fainter) fill, as its title text is dimmed too. The
   title and the position keep their system colours and stay readable on
   it. */
- (NSColor *)fillColorActive:(BOOL)active
{
	NSAppearanceName name = [[self effectiveAppearance] bestMatchFromAppearancesWithNames:
		[NSArray arrayWithObjects:NSAppearanceNameAqua, NSAppearanceNameDarkAqua, nil]];
	if ([name isEqualToString:NSAppearanceNameDarkAqua]) {
		return [NSColor colorWithWhite:1.0 alpha:(active ? 0.14 : 0.07)];
	}
	return [NSColor colorWithWhite:0.0 alpha:(active ? 0.10 : 0.05)];
}

/* Behind the name and the position: the part read, measured across this
   view (after the window buttons to the right edge). Not in full screen. */
- (void)drawFillActive:(BOOL)active
{
	NSWindow *window = [self window];
	if (fillFraction <= 0 || !window) return;
	if ([window styleMask] & NSWindowStyleMaskFullScreen) return;
	NSRect bounds = [self bounds];
	COTitleBarFill fill = COTitleBarFillMake(NSWidth(bounds), fillFraction, fillFromLeft);
	if (fill.width <= 0) return;
	NSRect rect = NSMakeRect(NSMinX(bounds) + fill.x, NSMinY(bounds), fill.width, NSHeight(bounds));
	[[self fillColorActive:active] set];
	NSRectFillUsingOperation(rect, NSCompositingOperationSourceOver);
}

- (void)drawRect:(NSRect)dirtyRect
{
	NSWindow *window = [self window];
	if (!window) return;
	BOOL active = [NSApp isActive] && ([window isMainWindow] || [window isKeyWindow]);
	[self drawFillActive:active];

	NSString *title = [window title];
	if ([title length] == 0 && [number length] == 0) return;

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
	COTitleBarLayout layout = (centresName && [number length] == 0)
		? COTitleBarCentredNameLayout(available, centreX, COTitleBarLeadingInset, ceil(nameSize.width))
		: COTitleBarLayoutMake(available, centreX, COTitleBarLeadingInset,
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
