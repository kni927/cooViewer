#import "BookWindowController.h"
#import "AppController.h"	/* appController outlet accessors (MW-3) */
#import "CustomWindow.h"
#import "BookmarkController.h"
#import "AllBookmarkController.h"	/* MW-5 item 5: app-wide half, reached via appController */
#import "CustomImageView.h"
#import "FullImagePanel.h"
#import "FilterPanelController.h"	/* per-window filters (code review L6) */
#import "RemoteControl.h"	/* kRemoteButton* constants used by the 1.2b14 migration block below */

@implementation BookWindowController
/* MW-5: DIALOG_OK/DIALOG_CANCEL went to AppController with -sheetOk:/
   -sheetCancel:, their only users here. */

/* MW-3 / KNOWN_ISSUES #19 (narrow fix). registerDefaults: and the
 * key/mouse-array "set default if absent" calls used to run in
 * -awakeFromNib, which made their effect on NSUserDefaults race any other
 * nib object's own -awakeFromNib (AppKit does not define the order between
 * them). +initialize runs once, before any instance exists and before the
 * main nib loads, so it cannot race.
 *
 * Only the pure-NSUserDefaults registration moves here. The skip-page
 * substitution and the version-migration blocks in -awakeFromNib stay
 * there: the 1.2b10 block calls the instance-only -pathFromAliasData:
 * (Alias Manager helpers, out of MW-3's scope to change), and all of the
 * migration steps share one `oldVersion` snapshot that must not be split
 * across two run times without risking a fresh-install / old-profile
 * migration bug. */
+ (void)initialize
{
	if (self != [BookWindowController class]) return;

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSMutableDictionary *appDefault = [NSMutableDictionary dictionary];

	float wheelSensitivity = 0.1;  // default: highest sensitivity (slider at max/high)

	[appDefault setObject:[NSNumber numberWithBool:YES] forKey:@"OpenLastFolder"];
	[appDefault setObject:[NSNumber numberWithFloat:wheelSensitivity] forKey:@"WheelSensitivity"];

	[appDefault setObject:[NSNumber numberWithInt:0] forKey:@"PrevPageMode"];
	[appDefault setObject:[NSNumber numberWithInt:0] forKey:@"CanScrollMode"];
	[appDefault setObject:[NSNumber numberWithInt:2] forKey:@"PrevPagePageBarPositionMode"];

	[appDefault setObject:[NSNumber numberWithBool:YES] forKey:@"ShowPageBar"];
	[appDefault setObject:[NSNumber numberWithBool:YES] forKey:@"ShowNumber"];

	/* ResolutionDisplay replaced the ShowResolution checkbox. A profile that
	   has no ResolutionDisplay yet keeps what it showed: ShowResolution NO →
	   Off, YES → In page number. ShowResolution is read here and nowhere
	   else, and is no longer registered, so the check sees only a value the
	   user's profile actually holds; without one, the registered default
	   (In page number) applies, as ShowResolution's registered YES did. Done
	   before -registerDefaults: so that default cannot mask an absent key. */
	if (![defaults objectForKey:@"ResolutionDisplay"]) {
		id showResolution = [defaults objectForKey:@"ShowResolution"];
		if (showResolution) {
			[defaults setInteger:([showResolution boolValue] ? COResolutionDisplayInPageNumber : COResolutionDisplayOff)
						  forKey:@"ResolutionDisplay"];
		}
	}
	[appDefault setObject:[NSNumber numberWithInt:COResolutionDisplayInPageNumber] forKey:@"ResolutionDisplay"];

	[appDefault setObject:[NSNumber numberWithInt:10] forKey:@"OpenRecentLimit"];

	[appDefault setObject:[NSNumber numberWithInt:NO] forKey:@"IgnoreImageDpi"];

	[defaults registerDefaults:appDefault];

	if (![defaults arrayForKey:@"KeyArray"]) [PreferenceController setDefaultKeyArray];
	if (![defaults arrayForKey:@"KeyArrayMode2"]) [PreferenceController setDefaultKeyArrayMode2];
	if (![defaults arrayForKey:@"KeyArrayMode3"]) [PreferenceController setDefaultKeyArrayMode3];
	if (![defaults arrayForKey:@"MouseArray"]) [PreferenceController setDefaultMouseArray];
	if (![defaults arrayForKey:@"MouseArrayMode2"]) [PreferenceController setDefaultMouseArrayMode2];
	if (![defaults arrayForKey:@"MouseArrayMode3"]) [PreferenceController setDefaultMouseArrayMode3];
}

/*
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[lock lock];
	
	[lock unlock];
	[pool release];
	[NSThread exit];
 
 
 [NSThread detachNewThreadSelector:@selector(lookaheadThread) toTarget:self withObject:nil];
	*/

/*
 NSTimeInterval start,stop,elapsed;
 start=[NSDate timeIntervalSinceReferenceDate];
 //処理
 stop=[NSDate timeIntervalSinceReferenceDate];
 elapsed=stop-start;
 NSLog(@"%f",elapsed);
 */

/* Set before the nib is loaded (see -[AppController awakeFromNib]), because
   -windowDidLoad below reads it. */
- (void)setAppController:(id)anAppController
{
	appController = anAppController;
}

/* MW-7 item 2 (KNOWN_ISSUES #26). Until MW-7 a window controller lived for
   the whole run of the app, so it had no -dealloc at all; now every closed
   window that is not the last one destroys one, along with everything below.

   Not released here: `appController` and `defaults` are borrowed, and every
   IBOutlet points at an object in BookWindow.xib — NSWindowController owns
   that nib's top-level objects and releases them, and the rest are subviews
   released with their window. `lastInput` is declared owning but nothing in
   this class ever assigns it (it is PreferenceController that keeps one of
   the same name); released anyway, as -release on nil costs nothing.

   The three timers are scheduled with target:self, so the run loop retains
   this object until they fire and -dealloc cannot run while one is pending
   — the slideshow timer in particular repeats, so it would keep the window
   controller alive for ever. -windowWillClose: already invalidates it;
   these calls are what makes that guaranteed rather than incidental. */
- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	/* MW-8. The pending -openRestoredBook a restoration leaves behind is
	   cancelled in -windowWillClose:, not here: the run loop retains this
	   object until such a request fires, so -dealloc cannot run while one is
	   outstanding — the same reason the timers below are invalidated
	   there. */
	[self releaseRestoredBookAccess];
	[currentBookBookmark release];

	[timer invalidate];
	timer = nil;
	[wheelUpTimer invalidate];
	wheelUpTimer = nil;
	[wheelDownTimer invalidate];
	wheelDownTimer = nil;

	[keyArray release];
	[keyArrayMode2 release];
	[keyArrayMode3 release];
	[mouseArray release];
	[mouseArrayMode2 release];
	[mouseArrayMode3 release];
	[lastInput release];

	[imageLoader release];
	[completeMutableArray release];
	[imageMutableArray release];
	[cacheArray release];
	[bookmarkArray release];
	[marksArray release];
	[currentBookSetting release];

	[firstImage release];
	[secondImage release];

	[currentBookPath release];
	[currentBookName release];
	[currentBookAlias release];
	[oldBookPath release];
	[oldBookName release];
	[oldBookAlias release];

	[lastSameFolderMenuUpdate release];
	/* The progress bar, label and cancel button are subviews of this
	   window's content view and go with it. */
	[archiveProgressSheet release];

	[lock release];
	[cacheLock release];

	[super dealloc];
}

/* MW-7. The one place that decides what "the book at this path" means; both
   -openPage:last: (which then remembers the file it was pointed at, so it
   can open on that page) and AppController's already-open check go through
   it, so the two cannot drift apart. */
+ (NSString *)resolvedBookPath:(NSString *)path
{
	if ([[NSImage imageFileTypes] containsObject:[[path pathExtension] lowercaseString]]
		&& [[path pathExtension] compare:@"pdf" options:NSCaseInsensitiveSearch] != NSOrderedSame) {
		return [path stringByDeletingLastPathComponent];
	}
	return path;
}

#pragma mark per-window identity (MW-6 item 1)

/* Where the second and later windows are placed. NSZeroPoint means "nothing
   has cascaded yet", which is exactly what -cascadeTopLeftFromPoint: wants:
   given NSZeroPoint it leaves the window where it is and just returns the
   point the next window should use. So the first window keeps its restored
   frame and still seeds the cascade for the ones after it. */
static NSPoint gNextWindowCascadePoint;

- (void)setWindowIndex:(int)index
{
	windowIndex = index;
}

- (int)windowIndex
{
	return windowIndex;
}

- (NSString *)frameAutosaveName:(NSString *)baseName
{
	if (windowIndex == 0) {
		return baseName;
	}
	return [NSString stringWithFormat:@"%@-%i",baseName,windowIndex+1];
}

/* MW-5 item 4. This body was -awakeFromNib until BookWindowController became
   the File's Owner of its own nib. -windowDidLoad is the documented
   NSWindowController hook: it runs once, after the whole of BookWindow.xib is
   instantiated and connected, so the pushes into imageView / thumController /
   fullImagePanel below no longer race those objects' own -awakeFromNib.
   AppKit does not order -awakeFromNib between nib objects — the same hazard
   as KNOWN_ISSUES #19. */
- (void)windowDidLoad
{
	[super windowDidLoad];

	threadCount = 0;
	imageLoader = nil;
	wheelUpTimer = nil;
	wheelDownTimer = nil;
	
	lock = [[NSLock allocWithZone:NULL] init];
	cacheLock = [[NSLock alloc] init];
	//lock = [[NSConditionLock allocWithZone:NULL] initWithCondition:0];
	//composeLock = [[NSLock allocWithZone:NULL] init];
	
	[imageView setTarget:self];
	/* The view listens to this window's Filter panel only from -setTarget:
	   on, after the panel restored the saved filters in -awakeFromNib, so
	   they are handed over again now. */
	[filterPanelController applyFiltersToOwnerWindow];
	/* v1.6.5: files dropped on the page open here, routed like a Finder open
	   (see -openDroppedPaths:). Registering for drags adds the dragging
	   destination callbacks only; mouse handling is unchanged. The overlay
	   above the page (AccessoryWindow) ignores mouse events, so drags reach
	   this view. */
	[imageView registerForDraggedTypes:[NSArray arrayWithObject:NSPasteboardTypeFileURL]];

	/* MW-6 item 1: window placement. The frame used to be autosaved under one
	   shared name, set in -[CustomWindow awakeFromNib] — with more than one
	   window that means every window restores onto the same rectangle and
	   whichever moved last overwrites the others' saved frame. The first
	   window keeps that name (and therefore the frame users already have
	   saved) while every window after it cascades down-right from the
	   previous one instead.

	   We cascade by hand rather than through NSWindowController's own
	   -shouldCascadeWindows, which only acts from -showWindow: — this app
	   shows the book window with -makeKeyAndOrderFront: (see
	   -openPage:last:), so that machinery would never run. Turned off
	   explicitly so the two can never both apply. */
	[self setShouldCascadeWindows:NO];
	if (windowIndex == 0) {
		[[self window] setFrameAutosaveName:[self frameAutosaveName:@"NormalWindow"]];
	}
	gNextWindowCascadePoint = [[self window] cascadeTopLeftFromPoint:gNextWindowCascadePoint];

	/* v1.6.2: seeded here so a window that never enters full screen still
	   has a valid answer to -currentWindowedSize. Restoration (if any) and
	   the autosave/cascade placement above have already run by this point,
	   so this is the window's real starting size, not the raw nib default. */
	lastWindowedSize = [[self window] frame].size;

	/* MW-8 (Step-0 decision 5). The identifier is what makes AppKit save
	   this window's state at all, and the restoration class is what it calls
	   to get the window back; both have to be set before the window is ever
	   shown. The frame, and whether the window was in native full screen,
	   are the window's own restorable state and are handled by AppKit —
	   -encodeRestorableStateWithCoder: below adds only the book. */
	[[self window] setIdentifier:CooViewerBookWindowRestorationIdentifier];
	[[self window] setRestorationClass:[AppController class]];

	/* "Open from same folder" submenu is populated lazily (on menuNeedsUpdate:)
	   to avoid touching the parent folder — and triggering macOS folder-access
	   permission prompts — every time a book is opened. We keep one persistent
	   NSMenu instance here so its delegate survives across refreshes. */
	if (![[appController openSameFolderMenuItem] submenu]) {
		[[appController openSameFolderMenuItem] setSubmenu:[[[NSMenu alloc] init] autorelease]];
	}
	[[[appController openSameFolderMenuItem] submenu] setAutoenablesItems:NO];
	[[[appController openSameFolderMenuItem] submenu] setDelegate:self];



	defaults = [NSUserDefaults standardUserDefaults];

	/* registerDefaults: and the key/mouse-array "set default if absent"
	   calls now run in +initialize, before this method can ever run — see
	   the comment there. */
	fitScreenMode = 0;
	rotateMode=0;

	keyArray = [[NSMutableArray alloc] initWithArray:[defaults arrayForKey:@"KeyArray"]];
	keyArrayMode2 = [[NSMutableArray alloc] initWithArray:[defaults arrayForKey:@"KeyArrayMode2"]];
	keyArrayMode3 = [[NSMutableArray alloc] initWithArray:[defaults arrayForKey:@"KeyArrayMode3"]];

	mouseArray = [[NSMutableArray alloc] initWithArray:[defaults arrayForKey:@"MouseArray"]];
	mouseArrayMode2 = [[NSMutableArray alloc] initWithArray:[defaults arrayForKey:@"MouseArrayMode2"]];
	mouseArrayMode3 = [[NSMutableArray alloc] initWithArray:[defaults arrayForKey:@"MouseArrayMode3"]];
	
	
	int skipPage = (int)[defaults integerForKey:@"SkipPage"];
	if (skipPage == 0) {
		skipPage = 10;
	}
	
	/* Indexed loops, not enumerators: an entry is replaced in place, and
	   mutating an array while an enumerator walks it raises (code review
	   L8). indexOfObject: also found the first *equal* entry, not this one. */
	id dic;
	id newDic;
	NSUInteger index;
	for (index = 0; index < [keyArray count]; index++) {
		dic = [keyArray objectAtIndex:index];
		if (![dic valueForKey:@"value"]) {
			switch ([[dic objectForKey:@"action"] intValue]) {
				case 13: case 14:
					newDic = [NSMutableDictionary dictionaryWithDictionary:dic];
					[newDic setObject:[NSNumber numberWithInt:skipPage] forKey:@"value"];
					[keyArray replaceObjectAtIndex:index withObject:newDic];
					break;
				default:
					break;
			}
		}
	}
	[defaults setObject:keyArray forKey:@"KeyArray"];
	for (index = 0; index < [mouseArray count]; index++) {
		dic = [mouseArray objectAtIndex:index];
		if (![dic valueForKey:@"value"]) {
			switch ([[dic objectForKey:@"action"] intValue]) {
				case 5: case 19: case 20:
					newDic = [NSMutableDictionary dictionaryWithDictionary:dic];
					[newDic setObject:[NSNumber numberWithInt:skipPage] forKey:@"value"];
					[mouseArray replaceObjectAtIndex:index withObject:newDic];
					break;
				default:
					break;
			}
		}
	}
	[defaults setObject:mouseArray forKey:@"MouseArray"];
	
#pragma mark normal
	 if (![defaults dictionaryForKey:@"BookSettings"]) {
		 [defaults setObject:[NSMutableDictionary dictionary] forKey:@"BookSettings"];
	 }
	 //bookSettings = [[NSMutableDictionary dictionaryWithDictionary:[defaults dictionaryForKey:@"BookSettings"]] retain];
	 if (![defaults arrayForKey:@"RecentItems"]) {
		 [defaults setObject:[NSMutableArray array] forKey:@"RecentItems"];
	 }
	 //recentItems = [[NSMutableArray arrayWithArray:[defaults arrayForKey:@"BookSettings"]] retain];
		 
	 
	interpolation = (int)[defaults integerForKey:@"Interpolation"];
	[imageView setInterpolation:interpolation];
	[defaults setInteger:interpolation forKey:@"Interpolation"];
    BOOL useCalayer = [defaults boolForKey:@"UseCALayer"];
    [imageView setUseCalayer:useCalayer];
    [defaults setBool:useCalayer forKey:@"UseCALayer"];
	
	
	/* A negative value would make the trim test (count > cacheSize+4)
	   compare against a huge unsigned number and never trim (code review
	   L11). */
	cacheSize = MAX(0, (int)[defaults integerForKey:@"ImageCache"]);
	[defaults setInteger:cacheSize forKey:@"ImageCache"];
	int thumbnailCache = (int)[defaults integerForKey:@"ThumbnailCache"];
	[defaults setInteger:thumbnailCache forKey:@"ThumbnailCache"];
	
	/*history*/
	alwaysRememberLastPage = [defaults boolForKey:@"AlwaysRememberLastPage"];
	[defaults setBool:alwaysRememberLastPage forKey:@"AlwaysRememberLastPage"];
	
	goToLastPageMode = (int)[defaults integerForKey:@"GoToLastPage"];
	[defaults setInteger:goToLastPageMode forKey:@"GoToLastPage"];
	openRecentLimit = (int)[defaults integerForKey:@"OpenRecentLimit"];
	
	/*loupe*/
	int loupeSize = (int)[defaults integerForKey:@"LoupeSize"];
	if (!loupeSize) loupeSize = 150;
	[defaults setInteger:loupeSize forKey:@"LoupeSize"];
	float loupeRate = [defaults floatForKey:@"LoupeRate"];
	if (!loupeRate) loupeRate = 1.0;
	[defaults setFloat:loupeRate forKey:@"LoupeRate"];
	/*view*/
	NSColor *viewBackGround;
	if ([defaults objectForKey:@"ViewBackGroundColor"]) {
		viewBackGround = [NSUnarchiver unarchiveObjectWithData:[defaults objectForKey:@"ViewBackGroundColor"]];
	} else {
		viewBackGround = [NSColor blackColor];
	}
	[[self window] setBackgroundColor:viewBackGround];
    viewBackGround = [viewBackGround colorWithAlphaComponent:1];

	/* MW-2: the "Fullscreen" default and the menu item's check-mark are
	   gone. Full screen is AppKit's own state now, read from the window's
	   style mask, and the Window menu carries the standard
	   Enter/Exit Full Screen item instead. */
	
	
	
	
	
	BOOL fitOriginal = [defaults boolForKey:@"FitOriginal"];
	[fullImagePanel setFitMode:fitOriginal];
	[defaults setBool:fitOriginal forKey:@"FitOriginal"];
	
	
	readMode = (int)[defaults integerForKey:@"ReadMode"];
	[defaults setInteger:readMode forKey:@"ReadMode"];
	

	
	
	rememberBookSettings = [defaults boolForKey:@"RememberBookSettings"];
	[defaults setBool:rememberBookSettings forKey:@"RememberBookSettings"];
	
	
	NSDictionary *thumbnail = [defaults dictionaryForKey:@"Thumbnail"];
	if (!thumbnail) thumbnail = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:2],@"row",[NSNumber numberWithInt:3],@"column",nil];
	
	[thumController setCellRow:[[thumbnail objectForKey:@"row"] intValue] 
						column:[[thumbnail objectForKey:@"column"] intValue]];
	[defaults setObject:thumbnail forKey:@"Thumbnail"];

	
	
	
	sliderValue = [defaults floatForKey:@"SlideshowDelay"];
	loopCheck = (int)[defaults integerForKey:@"LoopCheck"];
	
	
	pageBar = [defaults boolForKey:@"ShowPageBar"];
	if (![defaults dictionaryForKey:@"PageBarSize"]) {
		[defaults setObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:200],@"width",[NSNumber numberWithInt:15],@"height",nil]
					 forKey:@"PageBarSize"];
	}
	
	numberSwitch = [defaults boolForKey:@"ShowNumber"];
	resolutionDisplay = (int)[defaults integerForKey:@"ResolutionDisplay"];
	maxEnlargement = (int)[defaults integerForKey:@"MaxEnlargement"];
	
	
	singleSetting = (int)[defaults integerForKey:@"SingleSetting"];
	if (!singleSetting) {
		singleSetting = 740;
	}
	[defaults setInteger:singleSetting forKey:@"SingleSetting"];
	
	
	readSubFolder = [defaults boolForKey:@"ReadSubFolder"];
	
	wheelSensitivity = [defaults floatForKey:@"WheelSensitivity"];
		[imageView wheelSetting:wheelSensitivity];
		[thumController wheelSetting:wheelSensitivity];
	
	prevPageMode = (int)[defaults integerForKey:@"PrevPageMode"];
	canScrollMode = (int)[defaults integerForKey:@"CanScrollMode"];

	
	[defaults setFloat:sliderValue forKey:@"SlideshowDelay"];
	[defaults setFloat:wheelSensitivity forKey:@"WheelSensitivity"];
	
	[defaults setInteger:loopCheck forKey:@"LoopCheck"];
	[defaults setBool:numberSwitch forKey:@"ShowNumber"];
	[defaults setInteger:maxEnlargement forKey:@"MaxEnlargement"];
	[defaults setBool:readSubFolder forKey:@"ReadSubFolder"];

	
	
	cacheArray = [[NSMutableArray allocWithZone:NULL] init];
	imageMutableArray = [[NSMutableArray allocWithZone:NULL] init];
	bookmarkArray = [[NSMutableArray allocWithZone:NULL] init];
	currentBookSetting = [[NSMutableDictionary allocWithZone:NULL] init];
	marksArray = [[NSMutableArray allocWithZone:NULL] init];
	BOOL openLastFolder = [defaults boolForKey:@"OpenLastFolder"];
	[defaults setBool:openLastFolder forKey:@"OpenLastFolder"];
	[self setOpenRecentMenu];
	
	BOOL ignoreImageDpi = [defaults boolForKey:@"IgnoreImageDpi"];
	[fullImageView setIgnoreImageDpi:ignoreImageDpi];
	[imageView setIgnoreImageDpi:ignoreImageDpi];
	[defaults setBool:ignoreImageDpi forKey:@"IgnoreImageDpi"];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(viewDidEndLiveResize:)
												 name:@"ViewDidEndLiveResize"
											   object:imageView];

	/* MW-3: PreferenceController posts this instead of calling
	   -setPreferences directly. */
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(preferencesDidChange:)
												 name:@"PreferencesDidChange"
											   object:nil];


    openLinkMode = (int)[defaults integerForKey:@"OpenLinkMode"];
	[defaults setInteger:openLinkMode forKey:@"OpenLinkMode"];

	changeCurrentFolderMode = (int)[defaults integerForKey:@"ChangeCurrentFolder"];
	[defaults setInteger:changeCurrentFolderMode forKey:@"ChangeCurrentFolder"];
	
	
	NSString *oldVersion = [defaults stringForKey:@"Version"];
	NSString *nowVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
#pragma mark only under 1.2b10
	if (![defaults stringForKey:@"Version"]) {
		if ([defaults dictionaryForKey:@"BookSettings"]) {
			NSMutableDictionary *newBookSettings = [NSMutableDictionary dictionaryWithDictionary:[defaults dictionaryForKey:@"BookSettings"]];
			NSEnumerator *settingKeyEnu = [[defaults dictionaryForKey:@"BookSettings"] keyEnumerator];
			
			id settingKey;
			id setting;
			while (settingKey = [settingKeyEnu nextObject]) {
				setting = [newBookSettings objectForKey:settingKey];
				NSMutableDictionary *newSetting = [NSMutableDictionary dictionaryWithDictionary:setting];
				[newSetting setObject:[self pathFromAliasData:[setting objectForKey:@"alias"]] forKey:@"temppath"];
				[newBookSettings setObject:newSetting forKey:settingKey];
			}
			[defaults setObject:newBookSettings forKey:@"BookSettings"];
		}
		
		if ([defaults arrayForKey:@"LastPages"]) {
			NSMutableArray *newLastPages = [NSMutableArray arrayWithArray:[defaults arrayForKey:@"LastPages"]];
			
			NSEnumerator *enu = [[defaults arrayForKey:@"LastPages"] objectEnumerator];
			id object;
			while (object = [enu nextObject]) {
				int index = (int)[newLastPages indexOfObject:object];
				if ([[object objectForKey:@"page"] intValue] == 0) {
					[newLastPages removeObjectAtIndex:index];
				} else {
					NSMutableDictionary *newInnerDic = [NSMutableDictionary dictionaryWithDictionary:object];
					[newLastPages removeObjectAtIndex:index];
					[newInnerDic setObject:[self pathFromAliasData:[object objectForKey:@"alias"]] forKey:@"temppath"];
					[newLastPages addObject:newInnerDic];
				}
			}
			[defaults setObject:newLastPages forKey:@"LastPages"];
		}
		
		if ([defaults arrayForKey:@"RecentItems"]) {
			NSMutableArray *newRecentItems = [NSMutableArray arrayWithArray:[defaults arrayForKey:@"RecentItems"]];
			
			NSEnumerator *enu = [[defaults arrayForKey:@"RecentItems"] objectEnumerator];
			id object;
			while (object = [enu nextObject]) {
				NSMutableDictionary *newInnerDic = [NSMutableDictionary dictionaryWithDictionary:object];
				int index = (int)[[defaults arrayForKey:@"RecentItems"] indexOfObject:object];
				[newRecentItems removeObjectAtIndex:index];
				[newInnerDic setObject:[self pathFromAliasData:[object objectForKey:@"alias"]] forKey:@"temppath"];
				[newRecentItems insertObject:newInnerDic atIndex:index];
			}
			[defaults setObject:newRecentItems forKey:@"RecentItems"];
		}
		
	}
#pragma mark only under 1.2b14
	if ([@"1.2b14" versionCompare:oldVersion] == NSOrderedDescending && [defaults stringForKey:@"Version"]) {
		unichar plus = kRemoteButtonPlus;
		unichar minus = kRemoteButtonMinus;
		unichar menu = kRemoteButtonMenu;
		unichar play = kRemoteButtonPlay;
		unichar right = kRemoteButtonRight;
		unichar left = kRemoteButtonLeft;
		 NSArray *numericKeyArray = [[NSMutableArray alloc] initWithObjects:
			 [NSDictionary dictionaryWithObjectsAndKeys:
				 [NSNumber numberWithInt:39],@"action",@"0",@"keyname", [NSString stringWithFormat:@"0"],@"key",
				 [NSNumber numberWithInt:0],@"modifier",[NSNumber numberWithInt:0],@"value",
				 nil],
			[NSDictionary dictionaryWithObjectsAndKeys:
				[NSNumber numberWithInt:39],@"action",@"1",@"keyname", [NSString stringWithFormat:@"1"],@"key",
				[NSNumber numberWithInt:0],@"modifier",[NSNumber numberWithInt:10],@"value",
				nil],
			[NSDictionary dictionaryWithObjectsAndKeys:
				[NSNumber numberWithInt:39],@"action",@"2",@"keyname", [NSString stringWithFormat:@"2"],@"key",
				[NSNumber numberWithInt:0],@"modifier",[NSNumber numberWithInt:20],@"value",
				nil],
			[NSDictionary dictionaryWithObjectsAndKeys:
				[NSNumber numberWithInt:39],@"action",@"3",@"keyname", [NSString stringWithFormat:@"3"],@"key",
				[NSNumber numberWithInt:0],@"modifier",[NSNumber numberWithInt:30],@"value",
				nil],
			[NSDictionary dictionaryWithObjectsAndKeys:
				[NSNumber numberWithInt:39],@"action",@"4",@"keyname", [NSString stringWithFormat:@"4"],@"key",
				[NSNumber numberWithInt:0],@"modifier",[NSNumber numberWithInt:40],@"value",
				nil],
			[NSDictionary dictionaryWithObjectsAndKeys:
				[NSNumber numberWithInt:39],@"action",@"5",@"keyname", [NSString stringWithFormat:@"5"],@"key",
				[NSNumber numberWithInt:0],@"modifier",[NSNumber numberWithInt:50],@"value",
				nil],
			[NSDictionary dictionaryWithObjectsAndKeys:
				[NSNumber numberWithInt:39],@"action",@"6",@"keyname", [NSString stringWithFormat:@"6"],@"key",
				[NSNumber numberWithInt:0],@"modifier",[NSNumber numberWithInt:60],@"value",
				nil],
			[NSDictionary dictionaryWithObjectsAndKeys:
				[NSNumber numberWithInt:39],@"action",@"7",@"keyname", [NSString stringWithFormat:@"7"],@"key",
				[NSNumber numberWithInt:0],@"modifier",[NSNumber numberWithInt:70],@"value",
				nil],
			[NSDictionary dictionaryWithObjectsAndKeys:
				[NSNumber numberWithInt:39],@"action",@"8",@"keyname", [NSString stringWithFormat:@"8"],@"key",
				[NSNumber numberWithInt:0],@"modifier",[NSNumber numberWithInt:80],@"value",
				nil],
			[NSDictionary dictionaryWithObjectsAndKeys:
				[NSNumber numberWithInt:39],@"action",@"9",@"keyname", [NSString stringWithFormat:@"9"],@"key",
				[NSNumber numberWithInt:0],@"modifier",[NSNumber numberWithInt:90],@"value",
				nil],
			 
			 [NSDictionary dictionaryWithObjectsAndKeys:
				 [NSNumber numberWithInt:7],@"action",
				 @"AppleRemote Volume up",@"keyname", [NSString stringWithCharacters:&plus length:1],@"key",
				 [NSNumber numberWithInt:100],@"modifier",
				 nil],
			 [NSDictionary dictionaryWithObjectsAndKeys:
				 [NSNumber numberWithInt:6],@"action",
				 @"AppleRemote Volume down",@"keyname", [NSString stringWithCharacters:&minus length:1],@"key",
				 [NSNumber numberWithInt:100],@"modifier",
				 nil],
			 [NSDictionary dictionaryWithObjectsAndKeys:
				 [NSNumber numberWithInt:18],@"action",
				 @"AppleRemote Menu",@"keyname", [NSString stringWithCharacters:&menu length:1],@"key",
				 [NSNumber numberWithInt:100],@"modifier",
				 nil],
			 [NSDictionary dictionaryWithObjectsAndKeys:
				 [NSNumber numberWithInt:17],@"action",
				 @"AppleRemote Play",@"keyname", [NSString stringWithCharacters:&play length:1],@"key",
				 [NSNumber numberWithInt:100],@"modifier",
				 nil],
			 [NSDictionary dictionaryWithObjectsAndKeys:
				 [NSNumber numberWithInt:1],@"action",
				 @"AppleRemote Right",@"keyname", [NSString stringWithCharacters:&right length:1],@"key",
				 [NSNumber numberWithInt:100],@"modifier",
				 [NSNumber numberWithBool:YES],@"switchAction",
				 nil],
			 [NSDictionary dictionaryWithObjectsAndKeys:
				 [NSNumber numberWithInt:0],@"action",
				 @"AppleRemote Left",@"keyname", [NSString stringWithCharacters:&left length:1],@"key",
				 [NSNumber numberWithInt:100],@"modifier",
				 [NSNumber numberWithBool:YES],@"switchAction",
				 nil],
			nil];
		 [keyArray addObjectsFromArray:numericKeyArray];
		 [defaults setObject:keyArray forKey:@"KeyArray"];
		 [numericKeyArray release];
		 
		 if ([defaults objectForKey:@"PageBarBGColor"]) {
			 [defaults setObject:[NSArchiver archivedDataWithRootObject:
				 [[NSUnarchiver unarchiveObjectWithData:[defaults objectForKey:@"PageBarBGColor"]] colorWithAlphaComponent:0.8]] forKey:@"PageBarBGColor"];
		 }
	}
	if ([@"1.2b17" versionCompare:oldVersion] == NSOrderedDescending && [defaults stringForKey:@"Version"]) {
		[mouseArray addObject:
			[NSDictionary dictionaryWithObjectsAndKeys:
				[NSNumber numberWithInt:59],@"action",
				[NSNumber numberWithInt:1],@"button",
				[NSNumber numberWithInt:0],@"modifier",
				nil]];
		[mouseArray addObject:
			[NSDictionary dictionaryWithObjectsAndKeys:
				[NSNumber numberWithInt:59],@"action",
				[NSNumber numberWithInt:0],@"button",
				[NSNumber numberWithInt:4],@"modifier",
				nil]];
		[defaults setObject:mouseArray forKey:@"MouseArray"];
	}
	if ([@"1.2b23" versionCompare:oldVersion] == NSOrderedDescending && [defaults stringForKey:@"Version"]) {
		NSArray *multiTouchMouseArray = [[NSMutableArray alloc] initWithObjects:
		 [NSDictionary dictionaryWithObjectsAndKeys:
		  [NSNumber numberWithInt:6],@"action",
		  [NSNumber numberWithInt:2000],@"button",
		  [NSNumber numberWithInt:0],@"modifier",
		  [NSNumber numberWithBool:YES],@"switchAction",
		  nil],
		 [NSDictionary dictionaryWithObjectsAndKeys:
		  [NSNumber numberWithInt:7],@"action",
		  [NSNumber numberWithInt:1000],@"button",
		  [NSNumber numberWithInt:0],@"modifier",
		  [NSNumber numberWithBool:YES],@"switchAction",
		  nil],
		 [NSDictionary dictionaryWithObjectsAndKeys:
		  [NSNumber numberWithInt:14],@"action",
		  [NSNumber numberWithInt:4000],@"button",
		  [NSNumber numberWithInt:0],@"modifier",
		  nil],
		 [NSDictionary dictionaryWithObjectsAndKeys:
		  [NSNumber numberWithInt:15],@"action",
		  [NSNumber numberWithInt:3000],@"button",
		  [NSNumber numberWithInt:0],@"modifier",
		  nil],
		 [NSDictionary dictionaryWithObjectsAndKeys:
		  [NSNumber numberWithInt:49],@"action",
		  [NSNumber numberWithInt:7000],@"button",
		  [NSNumber numberWithInt:0],@"modifier",
		  nil],
		 [NSDictionary dictionaryWithObjectsAndKeys:
		  [NSNumber numberWithInt:50],@"action",
		  [NSNumber numberWithInt:8000],@"button",
		  [NSNumber numberWithInt:0],@"modifier",
		  nil],
		 [NSDictionary dictionaryWithObjectsAndKeys:
		  [NSNumber numberWithInt:63],@"action",
		  [NSNumber numberWithInt:6000],@"button",
		  [NSNumber numberWithInt:0],@"modifier",
		  nil],
		 [NSDictionary dictionaryWithObjectsAndKeys:
		  [NSNumber numberWithInt:64],@"action",
		  [NSNumber numberWithInt:5000],@"button",
		  [NSNumber numberWithInt:0],@"modifier",
		  nil],
		nil];
		[mouseArray addObjectsFromArray:multiTouchMouseArray];
		[multiTouchMouseArray release];
		[defaults setObject:mouseArray forKey:@"MouseArray"];
	}
#pragma mark versionCompareTest
	//versionCompare_test
	//1.2b10〜
	/*
	NSString *plist = oldVersion;
	NSString *nowVer = nowVersion;
	plist = @"";
	nowVer = @"1.2b14";
	NSComparisonResult result = [nowVer versionCompare:plist];
	
	if (result == NSOrderedAscending) {
		NSLog(@"%@ %@ left is small",nowVer,plist);
	} else if (result == NSOrderedSame) {
		NSLog(@"%@ %@ equal",nowVer,plist);
	} else if (result == NSOrderedDescending) {
		NSLog(@"%@ %@ left is big",nowVer,plist);
	} else {
		NSLog(@"%@ %@ err",nowVer,plist);
	}*/
#pragma mark set Version
	if ([nowVersion versionCompare:oldVersion] == NSOrderedDescending) {
		//NSLog(@"%@ %@ left is big",nowVer,plist);
		[defaults setObject:[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"] forKey:@"Version"];
	}
	[imageView setPreferences];
	[self setupInputMappings];
}


/* MW-7: this was the first half of -applicationDidFinishLaunchingSetup:, and
   it is per-window — it pushes this window's key/mouse mappings into this
   window's panels and image view. Every window needs it, not just the one
   that happens to exist when the app finishes launching, so it runs from
   -windowDidLoad instead. Nothing here reaches outside BookWindow.xib, whose
   objects are all instantiated and connected by then. */
- (void)setupInputMappings
{
	id object;
	NSEnumerator *enu;
	NSMutableArray *array = [NSMutableArray arrayWithArray:keyArray];
	[fullImagePanel setPageKey:array];
	[thumController setPageKey:array];

	NSMutableArray *array2 = [NSMutableArray array];
	enu = [mouseArrayMode2 objectEnumerator];
	while (object = [enu nextObject]) {
		if ([[object objectForKey:@"action"] intValue] == 41) {
			[array2 addObject:object];
		}
	}
	[imageView setDragScroll:array2 mode:1];

	NSMutableArray *array3 = [NSMutableArray array];
	enu = [mouseArrayMode3 objectEnumerator];
	while (object = [enu nextObject]) {
		if ([[object objectForKey:@"action"] intValue] == 41) {
			[array3 addObject:object];
		}
	}
	[imageView setDragScroll:array3 mode:2];
	[imageView setDragScroll:array3 mode:3];
}

 - (void)applicationDidFinishLaunchingSetup:(NSNotification *)notification
{
	if ([defaults boolForKey:@"OpenLastFolder"] == YES) {
		/* MW-6 item 4: "nothing was opened for us at launch" — by an
		   application:openFile: Apple event, typically. This used to test
		   [[self window] isVisible], which is only a proxy for it. */
		if (![self hasBookOpen]) {
			[self openTheLastPage:self];
		}
	}
 }

#pragma mark openFromAny
/* M3 (code review 2026-10-03): the window-level open entry points (File ▸
   Open, Open the Last Page, Open Recent, Open from Same Folder and its
   next/previous-folder keys, the All Bookmark browser's Open) refuse while
   this window is still loading a book or waiting on its password sheet. By
   then currentBookPath and the "old book" already belong to the pending open,
   so a second open would save the old book's page under the pending book's
   path, leak the saved old book, and let the stale sheet later install its
   book under the new title. AppController's Finder/drop gate keeps such a
   window out of routing for the same reason; these are the direct paths. */
- (BOOL)refuseOpenWhileBusy
{
	if (bookLoadInFlight || passwordOpenInFlight) {
		NSBeep();
		return YES;
	}
	return NO;
}

- (IBAction)openTheLastPage:(id)sender
{
	if ([self refuseOpenWhileBusy]) return;
	if ([imageView image]) {
		int page;
		if ([defaults arrayForKey:@"RecentItems"]) {
			id object = [appController searchFromRecentItems:currentBookPath index:nil];
			if (object) {
				if ([object objectForKey:@"page"]) {
					page = [[object objectForKey:@"page"] intValue];
					[self goTo:page array:nil];
					return;
				}
			}
		}
		if ([defaults arrayForKey:@"LastPages"]) {
			NSEnumerator *enu = [[defaults arrayForKey:@"LastPages"] objectEnumerator];
			id object;
			while (object = [enu nextObject]) {
				if ([[self pathFromAliasData:[object objectForKey:@"alias"]] isEqualToString:currentBookPath]) {
					page = [[object objectForKey:@"page"] intValue];
					[self goTo:page array:nil];
					return;
				}
			}
		}
	} else {
		if ([[defaults arrayForKey:@"RecentItems"] count]>0) {
			NSArray *array = [defaults arrayForKey:@"RecentItems"];
			[self setCurrentBookPath:[self pathFromAliasData:[[array objectAtIndex:0] objectForKey:@"alias"]]];
			
			[self openPage:[[[array objectAtIndex:0] objectForKey:@"page"] intValue] last:NO];
		}
	}
}


/* -application:openFile: used to live here, doing exactly what
   -openBookAtPath: does. AppController answers -application:openFiles: now,
   which routes Finder opens through the window registry, so the singular
   callback has no caller and no separate behaviour to preserve. */

-(IBAction)open:(id)sender
{
	if ([self refuseOpenWhileBusy]) return;
	if (timerSwitch) {
		[timer invalidate];
		timer = nil;
		timerSwitch=NO;
	}
	NSOpenPanel *openPanel = [NSOpenPanel openPanel];
	int openPanelResult;
	
	[openPanel setCanChooseDirectories:YES];
    NSMutableArray *tempArray = [NSMutableArray arrayWithArray:[COImageLoader fileTypes]];
    [openPanel setAllowedFileTypes:tempArray];
	openPanelResult = (int)[openPanel runModal];
	
	if (openPanelResult == NSCancelButton) {
		return;
	}
	if (openPanelResult == NSOKButton) {
		if (timerSwitch) {
			[timer invalidate];
			timer = nil;
			timerSwitch=NO;
		}
		[self setCurrentBookPathAndOldBookPath:[[openPanel URL] path]];
		
		[self openPage:0 last:NO];
	}
}


/* The book could not be opened — a bad archive, or a password prompt the user
   cancelled. Was the tail of -openPage:last:'s failure branch; extracted
   because cancelling a password sheet takes the same path with one difference
   (KNOWN_ISSUES #30, decision 1): it does not close the window.

   `closeWindow` NO leaves a bookless window ordered out but registered, which
   is the state MW-8 already established for a restore whose book has gone: not
   shown, reused by the next open, and — unlike a close — it cannot trip
   quit-on-last-close. A window that already had a book keeps showing it either
   way; nothing has been torn down at this point. */
/* Undo what the open entry points (-setCurrentBookPathAndOldBookPath: and
   -openPage:last:) did to the window's book identity before loading: the
   pending book's path, name and alias are released, and a window that has a
   book gets its own back from the "old book" slot. That slot is emptied in
   the same step — it held the only reference, which now belongs to
   currentBookPath — so the window is left exactly as it was before the open
   started (a finished open leaves it nil), rather than with both ivars
   naming one object. Nothing else of the window's state was touched before
   the load, and nothing was written to Recent Books, LastPages or the
   restorable bookmark: those happen only once a load has succeeded. */
- (void)restoreBookIdentityAfterAbandonedOpen
{
	[currentBookPath release];
	[currentBookName release];
	[currentBookAlias release];
	if ([self hasBookOpen]) {
		currentBookPath = oldBookPath;
		currentBookName = oldBookName;
		currentBookAlias = oldBookAlias;
		oldBookPath = nil;
		oldBookName = nil;
		oldBookAlias = nil;
	} else {
		currentBookPath = nil;
		currentBookName = nil;
		currentBookAlias = nil;
	}
}

- (void)abandonOpenWithLoader:(COImageLoader *)newImageLoader
				 fromFileName:(NSString *)fromFileName
				  closeWindow:(BOOL)closeWindow
{
	/* v1.6.x: the shared give-up funnel for a bad archive or a cancelled
	   password — whichever -openPage:last: this open started with, it
	   ends here rather than at the success tail. */
	[self openDidEnd];
	[newImageLoader release];
	[self restoreBookIdentityAfterAbandonedOpen];
	if ([self hasBookOpen]) {
		/*ウィンドウを開いているとき*/
		/* "Open from same folder" submenu is now refreshed lazily via
		   menuNeedsUpdate: (see setSameFolderMenu:) — not eagerly here —
		   to avoid hitting the parent folder (and triggering macOS folder
		   access prompts) on every book open. */
	} else {
		if (shownWithoutBook) {
			/* v1.6.5: a window the user opened empty (File ▸ New Window)
			   stays as it was, on screen and empty. Closing it would turn a
			   failed open into quit-on-last-close whenever it is the only
			   window and a book was read earlier in the session — a state
			   that did not exist before File ▸ New Window. */
		} else if (closeWindow && [[self window] isVisible]) {
			[[self window] performClose:self];
		} else {
			/* Also where a window this open never showed ends up (KNOWN_ISSUES
			   #30): it was kept hidden until the book could be shown, so there
			   is nothing on screen to close. It stays registered and bookless,
			   the state a cancelled password leaves, and the next open reuses
			   it. Not closing it also keeps it out of quit-on-last-close. */
			[[self window] orderOut:self];
		}
	}
	/* Carries the retain -openPage:last: took from currentBookPath, which only
	   the success path used to release. */
	[fromFileName release];
	[progressIndicator stopAnimation:self];
	//[imageView displayRect:rect];
}

/* MW-7: what -open: does once the path is known, without the panel. Used by
   -[AppController openBookInNewWindow:], which runs the panel itself because
   the choice of *which* window opens the book is an app-level one. */
-(void)openBookAtPath:(NSString *)path
{
	if ([self refuseOpenWhileBusy]) return;
	if (timerSwitch) {
		[timer invalidate];
		timer = nil;
		timerSwitch=NO;
	}
	[self setCurrentBookPathAndOldBookPath:path];

	[self openPage:0 last:NO];
}

/* v1.6.5, File ▸ New Window. Until now a book window was only ever on screen
   with a book in it (MW-7, MW-8): a bookless window is kept hidden. A window
   shown empty on purpose is therefore kept out of the two places that assume
   otherwise. Window restoration: AppKit would save it and bring it back next
   launch as a window with nothing to open — and count it as a restored
   window, which stands down OpenLastFolder — so it is not restorable until a
   book opens in it. Quit-on-last-close: see -abandonOpenWithLoader:... */
- (void)showEmptyWindow
{
	shownWithoutBook = YES;
	[[self window] setRestorable:NO];
	[[self window] makeKeyAndOrderFront:self];
}

/* What a Finder double-click opens (owner decision, 2026-10-03): a folder, or
   a file whose extension one of the document types in this app's
   CFBundleDocumentTypes declares — read from the bundle's Info.plist at run
   time, so the declaration Launch Services uses is the only list. That
   includes single image files, which open their folder at that page, unlike
   File ▸ Open's +[COImageLoader fileTypes]. Extensions are enough: every
   declared LSItemContentTypes entry comes with its extensions in the same
   document type, except public.directory, which is the folder case.
   Compared without regard to case, as Launch Services does. */
+ (BOOL)canOpenDroppedPath:(NSString *)path
{
	BOOL isDirectory = NO;
	if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory]) {
		return NO;
	}
	if (isDirectory) {
		return YES;
	}
	NSString *extension = [[path pathExtension] lowercaseString];
	if ([extension length] == 0) {
		return NO;
	}
	NSArray *documentTypes = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDocumentTypes"];
	NSEnumerator *typeEnu = [documentTypes objectEnumerator];
	NSDictionary *documentType;
	while (documentType = [typeEnu nextObject]) {
		NSEnumerator *extEnu = [[documentType objectForKey:@"CFBundleTypeExtensions"] objectEnumerator];
		NSString *declared;
		while (declared = [extEnu nextObject]) {
			if ([[declared lowercaseString] isEqualToString:extension]) {
				return YES;
			}
		}
	}
	return NO;
}

/* The same rule as a Finder double-click, with this window in place of the
   front window: see -[AppController openFiles:preferringWindow:entry:]. */
- (void)openDroppedPaths:(NSArray *)paths
{
	[appController openFiles:paths preferringWindow:self entry:@"drop"];
}


#pragma mark window restoration (MW-8)
/* Step-0 decision 5, the per-window half. AppController is the restoration
   class and produces the window; everything about *which book* that window
   shows is here.

   Image quality: what is encoded is a bookmark, a page number and the view
   mode — never a rendered image, and nothing here touches the render path.
   A restored window reaches the screen through -openPage:last: →
   -imageDisplay, the same single-resample path every other open uses, and a
   window restored into full screen is recomposed by
   -windowDidEnterFullScreen: → -recomposeForCurrentSize, which already
   existed. */

static NSString * const kBookBookmarkKey = @"cooViewerBookBookmark";
static NSString * const kBookPageKey     = @"cooViewerBookPage";
static NSString * const kBookViewModeKey = @"cooViewerBookViewMode";

- (void)beginRestoration
{
	restorationInFlight = YES;
}

- (void)endRestoration
{
	restorationInFlight = NO;
}

- (BOOL)isAwaitingRestoredBook
{
	/* Both halves matter: the first covers the window while AppKit is still
	   deciding what to restore into it, the second covers it from the moment
	   a book has been decoded until -openRestoredBook has opened it. The URL
	   itself cannot answer this — it is kept for the lifetime of the
	   security scope, which outlives the open. */
	return (restorationInFlight || restoredBookPending);
}

- (BOOL)isRestoredBookUnfinished
{
	/* KNOWN_ISSUES #33 added the fourth case: a restored book that turned out
	   to be encrypted is not finished while its password sheet is up. It
	   outlives -openRestoredBook now, because that method returns as soon as
	   the sheet is on screen instead of blocking until the book is open.
	   #33's loading half made the third case outlive it too: an archive is
	   read asynchronously, and restoredBookOpening stays set until the open
	   ends. */
	return (restorationInFlight || restoredBookPending || restoredBookOpening
			|| [self isWaitingForUserInput]);
}

- (int)restorablePageIndex
{
	/* `nowPage` is the page *after* the last one displayed, so a spread on
	   pages n and n+1 leaves it at n+2 — the same conversion
	   -windowWillClose: and -openPage:last: apply before writing a page
	   number into RecentItems/LastPages. */
	int page = nowPage - (secondImage ? 2 : 1);
	return (page < 0) ? 0 : page;
}

/* A security-scoped NSURL bookmark, deliberately not the Alias Manager data
   the rest of the app persists: restorable state is written by AppKit into
   the app's saved state, and this is the one place the plan carves out of
   "Alias Manager → NSURL bookmarks is out of scope for the MW arc"
   (docs/multiwindow-plan.md). cooViewer is not sandboxed, so the security
   scope is inert today; asking for it costs nothing and is what makes the
   stored bookmark still work if the app is ever sandboxed. */
- (void)setCurrentBookBookmarkForPath:(NSString *)path
{
	[currentBookBookmark release];
	currentBookBookmark = nil;
	if (path == nil) {
		return;
	}

	NSError *error = nil;
	NSData *bookmark = [[NSURL fileURLWithPath:path]
						bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope
						includingResourceValuesForKeys:nil
						relativeToURL:nil
						error:&error];
	if (bookmark == nil) {
		/* Not fatal: the window simply will not be restored. */
		NSLog(@"cooViewer: could not bookmark %@ for window restoration: %@",
			  path, [error localizedDescription]);
		return;
	}
	currentBookBookmark = [bookmark retain];
}

- (void)releaseRestoredBookAccess
{
	if (restoredBookURL == nil) {
		return;
	}
	if (restoredAccessStarted) {
		[restoredBookURL stopAccessingSecurityScopedResource];
		restoredAccessStarted = NO;
	}
	[restoredBookURL release];
	restoredBookURL = nil;
	restoredBookPending = NO;
}

/* The window's restorable state is one coder shared by the window, its
   delegate and its window controller — and this object is both the delegate
   and the window controller. In practice AppKit only calls the *delegate*
   pair (-window:willEncodeRestorableState: / -window:didDecodeRestorableState:
   below); the NSResponder methods it would call on a window controller are
   not sent to a plain, document-less NSWindowController. Verified on macOS
   26 by instrumenting all four: only the delegate pair fired.

   So the two methods the plan names are still the implementation, and the
   delegate pair is what drives them. If a future AppKit does start calling
   these directly the result is unchanged: encoding writes the same keys with
   the same values, and decoding is guarded against running twice. */
- (void)window:(NSWindow *)window willEncodeRestorableState:(NSCoder *)state
{
	[self encodeRestorableStateWithCoder:state];
}

- (void)window:(NSWindow *)window didDecodeRestorableState:(NSCoder *)state
{
	[self restoreStateWithCoder:state];
}

- (void)encodeRestorableStateWithCoder:(NSCoder *)coder
{
	[super encodeRestorableStateWithCoder:coder];

	if (![self hasBookOpen] || currentBookBookmark == nil) {
		return;
	}
	[coder encodeObject:currentBookBookmark forKey:kBookBookmarkKey];
	[coder encodeInt:[self restorablePageIndex] forKey:kBookPageKey];
	[coder encodeInt:fitScreenMode forKey:kBookViewModeKey];
}

- (void)restoreStateWithCoder:(NSCoder *)coder
{
	[super restoreStateWithCoder:coder];

	/* Once is enough — see -window:didDecodeRestorableState: above. */
	if (restoredBookURL != nil || [self hasBookOpen]) {
		return;
	}

	/* Whatever happens below, AppKit is done deciding about this window. */
	[self endRestoration];

	NSData *bookmark = [coder decodeObjectOfClass:[NSData class] forKey:kBookBookmarkKey];
	if (bookmark == nil) {
		return;
	}

	/* `stale` is read but not acted on: a stale bookmark still resolves, and
	   the one this window stores is rebuilt from the resolved path the
	   moment the book opens, so it heals itself without a special case. */
	BOOL stale = NO;
	NSError *error = nil;
	NSURL *url = [NSURL URLByResolvingBookmarkData:bookmark
										   options:NSURLBookmarkResolutionWithSecurityScope
									 relativeToURL:nil
							   bookmarkDataIsStale:&stale
											 error:&error];
	/* A book that has been deleted or is on an unmounted volume resolves to
	   nothing, or to a path that is no longer there. Leaving the window
	   empty is the graceful outcome: it is never shown (only -openPage:last:
	   shows it), and it stays available as the window the next book opens
	   into. OpenLastFolder is not run in its place — the system did restore
	   a window, so the gate in -[AppController applicationDidFinishLaunching:]
	   has already been decided by then. */
	if (url == nil || ![url isFileURL]
		|| ![[NSFileManager defaultManager] fileExistsAtPath:[url path]]) {
		NSLog(@"cooViewer: window restoration skipped, the book could not be found (%@)",
			  error ? [error localizedDescription] : @"no longer at the recorded location");
		return;
	}

	restoredBookURL = [url retain];
	restoredAccessStarted = [url startAccessingSecurityScopedResource];
	restoredBookPending = YES;
	restoredPage = [coder decodeIntForKey:kBookPageKey];
	restoredFitScreenMode = [coder decodeIntForKey:kBookViewModeKey];

	/* Not opened here. This runs inside AppKit's restoration pass, before
	   the app has finished launching and before the window has been given
	   its restored frame or put back into full screen; -openPage:last: is a
	   long, modal-capable operation that orders the window front. One
	   run-loop pass later the window is fully restored and the app is
	   running normally, and the book opens exactly as any other book does —
	   including the recompose that follows the full-screen transition. */
	[self performSelector:@selector(openRestoredBook) withObject:nil afterDelay:0.0];
}

- (void)openRestoredBook
{
	if (restoredBookURL == nil) {
		return;
	}
	NSString *path = [[[restoredBookURL path] copy] autorelease];
	int page = restoredPage;
	int viewMode = restoredFitScreenMode;
	/* The window is no longer waiting for a book — whether or not the open
	   below succeeds, nothing else is going to open one into it, and it has
	   to be reusable as an empty window if it fails. The URL and its
	   security scope stay until the book is torn down in
	   -windowWillClose:. */
	restoredBookPending = NO;
	restoredPage = 0;
	restoredFitScreenMode = 0;
	/* KNOWN_ISSUES #32: cleared when the open below ends (-openDidEnd), so a
	   Finder request held for this launch is not drained into the middle of
	   it. Since KNOWN_ISSUES #33's loading half that can be well after
	   -openPage:last: has returned: an archive is read asynchronously. */
	restoredBookOpening = YES;

	/* View mode before the book, so the spread is composed once, in the mode
	   it is going to be shown in. These are the same actions the View menu
	   sends — no scaling logic is duplicated or added here. */
	switch (viewMode) {
		case 1: [self fitToScreenWidth:self]; break;
		case 2: [self noScale:self]; break;
		case 3: [self fitToScreenWidthDivide:self]; break;
		default: break;
	}

	[self setCurrentBookPathAndOldBookPath:path];

	/* Restoration knows which page it wants, so the open's "go to the last
	   page?" handling — which only triggers on page 0, and can put up a modal
	   alert — must not run: the page it would offer is the one being restored
	   anyway. -openPageWithLoader:... skips it while restoredBookOpening is
	   set. (This used to set goToLastPageMode to 2 around the call and put it
	   back afterwards, which only worked while the whole open ran inside the
	   call.) */
	[self openPage:page last:NO];
}

#pragma mark -

-(void)openFromSameDir:(id)sender
{
	[self openFromSameDir:sender last:NO];
}

-(void)openFromSameDir:(id)sender last:(BOOL)isLast
{
	if ([self refuseOpenWhileBusy]) return;
	[self setCurrentBookPathAndOldBookPath:[sender representedObject]];

	[self openPage:0 last:isLast];
}


-(void)openFromOpenRecent:(id)sender
{
	if ([self refuseOpenWhileBusy]) return;
	[self setCurrentBookPathAndOldBookPath:[self pathFromAliasData:[[sender representedObject] objectForKey:@"alias"]]];
	
	[self openPage:[[[sender representedObject] objectForKey:@"page"] intValue] last:NO];
}



#pragma mark openning
- (void)openPage:(int)page last:(BOOL)last;
{
	/* v1.6.x: set here, at the very top, so a window is never mistaken for
	   "empty" while this open (restoration or ordinary) is running — see
	   the `bookLoadInFlight` ivar comment in the header. */
	bookLoadInFlight = YES;

	/* KNOWN_ISSUES #30/#33: a window that is not on screen yet — a new
	   window, or the hidden one the registry keeps — is shown only once
	   there is something to show (see `openShowDeferred` in the header), so
	   a book that cannot be opened does not flash a window up and close it
	   again. A window already on screen is brought forward now, as always,
	   and so is a restored window, so that restored windows keep coming
	   forward in the order their books are opened. */
	NSWindow *bookWindow = [self window];
	openShowDeferred = (!restoredBookOpening
						&& ![bookWindow isVisible]
						&& ![bookWindow isMiniaturized]);
	if (!openShowDeferred) {
		[bookWindow makeKeyAndOrderFront:self];
	}

	[progressIndicator startAnimation:self];
	[progressIndicator displayIfNeeded];
	
    /*
	[imageView lockFocus];
	NSRect rect = [[[self window] contentView] convertRect:[progressIndicator frame] toView:imageView];
	rect = NSMakeRect(rect.origin.x-2,rect.origin.y-2,rect.size.width+4,rect.size.height+4);
	NSBezierPath *bezier = [NSBezierPath bezierPath];
	float rad = 10.0;
	[bezier appendBezierPathWithArcWithCenter:NSMakePoint(rect.origin.x+rad,rect.origin.y+rect.size.height-rad)
									   radius:rad startAngle:90 endAngle:180];
	[bezier appendBezierPathWithArcWithCenter:NSMakePoint(rect.origin.x+rad,rect.origin.y+rad)
									   radius:rad startAngle:180 endAngle:270];
	[bezier appendBezierPathWithArcWithCenter:NSMakePoint(rect.origin.x+rect.size.width-rad,rect.origin.y+rad)
									   radius:rad startAngle:270  endAngle:0];
	[bezier appendBezierPathWithArcWithCenter:NSMakePoint(rect.origin.x+rect.size.width-rad,rect.origin.y+rect.size.height-rad)
									   radius:rad startAngle:0 endAngle:90];
	[bezier closePath];
	[[[NSColor grayColor] colorWithAlphaComponent:0.8] set];
	[bezier fill];
	[imageView unlockFocus];
	[imageView displayIfNeeded];
    */
	

	NSString *fromFileName = nil;
	NSString *resolvedBookPath = [BookWindowController resolvedBookPath:currentBookPath];
	if (![resolvedBookPath isEqualToString:currentBookPath]) {
		/* A single image file: the book is its folder, and this page is the
		   one to open on. fromFileName carries currentBookPath's retain —
		   -setCurrentBookPath: overwrites the ivar without releasing it —
		   and is released once the page index has been taken from it. */
		fromFileName = currentBookPath;
		[currentBookName release];
		[currentBookAlias release];
		[self setCurrentBookPath:resolvedBookPath];
	}
	
	/* KNOWN_ISSUES #33: `deferPasswordPrompt` — an encrypted archive makes the
	   loader report -needsPassword instead of blocking to ask, so the prompt
	   can be a sheet this window owns rather than a modal loop the whole
	   application sits in. The rest of the open then happens in
	   -openPageWithLoader:page:last:fromFileName:, either directly below or
	   from the sheet's completion handler.

	   KNOWN_ISSUES #33, the loading half: `deferArchiveRead` likewise — an
	   archive book is not read inside this initializer. The read runs on a
	   worker thread with no modal session (-beginArchiveLoadForLoader:...),
	   and the open resumes at -continueOpenWithLoader:... when it is done.
	   A folder, saved search or PDF is listed here as before, and goes on to
	   the same continuation directly. */
	COImageLoader *newImageLoader = [[COImageLoader alloc] initWithPath:currentBookPath
															displayPath:currentBookPath
														  readSubFolder:readSubFolder
															 controller:self
													deferPasswordPrompt:YES
													   deferArchiveRead:YES];

	if (newImageLoader && [newImageLoader needsArchiveRead]) {
		[self beginArchiveLoadForLoader:newImageLoader
								   page:page
								   last:last
						   fromFileName:fromFileName];
		return;
	}

	[self continueOpenWithLoader:newImageLoader page:page last:last fromFileName:fromFileName];
}

/* The open once the book has been read: an encrypted archive asks for its
   password first (KNOWN_ISSUES #33), anything else goes straight on. The loader
   and `fromFileName` are owned by the open, as for
   -openPageWithLoader:page:last:fromFileName:. */
- (void)continueOpenWithLoader:(COImageLoader *)newImageLoader
						  page:(int)page
						  last:(BOOL)last
				  fromFileName:(NSString *)fromFileName
{
	if (newImageLoader && [newImageLoader needsPassword]) {
		[self askPasswordForLoader:newImageLoader
							  page:page
							  last:last
					  fromFileName:fromFileName
					 wrongPassword:NO];
		return;
	}

	[self openPageWithLoader:newImageLoader page:page last:last fromFileName:fromFileName];
}

/* Every open ends in exactly one of five ways — it succeeds, the book cannot be
   opened, it is cancelled (the read or the password prompt), its window is
   closed, or a quit takes it down — and each of them comes through here, from
   the success tail of -openPageWithLoader:..., from -abandonOpenWithLoader:...
   (failure, cancel and quit), or from -windowWillClose:. The per-open flags
   are cleared in this one place so that none of the five can leave one set. */
- (void)openDidEnd
{
	bookLoadInFlight = NO;
	restoredBookOpening = NO;
	openShowDeferred = NO;
}

/* Puts a window on screen that this open has kept hidden so far (see
   `openShowDeferred`). Called when the open succeeds, when its load is slow
   enough for the progress sheet, and before a password sheet, each of which
   needs the window. */
- (void)showWindowForOpenIfNeeded
{
	if (!openShowDeferred) {
		return;
	}
	openShowDeferred = NO;
	[[self window] makeKeyAndOrderFront:self];
}

/* A book that cannot be opened at all, and why: a solid RAR4, refused at open
   instead of showing one page and then broken ones (KNOWN_ISSUES #39), or a
   book with no readable pages (#30). Called before -abandonOpenWithLoader:...,
   which may close this window. A window that stays on screen (it has a book,
   or is an empty File ▸ New Window) gets a sheet; otherwise the alert is
   application-modal and waits until this open has unwound, holding nothing
   of this controller's. A cancelled read or password prompt is not reported:
   the user ended that open. */
- (void)reportCannotOpenBook:(COImageLoader *)loader status:(COImageLoaderPagesStatus)status
{
	NSString *reason;
	if ([loader isUnsupportedSolidRAR4]) {
		reason = NSLocalizedString(@"This is a solid RAR4 archive, which cooViewer cannot read. A non-solid RAR or a ZIP (CBZ) of the same pages can be read.",@"");
	} else if (status == COImageLoaderNoImages) {
		reason = NSLocalizedString(@"It contains no images that cooViewer can show.",@"");
	} else if (status == COImageLoaderUnreadable) {
		reason = NSLocalizedString(@"The file could not be read. It may be damaged, or in a format cooViewer cannot read.",@"");
	} else if (status == COImageLoaderEncryptionUnsupported) {
		reason = NSLocalizedString(@"The archive is encrypted, and cooViewer cannot decrypt this kind of archive. Password-protected ZIP (CBZ) archives can be opened.",@"");
	} else {
		return;
	}
	NSString *name = [[loader displayPath] lastPathComponent];

	NSAlert *alert = [[[NSAlert alloc] init] autorelease];
	[alert setMessageText:[NSString stringWithFormat:
		NSLocalizedString(@"Cannot open \"%@\".",@""), name ? name : @""]];
	[alert setInformativeText:reason];
	[alert addButtonWithTitle:NSLocalizedString(@"OK",@"")];

	if ([self canPresentSheet] && ([self hasBookOpen] || shownWithoutBook)) {
		[alert beginSheetModalForWindow:[self sheetParentWindow] completionHandler:nil];
	} else {
		dispatch_async(dispatch_get_main_queue(), ^{
			[alert runModal];
		});
	}
}

/* The rest of -openPage:last:, split off so that an encrypted archive can
   resume here once its password sheet has been answered (KNOWN_ISSUES #33).
   Only three things cross the split: the loader (a +1 this method takes over),
   the page/last request, and `fromFileName` (which carries the retain
   -openPage:last: took from currentBookPath). Everything else is ivars. */
- (void)openPageWithLoader:(COImageLoader *)newImageLoader
					  page:(int)page
					  last:(BOOL)last
			  fromFileName:(NSString *)fromFileName
{
	//NSLog(@"controller mode=%i count=%i",[newImageLoader mode],[newImageLoader itemCount]);
	COImageLoaderPagesStatus pagesStatus =
		newImageLoader ? [newImageLoader pagesStatus] : COImageLoaderNotOpened;
	if (pagesStatus != COImageLoaderHasPages) {
		/*表示出来ない時は元に戻す*/
		/* KNOWN_ISSUES #30: a book with no readable pages ends here, with an
		   alert, before anything of the window's current book is torn down
		   and before Recent Books is touched. */
		[self reportCannotOpenBook:newImageLoader status:pagesStatus];
		[self abandonOpenWithLoader:newImageLoader
					   fromFileName:fromFileName
						closeWindow:YES];
		return;
	}
	/* The book opens: a window this open has kept hidden comes on screen now,
	   before the "Go to the last page?" alert below and before the first page
	   is composed for it. */
	[self showWindowForOpenIfNeeded];
	if ([self hasBookOpen]) {
		/*ウィンドウを開いてたら準備する*/
		//currentBookPathではなくoldBookPath
		//currentBookNameではなくoldBookName
		//なことに注意する事！

		/* The previous book is about to be torn down — its imageLoader
		   released and its page arrays emptied. Anything the outgoing book
		   left reading ahead has to be finished with them first. */
		[self joinLookaheadThreads];

		/*clear cache*/
		[cacheArray removeAllObjects];
		if (oldBookPath != nil) {
			/*historyの処理*/
			if (secondImage) {
				nowPage -= 2;
			} else {
				nowPage--;
			}
			[appController recordClosingBookSettings:oldBookPath
												  name:oldBookName
												 alias:oldBookAlias
											 bookmarks:bookmarkArray
										   bookSetting:currentBookSetting
												  page:nowPage
									   openRecentLimit:openRecentLimit
								alwaysRememberLastPage:alwaysRememberLastPage];
		}

		[completeMutableArray release];
		completeMutableArray = nil;
		[imageMutableArray removeAllObjects];
		[bookmarkArray removeAllObjects];
		[currentBookSetting removeAllObjects];
		[imageLoader release];
	}
	/* See note above: "Open from same folder" submenu refresh is deferred to
	   menuNeedsUpdate: so we don't touch the parent folder on every open. */
	if (oldBookPath != nil) {
		[oldBookPath release];
		[oldBookName release];
		[oldBookAlias release];
		oldBookPath = nil;
		oldBookName = nil;
		oldBookAlias = nil;
	}
	
	
	id tempCurrentBookSetting = [appController searchFromBookSettings:currentBookPath key:nil more:YES];
	if (tempCurrentBookSetting) {
		[currentBookSetting setDictionary:tempCurrentBookSetting];
	}

	NSMutableArray *newRecentItems;
	if (![defaults arrayForKey:@"RecentItems"]) {
		newRecentItems = [NSMutableArray array];
	} else {
		newRecentItems = [NSMutableArray arrayWithArray:[defaults arrayForKey:@"RecentItems"]];
	}
	NSMutableArray *lastPages;
	if (![defaults arrayForKey:@"LastPages"]) {
		lastPages = [NSMutableArray array];
	} else {
		lastPages = [NSMutableArray arrayWithArray:[defaults arrayForKey:@"LastPages"]];
	}
	NSData *aliasData = currentBookAlias;
	
	/*goto lastpage?*/
	/* Not for a book window restoration brought back: it knows which page it
	   wants, and the page this would offer is that one anyway. Keyed on
	   restoredBookOpening, which lasts as long as the open does, because the
	   open can now resume long after -openRestoredBook has returned (an
	   archive read, a password sheet). */
	int lastPageMode = restoredBookOpening ? 2 : goToLastPageMode;
	if (lastPageMode<2 && !last && page == 0) {
		id object = [appController searchFromRecentItems:currentBookPath index:nil];
		if (object) {
			page = [[object objectForKey:@"page"] intValue];
		}
		if (!page) {
			object = [appController searchFromLastPages:currentBookPath index:nil];
			if (object) {
				page = [[object objectForKey:@"page"] intValue];
			}
		}
		if (lastPageMode==0 && page) {
			NSAlert *alert = [[[NSAlert alloc] init] autorelease];
			[alert setMessageText:NSLocalizedString(@"Go to the last page",@"")];
			[alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"Do you want to go to %i page?",@""),page+1]];
			[alert addButtonWithTitle:NSLocalizedString(@"OK",@"")];
			[alert addButtonWithTitle:NSLocalizedString(@"Cancel",@"")];

			if([alert runModal] != NSAlertFirstButtonReturn) {
				page = 0;
			}
		}
	}
	/*add RecentItem*/
	if (openRecentLimit>0) {
		NSDictionary *newDic = [NSDictionary dictionaryWithObjectsAndKeys:aliasData,@"alias",currentBookPath,@"temppath",nil];
		if (alwaysRememberLastPage) {
			id object = [appController searchFromLastPages:currentBookPath index:nil];
			if (object) {
				newDic = object;
			}
		}
		int index = 0;
		id objectS = [appController searchFromRecentItems:currentBookPath index:&index];
		if (objectS) {
			[newRecentItems removeObjectAtIndex:index];
			newDic = objectS;
		}
		[newRecentItems insertObject:newDic atIndex:0];
		
		[defaults setObject:newRecentItems forKey:@"RecentItems"];
	} else {
		[defaults removeObjectForKey:@"RecentItems"];
	}
	[self setOpenRecentMenu];
	NSMenu *menu=[[appController openRecentMenuItem] submenu];
	[[menu itemAtIndex:0] setState:NSOnState];
	[[menu itemAtIndex:0] setEnabled:NO];

	[defaults synchronize];
	
	
	
	imageLoader = newImageLoader;
	completeMutableArray = [[imageLoader pathArray] retain];
	
	sortMode = 0;
	if ([currentBookSetting objectForKey:@"sortMode"]) {
		sortMode = [[currentBookSetting objectForKey:@"sortMode"] intValue];
	} else {
		sortMode = (int)[defaults integerForKey:@"SortMode"];
	}
	if (sortMode!=0) {
		[self setSortMode:sortMode page:-1];
	}
	

	
	if (fromFileName) {
		page = (int)[completeMutableArray indexOfObject:fromFileName];
		[fromFileName release];
	}
	if (last) {
		int temp = (int)[completeMutableArray count];
		temp--;
		if ([completeMutableArray count] > 1) {
			temp--;
			[imageMutableArray addObject:[self loadImage:temp]];
			temp++;
			[imageMutableArray addObject:[self loadImage:temp]];
			if ([self isSmallImage:[imageMutableArray objectAtIndex:0] page:temp] == NO){
				[imageMutableArray removeObjectAtIndex:0];
				temp++;
			}
			temp--;
		} else {
			[imageMutableArray addObject:[self loadImage:temp]];
		}
		nowPage = temp;
	} else {
		if (page >= [completeMutableArray count]) {
			page = 0;
		}
		nowPage = page;
		if ([completeMutableArray count] > page) {
			[imageMutableArray addObject:[self loadImage:page]];
			page++;
			if ([completeMutableArray count] > page) {
				[imageMutableArray addObject:[self loadImage:page]];
			}
		}
	}
	readMode = (int)[defaults integerForKey:@"ReadMode"];
	[marksArray removeAllObjects];
	
	if (currentBookSetting) {
		if ([currentBookSetting objectForKey:@"readMode"]) {
			readMode = [[currentBookSetting objectForKey:@"readMode"] intValue];
		}
		if ([currentBookSetting objectForKey:@"marks"]) {
			[marksArray addObjectsFromArray:[currentBookSetting objectForKey:@"marks"]];
		}
	}
	

	[imageView setPageString:nil];
	[imageView setResolutionString:nil];
	[[self window] setTitle:currentBookName];
	
	[bookmarkArray removeAllObjects];
	if (currentBookSetting) {
		if ([currentBookSetting objectForKey:@"bookmarks"]) {
			[bookmarkArray addObjectsFromArray:[currentBookSetting objectForKey:@"bookmarks"]];
		}
	}
	[self setBookmarkMenu];
	
	[thumController setImageLoader:imageLoader];
	[thumController setmaxCacheCount:(int)[defaults integerForKey:@"ThumbnailCache"]];
	
	
	[progressIndicator stopAnimation:self];
	//[imageView displayRect:rect];
	/* MW-6 item 4: the load succeeded, so this window now has a book. Set
	   before the display pass, since -imageDisplay is what used to make the
	   old [imageView image] test start answering YES. */
	bookOpen = YES;
	/* v1.6.x: the load this -openPage:last: started has finished. Not the
	   very end of the method, but nothing below can start another open. */
	[self openDidEnd];
	/* MW-8: and this is the book window restoration will bring back. Made
	   here, once per open, rather than in -encodeRestorableStateWithCoder:,
	   which runs again after every page turn. */
	[self setCurrentBookBookmarkForPath:currentBookPath];
	/* And this is the point at which closing the last window means the user
	   is finished, rather than a first open having failed — see
	   -[AppController applicationShouldTerminateAfterLastWindowClosed:]. */
	[appController windowControllerDidOpenBook:self];
	/* v1.6.5: a window shown empty by File ▸ New Window is an ordinary book
	   window from here on — restorable again, and closed like any other if a
	   later open into it fails. */
	shownWithoutBook = NO;
	[[self window] setRestorable:YES];
	[self viewSet];
	[self imageDisplay];
	
	if ([thumController isVisible]||[defaults boolForKey:@"ShowThumbnailWhenOpen"]) {
		if (secondImage) {
			int temp = nowPage;
			temp--;
			[thumController showThumbnail:temp];
		} else {
			[thumController showThumbnail:nowPage];
		}
	}
	
}
/* Archive open progress (COArchive extracts everything up front).
 *
 * Before MW-1 this dequeued NSApp's whole event queue looking for Esc and
 * dropped everything else on the floor. That silently ate input, and with
 * more than one window it would have eaten input aimed at windows that
 * were not loading anything. It now only records progress and reports
 * whether the load was cancelled.
 *
 * Called on the background load thread for a top-level open (see
 * -runArchiveLoadNamed:usingBlock:), and on the calling thread for a
 * nested one. Touches no AppKit state — the sheet is refreshed by a timer
 * on the main thread. */
- (BOOL)archiveReadProgress:(long long)done total:(long long)total
{
	atomic_store(&archiveLoadDone, done);
	atomic_store(&archiveLoadTotal, total);
	return atomic_load(&archiveLoadCancelled) ? NO : YES;
}

- (NSWindow *)sheetParentWindow
{
	return [self window];
}

/* YES when a sheet can actually be attached. A sheet on a window that is
 * not on screen never appears and its modal loop would never end, so the
 * callers fall back to their pre-MW-1 app-modal behaviour instead. */
- (BOOL)canPresentSheet
{
	NSWindow *parent = [self sheetParentWindow];
	return (parent != nil && [parent isVisible] && ![parent isMiniaturized]);
}

#pragma mark archive load progress sheet

- (void)buildArchiveProgressSheet
{
	if (archiveProgressSheet) return;

	NSRect frame = NSMakeRect(0, 0, 420, 108);
	archiveProgressSheet = [[NSWindow alloc] initWithContentRect:frame
	                                                   styleMask:NSWindowStyleMaskTitled
	                                                     backing:NSBackingStoreBuffered
	                                                       defer:YES];
	NSView *content = [archiveProgressSheet contentView];

	/* Views are owned by the sheet's view hierarchy; the ivars are just
	 * handles, valid for as long as archiveProgressSheet is retained. */
	archiveProgressLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(20, 68, 380, 20)] autorelease];
	[archiveProgressLabel setBezeled:NO];
	[archiveProgressLabel setDrawsBackground:NO];
	[archiveProgressLabel setEditable:NO];
	[archiveProgressLabel setSelectable:NO];
	[archiveProgressLabel setLineBreakMode:NSLineBreakByTruncatingMiddle];
	[content addSubview:archiveProgressLabel];

	archiveProgressBar = [[[NSProgressIndicator alloc] initWithFrame:NSMakeRect(20, 44, 380, 16)] autorelease];
	[archiveProgressBar setStyle:NSProgressIndicatorStyleBar];
	[archiveProgressBar setIndeterminate:YES];
	[archiveProgressBar setUsesThreadedAnimation:YES];
	[content addSubview:archiveProgressBar];

	archiveProgressCancelButton = [[[NSButton alloc] initWithFrame:NSMakeRect(310, 8, 92, 32)] autorelease];
	[archiveProgressCancelButton setBezelStyle:NSBezelStyleRounded];
	[archiveProgressCancelButton setTitle:NSLocalizedString(@"Cancel", @"")];
	[archiveProgressCancelButton setKeyEquivalent:@"\033"];	/* Esc, as before MW-1 */
	[archiveProgressCancelButton setTarget:self];
	[archiveProgressCancelButton setAction:@selector(cancelArchiveLoad:)];
	[content addSubview:archiveProgressCancelButton];
}

- (IBAction)cancelArchiveLoad:(id)sender
{
	/* Unambiguous by construction: the sheet belongs to exactly one load,
	 * and the flag it sets is read only by that load's progress callback.
	 * An asynchronous load (KNOWN_ISSUES #33) is also told through its own
	 * loader; pendingArchiveLoader is nil for the synchronous path. */
	atomic_store(&archiveLoadCancelled, 1);
	[pendingArchiveLoader cancelArchiveRead];
	[archiveProgressLabel setStringValue:NSLocalizedString(@"Cancelling…", @"")];
	[archiveProgressCancelButton setEnabled:NO];
}

#pragma mark asynchronous archive load (KNOWN_ISSUES #33)

/* The run-loop modes an open resumes in. The default mode, and the modal-panel
   mode so that a book opened from inside an application-modal session (the All
   Bookmarks browser's Open button, which leaves the browser up) still finishes
   while that session runs, as it did when the whole open ran inside it. Not
   the event-tracking mode: the open does not resume in the middle of a menu
   being tracked or a window being resized, but straight after. Main-queue
   blocks alone would run in all three. */
static NSArray *COOpenResumeModes(void)
{
	return [NSArray arrayWithObjects:NSDefaultRunLoopMode, NSModalPanelRunLoopMode, nil];
}

/* Runs `block` on the main thread in COOpenResumeModes(), on a later pass than
   the current one. Callable from any thread. */
static void COPerformOpenStep(void (^block)(void))
{
	dispatch_async(dispatch_get_main_queue(), ^{
		[[NSRunLoop mainRunLoop] performInModes:COOpenResumeModes() block:block];
		CFRunLoopWakeUp(CFRunLoopGetMain());
	});
}

/* KNOWN_ISSUES #33, the loading half. The archive of the book this window is
   opening is read on a worker thread, and no modal session runs while it is:
   the other windows can be raised, paged and driven from the menus throughout.
   The open is continuation-passing, as the password prompt's already is — the
   read's completion resumes it at -continueOpenWithLoader:..., exactly where
   -openPage:last: would have gone on had the read been inline.

   A read that is still running after 150 ms gets the progress sheet, as before
   (a ZIP or non-solid RAR reads only its directory and never gets one). The
   sheet is window-modal and nothing more: its Cancel button (Esc) cancels the
   read, and the open then ends as a cancelled read always has. A quit cancels
   it the same way (-cancelArchiveLoadForTermination). Closing the window
   cancels it and drops the open (-windowWillClose:). While it runs,
   bookLoadInFlight keeps this window out of every other open, as before
   (-refuseOpenWhileBusy, and AppController's routing gate).

   The block captures — and so retains — the loader, `fromFileName` and self
   for as long as the read runs, which is the lifetime they need. */
- (void)beginArchiveLoadForLoader:(COImageLoader *)loader
							 page:(int)page
							 last:(BOOL)last
					 fromFileName:(NSString *)fromFileName
{
	archiveLoadInFlight = YES;
	archiveLoadQuitting = NO;
	pendingArchiveLoader = loader;
	atomic_store(&archiveLoadCancelled, 0);
	atomic_store(&archiveLoadDone, 0);
	atomic_store(&archiveLoadTotal, 0);
	unsigned int token = ++archiveLoadToken;
	unsigned int closeCountAtStart = windowCloseCount;

	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		[loader readArchive];
		COPerformOpenStep(^{
			[self archiveLoadDidFinishWithLoader:loader
											page:page
											last:last
									fromFileName:fromFileName
										   token:token
									  closeCount:closeCountAtStart];
		});
	});

	[self performSelector:@selector(presentArchiveProgressSheetForLoad:)
			   withObject:[NSNumber numberWithUnsignedInt:token]
			   afterDelay:0.15
				  inModes:COOpenResumeModes()];
}

/* Whether the load a completion or a delayed step belongs to is still this
   window's current one: the window has not been closed since it started (a
   close drops the load, and the registry may since have reused the window for
   another open) and no other load has started. */
- (BOOL)isCurrentArchiveLoad:(unsigned int)token closeCount:(unsigned int)closeCountAtStart
{
	return (archiveLoadInFlight
			&& token == archiveLoadToken
			&& windowCloseCount == closeCountAtStart);
}

- (void)presentArchiveProgressSheetForLoad:(NSNumber *)token
{
	if (!archiveLoadInFlight || archiveLoadQuitting || archiveProgressSheetShown
		|| [token unsignedIntValue] != archiveLoadToken) {
		return;
	}
	/* A slow load is worth showing the window for: the sheet is what says
	   something is happening, and its Cancel button is the way out. */
	[self showWindowForOpenIfNeeded];
	if (![self canPresentSheet]) {
		/* Miniaturized: the read carries on without a sheet. */
		return;
	}
	if ([[self window] attachedSheet] != nil) {
		/* An earlier sheet on this window — the "Cannot open" alert of a
		   previous open — is still up. Try again once it may have gone. */
		[self performSelector:_cmd withObject:token afterDelay:0.15 inModes:COOpenResumeModes()];
		return;
	}

	[self buildArchiveProgressSheet];
	[archiveProgressBar setIndeterminate:YES];
	[archiveProgressBar setDoubleValue:0.0];
	[archiveProgressCancelButton setEnabled:YES];
	NSString *name = [[pendingArchiveLoader displayPath] lastPathComponent];
	[archiveProgressLabel setStringValue:
		[NSString stringWithFormat:NSLocalizedString(@"Opening “%@”…", @""),
			name ? name : @""]];

	[[self sheetParentWindow] beginSheet:archiveProgressSheet
					   completionHandler:^(NSModalResponse r) { (void)r; }];
	[archiveProgressBar startAnimation:self];
	archiveProgressSheetShown = YES;

	/* The run loop retains the timer, and the timer this object; both are let
	   go by -endArchiveProgressSheet, which every end of the load reaches. */
	archiveProgressTimer = [NSTimer timerWithTimeInterval:0.05
												   target:self
												 selector:@selector(refreshArchiveProgress:)
												 userInfo:nil
												  repeats:YES];
	[[NSRunLoop currentRunLoop] addTimer:archiveProgressTimer forMode:NSRunLoopCommonModes];
	[self refreshArchiveProgress:nil];
}

/* Takes the asynchronous load's progress sheet down, if it is up, and stops
   its timer. Answers whether there was a sheet. */
- (BOOL)endArchiveProgressSheet
{
	[archiveProgressTimer invalidate];
	archiveProgressTimer = nil;
	if (!archiveProgressSheetShown) {
		return NO;
	}
	archiveProgressSheetShown = NO;
	[archiveProgressBar stopAnimation:self];
	[[self sheetParentWindow] endSheet:archiveProgressSheet];
	[archiveProgressSheet orderOut:self];
	return YES;
}

/* The read has returned (finished, failed or cancelled), on the main thread. */
- (void)archiveLoadDidFinishWithLoader:(COImageLoader *)loader
								  page:(int)page
								  last:(BOOL)last
						  fromFileName:(NSString *)fromFileName
								 token:(unsigned int)token
							closeCount:(unsigned int)closeCountAtStart
{
	if (![self isCurrentArchiveLoad:token closeCount:closeCountAtStart]) {
		/* The window was closed during the read. -windowWillClose: has already
		   put the book identity back, taken the sheet down and cleared the
		   load's state — and by now the window may be running another open,
		   whose state that is. Only what this open owns is dropped. */
		[self discardPendingOpen:loader fromFileName:fromFileName];
		return;
	}

	if (![self endArchiveProgressSheet]) {
		[self resumeOpenAfterArchiveReadWithLoader:loader page:page last:last fromFileName:fromFileName];
		return;
	}
	/* AppKit is still taking the progress sheet down, and the open may need
	   to attach another one straight away — a password prompt, a "Cannot
	   open" alert, or a nested archive's own progress sheet. Resume on a later
	   pass, as the password re-ask does. archiveLoadInFlight stays YES across
	   the gap, so the window's identity is still the pending open's to a close
	   or a quit landing in it. */
	COPerformOpenStep(^{
		if (![self isCurrentArchiveLoad:token closeCount:closeCountAtStart]) {
			[self discardPendingOpen:loader fromFileName:fromFileName];
			return;
		}
		[self resumeOpenAfterArchiveReadWithLoader:loader page:page last:last fromFileName:fromFileName];
	});
}

- (void)resumeOpenAfterArchiveReadWithLoader:(COImageLoader *)loader
										page:(int)page
										last:(BOOL)last
								fromFileName:(NSString *)fromFileName
{
	BOOL quitting = archiveLoadQuitting;
	archiveLoadInFlight = NO;
	archiveLoadQuitting = NO;
	pendingArchiveLoader = nil;

	if (quitting) {
		/* A quit cancelled this read, and the process is still here — it is
		   between the quit's two passes, or the quit did not go ahead. Ends as
		   a cancel, without the alert a failed read would get: nothing of this
		   book was persisted, and nothing is now. */
		[self abandonOpenWithLoader:loader fromFileName:fromFileName closeWindow:NO];
		return;
	}

	/* Lists the entries — a cancelled read leaves the book not opened, which
	   -openPageWithLoader:... ends silently — and may open nested archives,
	   which still read synchronously (-runArchiveLoadNamed:usingBlock:). */
	[loader finishArchiveRead];
	[self continueOpenWithLoader:loader page:page last:last fromFileName:fromFileName];
}

- (BOOL)cancelArchiveLoadForTermination
{
	if (!archiveLoadInFlight) {
		return NO;
	}
	archiveLoadQuitting = YES;
	atomic_store(&archiveLoadCancelled, 1);
	[pendingArchiveLoader cancelArchiveRead];
	BOOL dismissedSheet = [self endArchiveProgressSheet];
	/* A window shown only for this open has nothing in it to come back to:
	   ordered out, it is not saved as a restorable window either. */
	if (![self hasBookOpen] && !shownWithoutBook) {
		[[self window] orderOut:self];
	}
	return dismissedSheet;
}

- (BOOL)isLoadingRestoredBook
{
	return (restoredBookOpening && archiveLoadInFlight);
}

- (void)refreshArchiveProgress:(id)sender
{
	long long done = atomic_load(&archiveLoadDone);
	long long total = atomic_load(&archiveLoadTotal);
	if (total <= 0) return;

	if ([archiveProgressBar isIndeterminate]) {
		[archiveProgressBar setIndeterminate:NO];
		[archiveProgressBar setMinValue:0.0];
		[archiveProgressBar setMaxValue:1.0];
	}
	double fraction = (double)done / (double)total;
	if (fraction < 0.0) fraction = 0.0;
	if (fraction > 1.0) fraction = 1.0;
	[archiveProgressBar setDoubleValue:fraction];
}

- (void)runArchiveLoadNamed:(NSString *)name usingBlock:(void (^)(void))block
{
	/* Nested load (an archive inside an archive), or no window to hang a
	 * sheet on: run it inline. This is what every load did before MW-1,
	 * minus the event pump — it blocks, but it cannot swallow input.
	 *
	 * KNOWN_ISSUES #33: the book a window opens no longer comes through here
	 * (see -beginArchiveLoadForLoader:...); what does is an archive its
	 * listing opens — nested in an archive, or inside a folder or saved
	 * search — and that keeps this synchronous path and its modal session.
	 * A window that open has kept hidden (`openShowDeferred`) counts as one a
	 * sheet can be hung on: it is shown below if the load turns out slow. */
	if (archiveLoadDepth > 0 || (![self canPresentSheet] && !openShowDeferred)) {
		archiveLoadDepth++;
		block();
		archiveLoadDepth--;
		return;
	}

	archiveLoadDepth++;
	atomic_store(&archiveLoadCancelled, 0);
	atomic_store(&archiveLoadDone, 0);
	atomic_store(&archiveLoadTotal, 0);

	dispatch_semaphore_t done = dispatch_semaphore_create(0);
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		block();
		dispatch_semaphore_signal(done);
	});

	/* Most opens finish immediately and must not flash a sheet: the
	 * common formats never report progress at all — COZipArchive reads
	 * only the central directory and CORarArchive uses the header-only
	 * parser, both "near instant" by design. Only a load that is still
	 * running after a grace period is worth showing UI for. Blocking the
	 * main thread for that period is imperceptible and keeps the fast
	 * path behaving exactly as it did before MW-1. */
	dispatch_time_t grace = dispatch_time(DISPATCH_TIME_NOW, 150ull * NSEC_PER_MSEC);
	if (dispatch_semaphore_wait(done, grace) == 0) {
		dispatch_release(done);
		archiveLoadDepth--;
		return;
	}

	[self showWindowForOpenIfNeeded];
	if (![self canPresentSheet]) {
		dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
		dispatch_release(done);
		archiveLoadDepth--;
		return;
	}

	[self buildArchiveProgressSheet];
	[archiveProgressBar setIndeterminate:YES];
	[archiveProgressBar setDoubleValue:0.0];
	[archiveProgressCancelButton setEnabled:YES];
	[archiveProgressLabel setStringValue:
		[NSString stringWithFormat:NSLocalizedString(@"Opening “%@”…", @""),
			name ? name : @""]];

	NSWindow *sheet = archiveProgressSheet;
	NSWindow *parent = [self sheetParentWindow];

	[parent beginSheet:sheet completionHandler:^(NSModalResponse r) { (void)r; }];
	[archiveProgressBar startAnimation:self];

	/* The read is already running off the main thread. The main thread now
	 * drives a modal session, so AppKit dispatches events normally (blocked
	 * by modality where appropriate) instead of us dequeuing and dropping
	 * them as before MW-1.
	 *
	 * The loop's exit condition is the semaphore, not a -stopModal posted
	 * from another thread. That matters: a -stopModal delivered before the
	 * modal loop had started would be a no-op and the loop would then never
	 * end. Here a read that finishes early just makes the next wait return
	 * 0, whenever that happens. The timed wait also paces the loop, so
	 * -runModalSession: is not spun continuously. */
	NSModalSession session = [NSApp beginModalSessionForWindow:sheet];
	for (;;) {
		dispatch_time_t slice = dispatch_time(DISPATCH_TIME_NOW, 20ull * NSEC_PER_MSEC);
		if (dispatch_semaphore_wait(done, slice) == 0) break;
		[NSApp runModalSession:session];
		[self refreshArchiveProgress:nil];
	}
	[NSApp endModalSession:session];
	dispatch_release(done);

	[archiveProgressBar stopAnimation:self];
	[parent endSheet:sheet];
	[sheet orderOut:self];
	archiveLoadDepth--;
}

/* Password prompt for an encrypted archive, called by COImageLoader while
 * opening a document. Built in code (NSAlert + a masked accessory field),
 * so no NIB is involved.
 *
 * Presented as a sheet on the window whose book needs the password
 * (MW-1); before that it was `[alert runModal]`, which blocked the whole
 * application and showed no association with any window. The caller's
 * retry loop needs an answer synchronously, so the sheet is run with its
 * own modal loop rather than left to the completion handler. Falls back
 * to app-modal when there is no window to attach to.
 *
 * Always called on the main thread: COImageLoader reaches it from
 * -checkArchiveContainer:, which runs after the background archive read
 * has finished.
 *
 * Returns the entered password, or nil for Cancel — and also for an empty
 * entry, so hitting OK with a blank field cannot spin the caller's retry
 * loop. COImageLoader treats nil as "leave the archive closed", which is
 * the same fail-closed path encrypted archives took before. */
- (NSString *)askArchivePassword:(COImageLoader *)loader wrongPassword:(BOOL)wrong
{
	NSAssert([NSThread isMainThread],
	         @"askArchivePassword: must be called on the main thread");

	NSAlert *alert = [[[NSAlert alloc] init] autorelease];
	[alert setMessageText:(wrong ? NSLocalizedString(@"Incorrect password",@"")
	                             : NSLocalizedString(@"Password required",@""))];
	NSString *name = [[loader displayPath] lastPathComponent];
	[alert setInformativeText:[NSString stringWithFormat:
		NSLocalizedString(@"Enter the password for \"%@\".",@""), name ? name : @""]];
	[alert addButtonWithTitle:NSLocalizedString(@"OK",@"")];
	[alert addButtonWithTitle:NSLocalizedString(@"Cancel",@"")];

	NSSecureTextField *field = [[[NSSecureTextField alloc]
		initWithFrame:NSMakeRect(0,0,260,24)] autorelease];
	[[field cell] setWraps:NO];
	[[field cell] setScrollable:YES];
	[alert setAccessoryView:field];
	[[alert window] setInitialFirstResponder:field];

	NSModalResponse response;
	if ([self canPresentSheet]) {
		[alert beginSheetModalForWindow:[self sheetParentWindow]
		              completionHandler:^(NSModalResponse r) {
			[NSApp stopModalWithCode:r];
		}];
		response = [NSApp runModalForWindow:[alert window]];
	} else {
		response = [alert runModal];
	}

	if (response != NSAlertFirstButtonReturn)
		return nil;					// Cancel
	NSString *entered = [[[field stringValue] copy] autorelease];
	return ([entered length] > 0) ? entered : nil;
}

/* The same prompt, window-modal, for the open this window is driving itself
 * (KNOWN_ISSUES #33). The synchronous version above stays for the one caller
 * that still needs an answer inline: a *nested* archive, opened by
 * COImageLoader from inside another archive's entry list, where the loader is
 * built without `deferPasswordPrompt` and the enclosing load is already
 * running inline.
 *
 * There is no modal loop here — only `beginSheetModalForWindow:`, so AppKit
 * blocks this window and leaves every other one live, which is the whole point
 * of the change. The open therefore has to continue from the completion
 * handler:
 *
 *   OK    → -tryPassword: → open (or ask again if it was wrong)
 *   Cancel → -abandonOpenWithLoader:...closeWindow:NO (decision 1)
 *
 * An empty entry counts as Cancel, as it did before: hitting OK with a blank
 * field cannot loop.
 *
 * The block retains the loader, `fromFileName` and self for as long as the
 * sheet is up (MRC copies retain captured objects), which is exactly the
 * lifetime needed — the controller cannot be deallocated while its own sheet
 * is waiting. Wrong-password re-prompts are not capped: the sheet's Cancel
 * button is the exit, an attempt limit would only add a second way to fail,
 * and it would buy nothing for a local file (decision 2). */
- (void)askPasswordForLoader:(COImageLoader *)loader
						page:(int)page
						last:(BOOL)last
				fromFileName:(NSString *)fromFileName
			   wrongPassword:(BOOL)wrong
{
	/* A window this open has kept hidden is the sheet's parent: show it. */
	[self showWindowForOpenIfNeeded];
	if (![self canPresentSheet]) {
		/* No window to hang a sheet on — the same fallback the rest of this
		   class uses. Ask inline and finish the open right here. */
		NSString *entered = [self askArchivePassword:loader wrongPassword:wrong];
		if (entered == nil ||
			[loader tryPassword:entered] != COArchiveCryptoOK) {
			[self abandonOpenWithLoader:loader
						   fromFileName:fromFileName
							closeWindow:(entered != nil)];
			return;
		}
		[self openPageWithLoader:loader page:page last:last fromFileName:fromFileName];
		return;
	}

	NSAlert *alert = [[[NSAlert alloc] init] autorelease];
	[alert setMessageText:(wrong ? NSLocalizedString(@"Incorrect password",@"")
								 : NSLocalizedString(@"Password required",@""))];
	NSString *name = [[loader displayPath] lastPathComponent];
	[alert setInformativeText:[NSString stringWithFormat:
		NSLocalizedString(@"Enter the password for \"%@\".",@""), name ? name : @""]];
	[alert addButtonWithTitle:NSLocalizedString(@"OK",@"")];
	[alert addButtonWithTitle:NSLocalizedString(@"Cancel",@"")];

	NSSecureTextField *field = [[[NSSecureTextField alloc]
		initWithFrame:NSMakeRect(0,0,260,24)] autorelease];
	[[field cell] setWraps:NO];
	[[field cell] setScrollable:YES];
	[alert setAccessoryView:field];
	[[alert window] setInitialFirstResponder:field];

	/* Read by -isWaitingForUserInput, so -[AppController settleLaunch] can tell
	   "restoration is still working" from "restoration is waiting for a
	   person" and not spend its deadline on the latter. Set here rather than
	   counted, and cleared only where this open ends, so the gap between a
	   rejected password and the next sheet is covered too. */
	passwordOpenInFlight = YES;

	/* Whether this window is closed while the prompt is up — see
	   `windowCloseCount` in the header for why this is not a flag. */
	unsigned int closeCountAtPrompt = windowCloseCount;

	[alert beginSheetModalForWindow:[self sheetParentWindow]
				 completionHandler:^(NSModalResponse r) {
		if (windowCloseCount != closeCountAtPrompt) {
			/* AppKit dismisses a sheet when its parent window closes, so this
			   handler can run for a window that no longer exists. */
			[self discardPendingOpen:loader fromFileName:fromFileName];
			return;
		}

		NSString *entered = nil;
		if (r == NSAlertFirstButtonReturn) {
			entered = [field stringValue];
			if ([entered length] == 0) entered = nil;
		}
		if (entered == nil) {						/* Cancel, or a blank entry */
			[self abandonOpenWithLoader:loader
						   fromFileName:fromFileName
							closeWindow:NO];
			passwordOpenInFlight = NO;
			return;
		}

		COArchiveCryptoStatus status = [loader tryPassword:entered];
		if (status == COArchiveCryptoOK) {
			[self openPageWithLoader:loader page:page last:last fromFileName:fromFileName];
			passwordOpenInFlight = NO;
			return;
		}
		if (status == COArchiveCryptoWrongPassword) {
			/* Ask again on the next pass rather than from inside this handler:
			   AppKit is still dismissing the old sheet, and a new one cannot be
			   attached to the window until it has gone. passwordOpenInFlight
			   stays YES across the gap, so a queued Finder open cannot be
			   drained into it. */
			dispatch_async(dispatch_get_main_queue(), ^{
				if (windowCloseCount != closeCountAtPrompt) {
					[self discardPendingOpen:loader fromFileName:fromFileName];
					return;
				}
				[self askPasswordForLoader:loader
									  page:page
									  last:last
							  fromFileName:fromFileName
							 wrongPassword:YES];
			});
			return;
		}
		/* Not a password problem any more (an unreadable archive): give up the
		   same way a bad book does, but without closing the window — the user
		   did supply a password, so this is not the cancel case. */
		[self abandonOpenWithLoader:loader
					   fromFileName:fromFileName
						closeWindow:NO];
		passwordOpenInFlight = NO;
	}];
}

/* Take a password prompt down so the application can quit (the #24 task's item
   B). Ending the sheet runs its completion handler with a response that is not
   OK, which is the ordinary cancel path — so this needs no separate teardown of
   its own, and the "a window that had a book keeps it" rule holds here too.
   Silent when this window has no prompt up. */
- (BOOL)cancelPasswordPromptForTermination
{
	if (!passwordOpenInFlight) {
		return NO;
	}
	NSWindow *sheet = [[self window] attachedSheet];
	if (sheet == nil) {
		return NO;
	}
	[[self window] endSheet:sheet returnCode:NSModalResponseCancel];
	return YES;
}

/* The window went away while its password prompt or its archive read was in
   flight: drop what the pending open owns. Deliberately touches nothing else.
   -windowWillClose: has already torn the window down, put its book identity
   back, stopped the spinner and cleared passwordOpenInFlight/bookLoadInFlight
   (and the read's own state) — and by the time
   this runs the registry may have reused the window for a newer open, whose
   flags and spinner those now are. */
- (void)discardPendingOpen:(COImageLoader *)loader fromFileName:(NSString *)fromFileName
{
	[loader release];
	[fromFileName release];
}

/* Whether this window has an open that is waiting on a person (its password
   sheet, or the moment between a rejected password and the next sheet). */
- (BOOL)isWaitingForUserInput
{
	return passwordOpenInFlight;
}

/* MW-5: -sheetOk:/-sheetCancel: moved to AppController. Their only users are
   the Preferences window's OK/Cancel buttons, and Preferences stays in
   MainMenu.xib while this class became the File's Owner of BookWindow.xib. */


#pragma mark dock
/* -[AppController applicationDockMenu:] (MW-3) queries this instead of
   reading imageView directly. MW-6 item 4: it now answers from the
   controller's own `bookOpen` state rather than from the view, and is the
   one predicate every "is a book open" test in this class goes through. */
- (BOOL)hasBookOpen
{
	return bookOpen;
}

- (BOOL)isBookLoadInFlight
{
	return bookLoadInFlight;
}

- (id)thumController
{
	return thumController;
}


#pragma mark -
#pragma mark load
- (NSImage*)loadThumbnailImage:(int)index
{
	return [thumController loadImage:index];
}

/* cacheArray is shared by the lookahead threads and the main thread
   (thumbnail panel, page-bar bubble), so every operation on it goes
   through these, under cacheLock (code review M8). */
- (NSImage *)cachedImageNamed:(NSString *)name
{
	NSImage *found = nil;
	[cacheLock lock];
	int i;
	for (i=0; i<[cacheArray count]; i++) {
		id object = [cacheArray objectAtIndex:i];
		if ([name isEqualToString:[object objectForKey:@"name"]]) {
			[[object retain] autorelease];
			[cacheArray addObject:object];
			[cacheArray removeObjectAtIndex:i];
			found = [[[object objectForKey:@"image"] retain] autorelease];
			break;
		}
	}
	[cacheLock unlock];
	return found;
}

- (void)cacheImage:(NSImage *)image named:(NSString *)name
{
	if (!image || !name) return;
	[cacheLock lock];
	[cacheArray addObject:[NSDictionary dictionaryWithObjectsAndKeys:name,@"name",image,@"image",nil]];
	[cacheLock unlock];
}

- (void)trimImageCache
{
	[cacheLock lock];
	while ([cacheArray count] > cacheSize+4) [cacheArray removeObjectAtIndex:0];
	[cacheLock unlock];
}

- (NSImage*)loadImage:(int)index
{
	if (cacheSize != 0) {
		NSImage *cached = [self cachedImageNamed:[completeMutableArray objectAtIndex:index]];
		if (cached) return cached;
	}
	if ([imageView image]) {
		if (secondImage) {
			int temp = nowPage;
			temp--;
			if (index == temp) {
				if (cacheSize != 0) {
					[self cacheImage:secondImage named:[completeMutableArray objectAtIndex:index]];
				}
				//NSLog(@"return2 %@",[completeMutableArray objectAtIndex:index]);
				return secondImage;
			}
			temp--;
			if (index == temp) {
				if (cacheSize != 0) {
					[self cacheImage:firstImage named:[completeMutableArray objectAtIndex:index]];
				}
				//NSLog(@"return2 %@",[completeMutableArray objectAtIndex:index]);
				return firstImage;
			}
		} else {
			int temp = nowPage;
			temp--;
			if (index == temp) {
				if (cacheSize != 0) {
					[self cacheImage:firstImage named:[completeMutableArray objectAtIndex:index]];
				}
				//NSLog(@"return2 %@",[completeMutableArray objectAtIndex:index]);
				return firstImage;
			}
		}
	}
	
	NSImage *image = [imageLoader itemAtIndex:index];	
    /*
	NSImageRep*	rep;
	NSArray *repArray=[image representations];
	for(repi=0;repi<[repArray count];repi++){
		rep =[repArray objectAtIndex:repi];
		if(rep){
			heightValue=(int)[rep pixelsHigh];
			widthValue=(int)[rep pixelsWide];
			break;
		}
	}
	if( (widthValue>0 && heightValue>0) && ([image size].width != widthValue || [image size].height != heightValue) ){
		//[image setScalesWhenResized:YES];
		[image setSize:NSMakeSize(widthValue,heightValue)];
	}
     */
	if (cacheSize != 0) {
		[self cacheImage:image named:[completeMutableArray objectAtIndex:index]];
		//NSLog(@"load %@",[completeMutableArray objectAtIndex:index]);
	}
	[self trimImageCache];
	return image;
}

/* The two thread entry points. -lookahead and -lookaheadAndCompose are also
   called directly on the main thread (the loop branches in
   -lockedImageDisplay), where nothing needs counting because they cannot
   outlive their caller; only a *detached* run does. The count is incremented
   before the detach, not here, so a thread that has not been scheduled yet is
   already accounted for. The argument is the generation the thread was
   detached in (see `lookaheadGeneration`).

   Each gets its own autorelease pool: the existing bodies create one only
   after taking `lock`, so anything autoreleased while blocked on it would
   otherwise have no pool. */
-(void)lookaheadThread:(NSNumber *)generation
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[self lookaheadForGeneration:[generation unsignedIntValue] compose:NO];
	atomic_fetch_sub(&pendingLookaheadCount, 1);
	[pool release];
}

-(void)lookaheadAndComposeThread:(NSNumber *)generation
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[self lookaheadForGeneration:[generation unsignedIntValue] compose:YES];
	atomic_fetch_sub(&pendingLookaheadCount, 1);
	[pool release];
}

- (void)detachLookaheadComposing:(BOOL)compose
{
	NSNumber *generation = [NSNumber numberWithUnsignedInt:atomic_load(&lookaheadGeneration)];
	atomic_fetch_add(&pendingLookaheadCount, 1);
	[NSThread detachNewThreadSelector:(compose ? @selector(lookaheadAndComposeThread:)
	                                           : @selector(lookaheadThread:))
	                         toTarget:self withObject:generation];
}

/* Waits (bounded) until no detached lookahead is left, then takes `lock`
   once, as the old barrier did: a lookahead that is mid-page holds it.
   The wait is bounded on purpose. -loadImage: can reach an archive read, and
   a read that ends up on the main thread's modal progress path would
   deadlock an unbounded wait. When it times out, the generation moves on,
   so a thread still queued behind `lock` returns without touching anything
   when it gets there. Returns whether the wait timed out. */
- (BOOL)waitForDetachedLookahead
{
	BOOL timedOut = NO;
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
	while (atomic_load(&pendingLookaheadCount) > 0) {
		if ([deadline timeIntervalSinceNow] <= 0) {
			timedOut = YES;
			atomic_fetch_add(&lookaheadGeneration, 1);
			break;
		}
		[NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
	}
	[lock lock];
	[lock unlock];
	return timedOut;
}

- (void)waitForLookahead
{
	[self waitForDetachedLookahead];
}

/* `threadStop` asks a running lookahead to stop at its next page boundary.
   A thread that saw the flag has already cleared it; clear it for the case
   where none did. */
- (void)stopLookahead
{
	threadStop = YES;
	[self waitForDetachedLookahead];
	threadStop = NO;
}

/* Called before either place that tears a book down: -windowWillClose: and
   -openPage:last:'s replacement of the previous book. Both release
   imageLoader and empty imageMutableArray / cacheArray, which is exactly
   what a lookahead thread is writing into.

   -stopLookahead covers a running thread and one that was detached but has
   not entered the body yet. The generation moves on in any case: a thread
   still waiting for `lock` after a timed-out wait would otherwise read the
   released imageLoader, or the next book's (code review M5).
   +detachNewThreadSelector:toTarget: retains this object for the thread's
   duration, so the controller itself stays valid. */
- (void)joinLookaheadThreads
{
	[self stopLookahead];
	atomic_fetch_add(&lookaheadGeneration, 1);
}

-(void)lookahead
{
	[self lookaheadForGeneration:atomic_load(&lookaheadGeneration) compose:NO];
}

-(void)lookaheadAndCompose
{
	[self lookaheadForGeneration:atomic_load(&lookaheadGeneration) compose:YES];
}

/* A detached run from an earlier generation: the main thread stopped
   waiting for it and has moved on. */
- (BOOL)lookaheadGenerationEnded:(unsigned int)generation
{
	return generation != atomic_load(&lookaheadGeneration);
}

-(void)lookaheadForGeneration:(unsigned int)generation compose:(BOOL)compose
{
	if (compose) {
		[self composeLookaheadForGeneration:generation];
		return;
	}
	[lock lock];
	if ([self lookaheadGenerationEnded:generation]) {
		[lock unlock];
		return;
	}
	threadCount++;
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	int i = nowPage;
	i += [imageMutableArray count];
	
	if (i < [completeMutableArray count]) {
		while([imageMutableArray count] < 2) {
			if (threadStop || [self lookaheadGenerationEnded:generation]) {
				threadStop = NO;
				threadCount--;
				[lock unlock];
				[pool release];
				return;
			}
			[imageMutableArray addObject:[self loadImage:i]];
			i = nowPage;
			i += [imageMutableArray count];
			if (i == [completeMutableArray count]) {
				break;
			}
		}
	} else if (nowPage == [completeMutableArray count]) {
	} else if (nowPage > [completeMutableArray count]) {
		nowPage = (int)[completeMutableArray count];
	}
	threadStop = NO;
	threadCount--;
	[lock unlock];
	[pool release];
}

-(void)composeLookaheadForGeneration:(unsigned int)generation
{
	[lock lock];
	if ([self lookaheadGenerationEnded:generation]) {
		[lock unlock];
		return;
	}
	threadCount++;
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	int i = nowPage;
	i += [imageMutableArray count];
	
	
	if (i < [completeMutableArray count]) {
		 while([imageMutableArray count] < 2) {
			 if (threadStop || [self lookaheadGenerationEnded:generation]) {
				 threadCount--;
				 threadStop = NO;
				 [lock unlock];
				 [pool release];
				 return;
			 }
			 [imageMutableArray addObject:[self loadImage:i]];
			 i = nowPage;
			 i += [imageMutableArray count];
			 if (i == [completeMutableArray count]) {
				 break;
			 }
		 }
	} else if (nowPage == [completeMutableArray count]) {
	} else if (nowPage > [completeMutableArray count]) {
		nowPage = (int)[completeMutableArray count];
	}
	
	if (threadStop) {
		threadCount--;
		threadStop = NO;
		[lock unlock];
		[pool release];
		return;
	}

	threadStop = NO;
	threadCount--;
	[lock unlock];
	[pool release];
}

#pragma mark image

-(BOOL)isSmallImage:(NSImage *)image page:(int)page
{
	int widthValue,heightValue;
	widthValue = [image size].width;
	heightValue = [image size].height;	
	if ([marksArray count] > 0 && page >= 0) {
		if ([marksArray containsObject:[NSString stringWithFormat:@"%i",page]]) {
			return NO;
		}
		if ([marksArray containsObject:[NSString stringWithFormat:@"%i-%i",page,page+1]]) {
			return YES;
		}
		if ([marksArray containsObject:[NSString stringWithFormat:@"%i-%i",page-1,page]]) {
			return YES;
		}
	}
	float setTemp;
	int s = 1000;
	setTemp = (float)singleSetting/s;
	float realTemp;
	realTemp = (float)widthValue/heightValue;
	if (setTemp < realTemp) {
		//big
		return NO;
	} else {
		//small
		return YES;
	}
}

/* Draws the spread. Each page goes straight into the view via
 * -[CustomImageView drawImages:and:]; there is no intermediate composite.
 *
 * The legacy "Old" path (BufferingMode = 0) used to branch here into
 * -returnComposeImage:and:, which scaled both pages into a lock-focus
 * canvas that was then scaled again into the view — two resampling steps
 * against this path's one. It was removed along with its screen cache;
 * see docs/DECISIONS.md. */
-(void)composeImage
{
	[imageView setImages:secondImage];
}

#pragma mark display

-(void)imageDisplay
{
	/*
	NSTimeInterval start,stop,elapsed;
	start=[NSDate timeIntervalSinceReferenceDate];
	*/
	//[lock lock];
	//[lock unlock];
	//[window disableFlushWindow];
	
	NSDisableScreenUpdates();
    [self lockedImageDisplay];
    NSEnableScreenUpdates();

	/* MW-8: the page this window would come back to has changed. This is the
	   only way into -lockedImageDisplay from outside, so it is the one place
	   a page turn has to be reported from. AppKit coalesces the invalidation
	   and re-encodes once, at the end of the run loop pass. */
	[[self window] invalidateRestorableState];

	//[window enableFlushWindow];
	//[window flushWindowIfNeeded];
	
	/*
	stop=[NSDate timeIntervalSinceReferenceDate];
	elapsed=stop-start;
	NSLog(@"%f",elapsed);
	 */
}

-(void)lockedImageDisplay
{
	/* No pages (a bookless ⌘N window, or one left empty by a cancelled
	   password prompt): nowPage 0 equals the count 0, which the branches
	   below read as "end of book". With LoopCheck 0 that rewinds and calls
	   this method again, without bound. */
	if ([completeMutableArray count] == 0) return;
	/* The display reads and removes the pages the last lookahead added;
	   it must not do so while that lookahead is still adding them, which
	   the `while ... count` polls below alone did not prevent (code review
	   M5). Every keyboard next-page already waited like this before
	   calling here. */
	[self waitForLookahead];
	if (readMode > 1) {
		if (nowPage == [completeMutableArray count]) {
			if (loopCheck == 0) {
				nowPage = 0;
				[self lookahead];
				[self lockedImageDisplay];
			} else if (loopCheck == 1) {
				[self nextFolder];
			} else if (loopCheck == 2) {
				[self nextFolder];
			} else {
				if (timerSwitch) {
					[timer invalidate];
					timer = nil;
					timerSwitch=NO;
				}
			}
		} else if (nowPage < [completeMutableArray count]) {
			/* No lookahead is running any more (waited for above), so an
			   empty list will not fill by itself: read the page here. */
			if ([imageMutableArray count] == 0) [self lookahead];
			if ([imageMutableArray count] == 0) return;
			//[self isSmallImage:[imageMutableArray objectAtIndex:0] page:nowPage+1];
			[imageView setImage:nil];
			[firstImage release];
			firstImage = nil;
			[secondImage release];
			secondImage = nil;
			
			
			nowPage++;
			firstImage = [[imageMutableArray objectAtIndex:0] retain];
			[self setPageTextField];
			[imageView setImage:firstImage];
			//[imageView setImage:[imageMutableArray objectAtIndex:0]];
			[imageMutableArray removeObjectAtIndex:0];
			[self detachLookaheadComposing:NO];
		}
	} else {
		if (nowPage < [completeMutableArray count]) {			
			/* As above: nothing will fill the list behind this point. */
			if ([imageMutableArray count] == 0) [self lookaheadAndCompose];
			if ([imageMutableArray count] == 0) return;
			[imageView setImage:nil];
			[firstImage release];
			firstImage = nil;
			[secondImage release];
			secondImage = nil;
			
			if ([self isSmallImage:[imageMutableArray objectAtIndex:0] page:nowPage+1] == YES) {
				/* The second page of a possible spread; this used to wait
				   for a still-running lookahead to add it. */
				if (nowPage+1 != [completeMutableArray count] && [imageMutableArray count] == 1) {
					[self lookaheadAndCompose];
				}
				if ([imageMutableArray count] > 1) {
					if ([self isSmallImage:[imageMutableArray objectAtIndex:1] page:nowPage+2] == YES) {
						firstImage = [[imageMutableArray objectAtIndex:0] retain];
						secondImage = [[imageMutableArray objectAtIndex:1] retain];
						
						nowPage += 2;
						[self setPageTextField];
						[self composeImage];
						[imageMutableArray removeObjectsInRange:NSMakeRange(0,2)];
					} else {
						nowPage++;
						firstImage = [[imageMutableArray objectAtIndex:0] retain];
						[self setPageTextField];
						[imageView setImage:firstImage];
						//[imageView setImage:[imageMutableArray objectAtIndex:0]];
						[imageMutableArray removeObjectAtIndex:0];
					}
				} else {
					nowPage++;
					firstImage = [[imageMutableArray objectAtIndex:0] retain];
					[self setPageTextField];
					[imageView setImage:firstImage];
					//[imageView setImage:[imageMutableArray objectAtIndex:0]];
					[imageMutableArray removeObjectAtIndex:0];
					
				}
			} else {
				nowPage++;
				firstImage = [[imageMutableArray objectAtIndex:0] retain];
				[self setPageTextField];
				[imageView setImage:firstImage];
				//[imageView setImage:[imageMutableArray objectAtIndex:0]];
				[imageMutableArray removeObjectAtIndex:0];
			}
			[self detachLookaheadComposing:YES];
		} else if (nowPage == [completeMutableArray count]) {
			if (loopCheck == 0) {
				nowPage = 0;
				[self lookaheadAndCompose];
				[self lockedImageDisplay];
			} else if (loopCheck == 1) {
				[self nextFolder];
				return;
			} else if (loopCheck == 2) {
				[self nextFolder];
				return;
			} else {
				if (timerSwitch) {
					[timer invalidate];
					timer = nil;
					timerSwitch=NO;
				}
			}
		}
	}
}


#pragma mark -
#pragma mark preferences

/* PreferenceController posts this (MW-3) instead of calling
   -[BookWindowController setPreferences] directly. */
- (void)preferencesDidChange:(NSNotification *)notification
{
	[self setPreferences];
}

- (void)setPreferences
{
	/* Below, the page and cache lists are changed and re-sorted on the main
	   thread; no lookahead may be adding to them meanwhile (code review M5). */
	[self waitForLookahead];
	[keyArray release];
	[keyArrayMode2 release];
	[keyArrayMode3 release];
	[mouseArray release];
	[mouseArrayMode2 release];
	[mouseArrayMode3 release];
	keyArray = [[NSMutableArray alloc] initWithArray:[defaults arrayForKey:@"KeyArray"]];
	keyArrayMode2 = [[NSMutableArray alloc] initWithArray:[defaults arrayForKey:@"KeyArrayMode2"]];
	keyArrayMode3 = [[NSMutableArray alloc] initWithArray:[defaults arrayForKey:@"KeyArrayMode3"]];
	mouseArray = [[NSMutableArray alloc] initWithArray:[defaults arrayForKey:@"MouseArray"]];
	mouseArrayMode2 = [[NSMutableArray alloc] initWithArray:[defaults arrayForKey:@"MouseArrayMode2"]];
	mouseArrayMode3 = [[NSMutableArray alloc] initWithArray:[defaults arrayForKey:@"MouseArrayMode3"]];
	
	rememberBookSettings = [defaults boolForKey:@"RememberBookSettings"];
	readSubFolder = [defaults boolForKey:@"ReadSubFolder"];
	loopCheck = (int)[defaults integerForKey:@"LoopCheck"];
	sliderValue = [defaults floatForKey:@"SlideshowDelay"];
	
	prevPageMode = (int)[defaults integerForKey:@"PrevPageMode"];
	canScrollMode = (int)[defaults integerForKey:@"CanScrollMode"];
	
	
	alwaysRememberLastPage = [defaults boolForKey:@"AlwaysRememberLastPage"];
	goToLastPageMode = (int)[defaults integerForKey:@"GoToLastPage"];
	
	openLinkMode = (int)[defaults integerForKey:@"OpenLinkMode"];
	
	changeCurrentFolderMode = (int)[defaults integerForKey:@"ChangeCurrentFolder"];
	
	int oldOpenRecentLimit = openRecentLimit;
	openRecentLimit = (int)[defaults integerForKey:@"OpenRecentLimit"];
	if (oldOpenRecentLimit!=openRecentLimit) {
		if (openRecentLimit>0) {
			int tmpOpenRecentLimit = openRecentLimit;
			if ([imageView image]) {
				tmpOpenRecentLimit++;
			}
			NSMutableArray *array;
			if (![defaults arrayForKey:@"RecentItems"]) {
				array = [NSMutableArray array];
			} else {
				array = [NSMutableArray arrayWithArray:[defaults arrayForKey:@"RecentItems"]];
			}
			while ([array count] > tmpOpenRecentLimit) {
				[array removeLastObject];
			}
			[defaults setObject:array forKey:@"RecentItems"];
			[self setOpenRecentMenu];
			if ([imageView image]) {
				NSMenu *menu=[[appController openRecentMenuItem] submenu];
				[[menu itemAtIndex:0] setState:NSOnState];
				[[menu itemAtIndex:0] setEnabled:NO];
			}
		} else {
			[defaults removeObjectForKey:@"RecentItems"];
			[self setOpenRecentMenu];
		}
	}
	
	/*cache*/
	cacheSize = MAX(0, (int)[defaults integerForKey:@"ImageCache"]);	// see -windowDidLoad
	[self trimImageCache];
	[thumController setmaxCacheCount:(int)[defaults integerForKey:@"ThumbnailCache"]];
	
	[fullImagePanel setFitMode:[defaults boolForKey:@"FitOriginal"]];
	
	

	
	[[self window] disableFlushWindow];
	
    BOOL useCalayer = [defaults boolForKey:@"UseCALayer"];
    [imageView setUseCalayer:useCalayer];
	
	BOOL ignoreImageDpi = [defaults boolForKey:@"IgnoreImageDpi"];
	[fullImageView setIgnoreImageDpi:ignoreImageDpi];
	[imageView setIgnoreImageDpi:ignoreImageDpi];

    NSColor *viewBackGround = [[NSUnarchiver unarchiveObjectWithData:[defaults objectForKey:@"ViewBackGroundColor"]] colorWithAlphaComponent:1];
    [[self window] setBackgroundColor:viewBackGround];
    if (fitScreenMode > 0) {
        [[imageView enclosingScrollView] setBackgroundColor:viewBackGround];
    }
	
	if (readMode != [defaults integerForKey:@"ReadMode"]) {
		if ([imageView image]) {
			BOOL readModeTemp = NO;
			if (currentBookSetting) {
				if ([currentBookSetting objectForKey:@"readMode"]) {
					readModeTemp = YES;
				}
			}
			if (!readModeTemp) {
				[self changeReadMode:(int)[defaults integerForKey:@"ReadMode"]];
			}
		}
	}
	if (sortMode != [defaults integerForKey:@"SortMode"]) {
		if ([imageView image]) {
			BOOL sortModeTemp = NO;
			if (currentBookSetting) {
				if ([currentBookSetting objectForKey:@"sortMode"]) {
					sortModeTemp = YES;
				}
			}
			if (!sortModeTemp) {
				[self setSortMode:(int)[defaults integerForKey:@"SortMode"] page:-1];
				[self goTo:0 array:nil];
			}
		}
	}
	if (singleSetting != [defaults integerForKey:@"SingleSetting"]) {
		singleSetting = (int)[defaults integerForKey:@"SingleSetting"];
		if ([imageView image]) {
			if (secondImage) {
				if (![self isSmallImage:firstImage page:nowPage-2] || ![self isSmallImage:secondImage page:nowPage-1]) {
					[imageMutableArray insertObject:secondImage atIndex:0];
					[imageMutableArray insertObject:firstImage atIndex:0];
					[secondImage release];
					secondImage = nil;
					[firstImage release];
					firstImage = nil;
					nowPage-=2;
					[self imageDisplay];
				}
			} else {
				if ([self isSmallImage:firstImage page:nowPage-1]) {
					[imageMutableArray insertObject:firstImage atIndex:0];
					nowPage--;
					[self imageDisplay];
				}
			}
		}
	}
	
	if (interpolation != [defaults integerForKey:@"Interpolation"]) {
		if (maxEnlargement != [defaults integerForKey:@"MaxEnlargement"] ){
			maxEnlargement = (int)[defaults integerForKey:@"MaxEnlargement"];
		}
		interpolation = (int)[defaults integerForKey:@"Interpolation"];
		[imageView setInterpolation:interpolation];
		if ([imageView image]) {
			if (secondImage) {
				[self composeImage];
			} else {
				[imageView setImage:firstImage];
			}
			[self lookaheadAndCompose];
		}
	} else if (maxEnlargement != [defaults integerForKey:@"MaxEnlargement"]) {
		maxEnlargement = (int)[defaults integerForKey:@"MaxEnlargement"];
		if ([imageView image]) {
			if (secondImage) {
				[self composeImage];
			} else {
				[imageView setImage:firstImage];
			}
			[self lookaheadAndCompose];
		}
	}
	
	pageBar = [defaults boolForKey:@"ShowPageBar"];
	BOOL newNumberSwitch = [defaults boolForKey:@"ShowNumber"];
	int newResolutionDisplay = (int)[defaults integerForKey:@"ResolutionDisplay"];
	if (numberSwitch != newNumberSwitch || resolutionDisplay != newResolutionDisplay) {
		numberSwitch = newNumberSwitch;
		resolutionDisplay = newResolutionDisplay;
		[self setPageTextField];
	}
	
	[imageView setPreferences];
	[[self window] enableFlushWindow];
	
	
	
	wheelSensitivity = [defaults floatForKey:@"WheelSensitivity"];
		[imageView wheelSetting:wheelSensitivity];
		[thumController wheelSetting:wheelSensitivity];
	
	[thumController setCellRow:[[[defaults dictionaryForKey:@"Thumbnail"] objectForKey:@"row"] intValue]
						column:[[[defaults dictionaryForKey:@"Thumbnail"] objectForKey:@"column"] intValue]];
	

	
	NSEnumerator *enu = [keyArray objectEnumerator];
	id object;
	/*
	 NSMutableArray *array = [NSMutableArray array];
	while (object = [enu nextObject]) {
		if ([[object objectForKey:@"action"] intValue] < 2) {
			[array addObject:object];
		}
	}
	 */
	NSMutableArray *array = [NSMutableArray arrayWithArray:keyArray];

	[fullImagePanel setPageKey:array];
	[thumController setPageKey:array];
	if ([thumController isVisible]) {
		if (secondImage) {
			int temp = nowPage;
			temp--;
			[thumController showThumbnail:temp];
		} else {
			[thumController showThumbnail:nowPage];
		}
	}
	
	NSMutableArray *array2 = [NSMutableArray array];
	enu = [mouseArrayMode2 objectEnumerator];
	while (object = [enu nextObject]) {
		if ([[object objectForKey:@"action"] intValue] == 41) {
			[array2 addObject:object];
		}
	}
	[imageView setDragScroll:array2 mode:1];
	
	NSMutableArray *array3 = [NSMutableArray array];
	enu = [mouseArrayMode3 objectEnumerator];
	while (object = [enu nextObject]) {
		if ([[object objectForKey:@"action"] intValue] == 41) {
			[array3 addObject:object];
		}
	}
	[imageView setDragScroll:array3 mode:2];
	[imageView setDragScroll:array3 mode:3];
}

#pragma mark menu

/* MW-4: moved bodily out of -validateMenuItem: (formerly the "Open the last
 * page" branch) so -[AppController validateMenuItem:] can call it for the
 * title of an action that now targets AppController. Body unchanged. */
- (BOOL)validateOpenTheLastPageMenuItem
{
	if ([[self window] isVisible] || [[self window] isMiniaturized]) {
		if ([defaults arrayForKey:@"RecentItems"]) {
			NSEnumerator *enu = [[defaults arrayForKey:@"RecentItems"] objectEnumerator];
			id object;
			while (object = [enu nextObject]) {
				if ([[self pathFromAliasData:[object objectForKey:@"alias"]] isEqualToString:currentBookPath] && [object objectForKey:@"page"]) {
					return YES;
				}
			}
		}
		if ([defaults arrayForKey:@"LastPages"]) {
			NSEnumerator *enu = [[defaults arrayForKey:@"LastPages"] objectEnumerator];
			id object;
			while (object = [enu nextObject]) {
				if ([[self pathFromAliasData:[object objectForKey:@"alias"]] isEqualToString:currentBookPath] && [object objectForKey:@"page"]) {
					return YES;
				}
			}
		}
	} else {
		if ([[defaults arrayForKey:@"RecentItems"] count]>0) {
			return YES;
		}
	}
	return NO;
}

- (BOOL)validateMenuItem:(NSMenuItem *)anItem
{
    if ([[anItem title] isEqualToString:NSLocalizedString(@"Start/Stop", @"")] == YES) {
		if ([[self window] isVisible]) {
			return YES;
		} else {
			return NO;
		}
	} else if ([[anItem title] isEqualToString:NSLocalizedString(@"Edit Bookmark...", @"")] == YES) {
		if ([[self window] isVisible]) {
			return YES;
		} else {
			//	return NO;
			return YES;
		}
	} else if ([[anItem title] isEqualToString:NSLocalizedString(@"Delete Settings", @"")] == YES) {
		if ([[self window] isVisible]) {
			return YES;
		} else {
			return NO;
		}
	} else if ([[anItem title] isEqualToString:NSLocalizedString(@"Right to Left", @"")] == YES) {
		if ([[self window] isVisible]) {
			if (readMode == 0) {
				[anItem setState:NSOnState];
			} else {
				[anItem setState:NSOffState];
			}
			return YES;
		} else {
			return NO;
		}
	} else if ([[anItem title] isEqualToString:NSLocalizedString(@"Left to Right", @"")] == YES) {
		if ([[self window] isVisible]) {
			if (readMode == 1) {
				[anItem setState:NSOnState];
			} else {
				[anItem setState:NSOffState];
			}
			return YES;
		} else {
			return NO;
		}
	} else if ([[anItem title] isEqualToString:NSLocalizedString(@"Right to Left (single)", @"")] == YES) {
		if ([[self window] isVisible]) {
			if (readMode == 2) {
				[anItem setState:NSOnState];
			} else {
				[anItem setState:NSOffState];
			}
			return YES;
		} else {
			return NO;
		}
	} else if ([[anItem title] isEqualToString:NSLocalizedString(@"Left to Right (single)", @"")] == YES) {
		if ([[self window] isVisible]) {
			if (readMode == 3) {
				[anItem setState:NSOnState];
			} else {
				[anItem setState:NSOffState];
			}
			return YES;
		} else {
			return NO;
		}
	} else if ([[anItem title] isEqualToString:NSLocalizedString(@"Fit to Screen", @"")] == YES) {
		if ([[self window] isVisible]) {
			if (fitScreenMode == 0) {
				[anItem setState:NSOnState];
			} else {
				[anItem setState:NSOffState];
			}
			return YES;
		} else {
			return NO;
		}
	} else if ([[anItem title] isEqualToString:NSLocalizedString(@"Fit to Screen Width", @"")] == YES) {
		if ([[self window] isVisible]) {
			if (fitScreenMode == 1) {
				[anItem setState:NSOnState];
			} else {
				[anItem setState:NSOffState];
			}
			return YES;
		} else {
			return NO;
		}
	} else if ([[anItem title] isEqualToString:NSLocalizedString(@"No Scale", @"")] == YES) {
		if ([[self window] isVisible]) {
			if (fitScreenMode == 2) {
				[anItem setState:NSOnState];
			} else {
				[anItem setState:NSOffState];
			}
			return YES;
		} else {
			return NO;
		}
	} else if ([[anItem title] isEqualToString:NSLocalizedString(@"Fit to Screen Width(divide)", @"")] == YES) {
		if ([[self window] isVisible]) {
			if (fitScreenMode == 3) {
				[anItem setState:NSOnState];
			} else {
				[anItem setState:NSOffState];
			}
			return YES;
		} else {
			return NO;
		}
	} else if ([[anItem title] isEqualToString:NSLocalizedString(@"Switch Single/Bind", @"")] == YES) {
		if ([[self window] isVisible]) {
			return YES;
		} else {
			return NO;
		}	
	} else if ([[anItem title] isEqualToString:NSLocalizedString(@"Rotate Left", @"")] == YES) {
		if ([[self window] isVisible]) {
			return YES;
		} else {
			return NO;
		}	
	} else if ([[anItem title] isEqualToString:NSLocalizedString(@"Rotate Right", @"")] == YES) {
		if ([[self window] isVisible]) {
			return YES;
		} else {
			return NO;
		}
		
	} else if ([[anItem title] isEqualToString:NSLocalizedString(@"Name", @"")] == YES) {
		if ([[self window] isVisible]) {
			if (sortMode == 0) {
				[anItem setState:NSOnState];
			} else {
				[anItem setState:NSOffState];
			}
			return YES;
		} else {
			return NO;
		} 
	} else if ([[anItem title] isEqualToString:NSLocalizedString(@"Shuffle", @"")] == YES) {
		if ([[self window] isVisible]) {
			if (sortMode == 1) {
				[anItem setState:NSOnState];
			} else {
				[anItem setState:NSOffState];
			}
			return YES;
		} else {
			return NO;
		} 
	} else if ([[anItem title] isEqualToString:NSLocalizedString(@"Creation Date", @"")] == YES) {
		if ([[self window] isVisible]) {
			if (sortMode == 2) {
				[anItem setState:NSOnState];
			} else {
				[anItem setState:NSOffState];
			}
			if ([imageLoader canSortByDate]) {
				return YES;
			} else {
				return NO;
			}
		} else {
			return NO;
		} 
	} else if ([[anItem title] isEqualToString:NSLocalizedString(@"Modification Date", @"")] == YES) {
		if ([[self window] isVisible]) {
			if (sortMode == 3) {
				[anItem setState:NSOnState];
			} else {
				[anItem setState:NSOffState];
			}
			if ([imageLoader canSortByDate]) {
				return YES;
			} else {
				return NO;
			}
		} else {
			return NO;
		} 
	} else {
		/*contextMenu*/
		NSRect left,right;
		if (![self readFromLeft]) {
			NSDivideRect ([[[self window] contentView] frame], &left, &right, [[[self window] contentView] frame].size.width/2, NSMinXEdge);
		} else {
			NSDivideRect ([[[self window] contentView] frame], &right, &left, [[[self window] contentView] frame].size.width/2, NSMinXEdge);
		}
		if ([[anItem title]  isEqualToString:NSLocalizedString(@"Add Bookmark", @"")] 
			|| [[anItem title]  isEqualToString:NSLocalizedString(@"Remove Bookmark", @"")]) {
			BOOL bookmarked = NO;
			if (!secondImage) {
				bookmarked = [self isBookmarkedPage:nowPage];
			} else {
				bookmarked = [self isBookmarkedPage:nowPage];
				if (!bookmarked) bookmarked = [self isBookmarkedPage:nowPage-1];
			}
			if (bookmarked && [[anItem title]  isEqualToString:NSLocalizedString(@"Add Bookmark", @"")]) {
				[anItem setTitle:NSLocalizedString(@"Remove Bookmark", @"")];
			} else if (!bookmarked && [[anItem title]  isEqualToString:NSLocalizedString(@"Remove Bookmark", @"")]) {
				[anItem setTitle:NSLocalizedString(@"Add Bookmark", @"")];
			}
		}
		

		if (NSPointInRect([[NSApp currentEvent] locationInWindow], left)) {
			if ([[anItem title]  isEqualToString:NSLocalizedString(@"Previous Bookmark", @"")] ){
				[anItem setTitle:NSLocalizedString(@"Next Bookmark", @"")];
			} else if ([[anItem title]  isEqualToString:NSLocalizedString(@"Go to FirstPage", @"")]) {
				[anItem setTitle:NSLocalizedString(@"Go to LastPage", @"")];
			} else if ([[anItem title]  isEqualToString:NSLocalizedString(@"Previous Folder", @"")]) {
				[anItem setTitle:NSLocalizedString(@"Next Folder", @"")];
			} else if ([[anItem title]  isEqualToString:NSLocalizedString(@"View at Original Size", @"")]) {
				[anItem setTag:1];
			} else if ([[anItem title]  isEqualToString:NSLocalizedString(@"Show in Finder", @"")]) {
				[anItem setTag:1];
			}
		} else {
			if ([[anItem title]  isEqualToString:NSLocalizedString(@"Next Bookmark", @"")] ){
				[anItem setTitle:NSLocalizedString(@"Previous Bookmark", @"")];
			} else if ([[anItem title]  isEqualToString:NSLocalizedString(@"Go to LastPage", @"")]) {
				[anItem setTitle:NSLocalizedString(@"Go to FirstPage", @"")];
			} else if ([[anItem title]  isEqualToString:NSLocalizedString(@"Next Folder", @"")]) {
				[anItem setTitle:NSLocalizedString(@"Previous Folder", @"")];
			} else if ([[anItem title]  isEqualToString:NSLocalizedString(@"View at Original Size", @"")]) {
				[anItem setTag:0];
			} else if ([[anItem title]  isEqualToString:NSLocalizedString(@"Show in Finder", @"")]) {
				[anItem setTag:0];
			}
		}
		if ([[anItem title]  isEqualToString:NSLocalizedString(@"Start Slideshow", @"")]) {
			if (timerSwitch) [anItem setTitle:NSLocalizedString(@"Stop Slideshow", @"")];
		} else if ([[anItem title]  isEqualToString:NSLocalizedString(@"Stop Slideshow", @"")]) {
			if (!timerSwitch) [anItem setTitle:NSLocalizedString(@"Start Slideshow", @"")];
		}
		return YES;
	}
}



- (void)strongSetBookmark
{
	//allBookmarkEditで本を開いた後ブックマーク編集してから戻って来たとき用
	[currentBookSetting removeAllObjects];
	id tempCurrentBookSetting = [appController searchFromBookSettings:currentBookPath key:nil more:YES];
	if (tempCurrentBookSetting) {
		[currentBookSetting setDictionary:tempCurrentBookSetting];
	}

	[bookmarkArray removeAllObjects];
	if (currentBookSetting) {
		if ([currentBookSetting objectForKey:@"bookmarks"]) {
			[bookmarkArray addObjectsFromArray:[currentBookSetting objectForKey:@"bookmarks"]];
		}
	}
	[self setBookmarkMenu];
}

/* The Bookmark menu's fixed head: Edit Bookmark…, All Bookmarks… and the
   separator. Everything after it is the front window's own bookmarks, rebuilt
   below and torn down in -windowWillClose:. Named because KNOWN_ISSUES #24
   added the second item and both loops silently depended on the count. */
static const NSInteger kBookmarkMenuFixedItemCount = 3;

- (void)setBookmarkMenu
{
	if (![[self window] isVisible]) {
		return;
	}
	
	id bookmarkMenuItem = [appController bookmarkMenuItem];
	while ([bookmarkMenuItem numberOfItems] > kBookmarkMenuFixedItemCount) {
		[bookmarkMenuItem removeItemAtIndex:kBookmarkMenuFixedItemCount];
	}

	int i;
	for (i=0; i<[bookmarkArray count]; i++)	{
		NSMenuItem*	menuItem;
		menuItem = [[NSMenuItem alloc]
                initWithTitle:[[bookmarkArray objectAtIndex:i] objectForKey:@"name"]
					   action:@selector(goBookmark:)
                keyEquivalent:@""];
		[menuItem autorelease];
		[menuItem setTarget:self];
		[menuItem setRepresentedObject:[[bookmarkArray objectAtIndex:i] objectForKey:@"page"]];
		[bookmarkMenuItem addItem:menuItem];
	}
}


-(void)setSameFolderMenu
{
	[self setSameFolderMenu:NO];
}
-(void)setSameFolderMenu:(BOOL)force
{
	NSMenu *menu = [[appController openSameFolderMenuItem] submenu];
	if (currentBookPath == nil) {
		[menu removeAllItems];
		return;
	}
	NSString *tmpCurrentPath = [self pathFromAliasData:currentBookAlias];
	NSString *tmpCurrentBookName = [tmpCurrentPath lastPathComponent];
	NSString *superPath = [tmpCurrentPath stringByDeletingLastPathComponent];

	BOOL updateMenu = NO;
	if ([menu numberOfItems] == 0) {
		updateMenu = YES;
	} else if (![[[[menu itemAtIndex:0] representedObject] stringByDeletingLastPathComponent]  isEqualToString:superPath]) {
		updateMenu = YES;
	} else if (force) {
		updateMenu = YES;
	}
	if (updateMenu) {
        NSMutableArray *superDirectoryArray = [NSMutableArray arrayWithArray:[[NSFileManager defaultManager] contentsOfDirectoryAtPath:superPath error:nil]];
		[superDirectoryArray sortUsingSelector:@selector(finderCompareS:)];

		[menu removeAllItems];
		NSEnumerator *enumerator = [superDirectoryArray objectEnumerator];
		id object;
		while (object = [enumerator nextObject]) {
			BOOL isDir;
			if ([object compare:@"." options:NSCaseInsensitiveSearch range:NSMakeRange(0,1)] != NSOrderedSame) {
				[[NSFileManager defaultManager] fileExistsAtPath:[superPath stringByAppendingPathComponent:object] isDirectory:&isDir];
				if (isDir) {
					NSMenuItem *item = [menu addItemWithTitle:object
													   action:@selector(openFromSameDir:)
												keyEquivalent:@""];
					[item setTarget:self];
					[item setRepresentedObject:[superPath stringByAppendingPathComponent:object]];
					
					if ([object isEqualToString:tmpCurrentBookName]) {
						[item setState:NSOnState];
					}
				} else {
					if([[COImageLoader fileTypes] containsObject:[[object pathExtension] lowercaseString]]){
						NSMenuItem *item = [menu addItemWithTitle:object
														   action:@selector(openFromSameDir:)
													keyEquivalent:@""];
						[item setTarget:self];
						[item setRepresentedObject:[superPath stringByAppendingPathComponent:object] ];
						
						if ([object isEqualToString:tmpCurrentBookName]) {
							[item setState:NSOnState];
						}
					}
				}
			}
		}
		[lastSameFolderMenuUpdate release];
		lastSameFolderMenuUpdate = [[NSDate date] retain];
	} else {
		/* Same folder, items kept: move the check mark to the current book.
		   This used to return early unless oldBookPath was set, which it
		   never is once an open has finished (code review M4). */
		NSEnumerator *enumerator = [[menu itemArray] objectEnumerator];
		id object;
		int setStateCount = 0;
		while (object = [enumerator nextObject]) {
			if ([[[object representedObject] lastPathComponent] isEqualToString:tmpCurrentBookName]){
				[object setState:NSOnState];
				setStateCount++;
			} else if ([object state] == NSOnState) {
				[object setState:NSOffState];
				setStateCount++;
			}
			if (setStateCount==2) {
				break;
			}
		}
	}
}


-(void)setOpenRecentMenu
{
	NSMutableArray *array;
	if (![defaults arrayForKey:@"RecentItems"]) {
		array = [NSMutableArray array];
	} else {
		array = [NSMutableArray arrayWithArray:[defaults arrayForKey:@"RecentItems"]];
	}
	NSMenu *menu=[[appController openRecentMenuItem] submenu];
	while ([menu numberOfItems] > 2) {
		[menu removeItemAtIndex:0];
	}
	NSEnumerator *enumerator = [array reverseObjectEnumerator];
	id object;
	while (object = [enumerator nextObject]) {
		NSData *aliasData = [object objectForKey:@"alias"];
		NSString *path = [self pathFromAliasData:aliasData];
		if (path) {
			if ([path isEqualToString:@"file not found"]) {
				NSMenuItem *menuItem = [[NSMenuItem alloc] 
                initWithTitle:[NSString stringWithFormat:@"file not found"]
					   action:nil 
                keyEquivalent:@""];
				[menuItem setEnabled:NO];
				[menuItem autorelease];
				[menu insertItem:menuItem atIndex:0];
			} else if ([object objectForKey:@"page"]) {
				int page = [[object objectForKey:@"page"] intValue];
				NSMenuItem *menuItem;
				SEL selector = @selector(openFromOpenRecent:);
				if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
					menuItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%@ (P%i)",[path lastPathComponent],page+1]
														  action:selector
												   keyEquivalent:@""];
				} else {
					menuItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%@ (P%i)",path,page+1]
														  action:selector
												   keyEquivalent:@""];
					[menuItem setEnabled:NO];
				}
				[menuItem setRepresentedObject:object];
				[menuItem autorelease];
				/* MW-7 (KNOWN_ISSUES #27): deliberately no target. The
				   *contents* of this menu are app-wide — they come from the
				   RecentItems default — so unlike the bookmark and same-folder
				   menus it does not go stale when the front window changes;
				   only the target did, because -setTarget:self froze it to
				   whichever window last rebuilt the menu. With no target,
				   -openFromOpenRecent: resolves through the responder chain to
				   the front window, the same way the actions MW-4 retargeted
				   at First Responder do. */
				[menu insertItem:menuItem atIndex:0];
			} else {
				NSMenuItem *menuItem = [[NSMenuItem alloc] 
                initWithTitle:[NSString stringWithFormat:@"%@ (-)",[path lastPathComponent]]
					   action:nil 
                keyEquivalent:@""];
				[menuItem autorelease];
				[menu insertItem:menuItem atIndex:0];
			}
		} else {
			[array removeObject:object];
			[defaults setObject:array forKey:@"RecentItems"];
			[defaults synchronize];
		}
	}
}

#pragma mark -


- (void)setPageTextField
{
	/*
	if (timerSwitch) {
		[imageView setSlideshow:YES];
	} else {
		[imageView setSlideshow:NO];
	}*/
	[imageView setPageString:[self pageTextFieldString]];
	[imageView setResolutionString:[self resolutionBarString]];
}

/* Pixel dimensions from the image's representations, not -[NSImage size],
   which is in points and depends on the file's DPI (KNOWN_ISSUES #6). nil
   when no representation reports them. */
- (NSString*)pixelSizeStringForImage:(NSImage*)image
{
	if (!image) return nil;
	NSArray *reps = [image representations];
	for (NSImageRep *rep in reps) {
		NSInteger w = [rep pixelsWide];
		NSInteger h = [rep pixelsHigh];
		if (w > 0 && h > 0) {
			return [NSString stringWithFormat:@"%ldx%ld", (long)w, (long)h];
		}
	}
	return nil;
}

/* The one formatter behind both bars. Each shown page becomes one entry —
   file name, dimensions, or both — and a spread joins its two entries with
   " | " in screen order (left page first), which depends on readMode
   (KNOWN_ISSUES #3). firstImage is always the earlier page (index nowPage-2
   on a spread, nowPage-1 alone), so callers must have assigned it before
   asking. With withNumber the result carries the "#page/count" prefix and
   the entries in parentheses; without it, only the dimensions. nil when no
   page is shown, or when there is nothing to show. */
- (NSString*)pageStringWithNumber:(BOOL)withNumber resolution:(BOOL)withResolution
{
	int count = (int)[completeMutableArray count];
	if (nowPage <= 0 || nowPage > count || !firstImage) return nil;
	if (secondImage && nowPage < 2) return nil;

	NSMutableArray *pages = [NSMutableArray array];	/* (index, image) pairs, left to right */
	if (!secondImage) {
		[pages addObject:[NSArray arrayWithObjects:[NSNumber numberWithInt:nowPage-1], firstImage, nil]];
	} else {
		NSArray *earlier = [NSArray arrayWithObjects:[NSNumber numberWithInt:nowPage-2], firstImage, nil];
		NSArray *later = [NSArray arrayWithObjects:[NSNumber numberWithInt:nowPage-1], secondImage, nil];
		if (readMode == 1 || readMode == 3) {
			[pages addObject:earlier];
			[pages addObject:later];
		} else {
			[pages addObject:later];
			[pages addObject:earlier];
		}
	}

	NSMutableArray *entries = [NSMutableArray array];
	for (NSArray *page in pages) {
		NSString *size = withResolution ? [self pixelSizeStringForImage:[page objectAtIndex:1]] : nil;
		if (withNumber) {
			NSString *name = [[completeMutableArray objectAtIndex:[[page objectAtIndex:0] intValue]] lastPathComponent];
			[entries addObject:(size ? [NSString stringWithFormat:@"%@ %@", name, size] : name)];
		} else if (size) {
			[entries addObject:size];
		}
	}
	if ([entries count] == 0) return nil;
	NSString *joined = [entries componentsJoinedByString:@" | "];
	if (!withNumber) return joined;

	if (secondImage) {
		return [NSString stringWithFormat:@"#%d-%d/%d (%@)", nowPage-1, nowPage, count, joined];
	}
	return [NSString stringWithFormat:@"#%d/%d (%@)", nowPage, count, joined];
}

/* The page-number bar. */
- (NSString*)pageTextFieldString
{
	if (!numberSwitch) return nil;
	return [self pageStringWithNumber:YES resolution:(resolutionDisplay == COResolutionDisplayInPageNumber)];
}

/* The separate resolution bar: dimensions only, independent of ShowNumber. */
- (NSString*)resolutionBarString
{
	if (resolutionDisplay != COResolutionDisplaySeparateBar) return nil;
	return [self pageStringWithNumber:NO resolution:YES];
}


- (IBAction)changeReadModeMenu:(id)sender
{
    if ([[sender title] isEqualToString:NSLocalizedString(@"Right to Left", @"")] == YES) {
		[self changeReadMode:0];
	} else if ([[sender title] isEqualToString:NSLocalizedString(@"Left to Right", @"")] == YES) {
		[self changeReadMode:1];
	} else if ([[sender title] isEqualToString:NSLocalizedString(@"Right to Left (single)", @"")] == YES) {
		[self changeReadMode:2];
	} else if ([[sender title] isEqualToString:NSLocalizedString(@"Left to Right (single)", @"")] == YES) {
		[self changeReadMode:3];
	}
}


- (IBAction)changeSortModeMenu:(id)sender
{
    if ([[sender title] isEqualToString:NSLocalizedString(@"Name", @"")] == YES) {
		[self setSortMode:0 page:0];
	} else if ([[sender title] isEqualToString:NSLocalizedString(@"Shuffle", @"")] == YES) {
		[self setSortMode:1 page:0];
	} else if ([[sender title] isEqualToString:NSLocalizedString(@"Creation Date", @"")] == YES) {
		[self setSortMode:2 page:0];
	} else if ([[sender title] isEqualToString:NSLocalizedString(@"Modification Date", @"")] == YES) {
		[self setSortMode:3 page:0];
		
	}
}


- (void)goBookmark:(id)sender
{
	//BookmarkMenuItem's action
	//NSLog(@"%d",[sender tag]);
	[imageView setPageString:[NSString stringWithFormat:@"%@",[sender title]]];
	/* No lookahead may be adding pages while the list changes below
	   (code review M5). */
	[self stopLookahead];
	nowPage = [[sender representedObject] intValue] - 1;
	[imageMutableArray removeAllObjects];
	[self lookahead];
	[self imageDisplay];

}


- (IBAction)editBookmark:(id)sender
{
	if (timerSwitch) {
		[timer invalidate];
		timer = nil;
		timerSwitch=NO;
	}
	if ([imageView image]) {
		NSDictionary *dic = [NSDictionary dictionaryWithObject:currentBookPath forKey:@"dirPath"];
		
		[bookmarkController setPathDic:dic];
		[bookmarkController editBookmark:bookmarkArray];
	} else {
		/* MW-5 item 5: the All Bookmark browser is app-wide and no longer
		   part of this window's BookmarkController. */
		[[appController allBookmarkController] editAllBookmark:bookmarkArray];
	}
}


- (IBAction)deleteSettings:(id)sender
{	
	NSData *alias = currentBookAlias;
	[currentBookSetting setObject:alias forKey:@"alias"];
	[currentBookSetting setObject:currentBookPath forKey:@"temppath"];
	[currentBookSetting removeObjectForKey:@"readMode"];
	[currentBookSetting removeObjectForKey:@"sortMode"];
	[currentBookSetting removeObjectForKey:@"marks"];
	
	[self changeReadMode:(int)[defaults integerForKey:@"ReadMode"]];
	[self setSortMode:(int)[defaults integerForKey:@"SortMode"] page:-1];
}


#pragma mark -
- (IBAction)fitToScreen:(id)sender
{
	if (fitScreenMode == 0) {
		return;
	}
	[[self window] disableFlushWindow];
	[[[self window] contentView] replaceSubview:[imageView enclosingScrollView] with:imageView];
	[imageView setFrame:[[[self window] contentView] frame]];
	
	fitScreenMode = 0;
	[imageView setScreenFitMode:fitScreenMode];
	if (secondImage) {
		[imageView setImages:firstImage];
	} else {
		[imageView setImage:firstImage];
	}
	[[self window] enableFlushWindow];
	[[self window] flushWindowIfNeeded];
	[imageView setInfoString:[NSString stringWithFormat:@"Fit to Screen"]];
	/* MW-8: the view mode is part of what this window restores to. */
	[[self window] invalidateRestorableState];
}

- (IBAction)fitToScreenWidth:(id)sender
{
	if (fitScreenMode == 1) {
		return;
	} else if (fitScreenMode == 0) {
		id scroll = [[NSScrollView alloc] init];
		[scroll setFrame:[[[self window] contentView] frame]];
		[(NSScrollView *)scroll setAutoresizingMask:[(CustomImageView *)imageView autoresizingMask]];
		[scroll setBackgroundColor:[[self window] backgroundColor]];
		[imageView retain];
		[[[self window] contentView] replaceSubview:imageView with:scroll];
		[scroll setDocumentView:imageView];
		[scroll release];
		[imageView release];
		//[scroll setDocumentCursor:[NSCursor openHandCursor]];
	}
	[[self window] disableFlushWindow];
	fitScreenMode = 1;
	[imageView setScreenFitMode:fitScreenMode];
	if (secondImage) {
		[imageView setImages:firstImage];
	} else {
		[imageView setImage:firstImage];
	}	
	[[self window] enableFlushWindow];
	[[self window] flushWindowIfNeeded];
	[imageView setInfoString:[NSString stringWithFormat:@"Fit to Screen Width"]];
	[[self window] invalidateRestorableState];
}

- (IBAction)fitToScreenWidthDivide:(id)sender
{
	if (fitScreenMode == 3) {
		return;
	} else if (fitScreenMode == 0) {
		id scroll = [[NSScrollView alloc] init];
		[scroll setFrame:[[[self window] contentView] frame]];
        [(NSScrollView *)scroll setAutoresizingMask:[(CustomImageView *)imageView autoresizingMask]];
		[scroll setBackgroundColor:[[self window] backgroundColor]];
		[imageView retain];
		[[[self window] contentView] replaceSubview:imageView with:scroll];
		[scroll setDocumentView:imageView];
		[scroll release];
		[imageView release];
		//[scroll setDocumentCursor:[NSCursor openHandCursor]];
	}
	[[self window] disableFlushWindow];
	fitScreenMode = 3;
	[imageView setScreenFitMode:fitScreenMode];
	if (secondImage) {
		[imageView setImages:firstImage];
	} else {
		[imageView setImage:firstImage];
	}	
	[[self window] enableFlushWindow];
	[[self window] flushWindowIfNeeded];
	[imageView setInfoString:[NSString stringWithFormat:@"Fit to Screen Width(Divide)"]];
	[[self window] invalidateRestorableState];
}

- (IBAction)noScale:(id)sender
{
	if (fitScreenMode == 2) {
		return;
	} else if (fitScreenMode == 0) {
		id scroll = [[NSScrollView alloc] init];		
		[scroll setFrame:[[[self window] contentView] frame]];
        [(NSScrollView *)scroll setAutoresizingMask:[(CustomImageView *)imageView autoresizingMask]];
		[scroll setBackgroundColor:[[self window] backgroundColor]];
		[imageView retain];
		[[[self window] contentView] replaceSubview:imageView with:scroll];
		[scroll setDocumentView:imageView];
		[scroll release];
		[imageView release];
		//[scroll setDocumentCursor:[NSCursor openHandCursor]];
	}
	[[self window] disableFlushWindow];
	fitScreenMode = 2;
	[imageView setScreenFitMode:fitScreenMode];
	if (secondImage) {
		[imageView setImages:firstImage];
	} else {
		[imageView setImage:firstImage];
	}
	[[self window] enableFlushWindow];
	[[self window] flushWindowIfNeeded];
	[imageView setInfoString:[NSString stringWithFormat:@"No Scale"]];
	[[self window] invalidateRestorableState];
}

- (IBAction)rotateRight:(id)sender
{
	rotateMode--;
	if (rotateMode < 0) {
		rotateMode = 3;
	}
	[imageView rotateRight];
}
- (IBAction)rotateLeft:(id)sender
{
	rotateMode++;
	if (rotateMode > 3) {
		rotateMode = 0;
	}
	[imageView rotateLeft];
}

/* MW-5: FilterPanelController moved into BookWindow.xib, so the Filter menu
   item in MainMenu.xib cannot target it directly any more. The item targets
   First Responder and lands here, on the window's own controller, which
   forwards to that window's panel. */
- (IBAction)openFilterPanel:(id)sender
{
	[filterPanelController openFilterPanel:sender];
}

#pragma mark -


/* Re-render for the window's current size. A two-page spread is composed
 * against the view, so any size change has to redo it.
 *
 * Before MW-2 this body was duplicated in -fullscreen: and
 * -viewDidEndLiveResize:. -fullscreen: is gone (the Window menu now has
 * AppKit's own Enter/Exit Full Screen item), so the fullscreen half is
 * driven by the real transition notifications below instead. Those are
 * needed because entering full screen is a programmatic frame change and
 * does not produce a live resize. */
- (void)recomposeForCurrentSize
{
	if (secondImage) {
		[imageView setImages:secondImage];
	} else {
		[imageView setImage:firstImage];
	}
}

- (void)windowDidEnterFullScreen:(NSNotification *)aNotification
{
	[self recomposeForCurrentSize];
}

- (void)windowDidExitFullScreen:(NSNotification *)aNotification
{
	[self recomposeForCurrentSize];
}

/* v1.6.2: keeps -lastWindowedSize current. Captured here rather than from
   -windowDidResize: guarded by -isInFullScreen: measured on-device, the
   style mask that -isInFullScreen reads is not yet set at the point the
   resize-to-screen-size itself fires, so that guard let the full-screen
   size through. -windowWillEnterFullScreen: fires before AppKit touches the
   frame at all, so the frame read here is always the true last windowed
   size, however many times the window was resized before this. */
- (void)windowWillEnterFullScreen:(NSNotification *)aNotification
{
	lastWindowedSize = [[self window] frame].size;
}

- (NSSize)currentWindowedSize
{
	if ([(CustomWindow *)[self window] isInFullScreen]) {
		return lastWindowedSize;
	}
	return [[self window] frame].size;
}


-(void)viewSet
{
	[imageView wheelSetting:wheelSensitivity];
	[thumController wheelSetting:wheelSensitivity];
}



- (void)windowWillClose:(NSNotification *)aNotofication
{
	/* MW-8: a window closed before its restored book was opened must not
	   have it opened afterwards — the pending request also retains this
	   object, which would keep a retired window controller alive. */
	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(openRestoredBook)
											   object:nil];
	[self releaseRestoredBookAccess];

	/* KNOWN_ISSUES #33: same for a password prompt in flight. Counting the
	   close stops both the sheet's own completion handler — which AppKit still
	   calls when it dismisses a sheet along with its parent — and a queued
	   re-ask from opening a book into a window that has gone. The flag has to
	   be cleared as well: -[AppController settleLaunch] holds its deadline
	   open for as long as any window is waiting on input, so leaving it set on
	   a closed window would stall a queued Finder open indefinitely.

	   Closing with the prompt still up ends that open as a Cancel would, so
	   the window's book identity is put back first: currentBookPath still
	   names the book waiting for its password, and the teardown below would
	   otherwise record *that* book in Recent Books with the shown book's page.
	   Tested on the sheet rather than on passwordOpenInFlight alone, which
	   stays YES through the open that follows an accepted password — by then
	   the identity is the new book's and must not be undone. (The window's
	   close button and Cmd+W are blocked while a sheet is attached, and a quit
	   cancels the prompt first, so this is a programmatic close only.) */
	windowCloseCount++;
	/* KNOWN_ISSUES #33, the loading half: the same holds for an archive read in
	   flight, for the whole of archiveLoadInFlight — the identity is the
	   pending open's until the read has handed the open back. The read is told
	   to stop, its sheet comes down, and its completion, seeing the count has
	   moved, drops only what it owns (-archiveLoadDidFinishWithLoader:...).
	   Unlike a password sheet, this can be a user's close: in the moment
	   before the progress sheet appears, the window takes Cmd+W. */
	if ((passwordOpenInFlight && [[self window] attachedSheet] != nil)
		|| archiveLoadInFlight) {
		[self restoreBookIdentityAfterAbandonedOpen];
	}
	if (archiveLoadInFlight) {
		atomic_store(&archiveLoadCancelled, 1);
		[pendingArchiveLoader cancelArchiveRead];
		[self endArchiveProgressSheet];
		archiveLoadInFlight = NO;
		archiveLoadQuitting = NO;
		pendingArchiveLoader = nil;
	}
	passwordOpenInFlight = NO;
	/* Whatever open this window was running is over; a window the registry
	   keeps must not come back with its spinner still going. */
	[progressIndicator stopAnimation:self];
	/* v1.6.5: a closed window is hidden, so it is not "shown empty" any
	   more; if the registry keeps it, it is reused like any hidden one. */
	shownWithoutBook = NO;
	/* v1.6.x: defensive, matching passwordOpenInFlight above — a closed
	   window must never keep reading as mid-load. -abandonOpenWithLoader:/
	   -discardPendingOpen: already clear this on their own exits; this
	   covers a close that lands while neither has run yet. -openDidEnd
	   clears the rest of the open's state with it: a restored book whose
	   window is closed is not going to finish opening. */
	[self openDidEnd];

	/* Was a bare [lock lock]/[lock unlock] pair, which waits only for a
	   lookahead that is already *inside* the body. A thread detached a
	   moment earlier and still blocked on that same lock would sail past it
	   and go on writing into the arrays torn down below. */
	[self joinLookaheadThreads];
	/* MW-6 item 4: tear the book down only if there is one. This used to test
	   [[self window] isVisible], which is YES for the whole of -windowWillClose:
	   even when the window is being closed by -openPage:last: after a failed
	   first open — a case in which every statement in the block is a no-op. */
	if ([self hasBookOpen]) {
		bookOpen = NO;
		[thumController setImageLoader:nil];
		if (timerSwitch) {
			[timer invalidate];
			timer = nil;
			timerSwitch=NO;
		}
		id bookmarkMenuItem = [appController bookmarkMenuItem];
		while ([bookmarkMenuItem numberOfItems] > kBookmarkMenuFixedItemCount) {
			[bookmarkMenuItem removeItemAtIndex:kBookmarkMenuFixedItemCount];
		}
		int iA;
		for (iA=0; iA<[[[appController openSameFolderMenuItem] submenu] numberOfItems]; iA++) {
			if ([[[[appController openSameFolderMenuItem] submenu] itemAtIndex:iA] state] == NSOnState) {
				[[[[appController openSameFolderMenuItem] submenu] itemAtIndex:iA] setState:NSOffState];
				break;
			}
		}
		if (currentBookPath != nil) {
			/*historyの処理*/
			if (secondImage) {
				nowPage -= 2;
			} else {
				nowPage--;
			}
			[appController recordBookSettingsOnWindowClose:currentBookPath
													   name:currentBookName
													  alias:currentBookAlias
												  bookmarks:bookmarkArray
												bookSetting:currentBookSetting
													   page:nowPage
											openRecentLimit:openRecentLimit
									 alwaysRememberLastPage:alwaysRememberLastPage
									  rememberBookSettings:rememberBookSettings];
		}


		[imageView setPageString:nil];
		[imageView setResolutionString:nil];
		[NSCursor setHiddenUntilMouseMoves:NO];
		[imageView setImage:nil];
		[firstImage release];
		firstImage = nil;
		[secondImage release];
		secondImage = nil;
		
		[completeMutableArray release];
		completeMutableArray = nil;
		oldBookPath = currentBookPath;
		oldBookName = currentBookName;
		oldBookAlias = currentBookAlias;
		currentBookPath = nil;
		currentBookName = nil;
		currentBookAlias = nil;
		[currentBookSetting removeAllObjects];
		[imageMutableArray removeAllObjects];
		[bookmarkArray removeAllObjects];
		[marksArray removeAllObjects];
		[self setOpenRecentMenu];
		
		[cacheArray removeAllObjects];
		if (imageLoader) {
			[imageLoader release];
			imageLoader = nil;
		}
		/* MW-8: there is no book here to restore any more. */
		[currentBookBookmark release];
		currentBookBookmark = nil;
	}

	/* This window's panels go with it, whether or not the registry retires
	   the controller. MW-7 did this only on retirement, to leave the last
	   window behaving exactly as it did before; Step-0 decision 4 makes that
	   impossible, because a panel left on screen is a visible window and
	   AppKit would never ask
	   -applicationShouldTerminateAfterLastWindowClosed: at all. */
	[self closeAuxiliaryPanels];

	/* MW-7: hand the window back to the registry. It is retired — removed
	   and released — unless it is the last one, which stays as the window
	   File ▸ Open and Open the last page reuse.

	   KNOWN_ISSUES #36: the accessory overlay outlives a retired controller
	   by one window close (#26), and holds unretained outlets to it. They
	   are dropped here, while this object is still alive (the registry's
	   release is an autorelease) — a draw request queued before the close
	   otherwise reaches -[AccessoryView drawRect:] after -dealloc and sends
	   -indicator to freed memory. Only on retirement: the kept last window
	   is reused by the next open with this same controller, and an overlay
	   detached from it drew neither the page number nor the page bar and
	   ignored mouse movement for the rest of the run (KNOWN_ISSUES #42). */
	if ([appController retireWindowController:self]) {
		[imageView detachAccessoryFromWindowController];
	}
}

/* The thumbnail, bookmark, full-image and filter panels are separate windows
   in the same nib as this window, so they are neither closed with it nor
   owned by it — NSWindowController releases them with the rest of the nib's
   top-level objects when it is deallocated. Left on screen they would
   outlive the window they belong to, and then be deallocated under AppKit's
   feet. */
- (void)closeAuxiliaryPanels
{
	[thumController closePanel];
	[bookmarkController closePanel];
	[filterPanelController closePanel];
	[fullImagePanel orderOut:self];
}

#pragma mark shared main-menu state (MW-6 item 3)

/* The bookmark menu, the "Open from same folder" submenu and the read-mode /
   sort-mode check-marks are one shared object each, hanging off the
   application's single main menu, but everything in them describes one
   window's book. They are built when a book is opened and torn down when its
   window closes, which is only correct as long as "the book" is unambiguous.
   Rebuilding them here makes the front window the one they describe. */
- (void)windowDidBecomeMain:(NSNotification *)notification
{
	/* MW-7: this is what makes this window "the front one" for every
	   app-level command AppController routes — File ▸ Open, Open the last
	   page, the dock menu, the Apple Remote. */
	[appController windowControllerDidBecomeFront:self];

	NSMenu *sameFolderMenu = [[appController openSameFolderMenuItem] submenu];
	if ([sameFolderMenu delegate] != self) {
		/* The submenu is built lazily by -menuNeedsUpdate:, so taking over as
		   its delegate is what redirects it at this window. Its *contents*
		   are still stale — the items carry the previous window's target and
		   represented paths — so flag it for a forced rebuild, but leave the
		   rebuild itself to the next -menuNeedsUpdate:. Doing it here would
		   enumerate the book's parent folder on every window activation,
		   which is the folder-access-prompt problem the lazy build exists to
		   avoid. */
		[sameFolderMenu setDelegate:self];
		sameFolderMenuNeedsRebuild = YES;
	}
	[self setBookmarkMenu];
	[self updateReadAndSortModeMenuState];
	/* Filters are per window (code review L6); an open Filter panel follows
	   the front window. */
	[filterPanelController ownerWindowBecameMain];
}

/* Read mode and sort mode are per-book overrides on a global default
   (currentBookSetting's "readMode"/"sortMode" over the ReadMode/SortMode
   preferences, applied in -openPage:last:), so the check-marks have to
   follow the front *book*, not the preference. -validateMenuItem: already
   computes exactly that from this window's readMode/sortMode ivars, so the
   items carrying those two actions are re-validated rather than having the
   localized-title dispatch duplicated here. */
- (void)updateReadAndSortModeMenuState
{
	[self updateReadAndSortModeMenuStateInMenu:[NSApp mainMenu]];
}

- (void)updateReadAndSortModeMenuStateInMenu:(NSMenu *)menu
{
	NSEnumerator *enu = [[menu itemArray] objectEnumerator];
	NSMenuItem *item;
	while (item = [enu nextObject]) {
		if ([item action] == @selector(changeReadModeMenu:)
			|| [item action] == @selector(changeSortModeMenu:)) {
			[self validateMenuItem:item];
		}
		if ([item hasSubmenu]) {
			[self updateReadAndSortModeMenuStateInMenu:[item submenu]];
		}
	}
}

#pragma mark NSMenuDelegate

- (void)menuNeedsUpdate:(NSMenu *)menu
{
	if (menu == [[appController openSameFolderMenuItem] submenu]) {
		[self refreshSameFolderMenu];
	}
}

/* Both of these touch the parent folder of the current book
   (contentsOfDirectoryAtPath: / attributesOfItemAtPath:). Doing this only
   when the user is about to open this submenu, or asks for the next or
   previous book in the folder — rather than on every book open or app
   activation — keeps macOS folder-access permission prompts limited to
   actual use of the feature (#5b). */
- (NSMenu *)refreshSameFolderMenu
{
	NSMenu *menu = [[appController openSameFolderMenuItem] submenu];
	/* Code review M4: the next/previous-folder keys can arrive before this
	   window has become the submenu's delegate (or after another window took
	   it over); claim it the same way -windowDidBecomeMain: does. */
	if ([menu delegate] != self) {
		[menu setDelegate:self];
		sameFolderMenuNeedsRebuild = YES;
	}
	[self checkCurrentFolderUpdated];
	/* MW-6 item 3: force the rebuild if the submenu was last built for a
	   different window. Without it -setSameFolderMenu: would keep the
	   other window's items whenever both books sit in the same folder,
	   and those items are targeted at that window. */
	[self setSameFolderMenu:sameFolderMenuNeedsRebuild];
	sameFolderMenuNeedsRebuild = NO;
	return menu;
}




- (void)viewDidEndLiveResize:(NSNotification *)aNotification
{
	[self recomposeForCurrentSize];
}

- (void)openLink:(NSURL *)url
{
	if (openLinkMode==2) return;
	
	NSModalResponse result = NSAlertFirstButtonReturn;
	if (openLinkMode==0) {
		NSAlert *alert = [[[NSAlert alloc] init] autorelease];
		[alert setMessageText:NSLocalizedString(@"Open URL",@"")];
		[alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"Open '%@' in default browser?",@""),url]];
		[alert addButtonWithTitle:NSLocalizedString(@"OK",@"")];
		[alert addButtonWithTitle:NSLocalizedString(@"Cancel",@"")];
		result = [alert runModal];
	}

	if(result == NSAlertFirstButtonReturn) {
		 [[NSWorkspace sharedWorkspace] openURL:url];
	}
}


#pragma mark -
#pragma mark return


-(int)maxEnlargement
{
	return maxEnlargement;
}
-(int)readMode
{
	return readMode;
}

-(BOOL)readFromLeft
{
	if (readMode == 1 || readMode == 3) {
		return YES;
	} else {
		return NO;
	}
}

-(BOOL)firstImage
{
	if (secondImage) {
		return YES;
	} else {
		return NO;
	}
}
-(id)image1
{
	return firstImage;
}
-(id)image2
{
	return secondImage;
}
-(BOOL)indicator
{
	return pageBar;
}

-(float)nowPar
{
	float count = [completeMutableArray count];
	float temp = nowPage;
	float par = temp/count;
	if (par > 1) {
		par = 0.0;
	}
	return par;
}

-(NSString*)currentImagePath
{
	if (nowPage > 0 && nowPage <= (int)[completeMutableArray count]) {
		return [completeMutableArray objectAtIndex:nowPage - 1];
	}
	return nil;
}

-(NSString*)currentBookPath
{
	return currentBookPath;
}

-(NSDictionary*)imageInfoForClickPoint:(NSPoint)windowPoint
{
	if (nowPage <= 0 || nowPage > (int)[completeMutableArray count]) return nil;
	if (!secondImage) {
		NSString *path = [completeMutableArray objectAtIndex:nowPage - 1];
		return [NSDictionary dictionaryWithObjectsAndKeys:path, @"path", firstImage, @"image", nil];
	}
	// 2-page: map click position to the correct page image.
	// composeImage draws secondImage/firstImage straight into the view:
	//   readMode 0,2 (RTL): image1(secondImage) drawn LEFT, image2(firstImage) drawn RIGHT
	//   readMode 1,3 (LTR): image2(firstImage) drawn LEFT, image1(secondImage) drawn RIGHT
	NSRect contentFrame = [[[self window] contentView] frame];
	float centerX = contentFrame.origin.x + contentFrame.size.width / 2.0f;
	BOOL clickedLeft = (windowPoint.x < centerX);
	BOOL firstOnLeft = (readMode == 1 || readMode == 3);
	int i = nowPage - 1;  // secondImage index
	int iS = i - 1;       // firstImage index
	if (iS < 0) {
		return [NSDictionary dictionaryWithObjectsAndKeys:
			[completeMutableArray objectAtIndex:i], @"path", secondImage, @"image", nil];
	}
	NSString *path;
	NSImage *image;
	if (clickedLeft == firstOnLeft) {
		path  = [completeMutableArray objectAtIndex:iS];
		image = firstImage;
	} else {
		path  = [completeMutableArray objectAtIndex:i];
		image = secondImage;
	}
	return [NSDictionary dictionaryWithObjectsAndKeys:path, @"path", image, @"image", nil];
}

-(int)nowPage
{
	int temp;
	if (secondImage) {
		temp = nowPage;
		temp--;
	} else {
		temp = nowPage;
	}
	return temp;
}

-(int)pageCount
{
	return (int)[completeMutableArray count];
}

-(NSArray*)bookmarkArray
{
	return bookmarkArray;
}

- (id)openSameFolderMenuItem
{
	return [[appController openSameFolderMenuItem] submenu];
}

- (int)sortMode
{
	return sortMode;
}

- (int)openLinkMode
{
	return openLinkMode;
}


#pragma mark -


#pragma mark Alias
- (NSString*)pathFromAliasData:(NSData*)data
{
	return [self pathFromAlias:[self aliasFromData:data]];
}
- (NSData*)aliasDataFromPath:(NSString*)path
{
	return [self dataFromAlias:[self aliasFromPath:path]];
}
- (AliasHandle)aliasFromPath:(NSString *)fullPath
{
    OSStatus	anErr = noErr;
    FSRef		ref;
    
    CFURLRef	tempURL = NULL;
    Boolean	gotRef = false;
    
    tempURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef)fullPath,
                                            kCFURLPOSIXPathStyle, false);
    
    if (tempURL == NULL) {
        return nil;
    }
    
    gotRef = CFURLGetFSRef(tempURL, &ref);
    
    CFRelease(tempURL);
    
    if (gotRef == false) {
        return nil;
    }
	
    AliasHandle	alias = NULL;
    
    anErr = FSNewAlias(NULL, &ref, &alias);
    
    if (anErr != noErr) {
        return nil;
    }
    return alias;
}

- (NSData *)dataFromAlias:(AliasHandle)alias
{	
	CFDataRef	data = NULL;
    CFIndex	len;
    SInt8	handleState;
    
    if (alias == NULL) {
        return NULL;
    }
    
    len = GetHandleSize((Handle)alias);
    
    handleState = HGetState((Handle)alias);
    
    HLock((Handle)alias);
    data = CFDataCreate(kCFAllocatorDefault, (const UInt8 *) *alias, len);
    
    HSetState((Handle)alias, handleState);
    
	DisposeHandle((Handle) alias);
	
    return [(NSData*)data autorelease];
}


- (AliasHandle)aliasFromData:(NSData*)data
{
	CFIndex	len;
    Handle	handle = NULL;
    
    if (data == NULL) {
        return NULL;
    }
    /*
    len = CFDataGetLength((CFDataRef)data);
    
    handle = NewHandle(len);
    
    if ((handle != NULL) && (len > 0)) {
        HLock(handle);
        //BlockMoveData(CFDataGetBytePtr((CFDataRef)data), *handle, len);
        memmove((void *)CFDataGetBytePtr((CFDataRef)data), (void *)*handle, len);
        HUnlock(handle);
    }
    */
    len = CFDataGetLength((CFDataRef)data);
    
    PtrToHand(CFDataGetBytePtr((CFDataRef)data), (Handle*)&handle, len);
    
    return (AliasHandle)handle;
}
- (NSString *)pathFromAlias:(AliasHandle)alias
{
    OSStatus	anErr = noErr;
    FSRef	tempRef;
    NSString	*result = nil;
    Boolean	wasChanged;
    if (alias != NULL) {		
		
		anErr = FSResolveAliasWithMountFlags(NULL,alias, &tempRef, &wasChanged, kResolveAliasFileNoUI);
		
		if (anErr != noErr) {
			//return [NSString stringWithFormat:@"file not found"];
			CFStringRef path = NULL;
			anErr = FSCopyAliasInfo(alias,NULL, NULL,&path,NULL,NULL);
			if (anErr != noErr) {
				result = [[NSString alloc] initWithFormat:@"file not found"];
			} else if (path) {
				result = [[NSString alloc] initWithString:(NSString *)path];
				//NSLog(@"%@",result);
			} else {
				result = [[NSString alloc] initWithFormat:@"file not found"];
			}
			DisposeHandle((Handle)alias);
			return [result autorelease];
		}
		CFURLRef	tempURL = NULL;
		CFStringRef	tempResult = NULL;
		
		if (&tempRef != NULL) {
			tempURL = CFURLCreateFromFSRef(kCFAllocatorDefault, &tempRef);
			if (tempURL == NULL) {
				//return [NSString stringWithFormat:@"file not found"];
				CFStringRef path = NULL;
				anErr = FSCopyAliasInfo(alias,NULL, NULL,&path,NULL,NULL);
				if (anErr != noErr) {
					result = [[NSString alloc] initWithFormat:@"file not found"];
				} else if (path) {
					result = [[NSString alloc] initWithString:(NSString *)path];
				} else {
					result = [[NSString alloc] initWithFormat:@"file not found"];
				}
				DisposeHandle((Handle)alias);
				return [result autorelease];
			}
			tempResult = CFURLCopyFileSystemPath(tempURL, kCFURLPOSIXPathStyle);
			CFRelease(tempURL);
		}
		
        result = (NSString *)tempResult;
    }
	DisposeHandle((Handle) alias);
    return [result autorelease];
}


@end

@implementation BookWindowController(private)
-(void)setCurrentBookPath:(NSString *)new
{	
	currentBookPath = [new retain];
	currentBookName = [[currentBookPath lastPathComponent] retain];
	currentBookAlias = [[self aliasDataFromPath:currentBookPath] retain];
}
-(void)setOldBookPath
{	
	oldBookPath = currentBookPath;
	oldBookName = currentBookName;
	oldBookAlias = currentBookAlias;
}
-(void)setCurrentBookPathAndOldBookPath:(NSString *)new 
{
	if (currentBookPath!=nil) {
		[self setOldBookPath];
	}
	[self setCurrentBookPath:new];
}
- (void)checkCurrentFolderUpdated
{
	if (changeCurrentFolderMode==2) return;
	
	if (currentBookPath!=nil) {
		NSString *oldSuperPath = [currentBookPath stringByDeletingLastPathComponent];
		
		NSString *tmpCurrentPath = [self pathFromAliasData:currentBookAlias];
		NSString *superPath = [tmpCurrentPath stringByDeletingLastPathComponent];
		
		BOOL updateMenu = NO;
		if (![oldSuperPath isEqualToString:superPath]) {
			
			NSModalResponse result = NSAlertFirstButtonReturn;
			if (changeCurrentFolderMode==0) {
				NSAlert *alert = [[[NSAlert alloc] init] autorelease];
				[alert setMessageText:NSLocalizedString(@"Change current folder",@"")];
				[alert setInformativeText:NSLocalizedString(@"The current opening book was moved. Are you sure you want to change current folder?",@"")];
				[alert addButtonWithTitle:NSLocalizedString(@"OK",@"")];
				[alert addButtonWithTitle:NSLocalizedString(@"Cancel",@"")];
				result = [alert runModal];
			}

			if(result == NSAlertFirstButtonReturn) {
				updateMenu = YES;
			} else {
				NSEnumerator *enumerator = [[[[appController openSameFolderMenuItem] submenu] itemArray] objectEnumerator];
				id object;
				while (object = [enumerator nextObject]) {
					if ([object state] == NSOnState){
						[object setEnabled:NO];
						break;
					}
				}
			}
		} else {
            NSDate *updateDate = [[[NSFileManager defaultManager] attributesOfItemAtPath:[superPath stringByResolvingSymlinksInPath] error:nil] fileModificationDate];
			NSComparisonResult res = [lastSameFolderMenuUpdate compare:updateDate];
			if (res == NSOrderedAscending) {
				updateMenu = YES;
			}
		}
		if (updateMenu) {
			[self setSameFolderMenu:YES];
		}
	}
	
}

@end
