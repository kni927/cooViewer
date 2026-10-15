//
//  COTitleBarLabelView.h
//  cooViewer
//
//  Title bar mode of the page position (PageBarNumber =
//  COPageBarNumberTitleBar): a view for a left title-bar accessory that
//  spans the title bar from after the window buttons to the right edge and
//  draws the window's title left-aligned (just after the buttons) and the
//  position ("3-4/12") centred on the window in a secondary colour; a long
//  title is shortened in the middle so it ends before the position. The window
//  controller hides the system title while this is installed; the window's
//  own title (Window menu, Dock, accessibility) stays the plain book name.
//
//  Fill title bar (PageBarTitleBarFill): the same view also fills its
//  background, behind the name and the position, with a light grey from
//  its leading end up to the reading position (from the right end for
//  right-to-left books). It spans the title bar from after the window
//  buttons to the right edge, so that is the span the fill measures. Not
//  drawn in full screen, where the title bar is hidden and only slides in
//  with the menu bar (-setInFullScreen:, set by the window controller);
//  there the view draws nothing and the system title is shown instead.
//  With the fill on and the position not in the title bar, the name is
//  centred as the system title is.
//
//  Draws text and flat fills only, never an image: the render path is not
//  involved.
//

#import <Cocoa/Cocoa.h>

@interface COTitleBarLabelView : NSView {
	NSString *number;
	NSFont *numberFont;
	double fillFraction;
	BOOL fillFromLeft;
	BOOL centresName;
	BOOL inFullScreen;
}

/* The position to show after the title; nil shows the title alone. Also
   redraws, so call it after the window's title changes. */
- (void)setNumber:(NSString *)string;

/* The position's font (the Page Number font, PageNumberFont); nil uses
   the title bar's own font size. Digits are made monospaced. */
- (void)setNumberFont:(NSFont *)font;

/* The title-bar fill: the part of the book read (0..1, as the page bar's
   read part); 0 draws no fill. fromLeft is the reading direction. */
- (void)setFillFraction:(double)fraction fromLeft:(BOOL)fromLeft;

/* YES centres the name on the window (the position is not shown here);
   NO keeps it left-aligned, as in Title bar mode. */
- (void)setCentresName:(BOOL)flag;

/* YES while the book window is in (or entering) full screen: draws
   nothing (the controller shows the system title there).
   Set by the window controller: in full screen this view is hosted by a
   separate system window, so [self window] does not say so. */
- (void)setInFullScreen:(BOOL)flag;

@end
