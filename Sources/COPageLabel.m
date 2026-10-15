//
//  COPageLabel.m
//  cooViewer
//

#import "COPageLabel.h"
#include <math.h>

const int COPageBarDefaultHeight = 18;
const int COPageBarLegacyDefaultHeight = 15;

NSString * const COPageBarHeightMigratedKey = @"PageBarHeightMigrated";
NSString * const COFileNameLocationKey = @"FileNameLocation";
NSString * const COPageBarTitleBarFillKey = @"PageBarTitleBarFill";
NSString * const COStatusBarOpacityKey = @"StatusBarOpacity";
const int COStatusBarDefaultOpacity = 80;

double COStatusBarAlpha(NSInteger storedPercent)
{
	if (storedPercent < 0) storedPercent = 0;
	if (storedPercent > 100) storedPercent = 100;
	return storedPercent / 100.0;
}

int COPageBarNumberModeFromStored(NSInteger stored)
{
	switch (stored) {
		case COPageBarNumberInBar:
		case COPageBarNumberOverlay:
		case COPageBarNumberOff:
		case COPageBarNumberTitleBar:
			return (int)stored;
		default:
			return COPageBarNumberInBar;
	}
}

NSString *COPageBarPositionString(int firstPage, int lastPage, int count)
{
	if (count <= 0 || firstPage < 1 || lastPage < firstPage || lastPage > count) return nil;
	if (firstPage == lastPage) {
		return [NSString stringWithFormat:@"%d/%d", firstPage, count];
	}
	return [NSString stringWithFormat:@"%d-%d/%d", firstPage, lastPage, count];
}

NSArray *COFileNameEntries(NSArray *names, NSArray *sizes)
{
	if ([names count] == 0) return nil;
	NSMutableArray *entries = [NSMutableArray arrayWithCapacity:[names count]];
	NSUInteger i;
	for (i = 0; i < [names count]; i++) {
		NSString *name = [names objectAtIndex:i];
		id size = (i < [sizes count]) ? [sizes objectAtIndex:i] : nil;
		if ([size isKindOfClass:[NSString class]] && [(NSString *)size length] > 0) {
			[entries addObject:[NSString stringWithFormat:@"%@ (%@)", name, size]];
		} else {
			[entries addObject:name];
		}
	}
	return entries;
}

NSString *COFileNameHUDString(NSArray *names, NSArray *sizes)
{
	NSArray *entries = COFileNameEntries(names, sizes);
	if (!entries) return nil;
	return [entries componentsJoinedByString:@" | "];
}

NSDictionary *COMigratedPageBarSize(id stored)
{
	if (![stored isKindOfClass:[NSDictionary class]]) return nil;
	id height = [stored objectForKey:@"height"];
	if (![height respondsToSelector:@selector(intValue)]) return nil;
	if ([height intValue] != COPageBarLegacyDefaultHeight) return nil;
	NSMutableDictionary *migrated = [NSMutableDictionary dictionaryWithDictionary:stored];
	[migrated setObject:[NSNumber numberWithInt:COPageBarDefaultHeight] forKey:@"height"];
	return migrated;
}

BOOL COMigratePageBarHeight(id store)
{
	if ([store objectForKey:COPageBarHeightMigratedKey]) return NO;
	NSDictionary *migrated = COMigratedPageBarSize([store objectForKey:@"PageBarSize"]);
	if (migrated) {
		[store setObject:migrated forKey:@"PageBarSize"];
	}
	[store setObject:[NSNumber numberWithBool:YES] forKey:COPageBarHeightMigratedKey];
	return (migrated != nil);
}


COTitleBarLayout COTitleBarLayoutMake(double viewWidth, double centreX, double leading,
                                      double nameWidth, double gap, double numberWidth)
{
	COTitleBarLayout layout;
	if (viewWidth < 0) viewWidth = 0;
	if (leading < 0) leading = 0;
	if (nameWidth < 0) nameWidth = 0;
	double nameEnd = viewWidth;	/* where the name must end */
	double numberX = 0;
	if (numberWidth > 0) {
		numberX = floor(centreX - numberWidth/2);
		if (numberX + numberWidth > viewWidth) numberX = viewWidth - numberWidth;
		if (numberX < 0) numberX = 0;
		nameEnd = numberX - gap;
	}
	double width = nameWidth;
	if (leading + width > nameEnd) width = nameEnd - leading;
	if (width < 0) width = 0;
	layout.nameX = leading;
	layout.nameWidth = width;
	layout.numberX = numberX;
	return layout;
}

COTitleBarLayout COTitleBarCentredNameLayout(double viewWidth, double centreX, double leading,
                                             double nameWidth)
{
	COTitleBarLayout layout;
	if (viewWidth < 0) viewWidth = 0;
	if (leading < 0) leading = 0;
	if (nameWidth < 0) nameWidth = 0;
	double room = viewWidth - leading;
	if (room < 0) room = 0;
	double width = (nameWidth > room) ? room : nameWidth;
	double x = floor(centreX - width/2);
	if (x + width > viewWidth) x = viewWidth - width;
	if (x < leading) x = leading;
	layout.nameX = x;
	layout.nameWidth = width;
	layout.numberX = 0;
	return layout;
}

COTitleBarFill COTitleBarFillMake(double width, double fraction, BOOL fromLeft)
{
	COTitleBarFill fill;
	if (width < 0 || isnan(width)) width = 0;
	if (isnan(fraction) || fraction < 0) fraction = 0;
	if (fraction > 1) fraction = 1;
	double filled = round(width * fraction);
	if (filled > width) filled = width;
	fill.width = filled;
	fill.x = fromLeft ? 0 : width - filled;
	return fill;
}

double COPageBarInBarFontSize(double barHeight, double lineHeightPerPoint)
{
	if (lineHeightPerPoint <= 0) lineHeightPerPoint = 1.2;
	/* The bar is drawn barHeight + 1 tall with a 1 px border inside it. */
	double room = barHeight - 3;
	double size = floor(room / lineHeightPerPoint * 2) / 2;
	if (size < 6) size = 6;
	return size;
}

double COStatusBarHeight(double textHeight)
{
	return ceil(textHeight) + 4;
}

/* Places an entry of `width` centred on `centre` within lo..hi: the
   width it gets and its x. */
static void COPlaceEntry(double centre, double width, double lo, double hi,
                         double *x, double *outWidth)
{
	double room = hi - lo;
	if (room <= 0 || width <= 0) {
		*x = (lo < hi) ? lo : 0;
		*outWidth = 0;
		return;
	}
	if (width > room) width = room;
	double left = floor(centre - width/2);
	if (left + width > hi) left = hi - width;
	if (left < lo) left = lo;
	*x = left;
	*outWidth = width;
}

COStatusBarLayout COStatusBarLayoutMake(double barWidth, double padding, double gap, int count,
                                        double leftMin, double leftMax, double leftWidth,
                                        double rightMin, double rightMax, double rightWidth)
{
	COStatusBarLayout layout = {0, 0, 0, 0};
	if (barWidth < 0) barWidth = 0;
	if (padding < 0) padding = 0;
	if (gap < 0) gap = 0;
	double lo = padding, hi = barWidth - padding;
	if (count <= 0 || hi <= lo) return layout;
	if (count == 1) {
		COPlaceEntry((leftMin + leftMax)/2, leftWidth, lo, hi, &layout.leftX, &layout.leftWidth);
		return layout;
	}
	/* Side by side: the right page starts no earlier than the middle of
	   the left one, and the left ends before the middle of the right. */
	double leftCentre = (leftMin + leftMax)/2, rightCentre = (rightMin + rightMax)/2;
	if (!(leftMax > leftMin && rightMax > rightMin && rightMin >= leftCentre && leftMax <= rightCentre
		  && rightCentre - leftCentre >= gap)) {
		leftMin = 0; leftMax = barWidth/2;
		rightMin = barWidth/2; rightMax = barWidth;
		leftCentre = barWidth/4; rightCentre = barWidth*3/4;
	}
	double edge = (leftMax + rightMin)/2;	/* the edge the pages share */
	double leftLo = MAX(lo, leftMin), leftHi = MIN(leftMax, edge - gap/2);
	double rightLo = MAX(rightMin, edge + gap/2), rightHi = MIN(hi, rightMax);
	COPlaceEntry(leftCentre, leftWidth, leftLo, leftHi, &layout.leftX, &layout.leftWidth);
	COPlaceEntry(rightCentre, rightWidth, rightLo, rightHi, &layout.rightX, &layout.rightWidth);
	return layout;
}

double COPageBarStatusBarLift(int pageBarPosition, double statusBarHeight)
{
	if (pageBarPosition < 2 || statusBarHeight <= 0) return 0;
	return statusBarHeight;
}

double COBottomHUDOffset(int mode, int pageBarPosition, double pageBarHeight,
                         double numberTextHeight, double statusBarHeight,
                         double pageBarMarginY)
{
	double offset = 17;
	double textHeight = ceil(numberTextHeight);
	if (statusBarHeight < 0) statusBarHeight = 0;
	if (pageBarPosition >= 2) {
		/* Everything about a bottom bar is measured from the top of the
		   status bar it sits on (0 without one). */
		double clear = pageBarHeight + 2;
		if (mode == COPageBarNumberOverlay) {
			clear += 1 + textHeight;
		} else if (mode == COPageBarNumberInBar) {
			/* The number is centred on the bar (2 + (height+1)/2 above its
			   bottom edge) and may be taller than it; the HUD starts 1 px
			   above its top (offset + 2 > text top). */
			double textClear = ceil((pageBarHeight + 1)/2.0 + textHeight/2.0) + 1;
			if (textClear > clear) clear = textClear;
		}
		/* The bar, and everything with it, sits pageBarMarginY above
		   where it would be without a margin. */
		clear += statusBarHeight + pageBarMarginY;
		if (clear > offset) offset = clear;
	}
	if (statusBarHeight > 0) {
		/* The HUD (at offset + 2) starts 1 px above the status bar. */
		double clear = statusBarHeight - 1;
		if (clear > offset) offset = clear;
	}
	return offset;
}
