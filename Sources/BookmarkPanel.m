#import "BookmarkPanel.h"

@implementation BookmarkPanel


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
	NSString *string = [theEvent characters];
	if ([string length] > 0 && [string characterAtIndex: 0] == NSDeleteCharacter) {
		[target performSelector:selector withObject:theEvent];
		return;
	} else {
        [super keyDown:theEvent];
    }
}


- (void)center
{
	return;
}

@end
