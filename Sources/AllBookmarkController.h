/* AllBookmarkController
 *
 * MW-5 (item 5, docs/multiwindow-plan.md): the app-wide half of the old
 * BookmarkController — the "All Bookmark" browser that edits the bookmarks
 * of every book recorded in the BookSettings default.
 *
 * The old class owned two panels with two different lifetimes: the per-book
 * Bookmark sheet, which belongs to a book window and moves into
 * BookWindow.xib, and this browser, which is app-wide and stays in
 * MainMenu.xib. A single nib object cannot own top-level objects in two
 * nibs, so the split has to happen before the nib split, not after it.
 *
 * Reaches the book window through `appController` rather than holding a
 * window-side outlet, since it outlives (and is independent of) any one
 * window.
 */

#import <Cocoa/Cocoa.h>

@interface AllBookmarkController : NSObject
{
	IBOutlet id appController;

	IBOutlet id allBookmarkPanel;
	IBOutlet id allBookmarkTableView;
	IBOutlet id allBookNameTableView;
	IBOutlet id allNewBookmarkTextField;
	IBOutlet id allBookmarkSplitView;

	NSUserDefaults *defaults;

	NSMutableDictionary *allBookmark;
	NSMutableArray *bookNameArray;

	id selectedView;
	NSMutableDictionary *completeAll;
}

- (void)setSplitViewPosition:(NSSplitView *)splitView position:(NSString *)position;

- (void)editAllBookmark:(NSMutableArray *)array;

- (IBAction)ok:(id)sender;
- (IBAction)cancel:(id)sender;
- (IBAction)addNewBookmark:(id)sender;
- (IBAction)openInFinder:(id)sender;
- (IBAction)openInSelf:(id)sender;
@end
