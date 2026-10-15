//
//  COPageLabel.h
//  cooViewer
//
//  The text of the page bar's position number and of the file-name HUD,
//  and the one-time move of the page bar's default height. Foundation only,
//  so the engine tests can build it without AppKit.
//

#import <Foundation/Foundation.h>

/* Values of the PageBarNumber preference (Preferences ▸ Page Number ▸
   Show in): where the page position ("9-10/20") is drawn. The stored
   values are those of v1.6.8; only the labels changed (Overlay is shown
   as "Above bar"). */
typedef enum {
	COPageBarNumberInBar = 0,	/* centred inside the page bar (default); size from the bar's height */
	COPageBarNumberOverlay = 1,	/* "Above bar": just outside the bar, on the side away from the window edge (below a top bar) */
	COPageBarNumberOff = 2,
	COPageBarNumberTitleBar = 3	/* centred in the window's title bar, the book name left-aligned */
} COPageBarNumberMode;

/* The stored PageBarNumber as a mode: an unknown value (such as 4, the
   short-lived Status bar choice) is In bar, the default. */
int COPageBarNumberModeFromStored(NSInteger stored);

/* Values of the FileNameLocation preference: where the file-name HUD
   (ShowNumber) is shown. */
typedef enum {
	COFileNameLocationHUD = 0,		/* the corner HUD (default) */
	COFileNameLocationStatusBar = 1	/* a full-width bar along the window's bottom edge */
} COFileNameLocation;

extern NSString * const COFileNameLocationKey;

/* PageBarTitleBarFill (Preferences ▸ Page Bar ▸ Fill title bar), a BOOL,
   default NO: the title bar's background is filled up to the reading
   position (COTitleBarLabelView), on its own or alongside the page bar
   (ShowPageBar). Window chrome only; nothing in full screen. */
extern NSString * const COPageBarTitleBarFillKey;

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

/* The entries of the file-name HUD, one per shown page in the order of
   names: the file name, followed by " (WxH)" when sizes holds a string at
   that index. nil when names is empty. */
NSArray *COFileNameEntries(NSArray *names, NSArray *sizes);

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

/* Title bar mode, in the coordinates of a view that spans the title bar
   from after the window buttons to the right edge: the book name starts
   at `leading` (left-aligned, as a left-aligned title would be), and the
   position is centred on centreX (the window's centre), kept within the
   view. The name is narrowed (nameWidth is then the width to truncate it
   to, possibly 0) so that it ends `gap` before the position. With
   numberWidth 0 the name may use the whole view. */
typedef struct {
	double nameX;
	double nameWidth;
	double numberX;
} COTitleBarLayout;

COTitleBarLayout COTitleBarLayoutMake(double viewWidth, double centreX, double leading,
                                      double nameWidth, double gap, double numberWidth);

/* The name alone, centred on centreX as the system title is (used when the
   title bar is filled but the position is not shown there): kept within
   leading..viewWidth and narrowed to it when longer. numberX is 0. */
COTitleBarLayout COTitleBarCentredNameLayout(double viewWidth, double centreX, double leading,
                                             double nameWidth);

/* The filled part of the title bar for a reading position of `fraction`
   (0..1, clamped) across a span `width` wide: from the left edge when
   fromLeft, else from the right edge (right-to-left books). Whole points;
   width 0 when there is nothing to fill. */
typedef struct {
	double x;
	double width;
} COTitleBarFill;

COTitleBarFill COTitleBarFillMake(double width, double fraction, BOOL fromLeft);

/* The point size of the position number drawn in a page bar of
   barHeight (PageBarSize "height"), for a font whose line height is
   lineHeightPerPoint times its point size: the line fits in the bar with
   about 1 px to spare above and below, inside the border, rounded down to
   a half point; never below 6 pt (a very short bar then cuts the number).
   The bar's height is the user's setting and the number follows it; no
   font setting applies in the bar. A lineHeightPerPoint of 0 or less is
   taken as 1.2. */
double COPageBarInBarFontSize(double barHeight, double lineHeightPerPoint);

/* The file-name status bar: its height for a text of textHeight. */
double COStatusBarHeight(double textHeight);

/* Where the file-name entries go in a status bar barWidth wide, with
   `padding` kept free at each end. Each entry is centred under its page:
   leftMin..leftMax is the left (or only) page's horizontal span in the
   bar's coordinates, rightMin..rightMax the right page's.
   - One entry: centred on its page, narrowed to the bar if needed and
     moved inside it.
   - Two entries: each stays within its page's span, and the two keep
     `gap` apart around the edge the pages share; an entry wider than its
     room is narrowed (the width to truncate it to). Spans that do not lie
     side by side (pages stacked by rotation) fall back to the two halves
     of the bar.
   A width of 0 means the entry is not drawn. */
typedef struct {
	double leftX;
	double leftWidth;
	double rightX;
	double rightWidth;
} COStatusBarLayout;

COStatusBarLayout COStatusBarLayoutMake(double barWidth, double padding, double gap, int count,
                                        double leftMin, double leftMax, double leftWidth,
                                        double rightMin, double rightMax, double rightWidth);

/* How far a bottom page bar (pageBarPosition 2, 3) is raised to sit just
   above a status bar of statusBarHeight (0 when none is shown). */
double COPageBarStatusBarLift(int pageBarPosition, double statusBarHeight);

/* How far the bottom corner HUDs (info, file name, resolution) sit above
   the bottom edge (before their own margin), for a page bar at
   pageBarPosition (0, 1 top; 2, 3 bottom) of pageBarHeight with the
   position shown by `mode` in a text of numberTextHeight, and a status bar
   of statusBarHeight (0 when none). 17 is the old constant, kept as the
   minimum. */
double COBottomHUDOffset(int mode, int pageBarPosition, double pageBarHeight,
                         double numberTextHeight, double statusBarHeight);
