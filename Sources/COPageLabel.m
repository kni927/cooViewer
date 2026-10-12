//
//  COPageLabel.m
//  cooViewer
//

#import "COPageLabel.h"

const int COPageBarDefaultHeight = 18;
const int COPageBarLegacyDefaultHeight = 15;

NSString * const COPageBarHeightMigratedKey = @"PageBarHeightMigrated";

NSString *COPageBarPositionString(int firstPage, int lastPage, int count)
{
	if (count <= 0 || firstPage < 1 || lastPage < firstPage || lastPage > count) return nil;
	if (firstPage == lastPage) {
		return [NSString stringWithFormat:@"%d/%d", firstPage, count];
	}
	return [NSString stringWithFormat:@"%d-%d/%d", firstPage, lastPage, count];
}

NSString *COFileNameHUDString(NSArray *names, NSArray *sizes)
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
