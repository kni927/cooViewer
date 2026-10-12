//
//  COExportSession.h
//  cooViewer
//
//  One File ▸ Export… of one window's book, from the pages sheet to the
//  finished file: the sheet with its "Pages" field and the check of what
//  was typed, then a plain save panel, the export itself on a worker thread (COExportPages, COExport.h)
//  behind a progress sheet with Cancel, and an alert if it fails.
//
//  The window controller creates one, holds it, and lets it go when the
//  session reports -exportSessionDidEnd:. Never reads, decodes or draws an
//  image: the render path is not involved.
//

#import <Cocoa/Cocoa.h>
#include <stdatomic.h>

@class COImageLoader;
@class COExportSession;

@protocol COExportSessionOwner
/* Main thread, once, when the session is over (exported, cancelled, failed,
   or abandoned with its window). */
- (void)exportSessionDidEnd:(COExportSession *)session;
@end

@interface COExportSession : NSObject <NSTextFieldDelegate>
{
	id <COExportSessionOwner> owner;	/* not retained; it holds us */
	NSWindow *window;			/* not retained; the owner's */
	COImageLoader *loader;			/* retained until the export ends */
	NSString *bookName;

	NSWindow *pagesSheet;			/* asks for the pages */
	NSTextField *pagesField;
	NSTextField *pagesHint;			/* the hint, or what is wrong with the field */
	NSString *pagesHintText;
	NSButton *continueButton;		/* not retained; in pagesSheet */
	NSString *pagesText;			/* the field when Continue was chosen */
	NSSavePanel *panel;

	NSIndexSet *pageIndexes;		/* 0-based book pages, validated */
	NSArray *pages;				/* COExportPage, in the same order */

	int state;				/* see COExportSession.m */
	BOOL windowGone;			/* closed, or the app is quitting: no more UI */
	_Atomic int cancelled;
	_Atomic int progressPermille;
	dispatch_group_t worker;

	NSWindow *progressSheet;
	NSProgressIndicator *progressBar;
	NSTextField *progressLabel;
	NSButton *cancelButton;
	NSTimer *progressTimer;
	BOOL progressSheetShown;
}

/* `bookName` is the name the default file name starts with. */
- (id)initWithLoader:(COImageLoader *)aLoader
            bookName:(NSString *)aBookName
              window:(NSWindow *)aWindow
               owner:(id <COExportSessionOwner>)anOwner;

/* Shows the pages sheet on the window; Continue there opens the save
   panel. */
- (void)begin;

/* YES from -begin until the session has ended. */
- (BOOL)isActive;

/* The window is closing: the save panel or the export is cancelled, and
   nothing more is shown. The export's worker finishes cleaning up on its
   own; the session still ends through the owner. */
- (void)cancelForWindowClose;

/* The app is quitting: as for a close, and then waits a moment for the
   worker to remove its staging files. Answers whether a sheet was taken
   down (see -[AppController cancelPendingOpensForTermination]). */
- (BOOL)cancelForTermination;

/* The owner is going away (its dealloc): the session forgets it and the
   window, and cancels as for a close. */
- (void)ownerWillGoAway;

/* The book's name for the default file name: the file name of an archive
   without its extension, or the folder's name. */
+ (NSString *)bookNameForLoader:(COImageLoader *)aLoader;

/* Whether the book in `aLoader` can be exported at all: an archive or a
   folder (not a PDF or a saved search) with pages. */
+ (BOOL)canExportLoader:(COImageLoader *)aLoader;
@end
