#import <Foundation/Foundation.h>

extern NSString * const CooViewerNewWindowSchemeInfoKey;

NSURL *CooViewerNewWindowURLForFileURL(NSURL *fileURL, NSString *scheme);
NSURL *CooViewerFileURLFromNewWindowURL(NSURL *requestURL, NSString *scheme);
