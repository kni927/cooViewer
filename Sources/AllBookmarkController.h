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
}

- (void)setSplitViewPosition:(NSSplitView *)splitView position:(NSString *)position;

- (void)editAllBookmark:(NSMutableArray *)array;

/* KNOWN_ISSUES #20 case 1. Whether the browser is the window AppKit is
   currently running modally — the one state in which a quit has to end the
   browser's session before it can proceed. */
- (BOOL)isRunningModal;
/* Ends the browser's modal session so that a quit can proceed, keeping its
   edits exactly as OK does. Returns YES when there was a session to end; the
   caller then has to let -runModalForWindow: return (one run-loop pass)
   before terminating. */
- (BOOL)endModalForTermination;
/* Forwards to -[NSApp terminate:]. The target AppKit finds for the
   nil-targeted "Quit and Close All Windows" alternate while the browser is
   modal; see the .m. */
- (IBAction)terminate:(id)sender;

- (IBAction)ok:(id)sender;
- (IBAction)cancel:(id)sender;
- (IBAction)addNewBookmark:(id)sender;
- (IBAction)openInFinder:(id)sender;
- (IBAction)openInSelf:(id)sender;
@end
