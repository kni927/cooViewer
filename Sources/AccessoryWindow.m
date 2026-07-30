//
//  AccessoryWindow.m
//  cooViewer
//
//  Created by coo on 08/02/12.
//  Copyright 2008 coo. All rights reserved.
//

#import "AccessoryWindow.h"
#import "AccessoryView.h"


@implementation AccessoryWindow

- (id)initWithContentRect:(NSRect)contentRect styleMask:(NSWindowStyleMask)styleMask backing:(NSBackingStoreType)bufferingType defer:(BOOL)deferCreation
{
	self = [super initWithContentRect:contentRect
							styleMask:NSBorderlessWindowMask
							  backing:bufferingType
								defer:deferCreation
		];
	return self;
}

- (id)initWithContentRect:(NSRect)contentRect styleMask:(NSWindowStyleMask)styleMask backing:(NSBackingStoreType)bufferingType defer:(BOOL)deferCreation screen:(NSScreen *)screen
{
	self = [super initWithContentRect:contentRect
							styleMask:NSBorderlessWindowMask
							  backing:bufferingType
								defer:deferCreation
							   screen:screen
		];
	return self;
}

/* MW-8: This window survives its parent's close to fire pending draw operations
   after the parent's BookWindowController is deallocated. The AccessoryView
   holds unretained IBOutlet references to controller and imageView, which
   become dangling pointers after window close. Clearing them here prevents
   use-after-free crashes if a draw event fires during the window close sequence.
   This is the teardown step that was omitted in MW-8 due to "no object ivars". */
- (void)dealloc
{
	AccessoryView *view = (AccessoryView *)[self contentView];
	if ([view isKindOfClass:[AccessoryView class]]) {
		[view clearOutletReferences];
	}
	[super dealloc];
}
@end
