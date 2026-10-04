//
//  AccessoryView.h
//  cooViewer
//
//  Created by coo on 08/02/12.
//  Copyright 2008 coo. All rights reserved.
//

#import <Cocoa/Cocoa.h>

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
