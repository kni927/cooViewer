
#import <Cocoa/Cocoa.h>
#import "BookWindowController.h"


@interface FullImagePanel : NSPanel {
	id keyArray;
	BookWindowController *target;
	BOOL fitMode;
}
- (void)setFitMode:(BOOL)yes;
-(void)setSelfMaxSize;
@end
