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
 * For a `.cvbdl` bundle (LSTypeIsPackage folder, not a real archive
 * file), COArchive is bypassed entirely: the bundle's top-level
 * contents are listed directly and the same sort/filter rule applies.
 *
 * Returns the entry's raw image data (already a supported image
 * format — PNG/JPEG/etc, whatever the archive/bundle stored), or nil
 * if the path can't be opened, is encrypted, has no image entries, or
 * the cover entry itself is corrupt/unreadable. Callers (the QL
 * providers) should treat nil as "no preview available", not an error
 * to surface. */
NSData *COExtractCoverImageData(NSString *path);
