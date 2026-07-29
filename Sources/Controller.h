/* Controller */

#import <Cocoa/Cocoa.h>
#include <stdatomic.h>
#import "ThumbnailController.h"
#import "BookmarkController.h"
#import "PreferenceController.h"
#import "NSString_Compare.h"

#import "COImageLoader.h"

@class AppController;

@interface Controller : NSObject <NSMenuDelegate>
{
	/* MW-3: the application delegate. Owns prefController and the
	   app-level menu-item outlets; Controller reaches them through its
	   accessors. */
	IBOutlet id appController;

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
    IBOutlet id window;
	
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
	
}
- (void)awakeFromNib;

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
- (IBAction)sheetCancel:(id)sender;
- (IBAction)sheetOk:(id)sender;


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

/* Whether a book is currently open, i.e. whether there is anything to show
   in a dock menu / continue-reading sense. Used by -[AppController
   applicationDockMenu:] (MW-3) in place of directly reading imageView. */
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
 * single-writer persistence API); Controller calls [appController ...]. */
/*
- (id)searchFromRecentItems:(NSString*)path index:(int*)index more:(BOOL)b;
- (id)searchFromLastPages:(NSString*)path index:(int*)index more:(BOOL)b;
*/
@end

@interface Controller (Input)
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

@interface Controller(private)
-(void)setCurrentBookPath:(NSString *)new;
-(void)setOldBookPath;
-(void)setCurrentBookPathAndOldBookPath:(NSString *)new;
-(void)checkCurrentFolderUpdated;
@end
