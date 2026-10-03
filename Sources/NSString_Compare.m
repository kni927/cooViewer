#import "NSString_Compare.h"
#include <sys/param.h>


const UCCollateOptions FINDER_COMPARE_OPTIONS =
kUCCollateComposeInsensitiveMask
| kUCCollateWidthInsensitiveMask
| kUCCollateCaseInsensitiveMask
| kUCCollateDigitsOverrideMask
| kUCCollateDigitsAsNumberMask
| kUCCollatePunctuationSignificantMask;

@implementation NSString (AddingCompare)
- (NSComparisonResult)finderCompareS:(NSString *)aString
{
	SInt32 compareResult = 0;
	NSUInteger length1 = [self length];
	NSUInteger length2 = [aString length];
	/* The strings include entry names from archive headers, which can be
	   any length: the usual case uses the stack, longer strings the heap. */
	UniChar stack1[MAXPATHLEN];
	UniChar stack2[MAXPATHLEN];
	UniChar *buff1 = length1 <= MAXPATHLEN ? stack1 : malloc(length1 * sizeof(UniChar));
	UniChar *buff2 = length2 <= MAXPATHLEN ? stack2 : malloc(length2 * sizeof(UniChar));

	if (buff1 && buff2) {
		[self getCharacters:buff1 range:NSMakeRange(0, length1)];
		[aString getCharacters:buff2 range:NSMakeRange(0, length2)];
		UCCompareTextDefault(FINDER_COMPARE_OPTIONS, buff1, length1, buff2, length2, NULL, &compareResult);
	} else {
		compareResult = (SInt32)[self compare:aString];
	}

	if (buff1 != stack1) free(buff1);
	if (buff2 != stack2) free(buff2);
	return((NSComparisonResult)compareResult);
}

- (NSComparisonResult)randomCompare:(NSString *)otherString
{
    int n;
	
    srand(rand()%time(NULL));
	//srand((unsigned)time(NULL));
    n = rand()%3;
	
    switch(n) {
        case 0: return NSOrderedAscending; break; //左小さい
        case 1: return NSOrderedSame; break; //同じ
        case 2: return NSOrderedDescending; break; //右小さい
    }
	
    return NSOrderedSame;
}

- (NSComparisonResult)fileCreationDateCompare:(NSString *)otherString
{
    NSDate *sourceDate = [[[NSFileManager defaultManager] attributesOfItemAtPath:[self stringByResolvingSymlinksInPath] error:nil] fileCreationDate];
    NSDate *otherDate = [[[NSFileManager defaultManager] attributesOfItemAtPath:[otherString stringByResolvingSymlinksInPath] error:nil] fileCreationDate];
	NSComparisonResult res = [sourceDate compare:otherDate];
	if (res == NSOrderedSame) {
		return [self finderCompareS:otherString];
	} else {
		return res;
	}
}

- (NSComparisonResult)fileModificationDateCompare:(NSString *)otherString
{
    NSDate *sourceDate = [[[NSFileManager defaultManager] attributesOfItemAtPath:[self stringByResolvingSymlinksInPath] error:nil] fileModificationDate];
    NSDate *otherDate = [[[NSFileManager defaultManager] attributesOfItemAtPath:[otherString stringByResolvingSymlinksInPath] error:nil] fileModificationDate];
	NSComparisonResult res = [sourceDate compare:otherDate];
	if (res == NSOrderedSame) {
		return [self finderCompareS:otherString];
	} else {
		return res;
	}
}

- (NSComparisonResult)versionCompare:(NSString *)otherString
{
	NSArray *selfArray = [self componentsSeparatedByString:@"b"];
	NSArray *otherArray = [otherString componentsSeparatedByString:@"b"];
	NSString *ver=[selfArray objectAtIndex:0];
	NSString *beta=nil;
	NSString *otherVer=[otherArray objectAtIndex:0];
	NSString *otherBeta=nil;
	if ([selfArray count] == 2) beta = [selfArray objectAtIndex:1];
	if ([otherArray count] == 2) otherBeta = [otherArray objectAtIndex:1];
	
	NSComparisonResult res = [ver compare:otherVer];
	if (res == NSOrderedSame) {
		if (beta == nil) return NSOrderedDescending;
		if (otherBeta == nil) return NSOrderedAscending;
		return [beta compare:otherBeta];
	} else {
		return res;
	}
}
@end
