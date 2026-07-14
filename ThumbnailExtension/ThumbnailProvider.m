//
//  ThumbnailProvider.m
//  cooViewerThumbnail
//
//  QuickLook thumbnail extension for cbz/cbr (phase 7).
//
//  Design: reuses COCoverExtractor (Sources/COCoverExtractor.m),
//  which reuses COArchive/COZipArchive/CORarArchive/CORarHeaderIndex
//  exactly as the main app does — the lazy readers from phases 2/4/6
//  are what make this fast enough for QuickLook's time budget
//  regardless of archive size or solid/non-solid RAR status. This
//  file only decodes the returned image data into an NSImage and
//  draws it, aspect-fit, into the requested thumbnail context.
//
//  Failure (corrupt/encrypted archive, no image entries) calls the
//  completion handler with a nil reply and an error rather than
//  drawing anything or crashing — QuickLook then falls back to a
//  generic icon for that file.
//

#import "ThumbnailProvider.h"
#import "COCoverExtractor.h"
#import <Cocoa/Cocoa.h>

@implementation ThumbnailProvider

- (void)provideThumbnailForFileRequest:(QLFileThumbnailRequest *)request
                      completionHandler:(void (^)(QLThumbnailReply * _Nullable, NSError * _Nullable))handler
{
	@autoreleasepool {
		NSData *coverData = COExtractCoverImageData([request.fileURL path]);
		NSImage *image = coverData ? [[[NSImage alloc] initWithData:coverData] autorelease] : nil;
		if (!image || ![image isValid]) {
			NSError *error = [NSError errorWithDomain:@"jp.coo.cooViewer.QuickLookThumbnail"
			                                      code:1
			                                  userInfo:@{NSLocalizedDescriptionKey: @"No cover image available"}];
			handler(nil, error);
			return;
		}

		CGSize contextSize = request.maximumSize;
		handler([QLThumbnailReply replyWithContextSize:contextSize currentContextDrawingBlock:^BOOL{
			NSSize imageSize = [image size];
			if (imageSize.width <= 0 || imageSize.height <= 0) return NO;

			// aspect-fit, centered
			CGFloat scale = MIN(contextSize.width / imageSize.width,
			                     contextSize.height / imageSize.height);
			NSSize drawSize = NSMakeSize(imageSize.width * scale, imageSize.height * scale);
			NSRect drawRect = NSMakeRect((contextSize.width - drawSize.width) / 2.0,
			                             (contextSize.height - drawSize.height) / 2.0,
			                             drawSize.width, drawSize.height);

			[image drawInRect:drawRect fromRect:NSZeroRect
			        operation:NSCompositingOperationSourceOver fraction:1.0];
			return YES;
		}], nil);
	}
}

@end
