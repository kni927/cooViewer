#import "BookWindowController.h"
#import "AppController.h"	/* appController outlet accessors (MW-3) */
#import "CustomWindow.h"
#import "BookmarkController.h"
#import "CustomImageView.h"
#import "FullImagePanel.h"
@implementation BookWindowController (Input)

/* The bound key and mouse actions that act on the window rather than on a
   page: close, open the last page, full screen and minimize. They are the
   only ones a window without a book (File ▸ New Window, or one left empty by
   a cancelled password prompt) runs; every other action would page through,
   or index into, a book that is not there. */
static BOOL IsWindowKeyAction(int action)
{
	return action == 46 || action == 48 || action == 49 || action == 50;
}

static BOOL IsWindowMouseAction(int action)
{
	return action == 57 || action == 60 || action == 61 || action == 62;
}

#pragma mark action
/* -remoteButton:pressedDown:clickCount: and the appleRemoteHoldDown state it
   maintains moved to AppController (MW-3, together with setupRemoteControl).
   This method is still reached from there via -timeredRemoteButtonEvent:. */
- (void)timeredRemoteButtonEvent:(NSString*)characters;
{
	if ([thumController isVisible]) {
		[thumController appleRemoteAction:characters];
	} else {
		BOOL slideshow = NO;
		if (timerSwitch) {
			[timer invalidate];
			timer = nil;
			timerSwitch = NO;
			slideshow = YES;
			[imageView setSlideshow:NO];
		}
		threadStop = NO;
		unichar character = [characters characterAtIndex:0];
		unsigned int cMod = 100;
		if (fitScreenMode == 0) {
			[self getKeyAction:character mod:cMod mode:0 slideshow:slideshow];
		} else if (fitScreenMode == 1) {
			if (![self getKeyAction:character mod:cMod mode:1 slideshow:slideshow]) {
				[self getKeyAction:character mod:cMod mode:0 slideshow:slideshow];
			}
		} else if (fitScreenMode == 2 || fitScreenMode == 3) {
			if (![self getKeyAction:character mod:cMod mode:2 slideshow:slideshow]) {
				[self getKeyAction:character mod:cMod mode:0 slideshow:slideshow];
			}
		}
	}
	if (![appController appleRemoteHoldDown]) return;
	[self performSelector:@selector(timeredRemoteButtonEvent:) withObject:characters afterDelay:0.1];
}

- (void)keyAction:(NSEvent*)sender
{
	/* A dead key (or an input-method keystroke) has no characters; there is
	   nothing to look up (code review M12). */
	if ([[sender charactersIgnoringModifiers] length] == 0) return;
	BOOL slideshow = NO;
	if (timerSwitch) {
		[timer invalidate];
		timer = nil;
		timerSwitch = NO;
		slideshow = YES;
		[imageView setSlideshow:NO];
		//return;
	}
	threadStop = NO;
	NSString *characters = [sender charactersIgnoringModifiers];
    unichar character = [characters characterAtIndex: 0];
	
	if ([[NSCharacterSet decimalDigitCharacterSet] characterIsMember:character]){
		if ([imageView pageMover]) {
			if ([imageView tempPageNum] > 99999) {
				return;
			}
			[imageView drawPageMover:[characters intValue]];
			return;
		}
	} else if (character == 0x1B) {
		//esc
		if ([imageView pageMover]) {
			[imageView drawPageMover:-1];
			return;
		} else {
			/* The close drops a pending display and abandons the lookahead;
			   nothing to wait for first (KNOWN_ISSUES #46). */
			[[self window] performClose:self];
			return;
		}
	} else if (character == NSDeleteCharacter) {
		if ([imageView pageMover]) {
			if ([imageView tempPageNum]<=0) {
				return;
			} else {
				[imageView drawPageMover:-2];
				return;
			}
		}
	} 
	
	unsigned int cMod = 0;
	BOOL shift = ([sender modifierFlags] & NSShiftKeyMask) ? YES : NO;
	BOOL option = ([sender modifierFlags] & NSAlternateKeyMask) ? YES : NO;
	BOOL control = ([sender modifierFlags] & NSControlKeyMask) ? YES : NO;
	BOOL numeric = ([sender modifierFlags] & NSNumericPadKeyMask) ? YES : NO;
	
	if (shift) cMod += 1;
	if (option) cMod += 2;
	if (control) cMod += 4;
	if (numeric) {
		if (character == NSLeftArrowFunctionKey||character == NSRightArrowFunctionKey||character == NSUpArrowFunctionKey||character == NSDownArrowFunctionKey) {
		} else {
			cMod += 8;
		}
	}
	
	if (fitScreenMode == 0) {
		[self getKeyAction:character mod:cMod mode:0 slideshow:slideshow];
	} else if (fitScreenMode == 1) {
		if (![self getKeyAction:character mod:cMod mode:1 slideshow:slideshow]) {
			[self getKeyAction:character mod:cMod mode:0 slideshow:slideshow];
		}
	} else if (fitScreenMode == 2 || fitScreenMode == 3) {
		if (![self getKeyAction:character mod:cMod mode:2 slideshow:slideshow]) {
			[self getKeyAction:character mod:cMod mode:0 slideshow:slideshow];
		}
	}
}

- (BOOL)getKeyAction:(unichar)character mod:(int)cMod mode:(int)mode slideshow:(BOOL)slideshow
{
	
    NSEnumerator *enu = nil;
	switch (mode) {
		case 0:
			enu = [keyArray objectEnumerator];
			break;
		case 1:
			enu = [keyArrayMode2 objectEnumerator];
			break;
		case 2:
			enu = [keyArrayMode3 objectEnumerator];
			break;
		default:break;
	}
	id dic;
	while (dic = [enu nextObject]) {
		if ([[dic objectForKey:@"key"] length] > 0 && character == [[dic objectForKey:@"key"] characterAtIndex:0] && cMod == [[dic objectForKey:@"modifier"] intValue]){
			int action = [[dic objectForKey:@"action"] intValue];
			if ([[dic objectForKey:@"switchAction"] boolValue] == YES && [self readFromLeft]) {
				switch (action) {
					case 0: action=1; break;
					case 1: action=0; break;
					case 2: action=3; break;
					case 3: action=2; break;
					case 4: action=5; break;
					case 5: action=4; break;
					case 6: action=7; break;
					case 7: action=6; break;
					case 8: action=9; break;
					case 9: action=8; break;
					case 13: action=14; break;
					case 14: action=13; break;
					case 26: action=27; break;
					case 27: action=26; break;
					case 35: action=36; break;
					case 36: action=35; break;
				default:
					break;
				}
			}
			if (![self hasBookOpen] && !IsWindowKeyAction(action)) return YES;
			switch (action) {
				case 0:
					//nextpage
					[self nextPage];
					break;
					
					
				case 1:
					//prevpage
					//[lock lock];
					//[lock unlock];
					[self prevPage];
					break;
					
					
					
				case 2:
					//halfnext
					[self halfNextPage];
					break;
					
					
					
				case 3:
					//halfprev
					[self halfprevPage];
					break;
					
					
					
				case 4:
					//lastpage
					[self goToLast];
					break;
					
					
					
				case 5:
					//toppage
					[self goToTop];
					break;
					
					
					
				case 6:
					//nextbookmark
					[self nextBookmark];
					break;
					
					
				case 7:
					//prevbookmark
					[self backBookmark];	
					break;
					
					
					
				case 8:
					//nextfolder
					[self nextFolder];
					break;
					
					
					
				case 9:
					//prevfolder
					[self backFolder];
					break;
					
					
				case 10:
					//add/removebookmark
					if ([self removeBookmark]) {
					} else {
						[self addBookmark];
					}
					break;
					
					
				case 11:
					//switchSingle
					[self switchSingle:nil];
					break;
					
					
					
				case 12:
					//shownumber
					numberSwitch = !numberSwitch;
					[defaults setBool:numberSwitch forKey:@"ShowNumber"];
					[self setPageTextField];
					//[imageView setNeedsDisplay];					
					break;
					
					
					
				case 13:
					//skip
					[self skipPages:[[dic objectForKey:@"value"] intValue]];
					break;
					
					
					
				case 14:
					//backskip
					[self backSkipPages:[[dic objectForKey:@"value"] intValue]];
					break;
					
					
					
				case 15:
					//origRight
					switch (readMode) {
						case 0:
							[self viewAtOriginalSizeFirst:self];
							break;
						case 1:
							[self viewAtOriginalSizeSecond:self];
							break;
						case 2:
							[self viewAtOriginalSizeFirst:self];
							break;
						case 3:
							[self viewAtOriginalSizeSecond:self];
							break;
						default:
							break;
					}
					
					break;
					
					
					
				case 16:
					//origLeft
					switch (readMode) {
						case 0:
							[self viewAtOriginalSizeSecond:self];
							break;
						case 1:
							[self viewAtOriginalSizeFirst:self];
							break;
						case 2:
							[self viewAtOriginalSizeSecond:self];
							break;
						case 3:
							[self viewAtOriginalSizeFirst:self];
							break;
						default:
							break;
					}
					break;
					
					
					
				case 17:
					//slideshow
					if (!slideshow) {
						[self slideshow:nil];
					}
					[self setPageTextField];
					break;
					
					
					
				case 18:
					//showThumbnail
					if (secondImage) {
						int temp = nowPage;
						temp--;
						[thumController showThumbnail:temp];
					} else {
						[thumController showThumbnail:nowPage];
					}
					break;
					
					
					
				case 19:
					//changeReadMode 
					if (readMode == 0) {
						[self changeReadMode:1];
					} else if (readMode == 1) {
						[self changeReadMode:2];
					} else if (readMode == 2) {
						[self changeReadMode:3];
					} else if (readMode == 3) {
						[self changeReadMode:0];
					}
					break;
					
				case 20:
					//showPageBar
					if (pageBar) {
						pageBar = NO;
					} else {
						pageBar = YES;
					}
					[defaults setBool:pageBar forKey:@"ShowPageBar"];
					[imageView drawPageBar];
					break;
				case 21:
					//showPageMover
					if (![imageView pageMover]) {
						[imageView drawPageMover:0];
					} else {
						if ([imageView tempPageNum]<=0) {
							[imageView drawPageMover:-1];
							break;
						} else {
							int tempPageNum = [imageView tempPageNum];
							tempPageNum--;
							[self goTo:tempPageNum array:nil];
							[imageView drawPageMover:-1];
						}
					}
					break;
				case 22:
					//show in finder R
					switch (readMode) {
						case 0:
							[self showInFinderFirst:self];
							break;
						case 1:
							[self showInFinderSecond:self];
							break;
						case 2:
							[self showInFinderFirst:self];
							break;
						case 3:
							[self showInFinderSecond:self];
							break;
						default:
							break;
					}
					break;
				case 23:
					//showInFinderL
					switch (readMode) {
						case 0:
							[self showInFinderSecond:self];
							break;
						case 1:
							[self showInFinderFirst:self];
							break;
						case 2:
							[self showInFinderSecond:self];
							break;
						case 3:
							[self showInFinderFirst:self];
							break;
						default:
							break;
					}
					break;
				case 24:
					//PageUp
					[imageView scrollUp];
					break;
				case 25:
					//PageDown
					[imageView scrollDown];
					break;
				case 26:
					//PageUp + PrevPage
					if ([imageView prev] == YES) {
						//[lock lock];
						//[lock unlock];
						if (prevPageMode == 1) [imageView setStartFromEnd:YES];
						[self prevPage];
					}
					break;
				case 27:
					//PageDown + NextPage
					if ([imageView next] == YES) {
						[self nextPage];
					}
					break;
				case 28:
					//ScrollToTop
					[imageView scrollToTop];
					break;
				case 29:
					//ScrollToEnd
					[imageView scrollToLast];
					break;
				case 30:
					//ScrollUp
					[imageView scrollTo:NSMakePoint(0,-1*([[dic objectForKey:@"value"] intValue]))];
					break;
				case 31:
					//ScrollDown
					[imageView scrollTo:NSMakePoint(0,[[dic objectForKey:@"value"] intValue])];
					break;
				case 32:
					//ScrollLeft
					[imageView scrollTo:NSMakePoint([[dic objectForKey:@"value"] intValue],0)];
					break;
				case 33:
					//ScrollRight
					[imageView scrollTo:NSMakePoint((-1*[[dic objectForKey:@"value"] intValue]),0)];
					break;
				case 34:
					//loupe
					[imageView setLoupe];
					break;
				case 35:
					//nextSubFolder
					[self nextSubFolder];
					break;
				case 36:
					//prevSubFolder
					[self prevSubFolder];
					break;
				case 37:
					//loupeRatePlus
					[defaults setFloat:[defaults floatForKey:@"LoupeRate"]+[[dic objectForKey:@"value"] floatValue] forKey:@"LoupeRate"];
					[imageView setLoupeRate];
					break;
				case 38:
					//loupeRateMinus
					if ([defaults floatForKey:@"LoupeRate"]-[[dic objectForKey:@"value"] floatValue]>1.0) {
						[defaults setFloat:[defaults floatForKey:@"LoupeRate"]-[[dic objectForKey:@"value"] floatValue] forKey:@"LoupeRate"];
					} else {
						[defaults setFloat:1.0 forKey:@"LoupeRate"];
					}
					[imageView setLoupeRate];
					break;
				case 39:
					//goto%
					[self goToPar:([[dic objectForKey:@"value"] floatValue]/100)];
					break;
				case 40:
					//rotateRight
					[self rotateRight:nil];
					break;
				case 41:
					//rotateLeft
					[self rotateLeft:nil];
					break;
				case 42:
					//changeViewMode
					[self setPageTextField];
					switch (fitScreenMode) {
						case 0:
							[self fitToScreenWidth:nil];
							break;
						case 1:
							[self fitToScreenWidthDivide:nil];
							break;
						case 2:
							[self fitToScreen:nil];
							break;
						case 3:
							[self noScale:nil];
							break;
						default:
							break;
					}
					break;
				case 51:
					//enlargeViewMode
					[self setPageTextField];
					switch (fitScreenMode) {
						case 0:
							[self fitToScreenWidth:nil];
							break;
						case 1:
							[self fitToScreenWidthDivide:nil];
							break;
						case 3:
							[self noScale:nil];
							break;
						default:
							break;
					}
					break;
				case 52:
					//reduceViewMode
					[self setPageTextField];
					switch (fitScreenMode) {
						case 1:
							[self fitToScreen:nil];
							break;
						case 2:
							[self fitToScreenWidthDivide:nil];
							break;
						case 3:
							[self fitToScreenWidth:nil];
							break;
						default:
							break;
					}
					break;
				case 43:
					//trashRight
					[self trashRight];
					break;
				case 44:
					//trashLeft
					[self trashLeft];
					break;
				case 45:
					//changeSortMode
					if ([imageLoader canSortByDate]) {
						switch (sortMode) {
							case 0:sortMode = 2;break;
							case 1:sortMode = 0;break;
							case 2:sortMode = 3;break;
							case 3:sortMode = 1;break;
							default:break;
						}
						[self setSortMode:sortMode page:0];
					} else {
						switch (sortMode) {
							case 0:sortMode = 1;break;
							case 1:sortMode = 0;break;
							case 2:sortMode = 0;break;
							case 3:sortMode = 0;break;
							default:break;
						}
						[self setSortMode:sortMode page:0];
					}	
					break;
				case 46:
					//close
					/* The close drops a pending display and abandons the lookahead;
					   nothing to wait for first (KNOWN_ISSUES #46). */
					[[self window] performClose:self];
					break;
				case 47:
					//randam
					[self setSortMode:1 page:0];
					break;
				case 48:
					//openTheLastPage
					{
						NSMenu *menu = [[[NSApp mainMenu] itemWithTitle:NSLocalizedString(@"File", @"")] submenu];
						NSMenuItem *item = [menu itemWithTitle:NSLocalizedString(@"Open the last page", @"")];
						if ([item isEnabled]) {
							[menu performActionForItemAtIndex:[menu indexOfItem:item]];
						}
					}
					break;
				case 49:
					//switchFullScreen
					{
						/* MW-2: was driven through the Window menu's own
						   "Fullscreen" item, whose check-mark doubled as the
						   state store. Goes straight to AppKit now. */
						[[self window] toggleFullScreen:self];
					}
					break;
				case 50:
					//minimizeWindow
					{
						NSMenu *menu = [[[NSApp mainMenu] itemWithTitle:NSLocalizedString(@"Window", @"")] submenu];
						NSMenuItem *item = [menu itemWithTitle:NSLocalizedString(@"Minimize", @"")];
						if ([item isEnabled]) {
							[menu performActionForItemAtIndex:[menu indexOfItem:item]];
						}
					}
					break;
				default:
					break;
			}
			return YES;
		}
	}
	return NO;
}


- (void)mouseAction:(NSEvent*)sender
{
	if (timerSwitch) {
		[timer invalidate];
		timer = nil;
		timerSwitch=NO;
		[imageView setSlideshow:NO];
	}
	
	int button = (int)[sender buttonNumber];
	unsigned int cMod = 0;
	BOOL shift = ([sender modifierFlags] & NSShiftKeyMask) ? YES : NO;
	BOOL option = ([sender modifierFlags] & NSAlternateKeyMask) ? YES : NO;
	BOOL control = ([sender modifierFlags] & NSControlKeyMask) ? YES : NO;
	
	if (shift) {
		cMod += 1;
	}
	if (option) {
		cMod += 2;
	}
	if (control) {
		cMod += 4;
	}
	
	
	threadStop = NO;
	NSRect left,right;
	switch (readMode) {
		case 0:
			NSDivideRect ([[[self window] contentView] frame], &left, &right, [[[self window] contentView] frame].size.width/2, NSMinXEdge);
			break;
		case 1:
			NSDivideRect ([[[self window] contentView] frame], &right, &left, [[[self window] contentView] frame].size.width/2, NSMinXEdge);
			break;
		case 2:
			NSDivideRect ([[[self window] contentView] frame], &left, &right, [[[self window] contentView] frame].size.width/2, NSMinXEdge);
			break;
		case 3:
			NSDivideRect ([[[self window] contentView] frame], &right, &left, [[[self window] contentView] frame].size.width/2, NSMinXEdge);
			break;
		default:
			NSDivideRect ([[[self window] contentView] frame], &left, &right, [[[self window] contentView] frame].size.width/2, NSMinXEdge);
			break;
	}
	BOOL leftBool = NSPointInRect([sender locationInWindow], left);
	if (fitScreenMode == 0) {
		[self getMouseAction:button mod:cMod mode:0 left:leftBool];
	} else if (fitScreenMode == 1 || fitScreenMode == 3) {
		if (![self getMouseAction:button mod:cMod mode:1 left:leftBool]) {
			[self getMouseAction:button mod:cMod mode:0 left:leftBool];
		}
	} else if (fitScreenMode == 2) {
		if (![self getMouseAction:button mod:cMod mode:2 left:leftBool]) {
			[self getMouseAction:button mod:cMod mode:0 left:leftBool];
		}
	}
}

- (void)multiTouchAction:(NSEvent*)sender action:(int)action
{
	unsigned int cMod = 0;
	int button = 0;
	switch (action) {
		case 0:
			//swipe right
			button += 1000;
			break;
		case 1:
			//swipe left
			button += 2000;
			break;
		case 2:
			//swipe up
			button += 3000;
			break;
		case 3:
			//swipe down
			button += 4000;
			break;
		case 4:
			//pinch in
			button += 5000;
			break;
		case 5:
			//pinch out
			button += 6000;
			break;
		case 6:
			//rotate right
			button += 7000;
			break;
		case 7:
			//rotate left
			button += 8000;
			break;
		default:
			break;
	}
	BOOL shift = ([sender modifierFlags] & NSShiftKeyMask) ? YES : NO;
	BOOL option = ([sender modifierFlags] & NSAlternateKeyMask) ? YES : NO;
	BOOL control = ([sender modifierFlags] & NSControlKeyMask) ? YES : NO;
	
	if (shift) {
		cMod += 1;
	}
	if (option) {
		cMod += 2;
	}
	if (control) {
		cMod += 4;
	}
	
	
	threadStop = NO;
	NSRect left,right;
	switch (readMode) {
		case 0:
			NSDivideRect ([imageView frame], &left, &right, [imageView frame].size.width/2, NSMinXEdge);
			break;
		case 1:
			NSDivideRect ([imageView frame], &right, &left, [imageView frame].size.width/2, NSMinXEdge);
			break;
		case 2:
			NSDivideRect ([imageView frame], &left, &right, [imageView frame].size.width/2, NSMinXEdge);
			break;
		case 3:
			NSDivideRect ([imageView frame], &right, &left, [imageView frame].size.width/2, NSMinXEdge);
			break;
		default:
			NSDivideRect ([imageView frame], &left, &right, [imageView frame].size.width/2, NSMinXEdge);
			break;
	}
	BOOL leftBool = NSPointInRect([sender locationInWindow], left);
	if (fitScreenMode == 0) {
		[self getMouseAction:button mod:cMod mode:0 left:leftBool];
	} else if (fitScreenMode == 1) {
		if (![self getMouseAction:button mod:cMod mode:1 left:leftBool]) {
			[self getMouseAction:button mod:cMod mode:0 left:leftBool];
		}
	} else if (fitScreenMode == 2 || fitScreenMode == 3) {
		if (![self getMouseAction:button mod:cMod mode:2 left:leftBool]) {
			![self getMouseAction:button mod:cMod mode:0 left:leftBool];
		}
	}
}

- (void)gestureAction:(NSEvent*)sender moved:(int)moved
{
	int button = (int)[sender buttonNumber];
	unsigned int cMod = 0;
	switch (moved) {
		case 0:
			//left
			cMod += 200;
			break;
		case 1:
			//right
			cMod += 300;
			break;
		case 2:
			//up
			cMod += 400;
			break;
		case 3:
			//down
			cMod += 500;
			break;
		default:
			break;
	}
	BOOL shift = ([sender modifierFlags] & NSShiftKeyMask) ? YES : NO;
	BOOL option = ([sender modifierFlags] & NSAlternateKeyMask) ? YES : NO;
	BOOL control = ([sender modifierFlags] & NSControlKeyMask) ? YES : NO;
	
	if (shift) {
		cMod += 1;
	}
	if (option) {
		cMod += 2;
	}
	if (control) {
		cMod += 4;
	}
	
	
	threadStop = NO;
	NSRect left,right;
	switch (readMode) {
		case 0:
			NSDivideRect ([imageView frame], &left, &right, [imageView frame].size.width/2, NSMinXEdge);
			break;
		case 1:
			NSDivideRect ([imageView frame], &right, &left, [imageView frame].size.width/2, NSMinXEdge);
			break;
		case 2:
			NSDivideRect ([imageView frame], &left, &right, [imageView frame].size.width/2, NSMinXEdge);
			break;
		case 3:
			NSDivideRect ([imageView frame], &right, &left, [imageView frame].size.width/2, NSMinXEdge);
			break;
		default:
			NSDivideRect ([imageView frame], &left, &right, [imageView frame].size.width/2, NSMinXEdge);
			break;
	}
	BOOL leftBool = NSPointInRect([sender locationInWindow], left);
	if (fitScreenMode == 0) {
		if (![self getMouseAction:button mod:cMod mode:0 left:leftBool]) {
			[self getMouseAction:button mod:100 mode:0 left:leftBool];
		}
	} else if (fitScreenMode == 1) {
		if (![self getMouseAction:button mod:cMod mode:1 left:leftBool]) {
			if (![self getMouseAction:button mod:cMod mode:0 left:leftBool]) {
				if (![self getMouseAction:button mod:100 mode:1 left:leftBool]) {
					[self getMouseAction:button mod:100 mode:0 left:leftBool];
				}
			}
		}
	} else if (fitScreenMode == 2 || fitScreenMode == 3) {
		if (![self getMouseAction:button mod:cMod mode:2 left:leftBool]) {
			if (![self getMouseAction:button mod:cMod mode:0 left:leftBool]) {
				if (![self getMouseAction:button mod:100 mode:2 left:leftBool]) {
					[self getMouseAction:button mod:100 mode:0 left:leftBool];
				}
			}
		}
	}
}

//- (void)getMouseAction:(int)button mod:(int)cMod left:(BOOL)left

- (BOOL)getMouseAction:(int)button mod:(int)cMod mode:(int)mode left:(BOOL)left
{
    NSEnumerator *enu = nil;
	switch (mode) {
		case 0:
			enu = [mouseArray objectEnumerator];
			break;
		case 1:
			enu = [mouseArrayMode2 objectEnumerator];
			break;
		case 2:
			enu = [mouseArrayMode3 objectEnumerator];
			break;
		default:break;
	}
	id dic;	
	while (dic = [enu nextObject]) {
		if (button == [[dic objectForKey:@"button"] intValue] && cMod == [[dic objectForKey:@"modifier"] intValue]){
			int action = [[dic objectForKey:@"action"] intValue];
			if ([[dic objectForKey:@"switchAction"] boolValue] == YES && [self readFromLeft]) {
				switch (action) {
					case 6: action=7; break;
					case 7: action=6; break;
					case 8: action=9; break;
					case 9: action=8; break;
					case 10: action=11; break;
					case 11: action=10; break;
					case 12: action=13; break;
					case 13: action=12; break;
					case 14: action=15; break;
					case 15: action=14; break;
					case 19: action=20; break;
					case 20: action=19; break;
					case 33: action=34; break;
					case 34: action=33; break;
					case 44: action=45; break;
					case 45: action=44; break;
					default:
						break;
				}
			}
			if (![self hasBookOpen] && !IsWindowMouseAction(action)) return YES;
			switch (action) {
				case 0:
					//next/prevpage
					if (left) {
						[self nextPage];
					} else {
						//[lock lock];
						//[lock unlock];
						[self prevPage];
					}
						break;
				case 1:
					//halfnext/prevpage
					if (left) {
						[self halfNextPage];
					} else {
						[self halfprevPage];
					}
						break;
				case 2:
					//lastpage/toppage
					if (left) {
						[self goToLast];
					} else {
						[self goToTop];
					}
					break;
				case 3:
					//next/prevbookmark
					if (left) {
						[self nextBookmark];
					} else {
						[self backBookmark];
					}
						break;
				case 4:
					//next/prevfolder
					if (left) {
						[self nextFolder];
					} else {
						[self backFolder];
					}
						break;
				case 5:
					//skip/backskip
					if (left) {
						[self skipPages:[[dic objectForKey:@"value"] intValue]];
					} else {
						[self backSkipPages:[[dic objectForKey:@"value"] intValue]];
					}
					break;
				case 6:
					//nextpage
					[self nextPage];
					break;
				case 7:
					//prevpage 
					//[lock lock];
					//[lock unlock];
					[self prevPage];
					break;
				case 8:
					//halfnext
					[self halfNextPage];
					break;
				case 9:
					//halfprev
					[self halfprevPage];
					break;
				case 10:
					//lastpage
					[self goToLast];
					break;
				case 11:
					//toppage
					[self goToTop];
					break;
				case 12:
					//nextbookmark	
					[self nextBookmark];
					break;
				case 13:
					//prevbookmark
					[self backBookmark];		
					break;
				case 14:
					//nextfolder	
					[self nextFolder];
					break;
				case 15:
					//prevfolder
					[self backFolder];
					break;
				case 16:
					//add/removebookmark
					if ([self removeBookmark]) {
					} else {
						[self addBookmark];
					}
					break;
				case 17:
					//switchSingle
					[self switchSingle:nil];
					
					break;
				case 18:
					//shownumber
					numberSwitch = !numberSwitch;
					[defaults setBool:numberSwitch forKey:@"ShowNumber"];
					[self setPageTextField];
					//[imageView setNeedsDisplay];		
					break;
				case 19:
					//skip
					[self skipPages:[[dic objectForKey:@"value"] intValue]];
					break;
				case 20:
					//backskip
					[self backSkipPages:[[dic objectForKey:@"value"] intValue]];
					break;
				case 21:
					//origRight
					switch (readMode) {
						case 0:
							[self viewAtOriginalSizeFirst:self];
							break;
						case 1:
							[self viewAtOriginalSizeSecond:self];
							break;
						case 2:
							[self viewAtOriginalSizeFirst:self];
							break;
						case 3:
							[self viewAtOriginalSizeSecond:self];
							break;
						default:
							break;
					}
					break;
				case 22:
					//origLeft
					switch (readMode) {
						case 0:
							[self viewAtOriginalSizeSecond:self];
							break;
						case 1:
							[self viewAtOriginalSizeFirst:self];
							break;
						case 2:
							[self viewAtOriginalSizeSecond:self];
							break;
						case 3:
							[self viewAtOriginalSizeFirst:self];
							break;
						default:
							break;
					}
					
					break;
				case 23:
					//slideshow	
					[self slideshow:nil];
					[self setPageTextField];
					break;
				case 24:
					//showThumbnail
					if (secondImage) {
						int temp = nowPage;
						temp--;
						[thumController showThumbnail:temp];
					} else {
						[thumController showThumbnail:nowPage];
					}
					
					break;
				case 25:
					//changeReadMode 
					if (readMode == 0) {
						[self changeReadMode:1];
					} else if (readMode == 1) {
						[self changeReadMode:2];
					} else if (readMode == 2) {
						[self changeReadMode:3];
					} else if (readMode == 3) {
						[self changeReadMode:0];
					}
					break;
				case 26:
					//showPageBar
					if (pageBar) {
						pageBar = NO;
					} else {
						pageBar = YES;
					}
					[defaults setBool:pageBar forKey:@"ShowPageBar"];
					[imageView drawPageBar];
					break;
				case 27:
					//viewOriginalL/R
					if (left) {
						[self viewAtOriginalSizeSecond:self];
					} else {
						[self viewAtOriginalSizeFirst:self];
					}
					break;
				case 28:
					//showInFinderR
					switch (readMode) {
						case 0:
							[self showInFinderFirst:self];
							break;
						case 1:
							[self showInFinderSecond:self];
							break;
						case 2:
							[self showInFinderFirst:self];
							break;
						case 3:
							[self showInFinderSecond:self];
							break;
						default:
							break;
					}
					break;
				case 29:
					//showInFinderL
					switch (readMode) {
						case 0:
							[self showInFinderSecond:self];
							break;
						case 1:
							[self showInFinderFirst:self];
							break;
						case 2:
							[self showInFinderSecond:self];
							break;
						case 3:
							[self showInFinderFirst:self];
							break;
						default:
							break;
					}
					break;
				case 30:
					//showInFinderL/R
					if (left) {
						[self showInFinderSecond:self];
					} else {
						[self showInFinderFirst:self];
					}
					break;
				case 31:
					//PageUp
					[imageView scrollUp];
					break;
				case 32:
					//PageDown
					[imageView scrollDown];
					break;
				case 33:
					//PageUp + PrevPage
					if ([imageView prev] == YES) {
						//[lock lock];
						//[lock unlock];
						if (prevPageMode == 1) [imageView setStartFromEnd:YES];
						[self prevPage];
					}
					break;
				case 34:
					//PageDown + NextPage
					if ([imageView next] == YES) {
						[self nextPage];
					}
					break;
				case 35:
					//ScrollToTop
					[imageView scrollToTop];
					break;
				case 36:
					//ScrollToEnd
					[imageView scrollToLast];
					break;
				case 37:
					//ScrollUp
					[imageView scrollTo:NSMakePoint(0,-1*([[dic objectForKey:@"value"] intValue]))];
					break;
				case 38:
					//ScrollDown
					[imageView scrollTo:NSMakePoint(0,[[dic objectForKey:@"value"] intValue])];
					break;
				case 39:
					//ScrollLeft
					[imageView scrollTo:NSMakePoint([[dic objectForKey:@"value"] intValue],0)];
					break;
				case 40:
					//ScrollRight
					[imageView scrollTo:NSMakePoint((-1*[[dic objectForKey:@"value"] intValue]),0)];
					break;
				case 41:
					//DragScroll
					break;
				case 42:
					//PageUp/Down + Prev/NextPage
					if (left) {
						if ([imageView next] == YES) {
							[self nextPage];
						}
					} else {
						if ([imageView prev] == YES) {
							//[lock lock];
							//[lock unlock];
							if (prevPageMode == 1) [imageView setStartFromEnd:YES];
							[self prevPage];
						}
					}
					break;
				case 43:
					//loupe
					[imageView setLoupe];
					break;
				case 44:
					//nextSubFolder
					[self nextSubFolder];
					break;
				case 45:
					//prevSubFolder
					[self prevSubFolder];
					break;
				case 46:
					//next/prevSubFolder
					if (left) {
						[self nextSubFolder];
					} else {
						[self prevSubFolder];
					}
					break;
				case 47:
					//loupeRatePlus
					[defaults setFloat:[defaults floatForKey:@"LoupeRate"]+[[dic objectForKey:@"value"] floatValue] forKey:@"LoupeRate"];
					[imageView setLoupeRate];
					break;
				case 48:
					//loupeRateMinus
					if ([defaults floatForKey:@"LoupeRate"]-[[dic objectForKey:@"value"] floatValue]>1.0) {
						[defaults setFloat:[defaults floatForKey:@"LoupeRate"]-[[dic objectForKey:@"value"] floatValue] forKey:@"LoupeRate"];
					} else {
						[defaults setFloat:1.0 forKey:@"LoupeRate"];
					}
					[imageView setLoupeRate];
					break;
				
				case 49:
					//rotateRight
					[self rotateRight:nil];
					break;
				case 50:
					//rotateLeft
					[self rotateLeft:nil];
					break;
				case 51:
					//changeViewMode
					[self setPageTextField];
					switch (fitScreenMode) {
						case 0:
							[self fitToScreenWidth:nil];
							break;
						case 1:
							[self fitToScreenWidthDivide:nil];
							break;
						case 2:
							[self fitToScreen:nil];
							break;
						case 3:
							[self noScale:nil];
							break;
						default:
							break;
					}
					break;
				case 63:
					//enlargeViewMode
					[self setPageTextField];
					switch (fitScreenMode) {
						case 0:
							[self fitToScreenWidth:nil];
							break;
						case 1:
							[self fitToScreenWidthDivide:nil];
							break;
						case 3:
							[self noScale:nil];
							break;
						default:
							break;
					}
					break;
				case 64:
					//reduceViewMode
					[self setPageTextField];
					switch (fitScreenMode) {
						case 1:
							[self fitToScreen:nil];
							break;
						case 2:
							[self fitToScreenWidthDivide:nil];
							break;
						case 3:
							[self fitToScreenWidth:nil];
							break;
						default:
							break;
					}
					break;
				case 52:
					//trashRight
					[self trashRight];
					break;
				case 53:
					//trashLeft
					[self trashLeft];
					break;
				case 54:
					//trashL/R
					if (left) {
						[self trashLeft];
					} else {
						[self trashRight];
					}
					break;
				case 55:
					//rotateL/R
					if (left) {
						[self rotateLeft:nil];
					} else {
						[self rotateRight:nil];
					}
					break;
				case 56:
					//changeSortMode
					if ([imageLoader canSortByDate]) {
						switch (sortMode) {
							case 0:sortMode = 2;break;
							case 1:sortMode = 0;break;
							case 2:sortMode = 3;break;
							case 3:sortMode = 1;break;
							default:break;
						}
						[self setSortMode:sortMode page:0];
					} else {
						switch (sortMode) {
							case 0:sortMode = 1;break;
							case 1:sortMode = 0;break;
							case 2:sortMode = 0;break;
							case 3:sortMode = 0;break;
							default:break;
						}
						[self setSortMode:sortMode page:0];
					}					
					break;	
				case 57:
					//close
					/* The close drops a pending display and abandons the lookahead;
					   nothing to wait for first (KNOWN_ISSUES #46). */
					[[self window] performClose:self];
					break;	
				case 58:
					//random
					[self setSortMode:1 page:0];
					break;
				case 59:
					//ContextualMenu
					[NSMenu popUpContextMenu:[imageView menu] withEvent:[NSApp currentEvent] forView:imageView];
					break;
				case 60:
					//openTheLastPage
				{
					NSMenu *menu = [[[NSApp mainMenu] itemWithTitle:NSLocalizedString(@"File", @"")] submenu];
					NSMenuItem *item = [menu itemWithTitle:NSLocalizedString(@"Open the last page", @"")];
					if ([item isEnabled]) {
						[menu performActionForItemAtIndex:[menu indexOfItem:item]];
					}
				}
					break;
				case 61:
					//switchFullScreen
				{
					/* MW-2: see case 49. */
					[[self window] toggleFullScreen:self];
				}
					break;
				case 62:
					//minimizeWindow
				{
					NSMenu *menu = [[[NSApp mainMenu] itemWithTitle:NSLocalizedString(@"Window", @"")] submenu];
					NSMenuItem *item = [menu itemWithTitle:NSLocalizedString(@"Minimize", @"")];
					if ([item isEnabled]) {
						[menu performActionForItemAtIndex:[menu indexOfItem:item]];
					}
				}
					break;
				default:
					break;
			}
			return YES;
		}
	}
	return NO;
}

- (IBAction)contextAction:(id)sender
{
	if (![self hasBookOpen]) return;
	if (timerSwitch) {
		[timer invalidate];
		timer = nil;
		timerSwitch=NO;
	}
	if ([[sender title] isEqualToString:NSLocalizedString(@"Add Bookmark", @"")]){
		[self addBookmark];
	} else if ([[sender title] isEqualToString:NSLocalizedString(@"Remove Bookmark", @"")]){
		[self removeBookmark];
	} else if ([[sender title] isEqualToString:NSLocalizedString(@"Go to LastPage", @"")]){
		[self goToLast];
	} else if ([[sender title] isEqualToString:NSLocalizedString(@"Go to FirstPage", @"")]){
		[self goToFirst];
	} else if ([[sender title] isEqualToString:NSLocalizedString(@"Next Bookmark", @"")]){
		[self nextBookmark];	
	} else if ([[sender title] isEqualToString:NSLocalizedString(@"Previous Bookmark", @"")]){
		[self backBookmark];
	} else if ([[sender title] isEqualToString:NSLocalizedString(@"Previous Folder", @"")]){
		[self backFolder];
	} else if ([[sender title] isEqualToString:NSLocalizedString(@"Next Folder", @"")]){
		[self nextFolder];
	} else if ([[sender title] isEqualToString:NSLocalizedString(@"Show Thumbnail", @"")]){
		[self showThumbnail];
	} else if ([[sender title] isEqualToString:NSLocalizedString(@"View at Original Size", @"")]){
		if ([sender tag] == 0) {
			[self viewAtOriginalSizeFirst:self];
		} else {
			[self viewAtOriginalSizeSecond:self];
		}
	} else if ([[sender title] isEqualToString:NSLocalizedString(@"Show in Finder", @"")]){
		if ([sender tag] == 0) {
			[self showInFinderFirst:self];
		} else {
			[self showInFinderSecond:self];
		}
	} else if ([[sender title] isEqualToString:NSLocalizedString(@"Start Slideshow", @"")]) {
		[self slideshow:self];
	} else if ([[sender title] isEqualToString:NSLocalizedString(@"Stop Slideshow", @"")]) {
		[self setPageTextField];
		/*既に止まってる*/
	}
}
/*
- (IBAction)nextFolder:(id)sender{
}
- (IBAction)addBookmark:(id)sender{
}
- (IBAction)backFolder:(id)sender{
}
- (IBAction)nextBookmark:(id)sender{
}
- (IBAction)backBookmark:(id)sender{
}
- (IBAction)showThumbnail:(id)sender{
}*/


- (void)wheelAction:(NSEvent*)event
{
	if (![self hasBookOpen]) return;
	if (timerSwitch) {
		[timer invalidate];
		timer = nil;
		timerSwitch=NO;
	}

	threadStop = NO;
	if (fitScreenMode > 0) {
		switch (canScrollMode) {
			case 0:
				[imageView scrollTo:NSMakePoint(([event deltaX]*10),([event deltaY]*10*-1))];
				return;
			case 1:
				if (![imageView scrollTo:NSMakePoint(([event deltaX]*10),([event deltaY]*10*-1))]) {
					return;
				} else {
					if ([event deltaY] < 0) {
						[imageView next];
					} else if ([event deltaY] > 0) {
						[imageView prev];
					}
				}
				return;
			case 2:
				if (![imageView scrollTo:NSMakePoint(([event deltaX]*10),([event deltaY]*10*-1))]) {
					return;
				} else {
					if ([event deltaY] < 0) {
						if (![imageView next]) {
							return;
						} else {
							[self nextPage];
						}
					} else if ([event deltaY] > 0) {
						if (![imageView prev]) {
							return;
						} else {
							if (prevPageMode == 1) [imageView setStartFromEnd:YES];
							[self prevPage];
						}
					}
				}
				return;
			case 3:
				break;
			default:break;
		}
	}
	
	if (wheelSensitivity == 0.0) {
		wheelDeltaAccum = 0.0;
		return;
	}

	// Reset accumulator on momentum-phase events to avoid unintended page turns
	// after the user stops physically scrolling.
	if ([event momentumPhase] != NSEventPhaseNone) {
		wheelDeltaAccum = 0.0;
		return;
	}

	// Accumulate deltaY so that precision-scroll devices (e.g. MX Anywhere 3S)
	// that send small fractional values per notch are handled correctly.
	wheelDeltaAccum += [event deltaY];

	if (wheelDeltaAccum <= -wheelSensitivity) {
		wheelDeltaAccum = 0.0;
		if (wheelUpTimer) {
			return;
		}
		wheelDownTimer = [NSTimer scheduledTimerWithTimeInterval:0.0 target:self
														selector:@selector(wheelDown)
														userInfo:NULL
														 repeats:NO];
	} else if (wheelDeltaAccum >= wheelSensitivity) {
		wheelDeltaAccum = 0.0;
		if (wheelDownTimer) {
			return;
		}
		wheelUpTimer = [NSTimer scheduledTimerWithTimeInterval:0.0 target:self
													  selector:@selector(wheelUp)
													  userInfo:NULL
													   repeats:NO];
	}
}


#pragma mark inAction

- (IBAction)showInFinderSecond:(id)sender
{
	if (![self hasShownPage]) return;	/* nothing on screen yet (KNOWN_ISSUES #46) */
	int i = nowPage;
	i--;
	NSString *currentFilePath = [imageLoader itemPathAtIndex:i];
	[[NSWorkspace sharedWorkspace] selectFile:currentFilePath inFileViewerRootedAtPath:@""];
	/*
	if ([[NSWorkspace sharedWorkspace] isFilePackageAtPath:[currentFilePath stringByDeletingLastPathComponent]]) {
		[[NSWorkspace sharedWorkspace] selectFile:[currentFilePath stringByDeletingLastPathComponent] inFileViewerRootedAtPath:nil];
	} else {
		[[NSWorkspace sharedWorkspace] selectFile:currentFilePath inFileViewerRootedAtPath:nil];
	}*/
}

- (IBAction)showInFinderFirst:(id)sender
{
	if (![self hasShownPage]) return;	/* nothing on screen yet (KNOWN_ISSUES #46) */
	int i = nowPage;
	i--;
	if (secondImage) i--;
	NSString *currentFilePath = [imageLoader itemPathAtIndex:i];
	[[NSWorkspace sharedWorkspace] selectFile:currentFilePath inFileViewerRootedAtPath:@""];
	/*
	if ([[NSWorkspace sharedWorkspace] isFilePackageAtPath:[currentFilePath stringByDeletingLastPathComponent]]) {
		[[NSWorkspace sharedWorkspace] selectFile:[currentFilePath stringByDeletingLastPathComponent] inFileViewerRootedAtPath:nil];
	} else {
		[[NSWorkspace sharedWorkspace] selectFile:currentFilePath inFileViewerRootedAtPath:nil];
	}*/
}

- (IBAction)viewAtOriginalSizeFirst:(id)sender
{
	if (![self hasShownPage]) return;	/* nothing on screen yet (KNOWN_ISSUES #46) */
	if (timerSwitch) {
		[timer invalidate];
		timer = nil;
		timerSwitch=NO;
	}
	id scrollView = [fullImageView enclosingScrollView];
	
	[fullImageView setImage:nil];
	[fullImageView setImageScaling:NSScaleNone];
	int i;
	if (!secondImage) {
		i = nowPage - 1;
		[fullImageView setImage:firstImage];
	} else {
		i = nowPage - 2;
		[fullImageView setImage:firstImage];
	}
	
    NSSize theScrollViewSize = [NSScrollView
                                frameSizeForContentSize:[fullImageView frame].size
                                horizontalScrollerClass:nil
                                  verticalScrollerClass:nil
                                             borderType:[scrollView borderType]
                                            controlSize:NSRegularControlSize
                                          scrollerStyle:[scrollView scrollerStyle]
    ];
	[fullImagePanel setContentSize:theScrollViewSize];
	
	NSRect theScrollViewRect;
	theScrollViewRect.origin = NSZeroPoint;
	theScrollViewRect.size = theScrollViewSize;
	NSRect theWindowMaxRect = [ NSWindow
				 frameRectForContentRect:theScrollViewRect
							   styleMask:[ fullImagePanel styleMask]
		];
	NSScreen *panelScreen = [fullImagePanel screen] ? [fullImagePanel screen] : [NSScreen mainScreen];
	NSRect fullscreenRect = [panelScreen frame];
	if (theWindowMaxRect.size.width > fullscreenRect.size.width) {
		theWindowMaxRect.size.width = fullscreenRect.size.width;
	}
	[fullImagePanel setMaxSize:theWindowMaxRect.size];
	
	[fullImagePanel setTitle:[NSString stringWithFormat:@"original %@",[[completeMutableArray objectAtIndex:i] lastPathComponent]]];
	
	if (readMode == 0 || readMode == 2) {
		[fullImagePanel setFrameOrigin:NSMakePoint(fullscreenRect.size.width - theWindowMaxRect.size.width,0)];
	} else {
		[fullImagePanel setFrameOrigin:NSMakePoint(0,5)];
	}
	
	[fullImagePanel makeKeyAndOrderFront:self];
}

- (IBAction)viewAtOriginalSizeSecond:(id)sender
{
	if (![self hasShownPage]) return;	/* nothing on screen yet (KNOWN_ISSUES #46) */
	if (timerSwitch) {
		[timer invalidate];
		timer = nil;
		timerSwitch=NO;
	}
	id scrollView = [fullImageView enclosingScrollView];
	[fullImageView setImage:nil];
	[fullImageView setImageScaling:NSScaleNone];
	int i;
	if (!secondImage) {
		i = nowPage - 1;
		[fullImageView setImage:firstImage];
	} else {
		i = nowPage - 1;
		[fullImageView setImage:secondImage];
	}
    NSSize theScrollViewSize = [NSScrollView
                                frameSizeForContentSize:[fullImageView frame].size
                                horizontalScrollerClass:nil
                                  verticalScrollerClass:nil
                                             borderType:[scrollView borderType]
                                            controlSize:NSRegularControlSize
                                          scrollerStyle:[scrollView scrollerStyle]
    ];
	[fullImagePanel setContentSize:theScrollViewSize];
	NSRect theScrollViewRect;
	theScrollViewRect.origin = NSZeroPoint;
	theScrollViewRect.size = theScrollViewSize;
	NSRect theWindowMaxRect = [ NSWindow
                     frameRectForContentRect:theScrollViewRect
								   styleMask:[ fullImagePanel styleMask]
		];
	NSScreen *panelScreen = [fullImagePanel screen] ? [fullImagePanel screen] : [NSScreen mainScreen];
	NSRect fullscreenRect = [panelScreen frame];
	if (theWindowMaxRect.size.width > fullscreenRect.size.width) {
		theWindowMaxRect.size.width = fullscreenRect.size.width;
	}
	[fullImagePanel setMaxSize:theWindowMaxRect.size];
	
	[fullImagePanel setTitle:[NSString stringWithFormat:@"original %@",[[completeMutableArray objectAtIndex:i] lastPathComponent]]];
	
	if (readMode == 0 || readMode == 2) {
		[fullImagePanel setFrameOrigin:NSMakePoint(0,5)];
	} else {
		[fullImagePanel setFrameOrigin:NSMakePoint(fullscreenRect.size.width - theWindowMaxRect.size.width,0)];
	}
	
	[fullImagePanel makeKeyAndOrderFront:self];
}




- (void)changeReadMode:(int)mode
{
	if (readMode == mode) {
		return;
	}
	/* KNOWN_ISSUES #46: the mode changes now; the shown pages are laid out
	   again by a display request (-redisplayShownPagesBody), which may have
	   to wait for the next page. */
	readMode = mode;
	if (![self hasShownPage]) {
		return;
	}
	
	if (rememberBookSettings) {
		[currentBookSetting setObject:[NSNumber numberWithInt:mode] forKey:@"readMode"];
	}
	
	[self viewSet];
	[self requestDisplay:CODisplayRedisplay argument:0 after:nil];
	
	
	if (readMode == 1) {
		[imageView setInfoString:[NSString stringWithFormat:@"read:left to right"]];
	} else if (readMode == 2) {
		[imageView setInfoString:[NSString stringWithFormat:@"read:right to left(single)"]];
	} else if (readMode == 3) {
		[imageView setInfoString:[NSString stringWithFormat:@"read:left to right(single)"]];
	} else if (readMode == 0) {
		[imageView setInfoString:[NSString stringWithFormat:@"read:right to left"]];
	}
}
- (void)setSortMode:(int)mode page:(int)p
{
	/* Re-sorting the page list the loader reads from (code review M5): no
	   thread may be inside the loader while it changes. KNOWN_ISSUES #46:
	   instead of waiting for the lookahead on the main thread, the sort runs
	   once the book's lane and the lookahead are out of the loader
	   (-sortPagesWhenLoaderIsFree:page:), at once when they already are. */
	//if (sortMode != mode) {
	sortMode = mode;
	[self sortPagesWhenLoaderIsFree:mode page:p];
	//}
}

/* The re-sort itself (was the body of -setSortMode:page:); called with the
   book's decodeLock held, or without a book lane. The go-to that follows a
   sort with a page is made by the caller. */
- (void)sortPageList:(int)mode remember:(BOOL)remember
{
	[completeMutableArray sortUsingSelector:@selector(finderCompareS:)];
	switch (mode) {
		case 0:
			//name
			//[completeMutableArray sortUsingSelector:@selector(finderCompareS:)];
			[imageView setInfoString:[NSString stringWithFormat:@"sort:name"]];
			break;
		case 1:
			//random
			[completeMutableArray sortUsingSelector:@selector(randomCompare:)];
			[imageView setInfoString:[NSString stringWithFormat:@"sort:shuffle"]];
			break;
		case 2:
			//creation
			if ([imageLoader canSortByDate]) {
				[completeMutableArray sortUsingSelector:@selector(fileCreationDateCompare:)];
				[imageView setInfoString:[NSString stringWithFormat:@"sort:Creation Date"]];
			}
			break;
		case 3:
			//modification
			if ([imageLoader canSortByDate]) {
				[completeMutableArray sortUsingSelector:@selector(fileModificationDateCompare:)];
				[imageView setInfoString:[NSString stringWithFormat:@"sort:Modification Date"]];
			}
			break;
		default:
			//[completeMutableArray sortUsingSelector:@selector(finderCompareS:)];
			break;
	}
	if (rememberBookSettings && remember) {
		[currentBookSetting setObject:[NSNumber numberWithInt:mode] forKey:@"sortMode"];
	}
}



/* KNOWN_ISSUES #46: the navigation entry points request a display; each
   body below is the legacy code, run at the request's commit. */
- (void)prevPage
{
	[self requestDisplay:CODisplayPrev argument:0 after:nil];
}

- (void)halfprevPage
{
	[self requestDisplay:CODisplayHalfPrev argument:0 after:nil];
}

- (void)nextPage
{
	[self requestDisplay:CODisplayNext argument:0 after:nil];
}

- (void)halfNextPage
{
	[self requestDisplay:CODisplayHalfNext argument:0 after:nil];
}

/* Key 2, mouse actions 1 and 8: from a spread, its second page becomes the
   first of the next display. */
- (void)halfNextPageBody
{
	if (nowPage < [completeMutableArray count]) {
		if (secondImage){
			nowPage--;
			[imageMutableArray insertObject:[self loadImage:nowPage] atIndex:0];
			//[imageMutableArray insertObject:secondImage atIndex:0];
		}
	}
	[self showPagesFromList];
}

/* Key 5, mouse action 11 and mouse action 2's right half: to the first page,
   unless it is already shown. */
- (void)goToTop
{
	[self requestDisplay:CODisplayTop argument:0 after:nil];
}

- (void)skipPages:(int)value
{
	[self requestDisplay:CODisplaySkip argument:value after:nil];
}

- (void)backSkipPages:(int)value
{
	[self requestDisplay:CODisplayBackSkip argument:value after:nil];
}

/* Key 13, mouse action 19 and mouse action 5's left half. The start is the
   legacy arithmetic, clamped at 0 as well (CODisplaySkipStart). */
- (void)skipPagesBody:(int)value
{
	[imageMutableArray removeAllObjects];
	nowPage = CODisplaySkipStart(nowPage, (int)[completeMutableArray count], value);
	[self lookahead];
	if ([imageMutableArray count] > 1) {
		if ([self isSmallImage:[imageMutableArray objectAtIndex:0] page:nowPage+1] == NO) {
			[imageMutableArray removeObjectAtIndex:0];
			nowPage++;
		} else if ([self isSmallImage:[imageMutableArray objectAtIndex:1] page:nowPage+2] == NO) {
			[imageMutableArray removeObjectAtIndex:0];
			nowPage++;
		}
	}
	[self showPagesFromList];
}

/* Key 14, mouse action 20 and mouse action 5's right half. */
- (void)backSkipPagesBody:(int)value
{
	[imageMutableArray removeAllObjects];
	nowPage = CODisplayBackSkipStart(nowPage, value);
	[self lookahead];
	[self showPagesFromList];
}

/* The body of -prevPage, run at its request's commit (KNOWN_ISSUES #46):
   the legacy code, without its waits for the lookahead (the request has
   abandoned it) — every page it reads is in readyPageImages. */
- (void)prevPageBody
{
	if (readMode > 1) {
		if (nowPage < 2) {
			if (loopCheck == 0) {
				[imageMutableArray removeAllObjects];
				nowPage = (int)[completeMutableArray count];
				nowPage --;
				[self lookahead];
			} else if (loopCheck == 1) {
				[self backFolder];
				return;
			} else if (loopCheck == 2) {
				[self backFolderLast];
				return;
			} else {
				return;
			}
		} else {
			[imageMutableArray removeAllObjects];
			nowPage -= 2;
			[self lookahead];
		}
		[self showPagesFromList];
	} else {
		if (!secondImage) {
			if (nowPage < 2) {
				if (loopCheck == 0) {
					[imageMutableArray removeAllObjects];
					nowPage = [self lastSpreadStartPage];
					[self lookahead];
					if ([imageMutableArray count] > 1) {
						if ([self isSmallImage:[imageMutableArray objectAtIndex:0] page:nowPage+1] == NO) {
							[imageMutableArray removeObjectAtIndex:0];
							nowPage++;
						} else if ([self isSmallImage:[imageMutableArray objectAtIndex:1] page:nowPage+2] == NO) {
							[imageMutableArray removeObjectAtIndex:0];
							nowPage++;
						}
					}
					[self showPagesFromList];
					return;
				} else if (loopCheck == 1) {
					[self backFolder];
					return;
				} else if (loopCheck == 2) {
					[self backFolderLast];
					return;
				} else {
					return;
				}
			} else if (nowPage == 2) {
				nowPage = 0;
				[imageMutableArray insertObject:[self loadImage:nowPage] atIndex:0];
				//[imageMutableArray insertObject:[imageView image] atIndex:1];
				//[imageMutableArray insertObject:[self loadImage:nowPage+1] atIndex:1];
				nowPage += 2;
				[imageMutableArray insertObject:[self loadImage:nowPage-1] atIndex:1];
				nowPage -= 2;
			} else if (nowPage > 2) {
				[imageMutableArray removeAllObjects];
				nowPage -= 3;
				[self lookahead];
				//NSLog(@"1 %@",imageMutableArray);
				//[imageMutableArray addObject:[imageView image]];
				//[imageMutableArray addObject:[self loadImage:nowPage+2]];
				nowPage += 3;
				[imageMutableArray addObject:[self loadImage:nowPage-1]];
				nowPage -= 3;
				//NSLog(@"2 %@",imageMutableArray);
				if ([self isSmallImage:[imageMutableArray objectAtIndex:0] page:nowPage+1] == NO){
					nowPage++;
					[imageMutableArray removeObjectAtIndex:0];
				} else if ([self isSmallImage:[imageMutableArray objectAtIndex:1] page:nowPage+2] == NO) {
					nowPage++;
					[imageMutableArray removeObjectAtIndex:0];
				}
				[self showPagesFromList];
				return;
			}
		} else {
			if (nowPage < 3) {
				if (loopCheck == 0) {
					[imageMutableArray removeAllObjects];
					nowPage = [self lastSpreadStartPage];
					[self lookahead];
					if ([imageMutableArray count] > 1) {
						if ([self isSmallImage:[imageMutableArray objectAtIndex:0] page:nowPage+1] == NO) {
							[imageMutableArray removeObjectAtIndex:0];
							nowPage++;
						} else if ([self isSmallImage:[imageMutableArray objectAtIndex:1] page:nowPage+2] == NO) {
							[imageMutableArray removeObjectAtIndex:0];
							nowPage++;
						}
					}
					[self showPagesFromList];
					return;
				} else if (loopCheck == 1) {
					[self backFolder];
					return;
				} else if (loopCheck == 2) {
					[self backFolderLast];
					return;
				} else {
					return;
				}
			} else if (nowPage < 4) {
				[imageMutableArray removeAllObjects];
				nowPage -= 3;
				[imageMutableArray addObject:[self loadImage:nowPage]];
				//[imageMutableArray addObject:firstImage];
				//[imageMutableArray addObject:secondImage];
				//[imageMutableArray addObject:[self loadImage:nowPage+1]];
				//[imageMutableArray addObject:[self loadImage:nowPage+2]];
				nowPage += 3;
				[imageMutableArray addObject:[self loadImage:nowPage-2]];
				[imageMutableArray addObject:[self loadImage:nowPage-1]];
				nowPage -= 3;
				[self showPagesFromList];
				return;
			} else if (nowPage > 3) {
				[imageMutableArray removeAllObjects];
				nowPage -= 4;
				[self lookahead];
				//[imageMutableArray addObject:firstImage];
				//[imageMutableArray addObject:secondImage];
				//[imageMutableArray addObject:[self loadImage:nowPage+2]];
				//[imageMutableArray addObject:[self loadImage:nowPage+3]];
				nowPage += 4;
				[imageMutableArray addObject:[self loadImage:nowPage-2]];
				[imageMutableArray addObject:[self loadImage:nowPage-1]];
				nowPage -= 4;
				
				if ([self isSmallImage:[imageMutableArray objectAtIndex:0] page:nowPage+1] == NO){
					nowPage++;
					[imageMutableArray removeObjectAtIndex:0];
				} else if ([self isSmallImage:[imageMutableArray objectAtIndex:1] page:nowPage+2] == NO) {
					nowPage++;
					[imageMutableArray removeObjectAtIndex:0];
				}
				[self showPagesFromList];
				return;
			}
		}
		[self showPagesFromList];
	}
}

/* The body of -halfprevPage (see -prevPageBody). */
- (void)halfprevPageBody
{
	if (readMode > 1) {
		if (nowPage <2) {
			if (loopCheck == 0) {
				[imageMutableArray removeAllObjects];
				nowPage = (int)[completeMutableArray count];
				nowPage --;
				[self lookahead];
			} else if (loopCheck == 1) {
				[self backFolder];
				return;
			} else if (loopCheck == 2) {
				[self backFolderLast];
				return;
			} else {
				return;
			}
		} else {
			[imageMutableArray removeAllObjects];
			nowPage -= 2;
			[self lookahead];
		}
		[self showPagesFromList];
	} else {
		if (!secondImage) {
			if (nowPage <2) {
				if (loopCheck == 0) {
					[imageMutableArray removeAllObjects];
					nowPage = (int)[completeMutableArray count];
					nowPage --;
					[self lookahead];
				} else if (loopCheck == 1) {
					[self backFolder];
					return;
				} else if (loopCheck == 2) {
					[self backFolderLast];
					return;
				} else {
					return;
				}
			} else if (nowPage == 2) {
				nowPage = 0;
				[imageMutableArray insertObject:[self loadImage:nowPage] atIndex:0];
				//[imageMutableArray insertObject:[imageView image] atIndex:1];
				//[imageMutableArray insertObject:[self loadImage:nowPage+1] atIndex:1];
				nowPage += 2;
				[imageMutableArray insertObject:[self loadImage:nowPage-1] atIndex:1];
				nowPage -= 2;
			} else if (nowPage > 2) {
				[imageMutableArray removeAllObjects];
				nowPage -= 3;
				[self lookahead];
				//[imageMutableArray addObject:[imageView image]];
				//[imageMutableArray addObject:[self loadImage:nowPage+2]];
				nowPage += 3;
				[imageMutableArray addObject:[self loadImage:nowPage-1]];
				nowPage -= 3;
				if ([self isSmallImage:[imageMutableArray objectAtIndex:0] page:nowPage+1] == NO){
					nowPage++;
					[imageMutableArray removeObjectAtIndex:0];
				} else if ([self isSmallImage:[imageMutableArray objectAtIndex:1] page:nowPage+2] == NO) {
					nowPage++;
					[imageMutableArray removeObjectAtIndex:0];
				} else {
				}
				
			}
		} else {
			if (nowPage < 3) {
				if (loopCheck == 0) {
					[imageMutableArray removeAllObjects];
					nowPage = [self lastSpreadStartPage];
					[self lookahead];
					if ([imageMutableArray count] > 1) {
						if ([self isSmallImage:[imageMutableArray objectAtIndex:0] page:nowPage+1] == NO) {
							[imageMutableArray removeObjectAtIndex:0];
							nowPage++;
						} else if ([self isSmallImage:[imageMutableArray objectAtIndex:1] page:nowPage+2] == NO) {
							[imageMutableArray removeObjectAtIndex:0];
							nowPage++;
						}
					}
				} else if (loopCheck == 1) {
					[self backFolder];
					return;
				} else if (loopCheck == 2) {
					[self backFolderLast];
					return;
				} else {
					return;
				}
			} else if (nowPage > 2) {
				[imageMutableArray removeAllObjects];
				nowPage -= 3;
				
				[imageMutableArray addObject:[self loadImage:nowPage]];
				//[imageMutableArray addObject:firstImage];
				//[imageMutableArray addObject:[self loadImage:nowPage+1]];
				nowPage += 3;
				[imageMutableArray addObject:[self loadImage:nowPage-2]];
				nowPage -= 3;
			}
		}	
		[self showPagesFromList];
	}
}

/* Where a lookahead for the book's last spread starts: two pages before the
   end, so the spread check can decide between one and two pages. A one-page
   book has no page before its last; count-2 would be -1 and the lookahead
   would read page -1 (code review L5). Callers test for two loaded pages
   before looking at the second. */
-(int)lastSpreadStartPage
{
	int page = (int)[completeMutableArray count] - 2;
	return page < 0 ? 0 : page;
}

-(void)goToLast
{
	[self requestDisplay:CODisplayLast argument:0 after:nil];
}

/* The body of -goToLast (see -prevPageBody). */
-(void)goToLastBody
{
	if (nowPage < [completeMutableArray count]) {
		[imageMutableArray removeAllObjects];
		nowPage = (int)[completeMutableArray count];
		if (readMode > 1) {
			nowPage--;
			[self lookahead];
		} else {
			nowPage = [self lastSpreadStartPage];
			[self lookahead];
			if ([imageMutableArray count] > 1) {
				if ([self isSmallImage:[imageMutableArray objectAtIndex:0] page:nowPage+1] == NO) {
					[imageMutableArray removeObjectAtIndex:0];
					nowPage++;
				} else if ([self isSmallImage:[imageMutableArray objectAtIndex:1] page:nowPage+2] == NO) {
					[imageMutableArray removeObjectAtIndex:0];
					nowPage++;
				}
			}
		}
		[self showPagesFromList];
	}
}
-(void)goToFirst
{
	[self requestDisplay:CODisplayFirst argument:0 after:nil];
}

/* The body of -goToFirst and of the top-page actions. */
-(void)goToFirstBody
{
	/* No lookahead may be adding pages while the list changes below
	   (code review M5). A jump, as in -goTo:array: (B2). */
	[self abandonLookahead];
	[imageMutableArray removeAllObjects];
	nowPage = 0;
	[self showPagesFromList];
}
-(void)showThumbnail
{	
	if (secondImage) {
		int temp = nowPage;
		temp--;
		[thumController showThumbnail:temp];
	} else {
		[thumController showThumbnail:nowPage];
	}
}

/* The next (or previous) bookmark after (before) the first page on screen,
   and its name, or NO. */
-(BOOL)bookmarkStepping:(BOOL)forward page:(int *)page title:(NSString **)title
{
	NSMutableArray *oldArray = [NSMutableArray array];
	int i;
	for (i = 0; i < [bookmarkArray count]; i++) {
		NSNumber *number = [NSNumber numberWithInt:[ [[bookmarkArray objectAtIndex:i] objectForKey:@"page"] intValue]];
		[oldArray addObject:number];
	}
	NSArray *newArray = [oldArray sortedArrayUsingSelector:@selector(compare:)];
	int iSS = nowPage;
	if (secondImage) {
		iSS--;
	}
	int found = 0;
	BOOL hit = NO;
	if (forward) {
		for (i = 0; i<[newArray count]; i++) {
			int iS = [[newArray objectAtIndex:i] intValue];
			if (iS > iSS) {
				found = iS;
				hit = YES;
				break;
			}
		}
	} else {
		for (i = (int)[newArray count]-1; i >= 0; i--) {
			int iS = [[newArray objectAtIndex:i] intValue];
			if (iS < iSS) {
				found = iS;
				hit = YES;
				break;
			}
		}
	}
	if (!hit) return NO;
	NSEnumerator *enumerator = [bookmarkArray objectEnumerator];
	id object;
	NSString *bookmarkTitle = nil;
	while (object = [enumerator nextObject]) {
		if ([[object objectForKey:@"page"] intValue] == found){
			bookmarkTitle = [object objectForKey:@"name"];
			break;
		}
	}
	*page = found;
	*title = bookmarkTitle;
	return YES;
}

/* KNOWN_ISSUES #46: a go-to request to the bookmarked page, whose name is
   shown once the page is. It used to read that page and the next one on the
   main thread first; the go-to reads the page and, in a spread, the next
   one only if it is shown with it — and clamps a bookmark past the end of
   the book to its last page. */
-(void)goToBookmarkStepping:(BOOL)forward
{
	/* Steps from the page on screen: none yet, nothing to step from. */
	if (![self hasShownPage]) return;
	int iS;
	NSString *bookmarkTitle;
	if (![self bookmarkStepping:forward page:&iS title:&bookmarkTitle]) return;
	NSString *title = [[bookmarkTitle retain] autorelease];
	[self requestDisplay:CODisplayGoTo argument:iS - 1 after:^{
		[imageView setInfoString:title];
	}];
}

-(void)nextBookmark
{
	[self goToBookmarkStepping:YES];
}

-(void)backBookmark
{
	[self goToBookmarkStepping:NO];
}

/* The "Open from same folder" item after (or before) the current book's,
   skipping disabled items and wrapping at the ends, with the check mark
   moved onto it; nil when the current book is not in the list. The submenu
   is built lazily (#5b), so it is refreshed for this window's book first —
   walking it as it stood could find nothing, or another folder's items
   targeted at another window (code review M4). */
-(id)sameFolderItemStepping:(BOOL)forward
{
	NSArray *items = [[self refreshSameFolderMenu] itemArray];
	if ([items count] == 0) return nil;
	NSEnumerator *enumerator = forward ? [items objectEnumerator] : [items reverseObjectEnumerator];
	id object;
	while (object = [enumerator nextObject]) {
		if ([object state] == NSOnState){
			[object setState:NSOffState];
			while (object = [enumerator nextObject]) {
				if ([object isEnabled]) {
					break;
				}
			}
			if (!object) {
				object = forward ? [items objectAtIndex:0] : [items lastObject];
			}
			[object setState:NSOnState];
			return object;
		}
	}
	return nil;
}

-(void)nextFolder
{
	id object = [self sameFolderItemStepping:YES];
	if (object) [self openFromSameDir:object];
}

-(void)backFolder
{
	id object = [self sameFolderItemStepping:NO];
	if (object) [self openFromSameDir:object];
}

-(void)backFolderLast
{
	id object = [self sameFolderItemStepping:NO];
	if (object) [self openFromSameDir:object last:YES];
}

- (void)nextSubFolder
{
	/* Steps from the page on screen (KNOWN_ISSUES #46: none yet, nothing to
	   step from). */
	if (![self hasShownPage]) return;
	int nextNow = [imageLoader nextFolder:nowPage];
	[self goTo:nextNow array:nil];
}

- (void)prevSubFolder
{
	if (![self hasShownPage]) return;	/* see -nextSubFolder */
	int prevNow;
	if (secondImage) {
		prevNow = [imageLoader prevFolder:nowPage-1];
	} else {
		prevNow = [imageLoader prevFolder:nowPage];
	}
	[self goTo:prevNow array:nil];
}

/* The original-size panel's next/previous. KNOWN_ISSUES #46: a page turn is
   a display request, so the panel follows the pages once it has committed
   (`after`). */
- (void)showOriginalOfShownPage:(BOOL)second
{
	int i;
	if (second && secondImage) {
		[fullImageView setImage:secondImage];
		i = nowPage - 1;
	} else {
		[fullImageView setImage:firstImage];
		i = secondImage ? nowPage - 2 : nowPage - 1;
	}
	if (i >= 0 && i < (int)[completeMutableArray count]) {
		[fullImagePanel setTitle:[NSString stringWithFormat:@"original %@",[[completeMutableArray objectAtIndex:i] lastPathComponent]]];
	}
}

-(void)nextOriginal
{
	if (![self hasShownPage]) return;
	if ([fullImageView image] == secondImage || !secondImage) {
		[self requestDisplay:CODisplayNext argument:0 after:^{
			[self showOriginalOfShownPage:NO];
		}];
	} else {
		[self showOriginalOfShownPage:YES];
	}
}

-(void)prevOriginal
{
	if (![self hasShownPage]) return;
	if ([fullImageView image] == secondImage && secondImage) {
		[self showOriginalOfShownPage:NO];
	} else {
		[self requestDisplay:CODisplayPrev argument:0 after:^{
			[self showOriginalOfShownPage:YES];
		}];
	}
}



- (void)wheelUp
{
	[self prevPage];
	wheelUpTimer = nil;
}
- (void)wheelDown
{
	[self nextPage];
	wheelDownTimer = nil;
}

/* A jump. KNOWN_ISSUES #46: a display request; `array` was already unused. */
- (void)goTo:(int)page array:(NSArray*)array
{
	[self requestDisplay:CODisplayGoTo argument:page after:nil];
}

/* The body of a go-to. A jump changes only nowPage and the list, so it
   abandons the lookahead rather than waiting for the page it is reading,
   and leaves the list empty: -showPagesFromList takes only the page or
   pages it shows, and the lookahead it starts reads on from there (B2). */
- (void)goToPageBody:(int)page
{
	[self abandonLookahead];
	nowPage = page;
	if (nowPage < 0) {
		nowPage = 0;
	} else if (nowPage >= [completeMutableArray count]) {
		nowPage = (int)[completeMutableArray count]-1;
	}
	[imageMutableArray removeAllObjects];
	[self showPagesFromList];
}

- (void)addBookmark
{
	/* Nothing on screen yet (KNOWN_ISSUES #46): no page to mark. */
	if (![self hasShownPage]) return;
	if (!secondImage) {
		[self addBookmarkWithPage:nowPage];
	} else {
		[self addBookmarkWithPage:nowPage-1];
	}
	[imageView setInfoString:@"Add bookmark"];
}
- (BOOL)isBookmarkedPage:(int)page
{
	id bookmark;
	int index;
	for (index=0; index<[bookmarkArray count]; index++) {
		bookmark = [bookmarkArray objectAtIndex:index];
		if ([[bookmark objectForKey:@"page"] intValue] == page) {
			return YES;
		}
	}
	return NO;
}
- (BOOL)removeBookmark
{
	BOOL b = NO;
	if (![self hasShownPage]) return NO;	/* see -addBookmark */
	if (!secondImage) {
		b = [self removeBookmarkWithPage:nowPage];
	} else {
		b = [self removeBookmarkWithPage:nowPage-1];
		if (!b) {
			b = [self removeBookmarkWithPage:nowPage];
		}
	}
	if (b) [imageView setInfoString:[NSString stringWithFormat:@"Remove bookmark"]];
	return b;
}

- (void)goToPar:(float)par
{
	if (![self hasBookOpen]) return;
	/* A jump, as in -goTo:array: (B2), and a display request like it
	   (KNOWN_ISSUES #46). */
	float temp = (int)[completeMutableArray count]*par;
	int page = (int)temp;
	if (page < 0) {
		page = 0;
	} else if (page >= [completeMutableArray count]) {
		/* par can reach 1 or more: a page-bar click in its last 2 px (outside
		   the inset rect the fraction is measured on), or a 100% go-to.
		   nowPage == count is "past the end" to -showPagesFromList, which
		   would wrap or open the next book (code review M11). */
		page = (int)[completeMutableArray count]-1;
	}
	[self requestDisplay:CODisplayGoTo argument:page after:nil];
}


- (IBAction)switchSingle:(id)sender
{
	if (![self hasBookOpen]) return;
	/* KNOWN_ISSUES #46: a display request — pairing a single page with the
	   next one may have to wait for that page. */
	[self requestDisplay:CODisplaySwitchSingle argument:0 after:nil];
}

/* The body of -switchSingle:. The pages a lookahead added are moved below;
   the request has abandoned the lookahead, and the next page the spread
   branch needs is on hand (code review M5, KNOWN_ISSUES #46). */
- (void)switchSingleBody
{
	if (nowPage > (int)[completeMutableArray count]) return;
	NSString *string;
	if (secondImage) {
		[imageMutableArray insertObject:secondImage atIndex:0];
		[secondImage release];
		secondImage = nil;
		[imageView setImage:firstImage];
		/*
		NSImage* temp = firstImage;
		firstImage = nil;
		[imageView setImage:temp];
		[temp release];*/
		nowPage--;
		if ([marksArray containsObject:[NSString stringWithFormat:@"%i",nowPage]]) {
			[marksArray removeObject:[NSString stringWithFormat:@"%i",nowPage]];
		}
		if ([marksArray containsObject:[NSString stringWithFormat:@"%i-%i",nowPage-1,nowPage]]) {
			[marksArray removeObject:[NSString stringWithFormat:@"%i-%i",nowPage-1,nowPage]];
		}
		if ([marksArray containsObject:[NSString stringWithFormat:@"%i-%i",nowPage,nowPage+1]]) {
			[marksArray removeObject:[NSString stringWithFormat:@"%i-%i",nowPage,nowPage+1]];
		}
		string = [NSString stringWithFormat:@"%i",nowPage];
		[marksArray addObject:string];
		
		/* Counted and generation-tagged like every other detach; these two
		   used to bypass -joinLookaheadThreads (code review M5). */
		[self detachLookaheadComposing:(readMode <= 1)];
	} else {
		if (nowPage == [completeMutableArray count]) {
			if ([self isSmallImage:firstImage page:nowPage]) {
				if ([marksArray containsObject:[NSString stringWithFormat:@"%i",nowPage]]) {
					[marksArray removeObject:[NSString stringWithFormat:@"%i",nowPage]];
				}
				if ([marksArray containsObject:[NSString stringWithFormat:@"%i",nowPage-1]]) {
					[marksArray removeObject:[NSString stringWithFormat:@"%i",nowPage-1]];
				}
				if ([marksArray containsObject:[NSString stringWithFormat:@"%i-%i",nowPage-1,nowPage]]) {
					[marksArray removeObject:[NSString stringWithFormat:@"%i-%i",nowPage-1,nowPage]];
				}
				if ([marksArray containsObject:[NSString stringWithFormat:@"%i-%i",nowPage,nowPage+1]]) {
					[marksArray removeObject:[NSString stringWithFormat:@"%i-%i",nowPage,nowPage+1]];
				}
				string = [NSString stringWithFormat:@"%i",nowPage];
				[marksArray addObject:string];
			} else {
				if ([marksArray containsObject:[NSString stringWithFormat:@"%i",nowPage]]) {
					[marksArray removeObject:[NSString stringWithFormat:@"%i",nowPage]];
				}
				if ([marksArray containsObject:[NSString stringWithFormat:@"%i",nowPage-1]]) {
					[marksArray removeObject:[NSString stringWithFormat:@"%i",nowPage-1]];
				}
				if ([marksArray containsObject:[NSString stringWithFormat:@"%i-%i",nowPage-1,nowPage]]) {
					[marksArray removeObject:[NSString stringWithFormat:@"%i-%i",nowPage-1,nowPage]];
				}
				if ([marksArray containsObject:[NSString stringWithFormat:@"%i-%i",nowPage,nowPage+1]]) {
					[marksArray removeObject:[NSString stringWithFormat:@"%i-%i",nowPage,nowPage+1]];
				}
				string = [NSString stringWithFormat:@"%i-%i",nowPage,nowPage+1];
				[marksArray addObject:string];
			}
			return;
		}
		//firstImage = [[imageView image] retain];
		/* The list can be empty here (nothing read ahead yet); this used to
		   raise. The page is in readyPageImages. */
		if ([imageMutableArray count] == 0) {
			[imageMutableArray addObject:[self loadImage:nowPage]];
		}
		secondImage = [[imageMutableArray objectAtIndex:0] retain];
		[imageMutableArray removeObjectAtIndex:0];
		[self composeImage];
		nowPage++;
		if ([marksArray containsObject:[NSString stringWithFormat:@"%i",nowPage]]) {
			[marksArray removeObject:[NSString stringWithFormat:@"%i",nowPage]];
		}
		if ([marksArray containsObject:[NSString stringWithFormat:@"%i",nowPage-1]]) {
			[marksArray removeObject:[NSString stringWithFormat:@"%i",nowPage-1]];
		}
		if ([marksArray containsObject:[NSString stringWithFormat:@"%i-%i",nowPage-1,nowPage]]) {
			[marksArray removeObject:[NSString stringWithFormat:@"%i-%i",nowPage-1,nowPage]];
		}
		if ([marksArray containsObject:[NSString stringWithFormat:@"%i-%i",nowPage,nowPage+1]]) {
			[marksArray removeObject:[NSString stringWithFormat:@"%i-%i",nowPage,nowPage+1]];
		}
		string = [NSString stringWithFormat:@"%i-%i",nowPage-1,nowPage];
		[marksArray addObject:string];
		/* Counted and generation-tagged like every other detach; these two
		   used to bypass -joinLookaheadThreads (code review M5). */
		[self detachLookaheadComposing:(readMode <= 1)];
	}
	[self setPageTextField];
	
	if (rememberBookSettings && [marksArray count] > 0) {
		[currentBookSetting setObject:marksArray forKey:@"marks"];
	}
	
}


/* dontSleepTimer moved to AppController (MW-3): it retained one controller
   via target:self and was never rebuilt, which only worked because
   BookWindowController used to be a nib singleton that is never deallocated. It must
   not be tied to one window controller's lifetime. */

-(IBAction)slideshow:(id)sender
{
	/* MW-6 item 4: there has to be a book to run a slideshow over; the
	   [[self window] isVisible] this replaces only stood in for that. */
	if ([self hasBookOpen]) {
		[NSCursor setHiddenUntilMouseMoves:YES];
		if (timerSwitch) {
			[appController dontSleepTimerStop];
			[timer invalidate];
			timer = nil;
			timerSwitch=NO;
			[imageView setSlideshow:NO];
		} else {
			/* One-shot (KNOWN_ISSUES #46): every display commit schedules
			   the next slide (-rescheduleSlideshowIfNeeded), so a slide
			   waiting for its page holds the slideshow back instead of
			   piling up page turns. */
			timer = [NSTimer scheduledTimerWithTimeInterval:sliderValue
													 target:self
												   selector:@selector(doSlideshow)
												   userInfo:NULL
													repeats:NO];
			timerSwitch=YES;
			[appController dontSleepTimerStart];
			[imageView setSlideshow:YES];
		}
	}
}

-(void)doSlideshow
{
	/* The one-shot timer that called this has fired and is gone. */
	timer = nil;
	/* A slide still waiting for its page: the next one is scheduled when it
	   commits. */
	if (displayRequestPending) return;
	[self nextPage];
	/* Nothing pending after the request (it committed, did nothing, or went
	   to another book): keep the slideshow going from here. */
	[self rescheduleSlideshowIfNeeded];
}

- (void)switchSingleWithPage:(int)page
{
	//NSLog(@"single %i,%i",page,nowPage);
	if (page == nowPage-1) {
		[self switchSingle:nil];
		return;
	}
	NSString *string;
	if ([marksArray containsObject:[NSString stringWithFormat:@"%i",page]]) {
		[marksArray removeObject:[NSString stringWithFormat:@"%i",page]];
	}
	if ([marksArray containsObject:[NSString stringWithFormat:@"%i-%i",page-1,page]]) {
		[marksArray removeObject:[NSString stringWithFormat:@"%i-%i",page-1,page]];
	}
	if ([marksArray containsObject:[NSString stringWithFormat:@"%i-%i",page,page+1]]) {
		[marksArray removeObject:[NSString stringWithFormat:@"%i-%i",page,page+1]];
	}
	string = [NSString stringWithFormat:@"%i",page];
	[marksArray addObject:string];
	
	if (rememberBookSettings && [marksArray count] > 0) {
		[currentBookSetting setObject:marksArray forKey:@"marks"];
	}
}

- (void)switchBindWithPage:(int)page
{
	//NSLog(@"bind %i,%i",page,nowPage);
	if (page == nowPage) {
		[self switchSingle:nil];
		return;
	}
	NSString *string;
	if (page == [completeMutableArray count]) {
		if ([marksArray containsObject:[NSString stringWithFormat:@"%i",page-1]]) {
			[marksArray removeObject:[NSString stringWithFormat:@"%i",page-1]];
		}
		string = [NSString stringWithFormat:@"%i-%i",page-1,page];
	} else {
		string = [NSString stringWithFormat:@"%i-%i",page,page+1];
	}
	if ([marksArray containsObject:[NSString stringWithFormat:@"%i",page]]) {
		[marksArray removeObject:[NSString stringWithFormat:@"%i",page]];
	}
	if ([marksArray containsObject:[NSString stringWithFormat:@"%i-%i",page-1,page]]) {
		[marksArray removeObject:[NSString stringWithFormat:@"%i-%i",page-1,page]];
	}
	if ([marksArray containsObject:[NSString stringWithFormat:@"%i-%i",page,page+1]]) {
		[marksArray removeObject:[NSString stringWithFormat:@"%i-%i",page,page+1]];
	}
	
	[marksArray addObject:string];
	
	if (rememberBookSettings && [marksArray count] > 0) {
		[currentBookSetting setObject:marksArray forKey:@"marks"];
	}
	
}

- (BOOL)removeBookmarkWithPage:(int)page
{	
	BOOL result = NO;
	if ([self isBookmarkedPage:page]) {
		result = YES;
	}
	
	if (!result) return result;
	
	id bookmark;
	int index;
	for (index=0; index<[bookmarkArray count]; index++) {
		bookmark = [bookmarkArray objectAtIndex:index];
		if ([[bookmark objectForKey:@"page"] intValue] == page) {
			[bookmarkArray removeObject:bookmark];
		}
	}
	
	[self setBookmarkMenu];
	return result;
}

- (void)addBookmarkWithPage:(int)page
{
	int bookmarkCount = (int)[bookmarkArray count];
	NSString *bookmarkCountName = [NSString stringWithFormat:@"bookmark%d",bookmarkCount + 1];
	NSString *bookmarkNowPageString = [NSString stringWithFormat:@"%d",page];
	
	NSDictionary *bookmarkDic = [NSDictionary dictionaryWithObjectsAndKeys:
		bookmarkCountName, @"name",
		bookmarkNowPageString, @"page",
		nil];
	
	
	[bookmarkArray addObject:bookmarkDic];	
	[self setBookmarkMenu];
}
- (void)trashLeft
{
	if (![self hasShownPage]) return;	/* nothing on screen yet (KNOWN_ISSUES #46) */
	int i;
	if (!secondImage) {
		i = nowPage - 1;
	} else {
		i = nowPage - 1;
	}
	[self trashFile:[imageLoader itemPathAtIndex:i]];
}
- (void)trashRight
{
	if (![self hasShownPage]) return;	/* nothing on screen yet (KNOWN_ISSUES #46) */
	int i;
	if (!secondImage) {
		i = nowPage - 1;
	} else {
		i = nowPage - 2;
	}
	[self trashFile:[imageLoader itemPathAtIndex:i]];
	
	
}
- (void)trashFile:(NSString*)path
{
	NSAlert *alert = [[[NSAlert alloc] init] autorelease];
	[alert setMessageText:NSLocalizedString(@"Move to Trash",@"")];
	[alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"Do you really want to move %@ to the trash?",@""),[path lastPathComponent]]];
	[alert addButtonWithTitle:NSLocalizedString(@"OK",@"")];
	[alert addButtonWithTitle:NSLocalizedString(@"Cancel",@"")];

	if([alert runModal] == NSAlertFirstButtonReturn) {
		BOOL b = NO;
		b = [[NSWorkspace sharedWorkspace] performFileOperation:NSWorkspaceRecycleOperation
														 source:[path stringByDeletingLastPathComponent]
													destination: @""
														  files: [NSArray arrayWithObject:[path lastPathComponent]]
															tag: nil];
		if(!b) {
			NSAppleScript*          script;
			NSAppleEventDescriptor* desc;
			NSDictionary*           error;
			NSString *string;
			//string = [NSString stringWithFormat:@"tell application \"Finder\" to delete POSIX file \"%@\"", [path precomposedStringWithCompatibilityMapping]]; 
			string = [NSString stringWithFormat:@"tell application \"Finder\" to delete selection"];
			script = [[NSAppleScript alloc] initWithSource:string];
			[[NSWorkspace sharedWorkspace] selectFile:path inFileViewerRootedAtPath:@""];
			desc = [script executeAndReturnError:&error];
			//NSLog(@"1 %@ %@",desc,error);
			[script release];
			string = [NSString stringWithFormat:@"tell application \"cooViewer\" to activate"]; 
			script = [[NSAppleScript alloc] initWithSource:string];
			desc = [script executeAndReturnError:&error];
			//NSLog(@"2 %@ %@",desc,error);
			[script release];
			
		}
	}
}
@end
