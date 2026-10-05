#import "COBookReadLane.h"
#import "COImageLoader.h"

#pragma mark display plan

static void COPlanAdd(CODisplayPlan *plan, int page, int count)
{
	if (page < 0 || page >= count) return;
	int i;
	for (i = 0; i < plan->pageCount; i++) {
		if (plan->pages[i] == page) return;
	}
	if (plan->pageCount >= CODisplayPlanMaxPages) return;
	/* keep ascending */
	i = plan->pageCount;
	while (i > 0 && plan->pages[i-1] > page) {
		plan->pages[i] = plan->pages[i-1];
		i--;
	}
	plan->pages[i] = page;
	plan->pageCount++;
}

static CODisplayPlan COPlanMake(CODisplayPlanKind kind)
{
	CODisplayPlan plan;
	memset(&plan, 0, sizeof(plan));
	plan.kind = kind;
	plan.probe = -1;
	return plan;
}

/* One page, and in spread mode the one after it if the first turns out small. */
static CODisplayPlan COPlanFrom(int page, CODisplayState s)
{
	CODisplayPlan plan = COPlanMake(CODisplayPlanShow);
	COPlanAdd(&plan, page, s.count);
	if (!s.singleMode && page >= 0 && page+1 < s.count) plan.probe = page;
	return plan;
}

/* The book's last spread, as -lastSpreadStartPage and the lookahead read it:
   the last two pages (one in a one-page book). */
static CODisplayPlan COPlanLastSpread(CODisplayState s)
{
	CODisplayPlan plan = COPlanMake(CODisplayPlanShow);
	int start = s.count - 2;
	if (start < 0) start = 0;
	COPlanAdd(&plan, start, s.count);
	COPlanAdd(&plan, start+1, s.count);
	return plan;
}

static CODisplayPlan COPlanPages(CODisplayState s, int from, int to)
{
	CODisplayPlan plan = COPlanMake(CODisplayPlanShow);
	int page;
	for (page = from; page <= to; page++) COPlanAdd(&plan, page, s.count);
	return plan;
}

/* The start of a book with nothing before it: LoopCheck 0 wraps (to `wrap`),
   1 and 2 go to the previous book, anything else does nothing. */
static CODisplayPlan COPlanBeforeStart(CODisplayState s, CODisplayPlan wrap)
{
	switch (s.loopCheck) {
		case 0: return wrap;
		case 1: return COPlanMake(CODisplayPlanPrevBook);
		case 2: return COPlanMake(CODisplayPlanPrevBookLast);
		default: return COPlanMake(CODisplayPlanNothing);
	}
}

/* -lockedImageDisplay (now -showPagesFromList). */
static CODisplayPlan COPlanNext(CODisplayState s)
{
	int N = s.nowPage, C = s.count;
	if (N < C) return COPlanFrom(N, s);
	if (N == C) {
		switch (s.loopCheck) {
			case 0:
				/* nowPage = 0, then a two-page lookahead, then the display
				   from the list */
				return COPlanPages(s, 0, 1);
			case 1:
			case 2:
				return COPlanMake(CODisplayPlanNextBook);
			default:
				/* stops the slideshow; reads nothing */
				return COPlanMake(CODisplayPlanShow);
		}
	}
	return COPlanMake(CODisplayPlanNothing);
}

/* -prevPage */
static CODisplayPlan COPlanPrev(CODisplayState s)
{
	int N = s.nowPage, C = s.count;
	if (s.singleMode) {
		if (N < 2) return COPlanBeforeStart(s, COPlanPages(s, C-1, C-1));
		return COPlanPages(s, N-2, N-1);
	}
	if (!s.spreadShown) {
		if (N < 2) return COPlanBeforeStart(s, COPlanLastSpread(s));
		if (N == 2) return COPlanPages(s, 0, 1);
		return COPlanPages(s, N-3, N-1);
	}
	if (N < 3) return COPlanBeforeStart(s, COPlanLastSpread(s));
	if (N < 4) return COPlanPages(s, 0, 2);
	return COPlanPages(s, N-4, N-1);
}

/* -halfprevPage */
static CODisplayPlan COPlanHalfPrev(CODisplayState s)
{
	int N = s.nowPage, C = s.count;
	if (s.singleMode) {
		if (N < 2) return COPlanBeforeStart(s, COPlanPages(s, C-1, C-1));
		return COPlanPages(s, N-2, N-1);
	}
	if (!s.spreadShown) {
		if (N < 2) return COPlanBeforeStart(s, COPlanPages(s, C-1, C-1));
		if (N == 2) return COPlanPages(s, 0, 1);
		return COPlanPages(s, N-3, N-1);
	}
	if (N < 3) return COPlanBeforeStart(s, COPlanLastSpread(s));
	return COPlanPages(s, N-3, N-2);
}

int CODisplaySkipStart(int nowPage, int count, int value)
{
	int start = nowPage + value - 2;
	if (start >= count) {
		start = count - 2;
	}
	return start < 0 ? 0 : start;
}

int CODisplayBackSkipStart(int nowPage, int value)
{
	int start = nowPage - (value + 2);
	return start < 0 ? 0 : start;
}

CODisplayPlan CODisplayPlanFor(CODisplayAction action, CODisplayState s, int argument)
{
	int N = s.nowPage, C = s.count;
	if (C <= 0) return COPlanMake(CODisplayPlanNothing);
	switch (action) {
		case CODisplayNext:
			return COPlanNext(s);
		case CODisplayPrev:
			return COPlanPrev(s);
		case CODisplayHalfNext:
			/* From a spread: its second page becomes the first. Otherwise the
			   next page, exactly as Next. */
			if (N < C && s.spreadShown) return COPlanFrom(N-1, s);
			return COPlanNext(s);
		case CODisplayHalfPrev:
			return COPlanHalfPrev(s);
		case CODisplayLast:
			if (N >= C) return COPlanMake(CODisplayPlanNothing);
			if (s.singleMode) return COPlanPages(s, C-1, C-1);
			return COPlanLastSpread(s);
		case CODisplayTop:
			if (s.shown && (s.spreadShown ? N <= 2 : N <= 1)) return COPlanMake(CODisplayPlanNothing);
			return COPlanFrom(0, s);
		case CODisplayFirst:
			return COPlanFrom(0, s);
		case CODisplayGoTo: {
			int page = argument;
			if (page < 0) page = 0;
			else if (page >= C) page = C-1;
			return COPlanFrom(page, s);
		}
		case CODisplaySkip: {
			int start = CODisplaySkipStart(N, C, argument);
			return COPlanPages(s, start, start+2);
		}
		case CODisplayBackSkip: {
			int start = CODisplayBackSkipStart(N, argument);
			return COPlanPages(s, start, start+1);
		}
		case CODisplaySwitchSingle:
			if (s.spreadShown || N == C) return COPlanMake(CODisplayPlanShow);
			if (N > C) return COPlanMake(CODisplayPlanNothing);
			return COPlanPages(s, N, N);
		case CODisplayRedisplay:
			if (!s.shown) return COPlanMake(CODisplayPlanNothing);
			if (s.spreadShown) return COPlanPages(s, N-2, N-1);
			return COPlanFrom(N-1, s);
		case CODisplayOpenLast:
			return COPlanLastSpread(s);
		default:
			return COPlanMake(CODisplayPlanNothing);
	}
}

int CODisplayActionIsRelative(CODisplayAction action)
{
	switch (action) {
		case CODisplayNext:
		case CODisplayPrev:
		case CODisplayHalfNext:
		case CODisplayHalfPrev:
		case CODisplaySkip:
		case CODisplayBackSkip:
		case CODisplaySwitchSingle:
		case CODisplayRedisplay:
			return 1;
		default:
			return 0;
	}
}

#pragma mark lane

/* The run-loop modes a delivery runs in: as an open's continuation does
   (BookWindowController's COOpenResumeModes), the default mode and the
   modal-panel mode, not the event-tracking mode — a page does not change under
   a menu being tracked, but straight after. */
static void COLanePerformOnMain(void (^block)(void))
{
	dispatch_async(dispatch_get_main_queue(), ^{
		[[NSRunLoop mainRunLoop] performInModes:[NSArray arrayWithObjects:NSDefaultRunLoopMode, NSModalPanelRunLoopMode, nil]
										  block:block];
		CFRunLoopWakeUp(CFRunLoopGetMain());
	});
}

@implementation COBookReadLane

- (id)initWithLoader:(COImageLoader *)aLoader
{
	self = [super init];
	if (self) {
		loader = [aLoader retain];
		decodeLock = [[NSLock alloc] init];
		[decodeLock setName:@"COBookReadLane.decodeLock"];
		dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,
																			   QOS_CLASS_USER_INITIATED, 0);
		queue = dispatch_queue_create("jp.coo.cooViewer.bookReadLane", attr);
		atomic_store(&token, 0);
	}
	return self;
}

- (void)dealloc
{
	dispatch_release(queue);
	[decodeLock release];
	[loader release];
	[super dealloc];
}

- (COImageLoader *)loader
{
	return loader;
}

- (NSLock *)decodeLock
{
	return decodeLock;
}

- (unsigned int)currentToken
{
	return atomic_load(&token);
}

- (unsigned int)beginRequest
{
	return atomic_fetch_add(&token, 1) + 1;
}

- (void)cancel
{
	atomic_fetch_add(&token, 1);
}

/* Under manual reference counting a __block object variable is not retained by
   the blocks that use it, so the lane, the index list and the completion are
   retained here and released by the main-thread delivery — never by the
   lane's queue, where a last release would deallocate the lane, and with it
   the loader, off the main thread. */
- (void)readPages:(NSArray *)indexes
			token:(unsigned int)requestToken
	   completion:(void (^)(NSDictionary *images))completion
{
	__block COBookReadLane *lane = [self retain];
	__block NSArray *pages = [indexes copy];
	__block void (^done)(NSDictionary *) = [completion copy];
	dispatch_async(queue, ^{
		__block NSMutableDictionary *images = [[NSMutableDictionary alloc] init];
		for (NSNumber *page in pages) {
			if (atomic_load(&lane->token) != requestToken) break;
			NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
			[lane->decodeLock lock];
			/* Cancelled while it waited for the lock: nothing to read for. */
			if (atomic_load(&lane->token) == requestToken) {
				id image = [lane->loader itemAtIndex:[page intValue]];
				/* A page the loader returned nothing for is still answered
				   (NSNull), so the caller does not ask for it again. */
				[images setObject:(image ? image : [NSNull null]) forKey:page];
			}
			[lane->decodeLock unlock];
			[pool release];
		}
		COLanePerformOnMain(^{
			if (atomic_load(&lane->token) == requestToken && done) {
				done(images);
			}
			[images release];
			[done release];
			[pages release];
			[lane release];
		});
	});
}

- (void)barrierWithToken:(unsigned int)requestToken completion:(void (^)(void))completion
{
	__block COBookReadLane *lane = [self retain];
	__block void (^done)(void) = [completion copy];
	dispatch_async(queue, ^{
		[lane->decodeLock lock];
		[lane->decodeLock unlock];
		COLanePerformOnMain(^{
			if (atomic_load(&lane->token) == requestToken && done) {
				done();
			}
			[done release];
			[lane release];
		});
	});
}

@end
