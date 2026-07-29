/* BookmarkController
 *
 * MW-5 (item 5): the per-book half. The app-wide "All Bookmark" browser
 * moved to AllBookmarkController; this class now owns only the Bookmark
 * sheet for the book shown in one window, and moves into BookWindow.xib
 * with the rest of that window's objects.
 */

#import <Cocoa/Cocoa.h>
#import "Controller.h"

@interface BookmarkController : NSObject
{
	IBOutlet id controller;

    IBOutlet id bookmarkPanel;
    IBOutlet id bookmarkTableView;

    IBOutlet id contextMenuItem;

    IBOutlet id newBookmarkTextField;

	/* The window the sheet is attached to. Not an outlet: -editBookmark:
	   always assigns it before the sheet is raised, so the nib connection it
	   used to have (to the one main window) was never read. */
	NSWindow *sheetWindow;

	NSMutableArray *bookmarkArray;

	NSString *directoryPath;
	NSString *bookName;
}

-(void)setPathDic:(NSDictionary*)dic;
-(void)editBookmark:(NSMutableArray*)array;
- (BOOL)validateMenuItem:(NSMenuItem *)anItem;

- (IBAction)deleteRow:(id)sender;
- (IBAction)ok:(id)sender;
- (IBAction)cancel:(id)sender;
- (IBAction)addNewBookmark:(id)sender;
@end
