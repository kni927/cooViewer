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
	/* Lookahead threads that have entered the body — incremented after
	   `lock` is taken, so it says "a lookahead is running", not "a lookahead
	   exists". -lockedImageDisplay reads it to decide whether waiting for a
	   second page is worth it. */
	int threadCount;
	/* Lookahead threads that have been *detached* and not yet returned,
	   including one that has not reached -lookahead yet. This is the one
	   -joinLookaheadThreads waits on: `threadCount` cannot answer "is it
	   safe to tear the book down", because a thread blocked on `lock` has
	   not incremented it yet. Written from both the main thread and the
	   lookahead threads. */
	_Atomic int pendingLookaheadCount;
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

	/* v1.6.2: the frame size this window last had while not in native full
	   screen. -frame reports the screen's frame while full screen, so a new
	   window inheriting "the front window's size" needs this instead when
	   the front window is currently full screen. Snapshotted in
	   -windowWillEnterFullScreen:, before AppKit touches the frame for the
	   transition, and seeded to the initial frame in -windowDidLoad so it is
	   always valid even for a window that has never gone full screen. Read
	   through -currentWindowedSize. */
	NSSize lastWindowedSize;

	/* MW-6 item 4: explicit "this window has a book open" state. It replaces
	   the two proxies the code used to test — [[self window] isVisible] and
	   [imageView image] — neither of which is the question being asked:
	   -openPage:last: orders the window front *before* the load starts, so
	   the window is visible while no book is open yet, and imageView's image
	   is a side effect of the display pass rather than controller state.
	   Set when a load completes, cleared when the window's book is torn down
	   in -windowWillClose:. Read through -hasBookOpen. */
	BOOL bookOpen;

	/* KNOWN_ISSUES #33: YES from the moment this window puts up a password
	   sheet until the open it belongs to has finished one way or the other.
	   Deliberately not "is a sheet on screen": it has to stay YES across the
	   run-loop pass between a rejected password and the re-presented sheet,
	   and across the open that follows an accepted one, because
	   -isRestoredBookUnfinished is what stops -[AppController settleLaunch]
	   draining a queued Finder open into the middle of either. Read through
	   -isWaitingForUserInput. */
	BOOL passwordOpenInFlight;

	/* Set by -windowWillClose:. A password sheet's completion handler can run
	   after its window has gone — AppKit dismisses sheets with their parent —
	   and the re-ask a rejected password schedules can fire then too; both
	   check this rather than acting on a torn-down window. */
	BOOL windowClosed;

	/* MW-8 (Step-0 decision 5). A security-scoped NSURL bookmark for the
	   book open in this window, made once when the book is opened rather
	   than at encode time — -encodeRestorableStateWithCoder: runs after
	   every page turn, and creating a bookmark touches the file system.
	   This is the one place the app uses NSURL bookmarks; everything else
	   still goes through the Alias Manager helpers (KNOWN_ISSUES #29). */
	NSData *currentBookBookmark;

	/* The book a restoration decoded for this window, and the state to open
	   it with. `restoredBookURL` is held for as long as the security scope
	   is: it is what -stopAccessingSecurityScopedResource has to be sent to,
	   so it outlives the open. The two flags are what
	   -isAwaitingRestoredBook answers with: `restorationInFlight` covers the
	   window between AppKit asking for it and -restoreStateWithCoder:
	   answering, `restoredBookPending` from there until the book has
	   actually been opened. `restoredBookOpening` covers the open itself,
	   which -isRestoredBookUnfinished needs and the other two do not — see
	   the comment on that method (KNOWN_ISSUES #32). */
	NSURL *restoredBookURL;
	BOOL restoredAccessStarted;
	BOOL restorationInFlight;
	BOOL restoredBookPending;
	BOOL restoredBookOpening;
	int restoredPage;
	int restoredFitScreenMode;
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

/* v1.6.2: this window's current size, in its own terms — the live frame
   size normally, or the last size it had before entering native full
   screen if it is full screen right now. Used by
   -[AppController openBookInNewWindow:] to size a newly created window
   after this one, without ever handing out the full-screen screen size. */
- (NSSize)currentWindowedSize;

/* The book a path opens. A single image file is a *page*, so its book is the
   parent folder (PDFs are books in their own right) — the resolution
   -openPage:last: performs on currentBookPath. Step-0 decision 2's
   "this book is already open" test is keyed on the result, not on the path
   the user picked. */
+ (NSString *)resolvedBookPath:(NSString *)path;

/* MW-5: the Filter panel and its controller moved into BookWindow.xib, so
   the Filter menu item can no longer target the controller directly. It
   targets First Responder now and resolves here. */
- (IBAction)openFilterPanel:(id)sender;

/* Called by -[AppController applicationDidFinishLaunching:] (MW-3): almost
   the entire original delegate method body is window-level. */
- (void)applicationDidFinishLaunchingSetup:(NSNotification *)notification;

- (IBAction)openTheLastPage:(id)sender;
- (IBAction)open:(id)sender;
/* MW-7: opens `path` in *this* window. The entry point AppController uses
   for a window it has just created, so the book-choosing UI can stay app
   level while the opening stays window level. */
- (void)openBookAtPath:(NSString *)path;
- (void)openFromSameDir:(id)sender;
- (void)openFromSameDir:(id)sender last:(BOOL)isLast;
- (void)openFromOpenRecent:(id)sender;
- (void)openPage:(int)page last:(BOOL)last;
/* The second half of -openPage:last:, and the failure tail it shares with a
   cancelled password prompt. Split out for KNOWN_ISSUES #33: an encrypted
   archive's prompt is a sheet now, so the open has to be resumable from that
   sheet's completion handler instead of running to the end in one call.
   `fromFileName` carries the retain -openPage:last: took from currentBookPath;
   whichever of these two finishes the open releases it. */
- (void)openPageWithLoader:(COImageLoader *)newImageLoader
					  page:(int)page
					  last:(BOOL)last
			  fromFileName:(NSString *)fromFileName;
- (void)abandonOpenWithLoader:(COImageLoader *)newImageLoader
				 fromFileName:(NSString *)fromFileName
				  closeWindow:(BOOL)closeWindow;

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
 * indicate the previous attempt was rejected.
 *
 * KNOWN_ISSUES #33: this synchronous form is now only for a *nested* archive —
 * one COImageLoader opens from inside another archive's entries, built without
 * `deferPasswordPrompt`, inside a load that already runs inline. The book this
 * window is opening uses the sheet below instead. */
- (NSString *)askArchivePassword:(COImageLoader *)loader wrongPassword:(BOOL)wrong;

/* Window-modal password prompt for the book this window is opening: no modal
 * loop, so the application's other windows stay live (KNOWN_ISSUES #33). The
 * open continues from the sheet's completion handler — OK retries through
 * -[COImageLoader tryPassword:], Cancel abandons the open without closing the
 * window (KNOWN_ISSUES #30, decision 1). */
- (void)askPasswordForLoader:(COImageLoader *)loader
						page:(int)page
						last:(BOOL)last
				fromFileName:(NSString *)fromFileName
			   wrongPassword:(BOOL)wrong;

/* YES while this window is showing a prompt only a person can dismiss. Read by
 * -[AppController settleLaunch], whose deadline is there to bound machine work
 * and must not be spent on someone typing a password. */
- (BOOL)isWaitingForUserInput;

/* Takes this window's password prompt down as a cancel, so that a quit can
 * proceed, answering whether there was one to take down. Called for every
 * window from -[AppController cancelPasswordPrompts]. */
- (BOOL)cancelPasswordPromptForTermination;


- (NSImage*)loadThumbnailImage:(int)index;
- (NSImage*)loadImage:(int)index;
- (void)lookahead;
- (void)lookaheadAndCompose;
/* Waits for every detached lookahead thread of this window to return, so a
   book can be torn down without one still writing into imageMutableArray /
   cacheArray or reading imageLoader. Bounded — see the .m. */
- (void)joinLookaheadThreads;


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
/* The resolved path of the book open in this window, or nil. Read by
   -[AppController windowControllerShowingBook:] for the de-duplication in
   Step-0 decision 2. */
- (NSString*)currentBookPath;
- (NSDictionary*)imageInfoForClickPoint:(NSPoint)windowPoint;
- (NSArray*)bookmarkArray;
- (id)openSameFolderMenuItem;
- (int)sortMode;
- (int)openLinkMode;

#pragma mark window restoration (MW-8)

/* -[AppController restoreWindowWithIdentifier:state:completionHandler:]
   brackets a restoration with these. Between them the window is neither
   empty nor open: its book has been asked for but not read yet, which is
   what -isAwaitingRestoredBook answers so the window registry does not
   reuse it as an empty window. -endRestoration only clears the "AppKit is
   still deciding" half; a window with a decoded book stays unavailable
   until that book is actually open. */
- (void)beginRestoration;
- (void)endRestoration;
- (BOOL)isAwaitingRestoredBook;

/* KNOWN_ISSUES #32. Whether this window still has restoration work in
   progress, in any of its three stages — AppKit deciding, a decoded book not
   yet opened, or that book's open still running. -[AppController settleLaunch]
   waits on this before it lets a held Finder request through, so it must stay
   YES for the open too: -isAwaitingRestoredBook deliberately goes NO at the
   *start* of -openRestoredBook (the window has to be reusable if the open
   fails), and -openPage:last: spins the run loop, so a drain scheduled with
   -performSelector:afterDelay: can otherwise land in the middle of it. */
- (BOOL)isRestoredBookUnfinished;

/* The page -encodeRestorableStateWithCoder: stores and -openPage:last:
   would be given to come back to it: the first of the pages on screen,
   whereas `nowPage` is the one after the last of them. Same conversion the
   RecentItems/LastPages writers do. */
- (int)restorablePageIndex;

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
