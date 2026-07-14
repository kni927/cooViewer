//
//  PreviewProvider.m
//  cooViewerPreview
//
//  QuickLook preview extension for cbz/cbr (phase 7).
//
//  Design: same rationale as ThumbnailExtension/ThumbnailProvider.m —
//  reuses COCoverExtractor (Sources/COCoverExtractor.m), which reuses
//  COArchive/COZipArchive/CORarArchive/CORarHeaderIndex unchanged, so
//  cover extraction stays fast (sub-second, even for the largest/
//  solid fixtures) regardless of archive size.
//
//  This returns a data-based QLPreviewReply directly from the
//  decoded cover bytes (already a supported image format — whatever
//  the archive stored, typically PNG/JPEG) rather than building a
//  view hierarchy; QuickLook renders and scales it itself. No XIB or
//  view controller needed for a single static cover image.
//

#import "PreviewProvider.h"
#import "COCoverExtractor.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@implementation PreviewProvider

- (void)providePreviewForFileRequest:(QLFilePreviewRequest *)request
                    completionHandler:(void (^)(QLPreviewReply * _Nullable reply, NSError * _Nullable error))handler
{
	@autoreleasepool {
		NSData *coverData = COExtractCoverImageData([request.fileURL path]);
		if (!coverData) {
			NSError *error = [NSError errorWithDomain:@"jp.coo.cooViewer.QuickLookPreview"
			                                      code:1
			                                  userInfo:@{NSLocalizedDescriptionKey: @"No cover image available"}];
			handler(nil, error);
			return;
		}

		NSImage *image = [[[NSImage alloc] initWithData:coverData] autorelease];
		NSSize imageSize = (image && [image isValid]) ? [image size] : NSMakeSize(800, 800);

		QLPreviewReply *reply = [[[QLPreviewReply alloc]
			initWithDataOfContentType:UTTypeImage
			               contentSize:CGSizeMake(imageSize.width, imageSize.height)
			         dataCreationBlock:^NSData * _Nullable(QLPreviewReply *replyToUpdate, NSError **error) {
			return coverData;
		}] autorelease];

		handler(reply, nil);
	}
}

@end
