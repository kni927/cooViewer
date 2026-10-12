//
//  COPageLabel.h
//  cooViewer
//
//  The text of the page bar's position number and of the file-name HUD,
//  and the one-time move of the page bar's default height. Foundation only,
//  so the engine tests can build it without AppKit.
//

#import <Foundation/Foundation.h>

/* Values of the PageBarNumber preference: where the page position
   ("9-10/20") is drawn. */
typedef enum {
	COPageBarNumberInBar = 0,	/* centred inside the page bar (default) */
	COPageBarNumberOverlay = 1,	/* just outside the bar, on the side away from the window edge */
	COPageBarNumberOff = 2
} COPageBarNumberMode;

/* The page bar's default height (PageBarSize "height"), and the default it
   had before the position number moved into the bar. */
extern const int COPageBarDefaultHeight;
extern const int COPageBarLegacyDefaultHeight;

/* Set once the PageBarSize migration below has run for this profile. */
extern NSString * const COPageBarHeightMigratedKey;

/* "9/20" for a single page, "9-10/20" for a spread. Pages are 1-based and
   in reading order (firstPage is the earlier page). nil when the numbers do
   not describe a page of the book. */
NSString *COPageBarPositionString(int firstPage, int lastPage, int count);

/* The file-name HUD: one entry per shown page, in screen order (left page
   first), joined with " | ". Each entry is the file name, followed by
   " (WxH)" when sizes is given and holds a string at that index (NSNull or
   a missing index means no size for that page). nil when names is empty. */
NSString *COFileNameHUDString(NSArray *names, NSArray *sizes);

/* The PageBarSize value to store in place of `stored`: the same size with
   the new default height when `stored` still holds the old default height,
   or nil when it should be kept as it is. */
NSDictionary *COMigratedPageBarSize(id stored);

/* Applies COMigratedPageBarSize to the PageBarSize in `store` once:
   nothing happens when COPageBarHeightMigratedKey is already set, and the
   key is set afterwards either way. `store` is NSUserDefaults or, in the
   tests, an NSMutableDictionary. Returns YES when it changed PageBarSize. */
BOOL COMigratePageBarHeight(id store);
