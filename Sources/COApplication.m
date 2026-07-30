#import "COApplication.h"
#import "AppController.h"

@implementation COApplication

/* Take any archive password prompt down first, then quit exactly as before.
 *
 * Each prompt ends as a cancel, by the rule the prompt already follows: a
 * window that had a book keeps it, a bookless window stays bookless. Nothing
 * about the abandoned book is persisted — RecentItems, LastPages and the
 * restorable state are all written by the second half of the open, which a
 * cancelled prompt never reaches — so an archive whose password was never
 * entered leaves no trace to come back on at the next launch.
 *
 * The super call is deferred by one run-loop pass when a prompt was actually
 * dismissed: -endSheet: starts AppKit's dismissal, and the sheet is not
 * detached from its window until that finishes, so terminating in the same
 * pass would meet the very refusal this override exists to avoid. With no
 * prompt up — every ordinary quit — nothing is deferred and the behaviour is
 * unchanged.
 */
- (void)terminate:(id)sender
{
	id delegate = [self delegate];
	if ([delegate respondsToSelector:@selector(cancelPasswordPrompts)]
		&& [delegate cancelPasswordPrompts]) {
		/* Comes back here on the next pass, where no prompt is left to dismiss
		   and the branch below runs. */
		[self performSelector:@selector(terminate:) withObject:sender afterDelay:0.0];
		return;
	}
	[super terminate:sender];
}

@end
