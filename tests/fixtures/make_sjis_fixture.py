#!/usr/bin/env python3

"""Create a ZIP archive with CP932-encoded Japanese filenames.

The archive deliberately:

- encodes filenames using CP932
- leaves ZIP general-purpose bit 11 unset
- does not add Unicode Path extra fields
- uses raw DEFLATE compression
- uses fixed timestamps for reproducible output

This represents legacy Japanese Windows ZIP archives whose filename
encoding is not explicitly declared in the ZIP metadata.
"""

from __future__ import annotations

import argparse
import binascii
import pathlib
import struct
import zlib
from dataclasses import dataclass


LOCAL_FILE_HEADER_SIGNATURE = 0x04034B50
CENTRAL_DIRECTORY_SIGNATURE = 0x02014B50
END_OF_CENTRAL_DIRECTORY_SIGNATURE = 0x06054B50

ZIP_VERSION_20 = 20
COMPRESSION_DEFLATE = 8

# Deliberately do not set bit 11 (UTF-8 filename flag).
GENERAL_PURPOSE_FLAGS = 0

# Fixed DOS timestamp: 2026-01-01 00:00:00
DOS_TIME = 0
DOS_DATE = ((2026 - 1980) << 9) | (1 << 5) | 1


@dataclass(frozen=True)
class Fixture:
    source_name: str
    archive_name: str


FIXTURES = (
    Fixture("001.png", "001_表紙.png"),
    Fixture("002.jpg", "002_縦長表示.jpg"),
    Fixture("003.png", "003_網点とカケアミ.png"),
    Fixture("004.jpg", "004_拡大縮小.jpg"),
)


@dataclass
class CentralDirectoryEntry:
    filename: bytes
    crc32: int
    compressed_size: int
    uncompressed_size: int
    local_header_offset: int


def raw_deflate(data: bytes) -> bytes:
    """Return a raw DEFLATE stream suitable for a ZIP entry."""
    compressor = zlib.compressobj(
        level=9,
        method=zlib.DEFLATED,
        wbits=-zlib.MAX_WBITS,
    )
    return compressor.compress(data) + compressor.flush()


def create_archive(source_dir: pathlib.Path, output_path: pathlib.Path) -> None:
    entries: list[CentralDirectoryEntry] = []

    output_path.parent.mkdir(parents=True, exist_ok=True)

    with output_path.open("wb") as archive:
        for fixture in FIXTURES:
            source_path = source_dir / fixture.source_name

            if not source_path.is_file():
                raise FileNotFoundError(f"Source file not found: {source_path}")

            data = source_path.read_bytes()
            compressed = raw_deflate(data)
            filename = fixture.archive_name.encode("cp932")

            crc32 = binascii.crc32(data) & 0xFFFFFFFF
            local_header_offset = archive.tell()

            local_header = struct.pack(
                "<IHHHHHIIIHH",
                LOCAL_FILE_HEADER_SIGNATURE,
                ZIP_VERSION_20,
                GENERAL_PURPOSE_FLAGS,
                COMPRESSION_DEFLATE,
                DOS_TIME,
                DOS_DATE,
                crc32,
                len(compressed),
                len(data),
                len(filename),
                0,  # Extra field length
            )

            archive.write(local_header)
            archive.write(filename)
            archive.write(compressed)

            entries.append(
                CentralDirectoryEntry(
                    filename=filename,
                    crc32=crc32,
                    compressed_size=len(compressed),
                    uncompressed_size=len(data),
                    local_header_offset=local_header_offset,
                )
            )

        central_directory_offset = archive.tell()

        for entry in entries:
            central_header = struct.pack(
                "<IHHHHHHIIIHHHHHII",
                CENTRAL_DIRECTORY_SIGNATURE,
                0x0314,  # Created by Unix, ZIP version 2.0
                ZIP_VERSION_20,
                GENERAL_PURPOSE_FLAGS,
                COMPRESSION_DEFLATE,
                DOS_TIME,
                DOS_DATE,
                entry.crc32,
                entry.compressed_size,
                entry.uncompressed_size,
                len(entry.filename),
                0,  # Extra field length
                0,  # Comment length
                0,  # Disk number
                0,  # Internal attributes
                0o100644 << 16,  # Unix regular-file permissions
                entry.local_header_offset,
            )

            archive.write(central_header)
            archive.write(entry.filename)

        central_directory_size = archive.tell() - central_directory_offset

        end_record = struct.pack(
            "<IHHHHIIH",
            END_OF_CENTRAL_DIRECTORY_SIGNATURE,
            0,  # Current disk
            0,  # Central directory disk
            len(entries),
            len(entries),
            central_directory_size,
            central_directory_offset,
            0,  # ZIP comment length
        )

        archive.write(end_record)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create a CP932 filename ZIP fixture."
    )
    parser.add_argument(
        "source_dir",
        type=pathlib.Path,
        help="Directory containing 001.png through 004.jpg",
    )
    parser.add_argument(
        "output",
        type=pathlib.Path,
        help="Output ZIP path",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    create_archive(
        source_dir=args.source_dir.resolve(),
        output_path=args.output.resolve(),
    )
    print(f"Created: {args.output}")


if __name__ == "__main__":
    main()