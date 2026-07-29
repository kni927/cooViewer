#import "AppController.h"
#import "Controller.h"
#import "PreferenceController.h"

@implementation AppController

/* Same timing as before MW-3: Controller's own -awakeFromNib called
   -setupRemoteControl as its last step, during nib load rather than at
   applicationDidFinishLaunching: time. AppController is a nib object too
   now (wired as NSApplication's delegate), so its own -awakeFromNib
   preserves that timing. */
- (void)awakeFromNib
{
	[self setupRemoteControl];
}

#pragma mark NSApplicationDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
	/* Almost the entire body is window-level (pushes keyArray/mouseArray
	   into the window's outlets, then the OpenLastFolder gate) — see the
	   MW-3 pre-implementation inventory in docs/multiwindow-plan.md. */
	[controller applicationDidFinishLaunchingSetup:notification];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
	[[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)applicationWillBecomeActive:(NSNotification *)aNotification
{
	[remoteControl startListening:self];
}
- (void)applicationWillResignActive:(NSNotification *)aNotification
{
	[remoteControl stopListening:self];
}
- (void)applicationDidBecomeActive:(NSNotification *)aNotification
{
	/* checkCurrentFolderUpdated stats the parent folder of the current book
	   (and may re-enumerate it via setSameFolderMenu:). Doing that every time
	   the app regains focus hits the parent folder constantly and can trigger
	   macOS folder-access permission prompts repeatedly. It's now run lazily,
	   right before the "Open from same folder" submenu is actually shown —
	   see -[Controller menuNeedsUpdate:]. */
}

- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename
{
	return [controller application:theApplication openFile:filename];
}

- (NSMenu *)applicationDockMenu:(NSApplication *)sender
{
	/* MW-3 finding: this used to read the per-window [imageView image]
	   directly; with exactly one window it now asks that window controller
	   whether a book is open. "The front window" (plural) is MW-7's job. */
	NSMenu *menu = [[[NSMenu alloc] init] autorelease];

	if (![controller hasBookOpen]) {
		NSMenuItem *menuItem;
		menuItem = [[NSMenuItem alloc] init];
		[menuItem setTitle:NSLocalizedString(@"Open the last page", @"")];
		[menuItem setAction:@selector(openTheLastPage:)];
		[menu addItem:menuItem];
		[menuItem release];
	}
	return menu;
}

#pragma mark appleRemote

- (void)setupRemoteControl
{
	remoteControl = [[AppleRemote alloc] initWithDelegate:self];
	[remoteControl setDelegate:self];

	// OPTIONAL CODE
	// The MultiClickRemoteBehavior adds extra functionality.
	// It works like a middle man between the delegate and the remote control
	remoteControlBehavior = [MultiClickRemoteBehavior new];
	[remoteControlBehavior setDelegate:self];
	[remoteControlBehavior setSimulateHoldEvent:YES];
	[remoteControl setOpenInExclusiveMode:YES];
	[remoteControl setDelegate:remoteControlBehavior];
	[remoteControl startListening:self];
}

- (BOOL)appleRemoteHoldDown
{
	return appleRemoteHoldDown;
}

#pragma mark action

/* Moved from Controller_input.m together with setupRemoteControl (MW-3
   finding #4). The body still needs window-side state (the window's
   visible/key state, the thumbnail panel, and the actual key dispatch in
   -timeredRemoteButtonEvent:), which stays on Controller and is reached
   through it — there is exactly one controller to route to until MW-7. */
- (void)remoteButton:(RemoteControlEventIdentifier)buttonIdentifier pressedDown:(BOOL)pressedDown clickCount:(unsigned int)clickCount
{
	appleRemoteHoldDown = NO;
	if (!pressedDown) {
		return;
	}
	UpdateSystemActivity( OverallAct );
	//UpdateSystemActivity(UsrActivity);

    unichar character = buttonIdentifier;
	switch(buttonIdentifier) {
		case kRemoteButtonRight_Hold:
			appleRemoteHoldDown = YES;
			character = kRemoteButtonRight;
			break;
		case kRemoteButtonLeft_Hold:
			appleRemoteHoldDown = YES;
			character = kRemoteButtonLeft;
			break;
		case kRemoteButtonPlus_Hold:
			appleRemoteHoldDown = YES;
			character = kRemoteButtonPlus;
			break;
		case kRemoteButtonMinus_Hold:
			appleRemoteHoldDown = YES;
			character = kRemoteButtonMinus;
			break;
		case kRemoteButtonPlay_Hold:
			appleRemoteHoldDown = YES;
			character = kRemoteButtonPlay;
			break;
		case kRemoteButtonMenu_Hold:
			appleRemoteHoldDown = YES;
			character = kRemoteButtonMenu;
			break;
		default:
			break;
	}
	NSString *characters = [NSString stringWithCharacters:&character length:1];

	NSWindow *bookWindow = [controller sheetParentWindow];
	if (![bookWindow isVisible] || ![bookWindow isKeyWindow]) {
		if ([prefController inKeyEdit]) {
			[prefController setKeyCharacters:characters];
			appleRemoteHoldDown = NO;
			return;
		}
		if (![[controller thumController] isVisible]) {
			appleRemoteHoldDown = NO;
			return;
		}
	}
	[controller timeredRemoteButtonEvent:characters];
}

#pragma mark dontSleep

- (void)dontSleepTimerStart
{
	if (dontSleepTimer == nil) {
		dontSleepTimer = [NSTimer scheduledTimerWithTimeInterval:25.0
														  target:self
														selector:@selector(dontSleep)
														userInfo:NULL
														 repeats:YES];
	}
}
- (void)dontSleepTimerStop
{
	[dontSleepTimer invalidate];
	dontSleepTimer = nil;
}
- (void)dontSleep
{
	UpdateSystemActivity( OverallAct );
	//UpdateSystemActivity( UsrActivity );
}

#pragma mark openFromAny

- (IBAction)open:(id)sender
{
	[controller open:sender];
}
- (IBAction)openTheLastPage:(id)sender
{
	[controller openTheLastPage:sender];
}

#pragma mark preferences

- (IBAction)preferences:(id)sender
{
	[prefController preferences];
}
- (IBAction)clearRecent:(id)sender
{
	[[NSUserDefaults standardUserDefaults] removeObjectForKey:@"RecentItems"];
	[[NSUserDefaults standardUserDefaults] synchronize];
	[controller setOpenRecentMenu];
}

#pragma mark menu outlet accessors
/* Builder methods for these menus stay on Controller (they read per-window
   book state); Controller reaches the items through these accessors. */

- (id)openRecentMenuItem
{
	return openRecentMenuItem;
}
- (id)openSameFolderMenuItem
{
	return openSameFolderMenuItem;
}
- (id)bookmarkMenuItem
{
	return bookmarkMenuItem;
}

#pragma mark window registry / app-wide panels (MW-5)

/* The book window controller. Exactly one entry today; MW-6 turns this into
   "the front window". */
- (id)controller
{
	return controller;
}

/* The All Bookmark browser (MW-5 item 5). App-wide, so it lives here rather
   than on a window controller. */
- (id)allBookmarkController
{
	return allBookmarkController;
}

#pragma mark validation

/* MW-4: this used to forward wholesale to -[Controller validateMenuItem:],
 * which held all 44 title branches (including the AppController items,
 * since everything but Controller itself was target="484" back then). Now
 * that the render-path/book actions target First Responder and resolve to
 * Controller via the window's delegate, Controller's method only needs to
 * validate items still explicitly targeted at it (the RightMenu
 * contextAction/sheet items) plus whatever the responder chain search finds
 * it for. This method now only needs to handle AppController's own items:
 * "Open the last page" keeps its original per-window check (moved to
 * -[Controller validateOpenTheLastPageMenuItem]); Open/Preferences/Clear
 * Recent had no special-case branch before (they fell through Controller's
 * default) and still don't. */
- (BOOL)validateMenuItem:(NSMenuItem *)anItem
{
	if ([[anItem title] isEqualToString:NSLocalizedString(@"Open the last page", @"")] == YES) {
		return [controller validateOpenTheLastPageMenuItem];
	}
	return YES;
}

#pragma mark persistence (MW-3 cont.)
/* Moved bodily from Controller.m, unchanged apart from -pathFromAliasData:/
   -aliasDataFromPath: calls now going through the `controller` outlet
   (those helpers stayed window-side). */

- (id)searchFromBookSettings:(NSString *)path key:(NSString **)key
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	if ([defaults dictionaryForKey:@"BookSettings"]) {
		NSEnumerator *enu = [[defaults dictionaryForKey:@"BookSettings"] objectEnumerator];
		id object;
		while (object = [enu nextObject]) {
			if ([[object objectForKey:@"temppath"] isEqualToString:path]) {
				if ([[controller pathFromAliasData:[object objectForKey:@"alias"]] isEqualToString:path]) {
					if (key) {
						*key = [[[defaults dictionaryForKey:@"BookSettings"] allKeysForObject:object] objectAtIndex:0];
					}
					return [NSDictionary dictionaryWithDictionary:object];
				}
			}
		}

		NSMutableDictionary *newDic = [NSMutableDictionary dictionaryWithDictionary:[defaults dictionaryForKey:@"BookSettings"]];
		NSEnumerator *enuS = [newDic keyEnumerator];
		id tempKey;
		while (tempKey = [enuS nextObject]) {
			if ([[controller pathFromAliasData:[[newDic objectForKey:tempKey] objectForKey:@"alias"]] isEqualToString:path]) {
				NSMutableDictionary *newInnerDic = [NSMutableDictionary dictionaryWithDictionary:[newDic objectForKey:tempKey]];
				[newInnerDic setObject:path forKey:@"temppath"];
				[newDic setObject:newInnerDic forKey:tempKey];

				if (key) {
					*key = tempKey;
				}
				[defaults setObject:newDic forKey:@"BookSettings"];
				return [NSDictionary dictionaryWithDictionary:newInnerDic];
			}
		}
	}
	if (key) *key = nil;
	return nil;
}

- (id)searchFromRecentItems:(NSString *)path index:(int *)index
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	if ([defaults arrayForKey:@"RecentItems"]) {
		NSEnumerator *enu = [[defaults arrayForKey:@"RecentItems"] objectEnumerator];
		id object;
		while (object = [enu nextObject]) {
			if ([[object objectForKey:@"temppath"] isEqualToString:path]) {
				if ([[controller pathFromAliasData:[object objectForKey:@"alias"]] isEqualToString:path]) {
					if (index) {
						*index = (int)[[defaults arrayForKey:@"RecentItems"] indexOfObject:object];
					}
					return [NSDictionary dictionaryWithDictionary:object];
				}
			}
		}

		NSEnumerator *enuS = [[defaults arrayForKey:@"RecentItems"] objectEnumerator];
		while (object = [enuS nextObject]) {
			if ([[controller pathFromAliasData:[object objectForKey:@"alias"]] isEqualToString:path]) {
				NSMutableArray *newArray = [NSMutableArray arrayWithArray:[defaults arrayForKey:@"RecentItems"]];
				NSMutableDictionary *newInnerDic = [NSMutableDictionary dictionaryWithDictionary:object];
				int tempIndex = (int)[[defaults arrayForKey:@"RecentItems"] indexOfObject:object];
				[newArray removeObjectAtIndex:tempIndex];
				[newInnerDic setObject:path forKey:@"temppath"];
				[newArray insertObject:newInnerDic atIndex:tempIndex];

				if (index) {
					*index = tempIndex;
				}
				[defaults setObject:newArray forKey:@"RecentItems"];
				return [NSDictionary dictionaryWithDictionary:newInnerDic];
			}
		}
	}
	if (index) *index = -1;
	return nil;
}

- (id)searchFromLastPages:(NSString *)path index:(int *)index
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	if ([defaults arrayForKey:@"LastPages"]) {
		NSEnumerator *enu = [[defaults arrayForKey:@"LastPages"] objectEnumerator];
		id object;
		while (object = [enu nextObject]) {
			if ([[object objectForKey:@"temppath"] isEqualToString:path]) {
				if ([[controller pathFromAliasData:[object objectForKey:@"alias"]] isEqualToString:path]) {
					if (index) {
						*index = (int)[[defaults arrayForKey:@"LastPages"] indexOfObject:object];
					}
					return [NSDictionary dictionaryWithDictionary:object];
				}
			}
		}

		NSEnumerator *enuS = [[defaults arrayForKey:@"LastPages"] objectEnumerator];
		while (object = [enuS nextObject]) {
			if ([[controller pathFromAliasData:[object objectForKey:@"alias"]] isEqualToString:path]) {
				NSMutableArray *newArray = [NSMutableArray arrayWithArray:[defaults arrayForKey:@"LastPages"]];
				NSMutableDictionary *newInnerDic = [NSMutableDictionary dictionaryWithDictionary:object];
				int tempIndex = (int)[[defaults arrayForKey:@"LastPages"] indexOfObject:object];
				[newArray removeObjectAtIndex:tempIndex];
				[newInnerDic setObject:path forKey:@"temppath"];
				[newArray insertObject:newInnerDic atIndex:tempIndex];

				if (index) {
					*index = (int)[[defaults arrayForKey:@"LastPages"] indexOfObject:object];
				}
				[defaults setObject:newArray forKey:@"LastPages"];
				return [NSDictionary dictionaryWithDictionary:newInnerDic];
			}
		}
	}
	if (index) *index = -1;
	return nil;
}

- (id)searchFromBookSettings:(NSString *)path key:(NSString **)key more:(BOOL)b
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	id searched = [self searchFromBookSettings:path key:key];
	if (searched) {
		return searched;
	} else if (!searched && b && [defaults dictionaryForKey:@"BookSettings"]) {
		NSString *temp;

		NSMutableDictionary *newDic = [NSMutableDictionary dictionaryWithDictionary:[defaults dictionaryForKey:@"BookSettings"]];
		NSEnumerator *enuS = [newDic keyEnumerator];
		id tempKey;

		while (tempKey = [enuS nextObject]) {
			temp = [controller pathFromAliasData:[[newDic objectForKey:tempKey] objectForKey:@"alias"]];
			if ([[temp lastPathComponent] isEqualToString:[path lastPathComponent]] && ![[NSFileManager defaultManager] fileExistsAtPath:temp]) {

				NSAlert *alert = [[[NSAlert alloc] init] autorelease];
				[alert setMessageText:NSLocalizedString(@"Setting is not found",@"")];
				[alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"Setting of %@ is not found.\nDo you want to use a setting of %@ ?",@""),path,temp]];
				[alert addButtonWithTitle:NSLocalizedString(@"OK",@"")];
				[alert addButtonWithTitle:NSLocalizedString(@"Cancel",@"")];

				if([alert runModal] == NSAlertFirstButtonReturn) {
					/*LastPagesの修正*/
					int lastPagesIndex;
					id lastPage = [self searchFromLastPages:temp index:&lastPagesIndex];
					if (lastPage) {
						NSMutableDictionary *newLastPage = [NSMutableDictionary dictionaryWithDictionary:lastPage];
						NSMutableArray *newLastPagesArray = [NSMutableArray arrayWithArray:[defaults arrayForKey:@"LastPages"]];
						[newLastPage setObject:path forKey:@"temppath"];
						[newLastPage setObject:[controller aliasDataFromPath:path] forKey:@"alias"];
						[newLastPagesArray removeObjectAtIndex:lastPagesIndex];
						[newLastPagesArray insertObject:newLastPage atIndex:lastPagesIndex];
						[defaults setObject:newLastPagesArray forKey:@"LastPages"];
					}
					/*RecentItemsの修正*/
					int recentItemsIndex;
					id recentItem = [self searchFromRecentItems:temp index:&recentItemsIndex];
					if (recentItem) {
						NSMutableDictionary *newRecentItem = [NSMutableDictionary dictionaryWithDictionary:recentItem];
						NSMutableArray *newRecentItemsArray = [NSMutableArray arrayWithArray:[defaults arrayForKey:@"RecentItems"]];
						[newRecentItem setObject:path forKey:@"temppath"];
						[newRecentItem setObject:[controller aliasDataFromPath:path] forKey:@"alias"];
						[newRecentItemsArray removeObjectAtIndex:recentItemsIndex];
						[newRecentItemsArray insertObject:newRecentItem atIndex:recentItemsIndex];
						[defaults setObject:newRecentItemsArray forKey:@"RecentItems"];
					}
					/*BookSettingsの修正*/
					NSMutableDictionary *newInnerDic = [NSMutableDictionary dictionaryWithDictionary:[newDic objectForKey:tempKey]];
					[newInnerDic setObject:path forKey:@"temppath"];
					[newInnerDic setObject:[controller aliasDataFromPath:path] forKey:@"alias"];
					[newDic setObject:newInnerDic forKey:tempKey];

					if (key) {
						*key = tempKey;
					}
					[defaults setObject:newDic forKey:@"BookSettings"];
					return [NSDictionary dictionaryWithDictionary:newInnerDic];
				}
			}
		}
	}
	return nil;
}

- (void)recordClosingBookSettings:(NSString *)path
                              name:(NSString *)name
                             alias:(NSData *)aliasData
                         bookmarks:(NSArray *)bookmarks
                       bookSetting:(NSMutableDictionary *)bookSetting
                              page:(int)page
                   openRecentLimit:(int)openRecentLimit
            alwaysRememberLastPage:(BOOL)alwaysRememberLastPage
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	NSMutableDictionary *dic;
	if (![defaults dictionaryForKey:@"BookSettings"]) {
		dic = [NSMutableDictionary dictionary];
	} else {
		dic = [NSMutableDictionary dictionaryWithDictionary:[defaults dictionaryForKey:@"BookSettings"]];
	}
	id key;
	[self searchFromBookSettings:path key:&key];

	[bookSetting setObject:aliasData forKey:@"alias"];
	[bookSetting setObject:path forKey:@"temppath"];
	if ([bookmarks count]>0) {
		[bookSetting setObject:bookmarks forKey:@"bookmarks"];
	} else if ([bookmarks count]==0) {
		[bookSetting removeObjectForKey:@"bookmarks"];
	}
	if ([bookSetting count]>2) {
		if (!key) {
			key = name;
			int i = 2;
			while ([dic objectForKey:key]) {
				key = [NSString stringWithFormat:@"%@#%i",name,i];
				i++;
			}
			[dic setObject:bookSetting forKey:key];
		} else {
			[dic setObject:bookSetting forKey:key];
		}
		[defaults setObject:dic forKey:@"BookSettings"];
	}

	NSNumber *pageNumber = [NSNumber numberWithInt:page];
	if (openRecentLimit>0) {
		NSMutableArray *newRecentItems;
		if (![defaults arrayForKey:@"RecentItems"]) {
			newRecentItems = [NSMutableArray array];
		} else {
			newRecentItems = [NSMutableArray arrayWithArray:[defaults arrayForKey:@"RecentItems"]];
		}
		int index = 0;
		id object = [self searchFromRecentItems:path index:&index];
		if (object) {
			[newRecentItems removeObjectAtIndex:index];
		}
		while ([newRecentItems count] >= openRecentLimit) {
			[newRecentItems removeLastObject];
		}
		[newRecentItems insertObject:[NSDictionary dictionaryWithObjectsAndKeys:aliasData,@"alias",pageNumber,@"page",path,@"temppath",nil] atIndex:0];
		[defaults setObject:newRecentItems forKey:@"RecentItems"];
	} else {
		[defaults removeObjectForKey:@"RecentItems"];
	}

	if (alwaysRememberLastPage && page > 0) {
		NSMutableArray *lastPages;
		if (![defaults arrayForKey:@"LastPages"]) {
			lastPages = [NSMutableArray array];
		} else {
			lastPages = [NSMutableArray arrayWithArray:[defaults arrayForKey:@"LastPages"]];
		}
		int index;
		id object = [self searchFromLastPages:path index:&index];
		if (object) {
			[lastPages removeObjectAtIndex:index];
		}
		[lastPages addObject:[NSDictionary dictionaryWithObjectsAndKeys:aliasData,@"alias",pageNumber,@"page",path,@"temppath",nil]];
		[defaults setObject:lastPages forKey:@"LastPages"];
	} else if (!alwaysRememberLastPage || page == 0) {
		NSMutableArray *lastPages;
		if (![defaults arrayForKey:@"LastPages"]) {
			lastPages = [NSMutableArray array];
		} else {
			lastPages = [NSMutableArray arrayWithArray:[defaults arrayForKey:@"LastPages"]];
		}
		int index;
		id object = [self searchFromLastPages:path index:&index];
		if (object) {
			[lastPages removeObjectAtIndex:index];
		}
		[defaults setObject:lastPages forKey:@"LastPages"];
	}
}

/* This call site's RecentItems removal has always used a plain
   -pathFromAliasData: comparison instead of -searchFromRecentItems:
   (temppath+alias match) — see the divergence note in AppController.h.
   Kept as an independent, faithful port of
   -[Controller windowWillClose:]'s original body rather than reconciled
   with -recordClosingBookSettings:...'s. */
- (void)recordBookSettingsOnWindowClose:(NSString *)path
                                    name:(NSString *)name
                                   alias:(NSData *)aliasData
                               bookmarks:(NSArray *)bookmarks
                             bookSetting:(NSMutableDictionary *)bookSetting
                                    page:(int)page
                         openRecentLimit:(int)openRecentLimit
                  alwaysRememberLastPage:(BOOL)alwaysRememberLastPage
                   rememberBookSettings:(BOOL)rememberBookSettings
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	NSMutableDictionary *dic;
	if (![defaults dictionaryForKey:@"BookSettings"]) {
		dic = [NSMutableDictionary dictionary];
	} else {
		dic = [NSMutableDictionary dictionaryWithDictionary:[defaults dictionaryForKey:@"BookSettings"]];
	}
	id key;
	[self searchFromBookSettings:path key:&key];

	if (!rememberBookSettings) {
		[bookSetting removeAllObjects];
	}

	[bookSetting setObject:aliasData forKey:@"alias"];
	[bookSetting setObject:path forKey:@"temppath"];
	if ([bookmarks count]>0) {
		[bookSetting setObject:bookmarks forKey:@"bookmarks"];
	} else if ([bookmarks count]==0) {
		[bookSetting removeObjectForKey:@"bookmarks"];
	}
	if ([bookSetting count]>2) {
		if (!key) {
			key = name;
			int i = 2;
			while ([dic objectForKey:key]) {
				key = [NSString stringWithFormat:@"%@#%i",name,i];
				i++;
			}
			[dic setObject:bookSetting forKey:key];
		} else {
			[dic setObject:bookSetting forKey:key];
		}
		[defaults setObject:dic forKey:@"BookSettings"];
	}

	NSNumber *pageNumber = [NSNumber numberWithInt:page];
	if (openRecentLimit>0) {
		NSMutableArray *array;
		if (![defaults arrayForKey:@"RecentItems"]) {
			array = [NSMutableArray array];
		} else {
			array = [NSMutableArray arrayWithArray:[defaults arrayForKey:@"RecentItems"]];
		}
		NSEnumerator *enu = [array objectEnumerator];
		id object;
		while (object = [enu nextObject]) {
			if ([[controller pathFromAliasData:[object objectForKey:@"alias"]] isEqualToString:path]) {
				[array removeObject:object];
				break;
			}
		}
		while ([array count] >= openRecentLimit) {
			[array removeLastObject];
		}
		[array insertObject:[NSDictionary dictionaryWithObjectsAndKeys:aliasData,@"alias",pageNumber,@"page",path,@"temppath",nil] atIndex:0];
		[defaults setObject:array forKey:@"RecentItems"];
	} else {
		[defaults removeObjectForKey:@"RecentItems"];
	}
	if (alwaysRememberLastPage && page > 0) {
		NSMutableArray *array;
		if (![defaults arrayForKey:@"LastPages"]) {
			array = [NSMutableArray array];
		} else {
			array = [NSMutableArray arrayWithArray:[defaults arrayForKey:@"LastPages"]];
		}
		NSEnumerator *enu = [array objectEnumerator];
		id object;
		while (object = [enu nextObject]) {
			if ([[controller pathFromAliasData:[object objectForKey:@"alias"]] isEqualToString:path]) {
				[array removeObject:object];
				break;
			}
		}
		[array addObject:[NSDictionary dictionaryWithObjectsAndKeys:aliasData,@"alias",pageNumber,@"page",path,@"temppath",nil]];
		[defaults setObject:array forKey:@"LastPages"];
	} else if (!alwaysRememberLastPage || page == 0) {
		NSMutableArray *lastPages;
		if (![defaults arrayForKey:@"LastPages"]) {
			lastPages = [NSMutableArray array];
		} else {
			lastPages = [NSMutableArray arrayWithArray:[defaults arrayForKey:@"LastPages"]];
		}
		int index;
		id object = [self searchFromLastPages:path index:&index];
		if (object) {
			[lastPages removeObjectAtIndex:index];
		}
		[defaults setObject:lastPages forKey:@"LastPages"];
	}
	[defaults synchronize];
}

@end
