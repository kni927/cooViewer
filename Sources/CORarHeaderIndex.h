//
//  CORarHeaderIndex.h
//  cooViewer
//
//  Header-only RAR4/RAR5 entry enumeration (rar-lazy phase 6).
//
//  RAR4/RAR5 block-layout and flag-bit knowledge in this file is
//  derived from XADMaster's XADRARParser.m and XADRAR5Parser.m
//  (Copyright (c) 2017-present, MacPaw Inc.,
//  https://github.com/tak758/XADMaster), reimplemented here as new,
//  self-contained code (see the design note below for why). Per
//  XADMaster's license:
//
//  This library is free software; you can redistribute it and/or
//  modify it under the terms of the GNU Lesser General Public
//  License as published by the Free Software Foundation; either
//  version 2.1 of the License, or (at your option) any later version.
//  This library is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
//  Lesser General Public License (Licence_xadmaster.txt) for details.
//
//  Design (docs/tasks/... phase 6 TASK; root cause: phase 5,
//  docs/tasks/2026-07-14-03-solid-rar-investigation.md):
//  - Phase 5 found that libarchive's archive_read_data_skip() on a
//    solid RAR5 stream actually runs the real decompressor and
//    discards the output — there is no cheap way to enumerate a
//    solid archive's entries through libarchive's public API. v1.3.7
//    (XADMaster) enumerated entries via raw file-offset seeks based
//    on each header's declared block size, never touching a
//    decompressor, solid or not — RAR headers record each entry's
//    compressed byte length even inside a solid stream.
//  - This file reimplements *only* that seek-based enumeration
//    strategy (informed by / derived from XADMaster's
//    XADRARParser.m and XADRAR5Parser.m, MacPaw Inc.,
//    LGPL-2.1-or-later — see Licence_xad.txt), as small,
//    self-contained C/Foundation code matching cooViewer's existing
//    style (COArchive.m/COZipArchive.m), rather than reusing
//    XADMaster's own CSHandle/XADArchiveParser/XADPath class
//    hierarchy, which pulls in ~3500 lines of infrastructure (input
//    handles, decryption, decompression engines) this project has no
//    other use for. Decoding a requested entry's *data* is still
//    entirely delegated to CORarArchive's existing libarchive-based
//    cursor pass — this file only builds the name/size list at open
//    time, faster.
//  - Deliberately bails out (returns nil) rather than guessing, for
//    every case where correctness could not be verified against a
//    real fixture in this project, or where the format gets
//    materially more complex:
//      - wrong/missing signature (not RAR4 or RAR5)
//      - archive-level header encryption (MHD_PASSWORD / RAR5
//        Encryption header — headers themselves need a password to
//        read further)
//      - multi-volume archives (RAR5 Volume flag / RAR4 MHD_VOLUME,
//        or any split-before/split-after file) — reassembling parts
//        across sibling volume files is deferred, not attempted
//      - RAR4 LHD_UNICODE-flagged names — XADMaster decodes these
//        with a bespoke run-length name encoding; ported here
//        untested (no RAR4 Unicode fixture exists in this repo to
//        verify against) risks silently wrong filenames, which is
//        worse than falling back
//      - any malformed field, truncation, or read past EOF
//    CORarArchive treats a nil result as "use the existing
//    libarchive-based index pass instead" (same fallback philosophy
//    as COArchive's zip/rar dispatch) — this file is a pure
//    optional fast path layered in front of already-correct code,
//    never the only way to open an archive.
//  - Per-entry filtering mirrors COArchive/CORarArchive's existing
//    policy exactly, so entry ordinals line up with what the
//    libarchive-based cursor pass will independently derive when
//    decoding a specific page: directories, zero-byte entries, and
//    AppleDouble ("._*") sidecars are excluded; per-entry encrypted
//    files are excluded and reported via outCrypted.
//  - RAR5 names are UTF-8 by spec (validated on read); RAR4 names
//    without LHD_UNICODE are raw legacy-charset bytes, handed to the
//    same shared uchardet-based decode used everywhere else in this
//    project.
//

#import <Foundation/Foundation.h>

@interface CORarHeaderEntry : NSObject
{
@public
	NSData *rawName;	// raw filename bytes as stored in the header
	NSString *utf8Name;	// non-nil when the format guarantees UTF-8
				// (RAR5 always); nil for RAR4, which goes
				// through the shared raw+uchardet decode
	unsigned long long compressedSize;
	unsigned long long uncompressedSize;
}
@end

/* Attempts a fast, header-only enumeration of path (RAR4 or RAR5).
 * Returns entries in stream order on success (same filtering policy
 * as CORarArchive's libarchive-based index pass), or nil if the
 * header-only path can't handle this archive for any reason — the
 * caller should fall back to the slower, already-correct libarchive
 * scan in that case. *outCrypted is set to YES if any per-entry
 * encrypted file was found (and skipped) along the way. */
NSArray *CORarParseHeadersAtPath(NSString *path, BOOL *outCrypted);
