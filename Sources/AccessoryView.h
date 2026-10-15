//
//  AccessoryView.h
//  cooViewer
//
//  Created by coo on 08/02/12.
//  Copyright 2008 coo. All rights reserved.
//

#import <Cocoa/Cocoa.h>

/* Set once +[AccessoryView migrateResolutionMarginInDefaults:] has run. */
extern NSString * const COResolutionMarginMigratedKey;

/* The page position's font for Above bar and Title bar (Preferences ▸
   Page Number ▸ Font), an archived NSFont. In the bar the size follows
   the bar's height instead (COPageBarInBarFontSize). */
extern NSString * const COPageNumberFontKey;

@interface AccessoryView : NSView 
{	
	NSTimer *infoStringTimer;
	NSTimer *accessoryTimer;
	NSDictionary*pageStringAttr;
	
	NSBezierPath *pageBarBezierPath;
	
	
	NSRect pageMoverRect;
	NSRect pageStringRect;
	NSRect infoStringRect;
	BOOL slideshow;
	
	
	BOOL drawAccessory;
	BOOL didFirst;
	
	IBOutlet id controller;
	IBOutlet id imageView;
	
	
	NSPoint pageMargin;
	NSPoint pageBarMargin;
	BOOL pageMover;
	
	BOOL drawPageBar;
	NSPoint mouseOldPoint;
	NSRect pageBarStringRect;
	BOOL pageBarShowThumbnail;
	NSRect pageBarRect;	
	float pageBarWidth;
	float pageBarHeight;
	int pageBarPosition;
	
	NSFont *pageBarFont; 
	NSColor *pageBarFontColor;	
	NSColor *pageBarBGColor;
	NSColor *pageBarBorderColor;
	NSColor *pageBarReadedColor;

	
	NSFont *textFont;
	NSColor *textFontColor;
	NSColor *textBGColor;
	NSColor *textBorderColor;
	
	BOOL autoHidePageBar;
	BOOL autoHidedPageBar;
	BOOL autoHidePageString;
	BOOL autoHidedPageString;
	NSAttributedString *pageString;
	NSAttributedString *infoString;
	/* The separate resolution bar (ResolutionDisplay = Separate bar). It has
	   its own corner, margin and font (ResolutionPosition,
	   Margin_Resolution, ResolutionTextFont, each falling back to the page
	   number's own when unset); colors and auto-hide are the page
	   number's. See -resolutionStringRect. */
	NSAttributedString *resolutionString;
	NSRect resolutionStringRect;
	NSDictionary *resolutionStringAttr;
	NSFont *resolutionFont;
	NSPoint resolutionMargin;
	int resolutionStringPosition;
	
	int tempPageNum;
	int pageStringPosition;

	/* The page position on the page bar ("9-10/20") and where it goes
	   (PageBarNumber, a COPageBarNumberMode). Drawn with the bar, so it
	   follows the bar's switch and auto-hide. Title bar mode draws nothing
	   here (BookWindowController shows it in the title bar). */
	NSString *pageBarNumber;
	int pageBarNumberMode;
	/* PageNumberFont: the number's font above (or below) the bar. */
	NSFont *pageNumberFont;
	/* The file-name status bar: shown with the page bar's auto-hide but
	   not its switch (-setFileNameStatusBar:entries:). */
	BOOL statusBarEnabled;
	NSArray *statusBarEntries;
	/* StatusBarOpacity as an alpha (0-1): the status bar background's. */
	double statusBarAlpha;
}
NSRect COIntRect(NSRect aRect);
-(void)setPreferences;

-(void)drawAccessory;

-(void)mouseMoved:(NSEvent*)theEvent;
-(void)setSlideshow:(BOOL)b;
-(void)setInfoString:(NSString*)string;
-(NSRect)infoStringRect;

-(void)hideAccessory;

-(void)setPageString:(NSString*)string;
-(NSString*)pageString;
-(NSRect)pageStringRect;

-(void)setResolutionString:(NSString*)string;
-(NSRect)resolutionStringRect;
/* Whether a resolution bar at position/margin/font shares the file-name
   HUD's row (and so is laid out beside it). */
+(BOOL)resolutionRowAtPosition:(int)position margin:(NSPoint)margin font:(NSFont*)font
	sharesPageRowAtPosition:(int)pagePosition margin:(NSPoint)pagePosMargin font:(NSFont*)pageFont;
/* Once per profile (COResolutionMarginMigratedKey): a Margin_Resolution
   stored for a bar in the file-name HUD's corner but on another row gets
   the width that -resolutionStringRect no longer adds there, so the bar
   stays where Preferences showed it. */
+(void)migrateResolutionMarginInDefaults:(NSUserDefaults*)defaults;

-(void)setPageBarNumberString:(NSString*)string;
-(void)setPageBarNumberMode:(int)mode;
/* The Page Number font: the stored PageNumberFont, or the default (the
   system font at its regular size) when none is stored or it cannot be
   read. */
+(NSFont*)defaultPageNumberFont;
+(NSFont*)pageNumberFontInDefaults:(NSUserDefaults*)defaults;
/* `font` with monospaced digits where the font has them, so the position
   does not shift sideways from page to page. */
+(NSFont*)fontWithMonospacedDigits:(NSFont*)font;
/* Draws the position number for a page bar drawn in barRect: centred on it
   and clipped to its width, or just outside it, by pageBarNumberMode. */
-(void)drawPageBarNumberForBarRect:(NSRect)barRect;
/* The page bar plus its number (beside it, or in it and reaching past a
   short bar): the area to redraw when the bar is shown, hidden or changed. */
-(NSRect)pageBarAreaRect;
/* The file-name status bar (FileNameLocation = Status bar, ShowNumber on):
   the entries in screen order (left page first), one or two. Disabled,
   nothing is drawn and nothing moves. */
-(void)setFileNameStatusBar:(BOOL)enabled entries:(NSArray*)entries;
/* The full-width bar along the bottom edge (empty when disabled), and how
   far a bottom page bar is raised to sit above it. */
-(NSRect)statusBarRect;
-(float)pageBarStatusBarLift;
/* Draws the status bar with the entries in it, each centred under its
   page (-[CustomImageView shownPageRectsInView:]) and truncated to stay
   within it, so the two never overlap. */
-(void)drawStatusBar;
/* The status bar background's opacity in percent (StatusBarOpacity), for
   the Preferences preview; -setPreferences reads it from the defaults. */
-(void)setStatusBarOpacity:(NSInteger)percent;

/* Page-number text attributes (color, background-dependent shadow) with
   the given font: the page number's with TextFont, the resolution bar's
   with ResolutionTextFont. */
-(NSDictionary*)textAttributesWithFont:(NSFont*)font;

-(void)drawPageBarBubble;
-(void)drawPageBar;
-(NSRect)pageBarRect;
-(NSRect)pageMoverRect;
-(void)drawPageMover:(int)page;
-(BOOL)pageMover;
-(int)tempPageNum;

-(BOOL)isMouseInPageBar;

/* Drop the unretained `controller` / `imageView` outlets before the objects
   behind them are released. See the implementation comment and
   docs/KNOWN_ISSUES.md #36. */
- (void)detachFromWindowController;



@end
