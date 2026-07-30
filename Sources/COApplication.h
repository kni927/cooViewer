/* COApplication
 *
 * The application object, subclassed for one reason: AppKit refuses to
 * terminate while a sheet is attached to a window, and it refuses *before*
 * consulting the delegate — measured by instrumenting
 * -applicationShouldTerminate:, which fires for an ordinary quit and not at all
 * for a quit attempted with an archive password prompt up. So Cmd+Q, the Quit
 * menu item and the AppleEvent quit were all silently discarded whenever a
 * password prompt was showing.
 *
 * -terminate: is the one funnel every one of those routes goes through, which
 * makes overriding it here the smallest fix that covers all of them. The
 * alternative — retargeting the Quit menu item at the delegate — was tried and
 * rejected: it works, but it also loses the "Quit and Close All Windows"
 * alternate item AppKit generates for a menu item bound to -terminate:.
 */

#import <Cocoa/Cocoa.h>

@interface COApplication : NSApplication
@end
