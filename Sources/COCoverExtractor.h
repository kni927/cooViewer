//
//  COCoverExtractor.h
//  cooViewer
//
//  Shared cover-image extraction for the QuickLook preview/thumbnail
//  extensions (phase 7). See COCoverExtractor.m for the design note.
//

#import <Foundation/Foundation.h>

/* Opens the zip/cbz/rar/cbr archive at path via COArchive (which
 * dispatches to the existing lazy COZipArchive/CORarArchive readers
 * unchanged), picks the first image entry in Finder sort order (the
 * same -finderCompareS: NSString category the main app's
 * COImageLoader uses — not reimplemented here), and decodes just
 * that one entry.
 *
 * Returns the entry's raw image data (already a supported image
 * format — PNG/JPEG/etc, whatever the archive stored), or nil if the
 * archive can't be opened, is encrypted, has no image entries, or the
 * cover entry itself is corrupt. Callers (the QL providers) should
 * treat nil as "no preview available", not an error to surface. */
NSData *COExtractCoverImageData(NSString *path);
