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
	   follows the bar's switch and auto-hide. */
	NSString *pageBarNumber;
	int pageBarNumberMode;
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
/* Draws the position number for a page bar drawn in barRect: centred on it
   and clipped to its width, or just outside it, by pageBarNumberMode. */
-(void)drawPageBarNumberForBarRect:(NSRect)barRect;
/* The page bar plus its number (beside it, or in it and reaching past a
   short bar): the area to redraw when the bar is shown, hidden or changed. */
-(NSRect)pageBarAreaRect;

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
