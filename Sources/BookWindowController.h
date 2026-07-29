/* BookWindowController */

#import <Cocoa/Cocoa.h>
#include <stdatomic.h>
#import "ThumbnailController.h"
#import "BookmarkController.h"
#import "PreferenceController.h"
#import "NSString_Compare.h"

#import "COImageLoader.h"

@class AppController;

@interface BookWindowController : NSWindowController <NSMenuDelegate>
{
	/* MW-3: the application delegate. Owns prefController and the
	   app-level menu-item outlets; BookWindowController reaches them through its
	   accessors. MW-5: no longer an outlet — AppController creates this object
	   and assigns itself via -setAppController: before the nib loads, since
	   the two now live in different nibs. */
	id appController;

	NSMutableDictionary *currentBookSetting;
	int threadCount;
	//NSMutableArray *recentItems;
	//NSMutableDictionary *bookSettings;
	
	
	int sortMode;
	BOOL threadStop;
	int cacheSize;
	NSMutableArray *cacheArray;
	
	//NSWindow *accWindow;
	IBOutlet id progressIndicator;
	int rotateMode;

	BOOL alwaysRememberLastPage;
	
	
	int goToLastPageMode;
	int openLinkMode;
	int openRecentLimit;
	int changeCurrentFolderMode;
	
	COImageLoader *imageLoader;

	int interpolation;
	
	NSMutableArray *marksArray;
	BOOL rememberBookSettings;
	
	
	BOOL pageBar;
	
	NSDictionary *lastInput;
	
	NSMutableArray *keyArray;
	NSMutableArray *keyArrayMode2;
	NSMutableArray *keyArrayMode3;
	NSMutableArray *mouseArray;
	NSMutableArray *mouseArrayMode2;
	NSMutableArray *mouseArrayMode3;
	
	int readMode;
	
	
	
	
	IBOutlet id thumController;
	
	float wheelSensitivity;

	
	int singleSetting;
	
	NSTimer *wheelUpTimer;
	NSTimer *wheelDownTimer;
	IBOutlet id bookmarkController;
	BOOL readSubFolder;
	
    IBOutlet id normalWindow;
	
	int loopCheck;
	
	IBOutlet id fullImagePanel;
    IBOutlet id fullImageView;

	/* MW-5: the Filter panel is per-window now and lives in BookWindow.xib. */
	IBOutlet id filterPanelController;


	/* Archive-load session (MW-1). The COArchive read runs on a
	 * background thread; these are written there and read on the main
	 * thread while the progress sheet's modal loop runs, so they are
	 * atomic. archiveLoadDepth counts nested COImageLoaders (an archive
	 * inside an archive): only depth 0 gets the background thread and
	 * the sheet, inner ones run inline on whatever thread they are on. */
	_Atomic int archiveLoadCancelled;
	_Atomic long long archiveLoadDone;
	_Atomic long long archiveLoadTotal;
	int archiveLoadDepth;
	NSWindow *archiveProgressSheet;
	NSProgressIndicator *archiveProgressBar;
	NSTextField *archiveProgressLabel;
	NSButton *archiveProgressCancelButton;

    //IBOutlet id pageTextField;
	
    IBOutlet id imageView;

	/* MW-5 (item 3): there is no `window` ivar. BookWindowController is an
	   NSWindowController, so the book window lives in the superclass's own
	   storage and every use goes through [self window]. The nib's File's
	   Owner "window" outlet connects through -setWindow:. */


	int maxEnlargement;

	NSUserDefaults *defaults;
	BOOL timerSwitch;
	//BOOL loopSwitch;
	BOOL numberSwitch;
	BOOL resolutionSwitch;
	BOOL fitMode;
	
	
	NSTimer *timer;
	
	
	float sliderValue;
	int nowPage;
	float wheelDeltaAccum;
	
	
	//NSRect fullscreenRect;
	//NSRect leftRect;
	//NSRect rightRect;
	NSData *currentBookAlias;
	NSString *currentBookPath;
	NSString *currentBookName;
	
	NSData *oldBookAlias;
	NSString *oldBookPath;
	NSString *oldBookName;
	
	NSMutableArray *completeMutableArray;
	NSMutableArray *imageMutableArray;
	//id imageMutableArray;
	
	NSMutableArray *bookmarkArray;

	
	
	//NSConditionLock *lock;
	NSLock *lock;
	
	
	NSImage *firstImage,*secondImage;
	
	int fitScreenMode;
	
	int prevPageMode;
	int canScrollMode;
	
	NSDate *lastSameFolderMenuUpdate;

	/* MW-6 item 3: set when this window becomes main while the "Open from
	   same folder" submenu was last built for a different one, and consumed
	   by -menuNeedsUpdate:. The rebuild has to stay lazy — it enumerates the
	   book's parent folder, which is exactly what must not happen on every
	   window activation (see -menuNeedsUpdate:). */
	BOOL sameFolderMenuNeedsRebuild;

	/* MW-6 item 1: this window's slot in AppController's window registry.
	   Assigned by AppController before the nib loads, and the only thing the
	   per-window frame autosave names are keyed on — see
	   -frameAutosaveName:. Always 0 while there is exactly one window. */
	int windowIndex;

	/* MW-6 item 4: explicit "this window has a book open" state. It replaces
	   the two proxies the code used to test — [[self window] isVisible] and
	   [imageView image] — neither of which is the question being asked:
	   -openPage:last: orders the window front *before* the load starts, so
	   the window is visible while no book is open yet, and imageView's image
	   is a side effect of the display pass rather than controller state.
	   Set when a load completes, cleared when the window's book is torn down
	   in -windowWillClose:. Read through -hasBookOpen. */
	BOOL bookOpen;
}
/* MW-5 item 4: the setup that used to run in -awakeFromNib runs here
   instead. -windowDidLoad is NSWindowController's documented hook and runs
   once, after every object in BookWindow.xib is instantiated and connected —
   which -awakeFromNib does not guarantee, since AppKit leaves the order
   between nib objects' -awakeFromNib undefined (KNOWN_ISSUES #19). This
   matters because the body pushes settings into imageView, thumController
   and fullImagePanel. */
- (void)windowDidLoad;

/* Set by AppController right after -initWithWindowNibName:, before the nib
   is loaded, because -windowDidLoad reads it. */
- (void)setAppController:(id)anAppController;

/* MW-6 item 1. Also set by AppController before the nib is loaded: both
   -windowDidLoad and the panel controllers in BookWindow.xib derive their
   frame autosave names from it during nib load. */
- (void)setWindowIndex:(int)index;
- (int)windowIndex;

/* The frame autosave name this window should use for `baseName`. The first
   window keeps the historical unsuffixed name so frames saved by earlier
   versions still restore; later windows get a suffixed one so they do not
   all write over the same saved frame. Panels living in BookWindow.xib are
   per-window and must ask for their name through here. */
- (NSString *)frameAutosaveName:(NSString *)baseName;

/* MW-5: the Filter panel and its controller moved into BookWindow.xib, so
   the Filter menu item can no longer target the controller directly. It
   targets First Responder now and resolves here. */
- (IBAction)openFilterPanel:(id)sender;

/* Called by -[AppController applicationDidFinishLaunching:] (MW-3): almost
   the entire original delegate method body is window-level. */
- (void)applicationDidFinishLaunchingSetup:(NSNotification *)notification;

- (IBAction)openTheLastPage:(id)sender;
- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename;
- (IBAction)open:(id)sender;
- (void)openFromSameDir:(id)sender;
- (void)openFromSameDir:(id)sender last:(BOOL)isLast;
- (void)openFromOpenRecent:(id)sender;
- (void)openPage:(int)page last:(BOOL)last;

/* Archive open progress. Called from COArchive's read, which since MW-1
 * runs on a background thread for a top-level load — this must stay
 * thread-safe and must not touch AppKit. Returns NO to cancel. */
- (BOOL)archiveReadProgress:(long long)done total:(long long)total;

/* Runs `block` (the COArchive read) so that it does not block the UI and
 * does not consume events aimed at anything else. At the outermost level
 * the block is run on a background thread while the main thread drives a
 * modal progress sheet; nested calls run it inline. Called by
 * COImageLoader. `name` labels the sheet. */
- (void)runArchiveLoadNamed:(NSString *)name usingBlock:(void (^)(void))block;
- (IBAction)cancelArchiveLoad:(id)sender;

/* The window sheets raised on behalf of a load should attach to. One
 * window today; the seam exists so MW-5 can make it per-window. */
- (NSWindow *)sheetParentWindow;

/* Modal password prompt for an encrypted archive, called from
 * COImageLoader while opening. Returns the entered password, or nil if
 * the user cancelled (the archive then stays closed). Pass wrong = YES to
 * indicate the previous attempt was rejected. */
- (NSString *)askArchivePassword:(COImageLoader *)loader wrongPassword:(BOOL)wrong;


- (NSImage*)loadThumbnailImage:(int)index;
- (NSImage*)loadImage:(int)index;
- (void)lookahead;
- (void)lookaheadAndCompose;


- (BOOL)isSmallImage:(NSImage *)image page:(int)page;
- (void)composeImage;


- (void)imageDisplay;
- (void)lockedImageDisplay;


- (void)setPreferences;
/* PreferenceController posts PreferencesDidChange (MW-3) instead of
   calling -setPreferences directly. */
- (void)preferencesDidChange:(NSNotification *)notification;
- (void)strongSetBookmark;

- (BOOL)validateMenuItem:(NSMenuItem *)anItem;
/* MW-4: the "Open the last page" branch of -validateMenuItem: moved out to
 * -[AppController validateMenuItem:], which owns that title now that
 * -openTheLastPage: is targeted at AppController. The check still needs
 * this object's window/currentBookPath/defaults state, so the logic stays
 * here behind this accessor rather than exposing those ivars. */
- (BOOL)validateOpenTheLastPageMenuItem;
- (void)setBookmarkMenu;
- (void)setSameFolderMenu;
- (void)setSameFolderMenu:(BOOL)force;
- (void)setOpenRecentMenu;


- (void)setPageTextField;
- (NSString*)pageTextFieldString;
- (IBAction)changeReadModeMenu:(id)sender;
- (IBAction)changeSortModeMenu:(id)sender;
- (void)goBookmark:(id)sender;
- (IBAction)editBookmark:(id)sender;
- (IBAction)deleteSettings:(id)sender;


- (IBAction)fitToScreen:(id)sender;
- (IBAction)fitToScreenWidth:(id)sender;
- (IBAction)fitToScreenWidthDivide:(id)sender;
- (IBAction)noScale:(id)sender;
- (IBAction)rotateRight:(id)sender;
- (IBAction)rotateLeft:(id)sender;
- (IBAction)showFilterPanel:(id)sender;


- (void)viewSet;
- (void)windowWillClose:(NSNotification *)aNotofication;

/* MW-6 item 3. The bookmark menu, the "Open from same folder" submenu and
   the read-mode / sort-mode check-marks are single, shared main-menu objects
   whose contents describe one window's book. They are built when that book
   is opened, which is only correct while there is one window — so they are
   also rebuilt from whichever window is now front. */
- (void)windowDidBecomeMain:(NSNotification *)notification;


- (void)viewDidEndLiveResize:(NSNotification *)aNotification;

- (void)openLink:(NSURL *)url;

- (int)maxEnlargement;
- (int)readMode;
- (BOOL)readFromLeft;
- (BOOL)firstImage;
- (id)image1;
- (id)image2;
- (BOOL)indicator;
- (float)nowPar;
- (int)nowPage;
- (int)pageCount;
- (NSString*)currentImagePath;
- (NSDictionary*)imageInfoForClickPoint:(NSPoint)windowPoint;
- (NSArray*)bookmarkArray;
- (id)openSameFolderMenuItem;
- (int)sortMode;
- (int)openLinkMode;

/* Whether a book is currently open in this window. Added in MW-3 for
   -[AppController applicationDockMenu:]; MW-6 item 4 generalises it into the
   single "a book is open" predicate for this class — see the `bookOpen`
   ivar. */
- (BOOL)hasBookOpen;
/* Exposes the window-side ThumbnailController to -[AppController
   remoteButton:pressedDown:clickCount:] (MW-3). */
- (id)thumController;



- (NSString*)pathFromAliasData:(NSData*)data;
- (NSData*)aliasDataFromPath:(NSString*)path;

- (AliasHandle)aliasFromPath:(NSString *)fullPath;
- (NSData *)dataFromAlias:(AliasHandle)alias;
- (NSString *)pathFromAlias:(AliasHandle)alias;
- (AliasHandle)aliasFromData:(NSData*)data;


/* searchFromBookSettings:key:[more:] / searchFromRecentItems:index: /
 * searchFromLastPages:index: moved to AppController (MW-3 cont.,
 * single-writer persistence API); BookWindowController calls [appController ...]. */
/*
- (id)searchFromRecentItems:(NSString*)path index:(int*)index more:(BOOL)b;
- (id)searchFromLastPages:(NSString*)path index:(int*)index more:(BOOL)b;
*/
@end

@interface BookWindowController (Input)
- (void)timeredRemoteButtonEvent:(NSString*)characters;
- (void)keyAction:(NSEvent*)sender;
- (BOOL)getKeyAction:(unichar)character mod:(int)cMod mode:(int)mode slideshow:(BOOL)slideshow;
- (void)mouseAction:(NSEvent*)sender;
- (void)gestureAction:(NSEvent*)sender moved:(int)moved;
- (void)multiTouchAction:(NSEvent*)sender action:(int)action;
- (BOOL)getMouseAction:(int)button mod:(int)cMod mode:(int)mode left:(BOOL)left;
- (IBAction)contextAction:(id)sender;
- (void)wheelAction:(NSEvent*)event;

- (void)goToPar:(float)par;
- (void)addBookmark;
- (BOOL)isBookmarkedPage:(int)page;
- (BOOL)removeBookmark;
- (void)goTo:(int)page array:(NSArray*)array;
- (void)nextFolder;
- (void)backFolder;
- (void)backFolderLast;
- (void)nextBookmark;
- (void)backBookmark;
- (void)showThumbnail;
- (void)prevPage;
- (void)halfprevPage;
- (void)goToLast;
- (void)goToFirst;
- (void)changeReadMode:(int)mode;
- (void)setSortMode:(int)mode page:(int)p;
- (IBAction)switchSingle:(id)sender;

- (IBAction)viewAtOriginalSizeFirst:(id)sender;
- (IBAction)viewAtOriginalSizeSecond:(id)sender;
- (IBAction)showInFinderFirst:(id)sender;
- (IBAction)showInFinderSecond:(id)sender;

- (void)switchBindWithPage:(int)page;
- (void)switchSingleWithPage:(int)page;
- (void)addBookmarkWithPage:(int)page;
- (BOOL)removeBookmarkWithPage:(int)page;

- (void)nextSubFolder;
- (void)prevSubFolder;

- (void)trashLeft;
- (void)trashRight;
- (void)trashFile:(NSString*)path;

/*
- (IBAction)nextFolder:(id)sender;
- (IBAction)addBookmark:(id)sender;
- (IBAction)backFolder:(id)sender;
- (IBAction)nextBookmark:(id)sender;
- (IBAction)backBookmark:(id)sender;
- (IBAction)showThumbnail:(id)sender;
*/

- (IBAction)slideshow:(id)sender;

- (void)nextOriginal;
- (void)prevOriginal;
@end

@interface BookWindowController(private)
-(void)setCurrentBookPath:(NSString *)new;
-(void)setOldBookPath;
-(void)setCurrentBookPathAndOldBookPath:(NSString *)new;
-(void)checkCurrentFolderUpdated;
@end
