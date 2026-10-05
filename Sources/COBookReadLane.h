/* COBookReadLane: page reads of one open book, off the main thread
 * (KNOWN_ISSUES #46).
 *
 * The window controller never reads a page that is not ready on the main
 * thread. It works out which pages a display needs (CODisplayPlanFor, below),
 * takes the ones it already has (the read-ahead list, the pages on screen, the
 * image cache), and asks the book's lane for the rest. The lane decodes them on
 * its own serial queue and hands them back on the main thread; the display is
 * then shown from what it was given ("decode first, then replay").
 *
 * One lane per open book. It owns the book's decodeLock: every background
 * decode of the book — the lane's and a detached lookahead's — happens under
 * it, so a re-sort of the page list can tell that no thread is inside the
 * loader (see -[BookWindowController setSortMode:page:]).
 *
 * Requests are tagged with a token. -beginRequest and -cancel move the token
 * on; a job whose token is no longer current stops before its next page and
 * delivers nothing. A delivery is made on the main thread, in the default and
 * modal-panel run-loop modes (not while a menu is tracked), and only if its
 * token is still current when it runs. */

#import <Foundation/Foundation.h>
#include <stdatomic.h>

@class COImageLoader;

#pragma mark display plan

/* What the user asked the window to show. Each one is replayed at commit by the
   legacy body of the same name in BookWindowController. */
typedef enum {
	CODisplayNone = 0,
	CODisplayNext,          /* next page or spread (also the slideshow) */
	CODisplayPrev,          /* -prevPage */
	CODisplayHalfNext,      /* one page on from a spread */
	CODisplayHalfPrev,      /* -halfprevPage */
	CODisplayLast,          /* -goToLast */
	CODisplayTop,           /* to page 0, unless page 0 is already shown */
	CODisplayFirst,         /* -goToFirst: to page 0 */
	CODisplayGoTo,          /* argument: page index (clamped to the book) */
	CODisplaySkip,          /* argument: the skip action's value */
	CODisplayBackSkip,      /* argument: the back-skip action's value */
	CODisplaySwitchSingle,  /* -switchSingle: */
	CODisplayRedisplay,     /* the shown pages again, laid out anew (read mode, spread setting) */
	CODisplayOpenLast       /* a book's first display, on its last page */
} CODisplayAction;

/* The shown state a plan is made from. `nowPage` is the controller's: the
   index after the last page on screen. */
typedef struct {
	int nowPage;
	int count;          /* pages in the book */
	int shown;          /* a page is on screen */
	int spreadShown;    /* two pages are on screen */
	int singleMode;     /* readMode > 1 */
	int loopCheck;      /* LoopCheck preference */
} CODisplayState;

typedef enum {
	CODisplayPlanNothing = 0,   /* the action does nothing in this state */
	CODisplayPlanShow,          /* run the body once `pages` (and the probe's) are on hand */
	CODisplayPlanNextBook,      /* the body would open the next book (-nextFolder) */
	CODisplayPlanPrevBook,      /* ... the previous one (-backFolder) */
	CODisplayPlanPrevBookLast   /* ... the previous one on its last page (-backFolderLast) */
} CODisplayPlanKind;

#define CODisplayPlanMaxPages 6

typedef struct {
	CODisplayPlanKind kind;
	int pageCount;
	int pages[CODisplayPlanMaxPages];   /* ascending, inside [0, count) */
	/* -1, or a page of `pages` whose image decides whether probe+1 is read
	   too: in spread mode a small page that is not the book's last is shown
	   with the next one (-isSmallImage:page:). Set only when probe+1 is a page
	   of the book. */
	int probe;
} CODisplayPlan;

/* The pages the legacy body of `action` reads in `state`. Pure; table-tested in
   tests/engine. */
CODisplayPlan CODisplayPlanFor(CODisplayAction action, CODisplayState state, int argument);

/* Where the skip and back-skip actions start reading: the legacy arithmetic,
   clamped to the book (a skip past the end lands on the last spread). Shared by
   the planner and the bodies so the two cannot disagree. */
int CODisplaySkipStart(int nowPage, int count, int value);
int CODisplayBackSkipStart(int nowPage, int value);

/* Actions that step from the pages on screen. They are ignored while nothing
   is shown (a book whose first page has not arrived yet). */
int CODisplayActionIsRelative(CODisplayAction action);

#pragma mark lane

@interface COBookReadLane : NSObject
{
	COImageLoader *loader;
	NSLock *decodeLock;
	dispatch_queue_t queue;
	_Atomic unsigned int token;
}

/* Retains `aLoader` for as long as the lane lives. */
- (id)initWithLoader:(COImageLoader *)aLoader;

- (COImageLoader *)loader;
/* Held by every background decode of this book (lane jobs and detached
   lookaheads). */
- (NSLock *)decodeLock;

/* The token a delivery must still carry to be delivered. */
- (unsigned int)currentToken;
/* Moves the token on and answers the new one: every job of an earlier token is
   dropped. */
- (unsigned int)beginRequest;
/* Moves the token on: every pending job is dropped. Any thread. */
- (void)cancel;

/* Decodes the pages `indexes` (NSNumbers) in order, each under decodeLock, and
   calls `completion` on the main thread with index -> NSImage for the pages it
   read (NSNull for a page the loader returned nothing for — every page asked
   for is answered), if `requestToken` is still current then. The job stops before its next
   page as soon as the token moves on; a stopped or stale job delivers nothing.
   The lane keeps the loader and itself alive until the delivery has run (or
   been dropped) on the main thread, so the last release of either never happens
   on the lane's queue. */
- (void)readPages:(NSArray *)indexes
			token:(unsigned int)requestToken
	   completion:(void (^)(NSDictionary *images))completion;

/* Queued behind every job already on the lane: takes decodeLock once (so it
   also waits for a lookahead that is decoding), then calls `completion` on the
   main thread if `requestToken` is still current. */
- (void)barrierWithToken:(unsigned int)requestToken completion:(void (^)(void))completion;
@end
