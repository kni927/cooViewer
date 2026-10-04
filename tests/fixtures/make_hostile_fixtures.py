#!/usr/bin/env python3

"""Create small synthetic archives with hostile metadata for the engine suite.

Written by tests/engine/run_tests.sh into tests/fixtures/generated/ (not
committed). Every payload is a few synthetic bytes, so no image or licence
is involved:

- long_name.cbz: two entries whose path names are about 5000 characters,
  longer than the 1024-unit buffers -finderCompareS: once copied into.
- dotdot.cbz: a page plus a nested archive named "../../escape.zip", whose
  name points outside any directory it is joined to.
- broken_nested.cbz: two pages, a readable nested archive, and a nested
  archive whose stored bytes fail their CRC check, so it cannot be
  extracted.
- rar4_huge_size.cbr: a RAR4 file header with LHD_LARGE whose 64-bit packed
  size runs far past the end of the file.
"""

from __future__ import annotations

import io
import pathlib
import struct
import sys
import zipfile
import zlib

PAGE = b"\xff\xd8 synthetic page \xff\xd9"


def long_name(page: str) -> str:
    # 25 components of 200 characters: each stays under the 255-byte
    # file-name limit, while the whole path is about 5000 characters
    parts = ["d%02d" % i + "x" * 197 for i in range(25)]
    return "/".join(parts) + "/" + page


def write_long_name(path: pathlib.Path) -> None:
    with zipfile.ZipFile(path, "w") as z:
        z.writestr(long_name("002.jpg"), PAGE + b"2")
        z.writestr(long_name("001.jpg"), PAGE + b"1")


def write_dotdot(path: pathlib.Path) -> None:
    inner = io.BytesIO()
    with zipfile.ZipFile(inner, "w") as z:
        z.writestr("inner.jpg", PAGE)
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("001.jpg", PAGE)
        z.writestr("../../escape.zip", inner.getvalue())


def write_broken_nested(path: pathlib.Path) -> None:
    good = io.BytesIO()
    with zipfile.ZipFile(good, "w") as z:
        z.writestr("inner.jpg", PAGE)
    broken = io.BytesIO()
    with zipfile.ZipFile(broken, "w") as z:
        z.writestr("lost.jpg", PAGE + b"BROKEN-NESTED-MARKER")
    with zipfile.ZipFile(path, "w") as z:      # stored: the bytes stay findable
        z.writestr("001.jpg", PAGE + b"1")
        z.writestr("broken.zip", broken.getvalue())
        z.writestr("good.zip", good.getvalue())
        z.writestr("002.jpg", PAGE + b"2")
    # flip one byte inside broken.zip's stored data, so that entry fails its
    # CRC check when it is extracted while every other entry stays intact
    data = bytearray(path.read_bytes())
    at = data.index(b"BROKEN-NESTED-MARKER")
    data[at] ^= 0xFF
    path.write_bytes(bytes(data))


def rar4_block(htype: int, flags: int, body: bytes) -> bytes:
    rest = struct.pack("<BHH", htype, flags, 7 + len(body)) + body
    return struct.pack("<H", zlib.crc32(rest) & 0xFFFF) + rest


def write_rar4_huge_size(path: pathlib.Path) -> None:
    name = b"001.jpg"
    lhd_large, long_block = 0x0100, 0x8000
    body = struct.pack("<IIBIIBBHI", len(PAGE), len(PAGE), 3, zlib.crc32(PAGE), 0, 20,
                       0x30, len(name), 0o100644)
    body += struct.pack("<II", 0x7FFFFFFF, 0)  # HIGH_PACK_SIZE, HIGH_UNP_SIZE
    body += name
    data = (b"Rar!\x1a\x07\x00"
            + rar4_block(0x73, 0, b"\x00" * 6)
            + rar4_block(0x74, lhd_large | long_block, body) + PAGE
            + rar4_block(0x7B, 0, b""))
    path.write_bytes(data)


def main() -> None:
    out = pathlib.Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    write_long_name(out / "long_name.cbz")
    write_dotdot(out / "dotdot.cbz")
    write_broken_nested(out / "broken_nested.cbz")
    write_rar4_huge_size(out / "rar4_huge_size.cbr")


if __name__ == "__main__":
    main()
