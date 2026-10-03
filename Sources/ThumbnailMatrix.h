/* ThumbnailMatrix */

#import <Cocoa/Cocoa.h>

@interface ThumbnailMatrix : NSMatrix
{
	NSAttributedString *attrString;
	NSPoint lastPoint;
	
	NSRect lastRect;
	
	NSMutableArray *bmarray;
}
- (void)setBookmarkIconAtRow:(int)row column:(int)column left:(BOOL)b;
- (void)removeBookmarkIconAtRow:(int)row column:(int)column;
- (void)resetBookMarkIcon;
@end
