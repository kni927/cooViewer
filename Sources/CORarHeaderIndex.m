//
//  CORarHeaderIndex.m
//  cooViewer
//
//  See CORarHeaderIndex.h for the design notes. Header-format
//  knowledge (block layouts, flag bits, RAR5 vint encoding) is
//  derived from XADMaster's XADRARParser.m / XADRAR5Parser.m
//  (Copyright (c) 2017-present, MacPaw Inc., LGPL-2.1-or-later).
//

#import "CORarHeaderIndex.h"
#include <stdio.h>
#include <string.h>

@implementation CORarHeaderEntry
- (void)dealloc
{
	[rawName release];
	[utf8Name release];
	[super dealloc];
}
@end

#pragma mark - low-level readers

static BOOL ReadBytes(FILE *f, void *buf, size_t n)
{
	if (n == 0) return YES;
	return fread(buf, 1, n, f) == n;
}

static BOOL ReadU8(FILE *f, uint8_t *out)
{
	int c = fgetc(f);
	if (c == EOF) return NO;
	*out = (uint8_t)c;
	return YES;
}

static BOOL ReadU16LE(FILE *f, uint16_t *out)
{
	uint8_t b[2];
	if (!ReadBytes(f, b, 2)) return NO;
	*out = (uint16_t)(b[0] | (b[1] << 8));
	return YES;
}

static BOOL ReadU32LE(FILE *f, uint32_t *out)
{
	uint8_t b[4];
	if (!ReadBytes(f, b, 4)) return NO;
	*out = (uint32_t)b[0] | ((uint32_t)b[1] << 8) |
	       ((uint32_t)b[2] << 16) | ((uint32_t)b[3] << 24);
	return YES;
}

/* RAR5 variable-length integer: 7 payload bits per byte, LSB group
 * first, bit 7 is the continuation flag. */
static BOOL ReadVInt(FILE *f, uint64_t *out)
{
	uint64_t res = 0;
	int pos = 0;
	for (;;) {
		int c = fgetc(f);
		if (c == EOF) return NO;
		uint8_t byte = (uint8_t)c;
		res |= ((uint64_t)(byte & 0x7f)) << pos;
		if (!(byte & 0x80)) { *out = res; return YES; }
		pos += 7;
		if (pos > 63) return NO;	// malformed: refuse to wrap
	}
}

/* base filename (after the last '/' or '\') starts with "._" */
static BOOL IsAppleDoubleName(const uint8_t *bytes, NSUInteger length)
{
	NSUInteger base = 0;
	for (NSUInteger i = 0; i < length; i++)
		if (bytes[i] == '/' || bytes[i] == '\\') base = i + 1;
	return (length - base >= 2) && bytes[base] == '.' && bytes[base + 1] == '_';
}

static CORarHeaderEntry *MakeEntry(NSData *rawName, NSString *utf8Name,
                                    unsigned long long compressedSize,
                                    unsigned long long uncompressedSize,
                                    BOOL hasUncompressedSize,
                                    BOOL hasFileCRC, uint32_t fileCRC)
{
	CORarHeaderEntry *e = [[[CORarHeaderEntry alloc] init] autorelease];
	e->rawName = [rawName retain];
	e->utf8Name = [utf8Name retain];
	e->compressedSize = compressedSize;
	e->uncompressedSize = uncompressedSize;
	e->hasUncompressedSize = hasUncompressedSize;
	e->hasFileCRC = hasFileCRC;
	e->fileCRC = fileCRC;
	return e;
}

#pragma mark - RAR5

static const uint8_t kRAR5Sig[8] = {'R','a','r','!',0x1a,0x07,0x01,0x00};

#define RAR5_HDR_MAIN       1
#define RAR5_HDR_FILE       2
#define RAR5_HDR_ENCRYPTION 4
#define RAR5_HDR_END        5

#define RAR5_ARCHIVEFLAG_VOLUME 0x0001

static NSMutableArray *ParseRAR5(FILE *f, off_t fileSize, BOOL *outCrypted, BOOL *outUnsupported)
{
	*outCrypted = NO;
	*outUnsupported = NO;

	if (fseeko(f, 0, SEEK_SET) != 0) return nil;
	uint8_t sig[8];
	if (!ReadBytes(f, sig, 8)) return nil;
	if (memcmp(sig, kRAR5Sig, 8) != 0) return nil;	// not RAR5

	// main archive header: crc(4) + headersize(vint); block.start is
	// captured *after* headersize, matching XADRAR5Parser's own
	// -endOfBlockHeader: arithmetic
	uint32_t crc32;
	uint64_t headersize, type, flags, extrasize, datasize;
	if (!ReadU32LE(f, &crc32)) return nil;
	if (!ReadVInt(f, &headersize)) return nil;
	off_t blockStart = ftello(f);
	if (!ReadVInt(f, &type)) return nil;
	if (!ReadVInt(f, &flags)) return nil;
	extrasize = 0; datasize = 0;
	if (flags & 0x0001) { if (!ReadVInt(f, &extrasize)) return nil; }
	if (flags & 0x0002) { if (!ReadVInt(f, &datasize)) return nil; }
	if (type != RAR5_HDR_MAIN) return nil;

	uint64_t archiveFlags;
	if (!ReadVInt(f, &archiveFlags)) return nil;
	if (archiveFlags & RAR5_ARCHIVEFLAG_VOLUME) { *outUnsupported = YES; return nil; }

	if (headersize > (uint64_t)fileSize) return nil;
	if (fseeko(f, blockStart + (off_t)headersize, SEEK_SET) != 0) return nil;

	NSMutableArray *entries = [NSMutableArray array];

	for (;;) {
		if (!ReadU32LE(f, &crc32)) break;	// clean EOF, done
		if (!ReadVInt(f, &headersize)) return nil;
		blockStart = ftello(f);
		if (!ReadVInt(f, &type)) return nil;
		if (!ReadVInt(f, &flags)) return nil;
		extrasize = 0; datasize = 0;
		if (flags & 0x0001) { if (!ReadVInt(f, &extrasize)) return nil; }
		if (flags & 0x0002) { if (!ReadVInt(f, &datasize)) return nil; }

		if (headersize > (uint64_t)fileSize || datasize > (uint64_t)fileSize) return nil;
		off_t headerEnd = blockStart + (off_t)headersize;

		if (type == RAR5_HDR_END) {
			break;
		} else if (type == RAR5_HDR_ENCRYPTION) {
			*outUnsupported = YES;	// header encryption: can't read further
			return nil;
		} else if (type == RAR5_HDR_FILE) {
			uint64_t fileflags, uncompsize = 0, attributes, compinfo = 0, osval, namelength;
			if (!ReadVInt(f, &fileflags)) return nil;
			if (!ReadVInt(f, &uncompsize)) return nil;
			if (!ReadVInt(f, &attributes)) return nil;
			(void)attributes;

			BOOL isDirectory = (fileflags & 0x0001) != 0;
			BOOL unknownSize = (fileflags & 0x0008) != 0;
			BOOL hasFileCRC = (fileflags & 0x0004) != 0;
			uint32_t fileCRC = 0;

			if (fileflags & 0x0002) { uint32_t mtime; if (!ReadU32LE(f, &mtime)) return nil; }
			if (hasFileCRC && !ReadU32LE(f, &fileCRC)) return nil;
			if (!isDirectory) { if (!ReadVInt(f, &compinfo)) return nil; }
			(void)compinfo;
			if (!ReadVInt(f, &osval)) return nil;
			(void)osval;
			if (!ReadVInt(f, &namelength)) return nil;
			if (namelength > 65535) return nil;

			NSMutableData *nameBuf = [NSMutableData dataWithLength:(NSUInteger)namelength];
			if (namelength > 0 && !ReadBytes(f, [nameBuf mutableBytes], (size_t)namelength))
				return nil;

			// multi-volume continuation (0x0008 = not first part,
			// 0x0010 = not last part): defer, don't reassemble
			if (flags & 0x0018) { *outUnsupported = YES; return nil; }

			BOOL entryEncrypted = NO;
			if (extrasize > 0) {
				off_t pos = ftello(f);
				off_t guard = 0;
				while (pos < headerEnd && guard++ < 64) {
					uint64_t recSize, recType;
					off_t recStart;
					if (!ReadVInt(f, &recSize)) break;
					recStart = ftello(f);
					if (!ReadVInt(f, &recType)) break;
					if (recType == 0x01) entryEncrypted = YES;	// file encryption record
					if (recSize == 0) break;
					if (fseeko(f, recStart + (off_t)recSize, SEEK_SET) != 0) break;
					pos = ftello(f);
				}
			}

			if (isDirectory) {
				// no entry
			} else if (entryEncrypted) {
				*outCrypted = YES;
			} else if (uncompsize == 0 && !unknownSize) {
				// zero-byte entry, skip
			} else if (!IsAppleDoubleName([nameBuf bytes], [nameBuf length])) {
				NSString *u8 = [[NSString alloc] initWithData:nameBuf encoding:NSUTF8StringEncoding];
				// RAR5 names are UTF-8 by spec; if that somehow fails,
				// fall through with rawName only (shared uchardet path)
				[entries addObject:MakeEntry(nameBuf, [u8 autorelease], datasize, uncompsize,
				                                  !unknownSize, hasFileCRC, fileCRC)];
			}
		}
		// type 3 (Service) and anything unrecognized: nothing extra
		// to read, just seek past via headerEnd+datasize below

		off_t next = headerEnd + (off_t)datasize;
		if (next <= blockStart) return nil;	// must move strictly forward
		if (next >= fileSize) break;
		if (fseeko(f, next, SEEK_SET) != 0) break;
	}

	return entries;
}

#pragma mark - RAR4

static const uint8_t kRAR4Sig[7] = {'R','a','r','!',0x1a,0x07,0x00};

#define MHD_VOLUME    0x0001
#define MHD_PASSWORD  0x0080

#define LHD_SPLIT_BEFORE 0x0001
#define LHD_SPLIT_AFTER  0x0002
#define LHD_PASSWORD     0x0004
#define LHD_UNICODE      0x0200
#define LHD_LARGE        0x0100
#define LHD_WINDOWMASK   0x00e0
#define LHD_DIRECTORY    0x00e0

#define RARFLAG_LONG_BLOCK 0x8000

#define RAR4_BLOCK_ARCHIVE 0x73
#define RAR4_BLOCK_FILE    0x74
#define RAR4_BLOCK_END     0x7b

static NSMutableArray *ParseRAR4(FILE *f, off_t fileSize, BOOL *outCrypted, BOOL *outUnsupported)
{
	*outCrypted = NO;
	*outUnsupported = NO;

	if (fseeko(f, 0, SEEK_SET) != 0) return nil;
	uint8_t sig[7];
	if (!ReadBytes(f, sig, 7)) return nil;
	if (memcmp(sig, kRAR4Sig, 7) != 0) return nil;	// not RAR4

	NSMutableArray *entries = [NSMutableArray array];
	uint16_t archiveflags = 0;

	for (;;) {
		off_t blockStart = ftello(f);
		uint16_t crc16, flags, headersize;
		uint8_t type;
		if (!ReadU16LE(f, &crc16)) break;	// clean EOF
		if (!ReadU8(f, &type)) return nil;
		if (!ReadU16LE(f, &flags)) return nil;
		if (!ReadU16LE(f, &headersize)) return nil;
		if (headersize < 7) return nil;	// malformed

		uint32_t datasize32 = 0;
		if ((flags & RARFLAG_LONG_BLOCK) || type == RAR4_BLOCK_FILE) {
			if (!ReadU32LE(f, &datasize32)) return nil;
		}
		unsigned long long datasize = datasize32;

		off_t datastart = blockStart + (off_t)headersize;
		if (datastart < blockStart || headersize > fileSize) return nil;

		if (type == RAR4_BLOCK_ARCHIVE) {
			archiveflags = flags;
			if (archiveflags & MHD_VOLUME) { *outUnsupported = YES; return nil; }
			if (archiveflags & MHD_PASSWORD) { *outUnsupported = YES; return nil; }
		} else if (type == RAR4_BLOCK_FILE) {
			uint32_t size32, filecrc, dostime, attrs;
			uint8_t os, version, method;
			uint16_t namelength;
			if (!ReadU32LE(f, &size32)) return nil;
			if (!ReadU8(f, &os)) return nil;
			if (!ReadU32LE(f, &filecrc)) return nil;
			if (!ReadU32LE(f, &dostime)) return nil;
			(void)dostime;
			if (!ReadU8(f, &version)) return nil;
			if (!ReadU8(f, &method)) return nil;
			(void)method;
			if (!ReadU16LE(f, &namelength)) return nil;
			if (!ReadU32LE(f, &attrs)) return nil;

			unsigned long long size = size32;
			if (flags & LHD_LARGE) {
				uint32_t highpack, highunp;
				if (!ReadU32LE(f, &highpack)) return nil;
				if (!ReadU32LE(f, &highunp)) return nil;
				datasize += ((unsigned long long)highpack) << 32;
				size += ((unsigned long long)highunp) << 32;
			}

			if (namelength > 65535) return nil;
			NSMutableData *nameBuf = [NSMutableData dataWithLength:namelength];
			if (namelength > 0 && !ReadBytes(f, [nameBuf mutableBytes], namelength))
				return nil;

			// multi-volume split file: defer, don't reassemble
			if (flags & (LHD_SPLIT_BEFORE | LHD_SPLIT_AFTER)) { *outUnsupported = YES; return nil; }

			// LHD_UNICODE uses a bespoke run-length name encoding;
			// there is no RAR4-Unicode fixture in this repo to verify
			// a from-scratch port against, so defer to the fallback
			// rather than risk silently wrong filenames (see header).
			if (flags & LHD_UNICODE) { *outUnsupported = YES; return nil; }

			BOOL isDirectory = ((flags & LHD_WINDOWMASK) == LHD_DIRECTORY) ||
			                   (version == 15 && os == 0 && (attrs & 0x10));
			BOOL isEncrypted = (flags & LHD_PASSWORD) != 0;

			if (isDirectory) {
				// no entry
			} else if (isEncrypted) {
				*outCrypted = YES;
			} else if (size == 0) {
				// zero-byte entry, skip
			} else if (!IsAppleDoubleName([nameBuf bytes], [nameBuf length])) {
				[entries addObject:MakeEntry(nameBuf, nil, datasize, size,
				                                  YES, YES, filecrc)];
			}
		}

		if (type == RAR4_BLOCK_END) break;

		off_t next = datastart + (off_t)datasize;
		if (next <= blockStart) return nil;
		if (next >= fileSize) break;
		if (fseeko(f, next, SEEK_SET) != 0) break;
	}

	return entries;
}

#pragma mark - public entry point

NSArray *CORarParseHeadersAtPath(NSString *path, BOOL *outCrypted)
{
	FILE *f = fopen([path fileSystemRepresentation], "rb");
	if (!f) return nil;

	if (fseeko(f, 0, SEEK_END) != 0) { fclose(f); return nil; }
	off_t fileSize = ftello(f);
	if (fileSize < 8) { fclose(f); return nil; }

	BOOL crypted = NO, unsupported = NO;
	NSMutableArray *entries = ParseRAR5(f, fileSize, &crypted, &unsupported);
	if (!entries && !unsupported) {
		crypted = NO;
		entries = ParseRAR4(f, fileSize, &crypted, &unsupported);
	}

	fclose(f);

	if (!entries) return nil;
	*outCrypted = crypted;
	return entries;
}
