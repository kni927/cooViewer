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
//  Draws text only, never an image: the render path is not involved.
//

#import <Cocoa/Cocoa.h>

@interface COTitleBarLabelView : NSView {
	NSString *number;
}

/* The position to show after the title; nil shows the title alone. Also
   redraws, so call it after the window's title changes. */
- (void)setNumber:(NSString *)string;

@end
