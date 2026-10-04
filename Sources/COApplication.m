#import "COApplication.h"
#import "AppController.h"

@implementation COApplication

/* Take any archive password prompt, any archive load's progress sheet
 * (KNOWN_ISSUES #33's loading half, #20 case 3) and the All Bookmarks
 * browser's modal session down first, then quit exactly as before.
 *
 * A load is cancelled rather than waited for: its read is told to stop, and
 * the open ends silently if the read returns before the process exits. Like a
 * prompt, it has persisted nothing of its book.
 *
 * Each prompt ends as a cancel, by the rule the prompt already follows: a
 * window that had a book keeps it, a bookless window stays bookless. Nothing
 * about the abandoned book is persisted — RecentItems, LastPages and the
 * restorable state are all written by the second half of the open, which a
 * cancelled prompt never reaches — so an archive whose password was never
 * entered leaves no trace to come back on at the next launch.
 *
 * The All Bookmarks browser (KNOWN_ISSUES #20 case 1) ends as an OK: its edits
 * are saved, so quitting loses nothing that closing the browser first would
 * have kept.
 *
 * The super call is deferred by one run-loop pass when either was actually
 * taken down. For a prompt, -endSheet: starts AppKit's dismissal, and the
 * sheet is not detached from its window until that finishes, so terminating in
 * the same pass would meet the very refusal this override exists to avoid (a
 * progress sheet is the same). For
 * the browser, -stopModalWithCode: only asks -runModalForWindow: to return; the
 * browser saves after it has, and the delayed perform below — scheduled in the
 * default run-loop mode, which the modal loop does not run — cannot fire before
 * then. With neither up — every ordinary quit — nothing is deferred and the
 * behaviour is unchanged.
 */
- (void)terminate:(id)sender
{
	id delegate = [self delegate];
	BOOL endedModal = NO;
	BOOL dismissedPrompt = NO;
	if ([delegate respondsToSelector:@selector(endAllBookmarksModalForTermination)]) {
		endedModal = [delegate endAllBookmarksModalForTermination];
	}
	if ([delegate respondsToSelector:@selector(cancelPendingOpensForTermination)]) {
		dismissedPrompt = [delegate cancelPendingOpensForTermination];
	}
	if (endedModal || dismissedPrompt) {
		/* Comes back here on the next pass, where nothing is left to take
		   down and the branch below runs. `sender` is passed through so the
		   "Quit and Close All Windows" alternate keeps its meaning. */
		[self performSelector:@selector(terminate:) withObject:sender afterDelay:0.0];
		return;
	}
	[super terminate:sender];
}

/* KNOWN_ISSUES #20 case 1. While a window runs application-modal, AppKit
 * disables every menu item whose target is outside that window unless the
 * target answers YES here. The Quit item (and so Cmd+Q) targets the
 * application object, so this is what lets it through — but only while the
 * All Bookmarks browser is the modal window. It does not reach the "Quit and
 * Close All Windows" alternate: AppKit adds that item without a target, and a
 * nil-targeted -terminate: never gets as far as the application object during
 * a modal session; -[AllBookmarkController terminate:] is its target there.
 * The other application-modal windows (Preferences, the nested-archive
 * password prompt, the archive-load session of an archive nested in a book or
 * inside a folder book) keep the behaviour they had: there the quit stays
 * disabled or deferred until they end. The load of the book a window opens is
 * no longer one of them (KNOWN_ISSUES #33): its progress sheet is window-modal
 * only, so Quit stays enabled and -terminate: above cancels it. */
- (BOOL)worksWhenModal
{
	id delegate = [self delegate];
	return [delegate respondsToSelector:@selector(isAllBookmarksBrowserModal)]
		&& [delegate isAllBookmarksBrowserModal];
}

/* The YES above would also enable the application menu's other items that
 * target this object (About, Hide, Hide Others, Show All). Only the quit is
 * meant to work during the browser's session, so those stay disabled as they
 * were. Outside that session this is the inherited validation, unchanged. */
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	if ([menuItem action] != @selector(terminate:) && [self worksWhenModal]) {
		return NO;
	}
	return [super validateMenuItem:menuItem];
}

@end
