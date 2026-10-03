//
//  FilterPanelController.h
//  cooViewer
//
//  Created by coo on 2020/01/11.
//

#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>
#import <QuartzCore/QuartzCore.h>

@interface FilterPanelController : NSObject
{
    /* MW-6 item 2: the BookWindowController that owns this panel's window,
       so the panel can ask it for a per-window frame autosave name. Wired to
       File's Owner in BookWindow.xib, the same way BookmarkController's
       `controller` outlet is. */
    IBOutlet id controller;

    IBOutlet id filterPanel;
    IBOutlet id scrollView;
    IBOutlet id popupButton;
    IBOutlet id contentsView;
    
    NSMutableDictionary *filterDic;
    NSMutableArray *selectedFilterKeys;
    NSMutableDictionary *selectedFilters;
    NSMutableDictionary *selectedFilterUIViews;
}
- (BOOL)validateMenuItem:(NSMenuItem *)anItem;
- (IBAction)openFilterPanel:(id)sender;
/* MW-7: ordered out when the owning window is closed and retired. */
- (void)closePanel;
/* L6: the owning window became the main one. If another window's Filter
   panel is on screen, this window's panel takes its place, so the panel
   on screen always shows and edits the front window's filters. */
- (void)ownerWindowBecameMain;
/* L6: tells the owning window's image view the current filters (they are
   posted with the owning BookWindowController as the object); called once
   the view listens, see -[BookWindowController windowDidLoad]. */
- (void)applyFiltersToOwnerWindow;
@end

@interface FilterPanelController(private)
- (void)setUserDefaults;
- (void)sendNotification;
@end
