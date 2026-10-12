//
//  COExportSession.m
//  cooViewer
//

#import "COExportSession.h"
#import "COExport.h"
#import "COImageLoader.h"

/* `state` */
enum {
	COExportSessionIdle = 0,	/* created, -begin not called */
	COExportSessionPages,		/* the pages sheet is up */
	COExportSessionPanel,		/* the save panel is up */
	COExportSessionRunning,		/* the worker is exporting */
	COExportSessionEnded
};

/* The run-loop modes the session's delayed steps run in, as for an open's
   (BookWindowController.m, COOpenResumeModes). */
static NSArray *COExportSessionModes(void)
{
	return [NSArray arrayWithObjects:NSDefaultRunLoopMode, NSModalPanelRunLoopMode, nil];
}

@interface COExportSession (Private)
- (void)panelEndedWithResult:(NSModalResponse)result;
- (NSString *)resolvePagesFromText:(NSString *)text;
- (NSString *)updatePagesProblem;
- (void)pagesSheetEndedWithResult:(NSModalResponse)result;
- (void)showSavePanel:(id)sender;
- (void)startExportToURL:(NSURL *)url;
- (void)presentProgressSheet:(id)sender;
- (void)refreshProgress:(id)sender;
- (void)endProgressSheet;
- (void)finishWithResult:(COExportResult)result failedPage:(NSUInteger)failedPage
                 message:(NSString *)message destination:(NSURL *)destination;
- (void)end;
@end

@implementation COExportSession

+ (BOOL)canExportLoader:(COImageLoader *)aLoader
{
	if (!aLoader || [aLoader itemCount] <= 0) return NO;
	int mode = [aLoader mode];
	return (mode == 0 || mode == 2);
}

+ (NSString *)bookNameForLoader:(COImageLoader *)aLoader
{
	NSString *path = [aLoader displayPath] ? [aLoader displayPath] : [aLoader filePath];
	NSString *name = [path lastPathComponent];
	if ([aLoader mode] == 2) name = [name stringByDeletingPathExtension];
	return [name length] > 0 ? name : @"book";
}

- (id)initWithLoader:(COImageLoader *)aLoader
            bookName:(NSString *)aBookName
              window:(NSWindow *)aWindow
               owner:(id <COExportSessionOwner>)anOwner
{
	self = [super init];
	if (self) {
		loader = [aLoader retain];
		bookName = [aBookName copy];
		window = aWindow;
		owner = anOwner;
		state = COExportSessionIdle;
		atomic_store(&cancelled, 0);
		atomic_store(&progressPermille, 0);
		worker = dispatch_group_create();
	}
	return self;
}

- (void)dealloc
{
	[progressTimer invalidate];
	[loader release];
	[bookName release];
	[panel release];
	[pagesField release];
	[pagesHint release];
	[pagesHintText release];
	[pagesSheet release];
	[pagesText release];
	[pageIndexes release];
	[pages release];
	[progressSheet release];
	if (worker) dispatch_release(worker);
	[super dealloc];
}

- (BOOL)isActive
{
	return state == COExportSessionPages || state == COExportSessionPanel
		|| state == COExportSessionRunning;
}

#pragma mark pages sheet

/* The sheet that asks for the pages, before the save panel. The save panel
   is not used for this: its own UI (Save button included) is a remote view
   in another process on current macOS, also for this unsandboxed app, so
   an accessory field there could not reliably take Return and Enter as
   Save (owner decision, 2026-10-12). */
- (NSWindow *)newPagesSheet
{
	NSWindow *sheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 460, 160)
	                                              styleMask:NSWindowStyleMaskTitled
	                                                backing:NSBackingStoreBuffered
	                                                  defer:YES];
	[sheet setReleasedWhenClosed:NO];
	NSView *content = [sheet contentView];

	NSTextField *title = [NSTextField labelWithString:
		NSLocalizedString(@"Export Pages", @"Export pages sheet")];
	[title setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
	[title setTranslatesAutoresizingMaskIntoConstraints:NO];
	[content addSubview:title];

	NSTextField *message = [NSTextField wrappingLabelWithString:
		NSLocalizedString(@"Choose the pages to export in the Pages field below, or leave it empty to export all pages.", @"Export save panel")];
	[message setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	[message setSelectable:NO];
	[message setPreferredMaxLayoutWidth:420];
	[message setTranslatesAutoresizingMaskIntoConstraints:NO];
	[content addSubview:message];

	NSTextField *label = [NSTextField labelWithString:
		NSLocalizedString(@"Pages:", @"Export save panel")];
	[label setTranslatesAutoresizingMaskIntoConstraints:NO];
	[content addSubview:label];

	[pagesField release];
	pagesField = [[NSTextField alloc] initWithFrame:NSZeroRect];
	[pagesField setTranslatesAutoresizingMaskIntoConstraints:NO];
	[[pagesField cell] setPlaceholderString:[NSString stringWithFormat:
		NSLocalizedString(@"All pages (1-%d)", @"Export save panel"), [loader itemCount]]];
	[[pagesField cell] setWraps:NO];
	[[pagesField cell] setScrollable:YES];
	[pagesField setDelegate:self];
	if (pagesText) [pagesField setStringValue:pagesText];
	[content addSubview:pagesField];

	[pagesHintText release];
	pagesHintText = [[NSString alloc] initWithFormat:
		NSLocalizedString(@"Empty = all pages (1-%d). Examples: 5, 20-30, 1-3,7,10-12", @"Export save panel"),
		[loader itemCount]];
	/* Shows the hint, or, while the field is not valid, what is wrong with
	   it (-updatePagesProblem). */
	[pagesHint release];
	pagesHint = [[NSTextField wrappingLabelWithString:pagesHintText] retain];
	[pagesHint setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	[pagesHint setTextColor:[NSColor secondaryLabelColor]];
	[pagesHint setSelectable:NO];
	[pagesHint setPreferredMaxLayoutWidth:420];
	[pagesHint setTranslatesAutoresizingMaskIntoConstraints:NO];
	[content addSubview:pagesHint];

	continueButton = [NSButton buttonWithTitle:NSLocalizedString(@"Continue…", @"Export pages sheet")
	                                    target:self action:@selector(continuePages:)];
	[continueButton setKeyEquivalent:@"\r"];
	[continueButton setTranslatesAutoresizingMaskIntoConstraints:NO];
	[content addSubview:continueButton];

	NSButton *cancel = [NSButton buttonWithTitle:NSLocalizedString(@"Cancel", @"")
	                                      target:self action:@selector(cancelPages:)];
	[cancel setKeyEquivalent:@"\033"];
	[cancel setTranslatesAutoresizingMaskIntoConstraints:NO];
	[content addSubview:cancel];

	[label setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
	[label setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
	[NSLayoutConstraint activateConstraints:[NSArray arrayWithObjects:
		[[content widthAnchor] constraintEqualToConstant:460],
		[[title topAnchor] constraintEqualToAnchor:[content topAnchor] constant:20],
		[[title leadingAnchor] constraintEqualToAnchor:[content leadingAnchor] constant:20],
		[[title trailingAnchor] constraintLessThanOrEqualToAnchor:[content trailingAnchor] constant:-20],
		[[message topAnchor] constraintEqualToAnchor:[title bottomAnchor] constant:8],
		[[message leadingAnchor] constraintEqualToAnchor:[content leadingAnchor] constant:20],
		[[message trailingAnchor] constraintEqualToAnchor:[content trailingAnchor] constant:-20],
		[[pagesField topAnchor] constraintEqualToAnchor:[message bottomAnchor] constant:14],
		[[label leadingAnchor] constraintEqualToAnchor:[content leadingAnchor] constant:20],
		[[label firstBaselineAnchor] constraintEqualToAnchor:[pagesField firstBaselineAnchor]],
		[[pagesField leadingAnchor] constraintEqualToAnchor:[label trailingAnchor] constant:8],
		[[pagesField trailingAnchor] constraintEqualToAnchor:[content trailingAnchor] constant:-20],
		[[pagesHint topAnchor] constraintEqualToAnchor:[pagesField bottomAnchor] constant:6],
		[[pagesHint leadingAnchor] constraintEqualToAnchor:[pagesField leadingAnchor]],
		[[pagesHint trailingAnchor] constraintEqualToAnchor:[content trailingAnchor] constant:-20],
		[[continueButton topAnchor] constraintEqualToAnchor:[pagesHint bottomAnchor] constant:18],
		[[continueButton trailingAnchor] constraintEqualToAnchor:[content trailingAnchor] constant:-20],
		[[continueButton bottomAnchor] constraintEqualToAnchor:[content bottomAnchor] constant:-20],
		[[cancel firstBaselineAnchor] constraintEqualToAnchor:[continueButton firstBaselineAnchor]],
		[[cancel trailingAnchor] constraintEqualToAnchor:[continueButton leadingAnchor] constant:-12],
		[[cancel widthAnchor] constraintGreaterThanOrEqualToConstant:80],
		[[continueButton widthAnchor] constraintGreaterThanOrEqualToConstant:80],
		nil]];
	[sheet setInitialFirstResponder:pagesField];
	[sheet setDefaultButtonCell:[continueButton cell]];
	return sheet;
}

/* Asks for the pages; Continue then opens the save panel. */
- (void)begin
{
	if (state != COExportSessionIdle && state != COExportSessionPanel) return;
	state = COExportSessionPages;

	[pagesSheet release];
	pagesSheet = [self newPagesSheet];
	[self updatePagesProblem];
	[pagesSheet setContentSize:[[pagesSheet contentView] fittingSize]];

	[self retain];	/* until the sheet's completion has run */
	[window beginSheet:pagesSheet completionHandler:^(NSModalResponse result) {
		[self pagesSheetEndedWithResult:result];
		[self release];
	}];
	[pagesSheet makeFirstResponder:pagesField];
	[[pagesField currentEditor] selectAll:nil];
}

/* Checks the Pages field and shows the result under it: the hint while
   it is valid, otherwise what is wrong, in the system's error colour;
   Continue is enabled only while it is valid. Returns the problem, or
   nil. Main thread. */
- (NSString *)updatePagesProblem
{
	NSString *problem = [self resolvePagesFromText:[pagesField stringValue]];
	if (problem) {
		[pagesHint setStringValue:problem];
		[pagesHint setTextColor:[NSColor systemRedColor]];
	} else {
		[pagesHint setStringValue:pagesHintText ? pagesHintText : @""];
		[pagesHint setTextColor:[NSColor secondaryLabelColor]];
	}
	[continueButton setEnabled:(problem == nil)];
	return problem;
}

- (void)controlTextDidChange:(NSNotification *)notification
{
	if ([notification object] != pagesField) return;
	[self updatePagesProblem];
}

/* Return and keypad Enter (fn-Return), which reach a field editor as
   insertNewline: when no key equivalent took them, both act as Continue;
   while the pages are not valid (Continue disabled), they only beep. */
- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command
{
	if (control != pagesField) return NO;
	if (command == @selector(insertNewline:) || command == @selector(insertLineBreak:)
	    || command == @selector(insertNewlineIgnoringFieldEditor:)) {
		[self continuePages:pagesField];
		return YES;
	}
	return NO;
}

- (IBAction)continuePages:(id)sender
{
	if (state != COExportSessionPages) return;
	if ([self updatePagesProblem]) {
		NSBeep();
		[pagesSheet makeFirstResponder:pagesField];
		return;
	}
	[pagesText release];
	pagesText = [[pagesField stringValue] copy];
	[window endSheet:pagesSheet returnCode:NSModalResponseOK];
}

- (IBAction)cancelPages:(id)sender
{
	if (state != COExportSessionPages) return;
	[window endSheet:pagesSheet returnCode:NSModalResponseCancel];
}

- (void)pagesSheetEndedWithResult:(NSModalResponse)result
{
	[pagesSheet orderOut:nil];
	[pagesField setDelegate:nil];
	if (result != NSModalResponseOK || windowGone || state != COExportSessionPages) {
		[self end];
		return;
	}
	/* After the sheet has gone. */
	[self performSelector:@selector(showSavePanel:) withObject:nil
			   afterDelay:0.0 inModes:COExportSessionModes()];
}

#pragma mark save panel

/* A plain save panel, named from the accepted page list. Cancel there ends
   the export. */
- (void)showSavePanel:(id)sender
{
	if (state != COExportSessionPages || windowGone) {
		[self end];
		return;
	}
	state = COExportSessionPanel;

	[panel release];
	panel = [[NSSavePanel savePanel] retain];
	[panel setAllowedFileTypes:[NSArray arrayWithObject:@"cbz"]];
	[panel setAllowsOtherFileTypes:YES];
	[panel setCanCreateDirectories:YES];

	NSString *bookPath = [loader displayPath] ? [loader displayPath] : [loader filePath];
	NSString *directory = [bookPath stringByDeletingLastPathComponent];
	if ([directory length] > 0 && [[NSFileManager defaultManager] fileExistsAtPath:directory]) {
		[panel setDirectoryURL:[NSURL fileURLWithPath:directory isDirectory:YES]];
	}
	[panel setNameFieldStringValue:COExportDefaultFileName(bookName, pagesText)];

	[self retain];	/* until the panel's completion has run */
	[panel beginSheetModalForWindow:window completionHandler:^(NSModalResponse result) {
		[self panelEndedWithResult:result];
		[self release];
	}];
}

/* Parses `text` and finds every chosen page's bytes. Returns nil when the
   pages can be exported (pageIndexes and pages are then set), or what is
   wrong. Main thread. */
- (NSString *)resolvePagesFromText:(NSString *)text
{
	[pageIndexes release];
	pageIndexes = nil;
	[pages release];
	pages = nil;

	NSUInteger count = (NSUInteger)[loader itemCount];
	COExportPageListError error = COExportPageListOK;
	NSString *bad = nil;
	NSIndexSet *indexes = COExportParsePageList(text, count, &error, &bad);
	if (!indexes) {
		switch (error) {
		case COExportPageListSyntax:
			return [NSString stringWithFormat:NSLocalizedString(@"“%@” is not a page number or a range of pages.", @"Export"), bad ? bad : @""];
		case COExportPageListOutOfRange:
			return [NSString stringWithFormat:NSLocalizedString(@"“%@” is outside this book, which has pages 1-%lu.", @"Export"), bad ? bad : @"", (unsigned long)count];
		case COExportPageListReversed:
			return [NSString stringWithFormat:NSLocalizedString(@"The range “%@” is reversed. Write the lower page number first.", @"Export"), bad ? bad : @""];
		default:
			return NSLocalizedString(@"There are no pages to export.", @"Export");
		}
	}

	NSMutableArray *resolved = [NSMutableArray arrayWithCapacity:[indexes count]];
	NSUInteger index = [indexes firstIndex];
	while (index != NSNotFound) {
		COExportPage *page = [loader exportPageAtIndex:(int)index];
		if (!page) {
			/* A PDF inside a folder book: its pages are drawn from the PDF
			   and have no file of their own to copy. */
			return [NSString stringWithFormat:NSLocalizedString(@"Page %lu is a page of a PDF file. Export copies the original page files, and a PDF page has none.", @"Export"), (unsigned long)(index + 1)];
		}
		[resolved addObject:page];
		index = [indexes indexGreaterThanIndex:index];
	}
	pageIndexes = [indexes copy];
	pages = [resolved copy];
	return nil;
}

- (void)panelEndedWithResult:(NSModalResponse)result
{
	NSURL *url = [[[panel URL] retain] autorelease];

	if (result != NSModalResponseOK || windowGone || !url) {
		[self end];
		return;
	}
	/* The pages sheet has resolved the pages; resolve again in case the
	   book was re-sorted since. */
	NSString *problem = [self resolvePagesFromText:pagesText];
	if (problem) {
		/* Say so, and offer the pages sheet again with what was typed. */
		NSAlert *alert = [[[NSAlert alloc] init] autorelease];
		[alert setMessageText:problem];
		[alert addButtonWithTitle:NSLocalizedString(@"OK", @"")];
		[self retain];
		dispatch_async(dispatch_get_main_queue(), ^{
			[alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse r) {
				(void)r;
				if (windowGone) {
					[self end];
				} else {
					dispatch_async(dispatch_get_main_queue(), ^{ [self begin]; });
				}
			}];
			[self release];
		});
		return;
	}
	[self startExportToURL:url];
}

#pragma mark export

- (void)startExportToURL:(NSURL *)url
{
	state = COExportSessionRunning;
	atomic_store(&cancelled, 0);
	atomic_store(&progressPermille, 0);

	/* The block retains this session, and through it the loader and the
	   pages (and so their archives), until the worker is done. */
	dispatch_group_enter(worker);
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSUInteger failedPage = NSNotFound;
		NSString *message = nil;
		COExportResult result;
		@autoreleasepool {
			result = COExportPages(pages, url,
				^BOOL(void) { return atomic_load(&cancelled) != 0; },
				^(double fraction) { atomic_store(&progressPermille, (int)(fraction * 1000.0)); },
				&failedPage, &message);
			[message retain];
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			[self finishWithResult:result failedPage:failedPage message:message destination:url];
			[message release];
		});
		dispatch_group_leave(worker);
	});

	/* A short export never shows a sheet. */
	[self performSelector:@selector(presentProgressSheet:) withObject:nil
			   afterDelay:0.15 inModes:COExportSessionModes()];
}

- (void)presentProgressSheet:(id)sender
{
	if (state != COExportSessionRunning || windowGone || progressSheetShown) return;
	if (![window isVisible] || [window isMiniaturized]) return;
	if ([window attachedSheet] != nil) {
		/* The save panel may still be going away. */
		[self performSelector:_cmd withObject:nil afterDelay:0.15 inModes:COExportSessionModes()];
		return;
	}
	if (!progressSheet) {
		progressSheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 108)
		                                            styleMask:NSWindowStyleMaskTitled
		                                              backing:NSBackingStoreBuffered
		                                                defer:YES];
		[progressSheet setReleasedWhenClosed:NO];
		NSView *content = [progressSheet contentView];

		progressLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(20, 68, 380, 20)] autorelease];
		[progressLabel setBezeled:NO];
		[progressLabel setDrawsBackground:NO];
		[progressLabel setEditable:NO];
		[progressLabel setSelectable:NO];
		[progressLabel setLineBreakMode:NSLineBreakByTruncatingMiddle];
		[content addSubview:progressLabel];

		progressBar = [[[NSProgressIndicator alloc] initWithFrame:NSMakeRect(20, 44, 380, 16)] autorelease];
		[progressBar setStyle:NSProgressIndicatorStyleBar];
		[progressBar setIndeterminate:NO];
		[progressBar setMinValue:0.0];
		[progressBar setMaxValue:1.0];
		[content addSubview:progressBar];

		cancelButton = [[[NSButton alloc] initWithFrame:NSMakeRect(310, 8, 92, 32)] autorelease];
		[cancelButton setBezelStyle:NSBezelStyleRounded];
		[cancelButton setTitle:NSLocalizedString(@"Cancel", @"")];
		[cancelButton setKeyEquivalent:@"\033"];
		[cancelButton setTarget:self];
		[cancelButton setAction:@selector(cancel:)];
		[content addSubview:cancelButton];
	}
	[progressLabel setStringValue:[NSString stringWithFormat:
		NSLocalizedString(@"Exporting “%@”…", @"Export progress"), bookName]];
	[cancelButton setEnabled:YES];
	[self refreshProgress:nil];
	[window beginSheet:progressSheet completionHandler:^(NSModalResponse r) { (void)r; }];
	progressSheetShown = YES;

	/* The run loop retains the timer, and the timer this session, until
	   -endProgressSheet. */
	progressTimer = [NSTimer timerWithTimeInterval:0.1 target:self
	                                      selector:@selector(refreshProgress:)
	                                      userInfo:nil repeats:YES];
	[[NSRunLoop currentRunLoop] addTimer:progressTimer forMode:NSRunLoopCommonModes];
}

- (void)refreshProgress:(id)sender
{
	double fraction = atomic_load(&progressPermille) / 1000.0;
	if (fraction < 0.0) fraction = 0.0;
	if (fraction > 1.0) fraction = 1.0;
	[progressBar setDoubleValue:fraction];
}

- (IBAction)cancel:(id)sender
{
	atomic_store(&cancelled, 1);
	[progressLabel setStringValue:NSLocalizedString(@"Cancelling…", @"")];
	[cancelButton setEnabled:NO];
}

- (void)endProgressSheet
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(presentProgressSheet:) object:nil];
	[progressTimer invalidate];
	progressTimer = nil;
	if (!progressSheetShown) return;
	progressSheetShown = NO;
	[window endSheet:progressSheet];
	[progressSheet orderOut:nil];
}

- (void)finishWithResult:(COExportResult)result failedPage:(NSUInteger)failedPage
                 message:(NSString *)message destination:(NSURL *)destination
{
	[self endProgressSheet];

	NSString *problem = nil;
	if (result == COExportReadFailed) {
		NSUInteger bookPage = NSNotFound;
		if (failedPage != NSNotFound && pageIndexes) {
			NSUInteger index = [pageIndexes firstIndex];
			NSUInteger i;
			for (i = 0; i < failedPage && index != NSNotFound; i++) {
				index = [pageIndexes indexGreaterThanIndex:index];
			}
			bookPage = index;
		}
		problem = bookPage != NSNotFound
			? [NSString stringWithFormat:NSLocalizedString(@"Page %lu could not be read.", @"Export"), (unsigned long)(bookPage + 1)]
			: NSLocalizedString(@"A page could not be read.", @"Export");
	} else if (result == COExportWriteFailed) {
		problem = message ? message : @"";
	}
	if (result != COExportOK && result != COExportCancelled) {
		NSLog(@"Export of %@ to %@ failed: %@", [loader filePath], [destination path], problem);
	}

	/* The loader (and with it any nested archive's temporary files) goes on
	   the main thread, as a window's book always does. */
	[pages release];
	pages = nil;
	[loader release];
	loader = nil;

	if (problem && !windowGone && [window isVisible]) {
		NSAlert *alert = [[[NSAlert alloc] init] autorelease];
		[alert setMessageText:[NSString stringWithFormat:
			NSLocalizedString(@"Could not export “%@”.", @"Export"), bookName]];
		[alert setInformativeText:problem];
		[alert addButtonWithTitle:NSLocalizedString(@"OK", @"")];
		[alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse r) { (void)r; }];
	}
	[self end];
}

- (void)end
{
	if (state == COExportSessionEnded) return;
	state = COExportSessionEnded;
	[[self retain] autorelease];
	[owner exportSessionDidEnd:self];
}

#pragma mark window close and quit

- (void)cancelForWindowClose
{
	windowGone = YES;
	atomic_store(&cancelled, 1);
	if (state == COExportSessionPages) {
		[window endSheet:pagesSheet returnCode:NSModalResponseCancel];
	} else if (state == COExportSessionPanel) {
		[panel cancel:nil];
	}
	[self endProgressSheet];
}

- (void)ownerWillGoAway
{
	[self cancelForWindowClose];
	owner = nil;
	window = nil;
}

- (BOOL)cancelForTermination
{
	BOOL hadSheet = progressSheetShown || (state == COExportSessionPages)
		|| (state == COExportSessionPanel);
	[self cancelForWindowClose];
	if (state == COExportSessionRunning) {
		/* Give the worker a moment to stop and remove its staging files.
		   A page being read when the cancel came (one solid RAR entry) can
		   take longer; what is left then is only in the staging
		   directory, never at the destination. */
		dispatch_group_wait(worker, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
	}
	return hadSheet;
}
@end
