#!/usr/bin/env python3

"""Create a minimal RAR4 (STORE method) archive for testing.

No fixture-generation tool for legacy RAR4 was available in the CI/dev
environment when this was written (modern `rar`/`unrar` only create
RAR5 archives) — see docs/tasks/2026-07-14-04-rar-header-parser.md.
This hand-writes the RAR4 block format directly: signature, one
archive header, one STORE-method file header per source file, and an
end header. STORE means the "compressed" bytes are the raw file
bytes, so no RAR compressor is needed to produce a file libarchive
(and CORarHeaderIndex's from-scratch parser) can read correctly.

Block layout and header CRC scope were derived by reading XADMaster's
XADRARParser.m and cross-checked by verifying the output opens
correctly under libarchive's RAR4 reader
(archive_read_support_format_rar).
"""

from __future__ import annotations

import argparse
import pathlib
import struct
import zlib
from dataclasses import dataclass

RAR4_SIGNATURE = bytes([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00])

HEAD_ARCHIVE = 0x73
HEAD_FILE = 0x74
HEAD_END = 0x7B


@dataclass(frozen=True)
class Fixture:
    source_name: str
    archive_name: str


FIXTURES = (
    Fixture("001.png", "001.png"),
    Fixture("002.jpg", "002.jpg"),
    Fixture("003.png", "003.png"),
    Fixture("004.jpg", "004.jpg"),
)


def head_crc(rest: bytes) -> int:
    """HEAD_CRC: low 16 bits of the standard CRC-32 over every header
    byte except HEAD_CRC itself (verified against libarchive's own
    read_header()/MAIN_HEAD CRC checks in archive_read_support_format_rar.c)."""
    return zlib.crc32(rest) & 0xFFFF


def archive_header_block() -> bytes:
    flags = 0x0000
    reserved = b"\x00" * 6
    headsize = 7 + len(reserved)
    rest = struct.pack("<BHH", HEAD_ARCHIVE, flags, headsize) + reserved
    return struct.pack("<H", head_crc(rest)) + rest


def file_header_block(name: str, data: bytes) -> bytes:
    namebytes = name.encode("ascii")
    flags = 0x0000
    typeflags = struct.pack("<BH", HEAD_FILE, flags)
    packsize = struct.pack("<I", len(data))  # PACK_SIZE; counted in HEAD_SIZE
    payload = struct.pack(
        "<IBIIBBHI",
        len(data),  # UNP_SIZE
        3,  # HOST_OS (Unix)
        zlib.crc32(data) & 0xFFFFFFFF,  # FILE_CRC
        0,  # FTIME
        20,  # UNP_VER (2.0)
        0x30,  # METHOD (store, no compression)
        len(namebytes),  # NAME_SIZE
        0o100644,  # FILE_ATTR
    ) + namebytes
    headsize = 7 + len(packsize) + len(payload)
    rest = typeflags + struct.pack("<H", headsize) + packsize + payload
    return struct.pack("<H", head_crc(rest)) + rest + data


def end_header_block() -> bytes:
    rest = struct.pack("<BHH", HEAD_END, 0x0000, 7)
    return struct.pack("<H", head_crc(rest)) + rest


def create_archive(source_dir: pathlib.Path, output_path: pathlib.Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)

    blocks = [RAR4_SIGNATURE, archive_header_block()]
    for fixture in FIXTURES:
        source_path = source_dir / fixture.source_name
        if not source_path.is_file():
            raise FileNotFoundError(f"Source file not found: {source_path}")
        data = source_path.read_bytes()
        blocks.append(file_header_block(fixture.archive_name, data))
    blocks.append(end_header_block())

    output_path.write_bytes(b"".join(blocks))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create a minimal RAR4 (STORE) fixture.")
    parser.add_argument("source_dir", type=pathlib.Path, help="Directory containing 001.png through 004.jpg")
    parser.add_argument("output", type=pathlib.Path, help="Output .cbr path")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    create_archive(source_dir=args.source_dir.resolve(), output_path=args.output.resolve())
    print(f"Created: {args.output}")


if __name__ == "__main__":
    main()
