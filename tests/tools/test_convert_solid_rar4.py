#!/usr/bin/env python3
"""Tests for tools/convert_solid_rar4.py.

Fixtures are generated into a temporary folder and removed afterwards.
RAR4 archives are written by hand (rar 7.x can no longer create RAR4), so
their data is STORE with the solid flags set, as in
tests/fixtures/make_rar4_fixture.py; a RAR5 archive is made with `rar`
when it is installed. Conversion runs need 7zz and/or unar; cases whose
extractor is missing are skipped. The Trash is never touched: the
--delete-originals cases replace the trash step with a recorder.

    /usr/bin/python3 tests/tools/test_convert_solid_rar4.py
"""

from __future__ import annotations

import contextlib
import io
import os
import pathlib
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile
import zlib
from unittest import mock

REPO = pathlib.Path(__file__).resolve().parents[2]
TOOL = REPO / "tools" / "convert_solid_rar4.py"
SRC = REPO / "tests" / "fixtures" / "src"
RAR = shutil.which("rar")
HAVE_7ZZ = shutil.which("7zz") is not None
HAVE_UNAR = shutil.which("unar") is not None and shutil.which("lsar") is not None

sys.dont_write_bytecode = True
sys.path.insert(0, str(REPO / "tools"))
import convert_solid_rar4 as tool  # noqa: E402

RAR4_SIG = b"Rar!\x1a\x07\x00"
MHD_VOLUME, MHD_SOLID, MHD_PASSWORD, MHD_FIRSTVOLUME = 0x0001, 0x0008, 0x0080, 0x0100
LHD_PASSWORD, LHD_SOLID, LHD_UNICODE, LHD_DIRECTORY = 0x0004, 0x0010, 0x0200, 0x00E0

PAGES = {name: (SRC / name).read_bytes() for name in ("001.png", "002.jpg", "003.png", "004.jpg")}
MTIME_NS = 1_000_000_000 * 1_200_000_000  # 2008-01-10, an "old" book


def rar4_block(htype, flags, body=b"", add=None):
    if add is not None:
        flags |= 0x8000
        body = struct.pack("<I", add) + body
    rest = struct.pack("<BHH", htype, flags, 7 + len(body)) + body
    return struct.pack("<H", zlib.crc32(rest) & 0xFFFF) + rest


def rar4_file(raw_name, data, flags=0, crc=None):
    """A STORE file header; raw_name is bytes as stored in the header."""
    body = struct.pack("<IBIIBBHI", len(data), 3,
                       zlib.crc32(data) if crc is None else crc,
                       0x3C210000,  # 2010-01-01 DOS time
                       20, 0x30, len(raw_name), 0o040755 if flags & LHD_DIRECTORY == LHD_DIRECTORY
                       else 0o100644) + raw_name
    return rar4_block(0x74, flags, body, add=len(data)) + data


def rar4_archive(entries, main_flags=MHD_SOLID):
    """entries: (raw name, data, extra flags[, stored crc]); file headers
    after the first get LHD_SOLID when the archive is solid."""
    blocks = [RAR4_SIG, rar4_block(0x73, main_flags, b"\x00" * 6)]
    for i, entry in enumerate(entries):
        raw_name, data, flags = entry[:3]
        crc = entry[3] if len(entry) > 3 else None
        if main_flags & MHD_SOLID and i:
            flags |= LHD_SOLID
        blocks.append(rar4_file(raw_name, data, flags, crc))
    blocks.append(rar4_block(0x7B, 0))
    return b"".join(blocks)


def u(name):
    return name.encode("utf-8")


def encname(name):
    """RAR 3.x name field for LHD_UNICODE: the OEM (cp932) name, NUL, then
    the compressed Unicode form (technote "Unicode file names"). Every
    character uses opcode 2 (two bytes, low first) after a HighByte of 0."""
    name = name.replace("/", "\\")
    enc = bytearray([0])
    chars = [ord(c) for c in name]
    for i in range(0, len(chars), 4):
        group = chars[i:i + 4]
        enc.append(int("10" * len(group) + "00" * (4 - len(group)), 2))
        for c in group:
            enc += struct.pack("<H", c)
    return name.encode("cp932") + b"\x00" + bytes(enc)


def snapshot(root):
    state = {}
    for dirpath, dirnames, filenames in os.walk(root):
        for name in dirnames + filenames:
            p = os.path.join(dirpath, name)
            st = os.lstat(p)
            state[p] = (st.st_mode, st.st_size, st.st_mtime_ns)
    return state


# name in the ZIP -> page bytes, in archive order
EXPECTED = {
    "solid_jp.cbz": [("表紙/001_表紙.png", PAGES["001.png"]),
                     ("002.jpg", PAGES["002.jpg"]),
                     ("003_網点とカケアミ.png", PAGES["003.png"]),
                     ("004.jpg", PAGES["004.jpg"])],
    "solid_ascii.zip": [(n, PAGES[n]) for n in PAGES],
    "UPPER.CBZ": [("001.png", PAGES["001.png"])],
    "solid_encname.cbz": [("縦長/002_縦長表示.jpg", PAGES["002.jpg"]),
                          ("001.png", PAGES["001.png"])],
    "solid_legacy.cbz": [("表紙.jpg", PAGES["002.jpg"]),
                         ("ソフト/001.png", PAGES["001.png"])],
}

CONVERTIBLE = ("solid_jp.cbr", "solid_ascii.rar", "UPPER.CBR", "solid_encname.cbr",
               "solid_legacy.cbr", "corrupt.cbr")

SKIPS = {
    "plain_rar4.cbr": "not solid",
    "r5_solid.cbr": "RAR5",
    "zip_named.cbr": "not RAR (ZIP)",
    "exists.cbr": "target exists",
    "crypt_headers.cbr": "header-encrypted",
    "volume.part1.rar": "multi-volume",
    "password.cbr": "password-protected",
}
# skip reasons of files that are not solid RAR4: summary only by default
UNLISTED = ("not solid", "RAR5", "not RAR (ZIP)")


def make_books(root):
    root.mkdir(parents=True)
    p = PAGES
    books = {
        "solid_jp.cbr": rar4_archive([
            (u("表紙"), b"", LHD_UNICODE | LHD_DIRECTORY),
            (u("表紙\\001_表紙.png"), p["001.png"], LHD_UNICODE),
            (u("002.jpg"), p["002.jpg"], 0),
            (u("__MACOSX\\._002.jpg"), b"\x00\x05\x16\x07appledouble", 0),
            (u("003_網点とカケアミ.png"), p["003.png"], LHD_UNICODE),
            (u(".DS_Store"), b"\x00\x00\x00\x01Bud1", 0),
            (u("004.jpg"), p["004.jpg"], 0),
        ]),
        "solid_ascii.rar": rar4_archive([(u(n), d, 0) for n, d in p.items()]),
        "UPPER.CBR": rar4_archive([(u("001.png"), p["001.png"], 0)]),
        # WinRAR 3.x style: OEM name + NUL + compressed Unicode name
        "solid_encname.cbr": rar4_archive([
            (encname("縦長/002_縦長表示.jpg"), p["002.jpg"], LHD_UNICODE),
            (u("001.png"), p["001.png"], 0),
        ]),
        # Shift_JIS names without LHD_UNICODE; both have a 0x5C trail byte
        "solid_legacy.cbr": rar4_archive([
            ("表紙.jpg".encode("cp932"), p["002.jpg"], 0),
            ("ソフト\\001.png".encode("cp932"), p["001.png"], 0),
        ]),
        # stored CRC does not match the data
        "corrupt.cbr": rar4_archive([(u("001.png"), p["001.png"], 0),
                                     (u("002.jpg"), p["002.jpg"], 0, 0x12345678)]),
        "plain_rar4.cbr": rar4_archive([(u("001.png"), p["001.png"], 0)], main_flags=0),
        "exists.cbr": rar4_archive([(u("001.png"), p["001.png"], 0)]),
        "exists.cbz": b"already here",
        "crypt_headers.cbr": RAR4_SIG + rar4_block(0x73, MHD_SOLID | MHD_PASSWORD, b"\x00" * 6)
                             + bytes(range(256)),
        "volume.part1.rar": rar4_archive([(u("001.png"), p["001.png"], 0x0002)],
                                         main_flags=MHD_SOLID | MHD_VOLUME | MHD_FIRSTVOLUME),
        "password.cbr": rar4_archive([(u("001.png"), p["001.png"], 0),
                                      (u("002.jpg"), p["002.jpg"], LHD_PASSWORD)]),
    }
    for name, data in books.items():
        (root / name).write_bytes(data)
        if name.endswith((".cbr", ".rar", ".CBR")):
            os.utime(root / name, ns=(MTIME_NS, MTIME_NS))
    with zipfile.ZipFile(root / "zip_named.cbr", "w") as z:
        z.writestr("001.jpg", p["002.jpg"])
    if RAR:
        work = root.parent / "rar5work"
        work.mkdir()
        for n, d in p.items():
            (work / n).write_bytes(d)
        subprocess.run([RAR, "a", "-idq", "-ep", "-s", str(root / "r5_solid.cbr")] + list(p),
                       cwd=work, check=True)
        shutil.rmtree(work)
    else:
        (root / "r5_solid.cbr").write_bytes(b"Rar!\x1a\x07\x01\x00" + b"\x00" * 16)


def run_tool(*args):
    proc = subprocess.run([sys.executable, "-B", str(TOOL)] + [str(a) for a in args],
                          capture_output=True, text=True)
    return proc


def run_main(*args):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        status = tool.main([str(a) for a in args])
    return status, out.getvalue()


class ConvertTestBase(unittest.TestCase):
    def setUp(self):
        self.tmp = pathlib.Path(tempfile.mkdtemp(prefix="convert_rar4_test."))
        self.root = self.tmp / "books"
        make_books(self.root)

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def line_for(self, output, name):
        mark = os.sep + name
        lines = [l for l in output.splitlines() if not l.startswith(" ")  # summary list
                 and (l.endswith(mark) or mark + " -> " in l or mark + ": " in l)]
        self.assertEqual(len(lines), 1, "%s in:\n%s" % (name, output))
        return lines[0]

    def assertConverted(self, target):
        path = self.root / target
        self.assertTrue(path.is_file(), target)
        with zipfile.ZipFile(path) as z:
            infos = z.infolist()
            self.assertEqual([i.filename for i in infos], [n for n, _ in EXPECTED[target]])
            for info, (_name, data) in zip(infos, EXPECTED[target]):
                self.assertEqual(info.compress_type, zipfile.ZIP_STORED)
                self.assertTrue(info.flag_bits & 0x800, info.filename)
                self.assertEqual(z.read(info), data, info.filename)
            self.assertIsNone(z.testzip())
        self.assertEqual(path.stat().st_mtime_ns, MTIME_NS)

    def assertNoLeftovers(self):
        names = os.listdir(self.root)
        self.assertEqual([n for n in names if n.endswith(".partial")], [])


class DryRunTest(ConvertTestBase):
    def test_dry_run_writes_nothing(self):
        before = snapshot(self.tmp)
        proc = run_tool(self.root)
        self.assertEqual(snapshot(self.tmp), before)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        out = proc.stdout
        for name in CONVERTIBLE:
            self.assertTrue(self.line_for(out, name).startswith("would convert: "))
        self.assertIn("solid_ascii.rar -> solid_ascii.zip", out)
        self.assertIn("UPPER.CBR -> UPPER.CBZ", out)
        self.assertIn("[legacy names, cp932, needs unar]", self.line_for(out, "solid_legacy.cbr"))
        for name, reason in SKIPS.items():
            if reason in UNLISTED:
                self.assertNotIn(os.sep + name, out)
            else:
                line = self.line_for(out, name)
                self.assertTrue(line.startswith("skip (%s" % reason), line)
        self.assertIn("would convert: %d" % len(CONVERTIBLE), out)
        self.assertIn("dry run, nothing written", out)
        for reason in UNLISTED:
            self.assertRegex(out, r"skipped, %s.*: 1 \(not listed; --list-all lists them\)"
                             % re.escape(reason))

    def test_list_all(self):
        proc = run_tool("--list-all", self.root)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        for name, reason in SKIPS.items():
            line = self.line_for(proc.stdout, name)
            self.assertTrue(line.startswith("skip (%s" % reason), line)
        self.assertNotIn("not listed", proc.stdout)

    def test_delete_needs_convert(self):
        proc = run_tool("--delete-originals", self.root)
        self.assertEqual(proc.returncode, 2)
        self.assertIn("--delete-originals needs --convert", proc.stderr)

    def test_help_mentions_online_only(self):
        proc = run_tool("--help")
        self.assertEqual(proc.returncode, 0)
        self.assertIn("online-only", proc.stdout)
        self.assertIn("will sync", proc.stdout)


class ConvertTest(ConvertTestBase):
    def check_common(self, proc):
        out = proc.stdout
        # corrupt.cbr fails, so the run reports failure but carries on
        self.assertEqual(proc.returncode, 1, out + proc.stderr)
        self.assertTrue(self.line_for(out, "corrupt.cbr").startswith("FAILED: "))
        self.assertFalse((self.root / "corrupt.cbz").exists())
        self.assertConverted("solid_jp.cbz")
        self.assertConverted("solid_ascii.zip")
        self.assertConverted("UPPER.CBZ")
        self.assertConverted("solid_encname.cbz")
        line = self.line_for(out, "solid_jp.cbr")
        self.assertIn("(4 pages", line)
        for left in ("directory entry 表紙", "macOS metadata __MACOSX/._002.jpg",
                     "macOS metadata .DS_Store"):
            self.assertIn("  left out " + left, out)
        # originals stay; skipped books get no target
        for name in CONVERTIBLE + tuple(SKIPS):
            self.assertTrue((self.root / name).exists(), name)
        self.assertEqual((self.root / "exists.cbz").read_bytes(), b"already here")
        for name in ("plain_rar4.cbz", "r5_solid.cbz", "zip_named.cbz", "password.cbz",
                     "crypt_headers.cbz", "volume.part1.zip"):
            self.assertFalse((self.root / name).exists(), name)
        self.assertNoLeftovers()
        return out

    @unittest.skipUnless(HAVE_7ZZ, "7zz not installed")
    def test_convert_7zz(self):
        out = self.check_common(run_tool("--convert", "--extractor", "7zz", self.root))
        self.assertIn("needs unar", self.line_for(out, "solid_legacy.cbr"))
        self.assertFalse((self.root / "solid_legacy.cbz").exists())
        self.assertIn("failed: 2", out)

    @unittest.skipUnless(HAVE_UNAR, "unar not installed")
    def test_convert_unar(self):
        out = self.check_common(run_tool("--convert", "--extractor", "unar", self.root))
        self.assertConverted("solid_legacy.cbz")
        self.assertIn("failed: 1", out)

    @unittest.skipUnless(HAVE_7ZZ and HAVE_UNAR, "needs both 7zz and unar")
    def test_convert_auto(self):
        out = self.check_common(run_tool("--convert", self.root))
        self.assertConverted("solid_legacy.cbz")
        self.assertIn(", unar)", self.line_for(out, "solid_legacy.cbr"))
        self.assertIn(", 7zz)", self.line_for(out, "solid_jp.cbr"))
        self.assertIn("converted: 5", out)


@unittest.skipUnless(HAVE_7ZZ or HAVE_UNAR, "no extractor installed")
class VerifyTest(ConvertTestBase):
    def setUp(self):
        super().setUp()
        self.book = self.root / "solid_ascii.rar"
        self.pages = [(n, n, len(d), zlib.crc32(d)) for n, d in PAGES.items()]
        self.good = self.tmp / "good.zip"
        with zipfile.ZipFile(self.good, "w") as z:
            for n, d in PAGES.items():
                info = tool.Utf8ZipInfo(n, (2010, 1, 1, 0, 0, 0))
                z.writestr(info, d)

    def test_good_zip_passes(self):
        tool.verify_zip(str(self.good), self.pages)

    def test_flipped_byte_is_caught(self):
        data = bytearray(self.good.read_bytes())
        data[100] ^= 0xFF  # inside the first entry's stored data
        bad = self.tmp / "flipped.zip"
        bad.write_bytes(bytes(data))
        with self.assertRaisesRegex(tool.BookError, "CRC"):
            tool.verify_zip(str(bad), self.pages)

    def test_replaced_entry_is_caught(self):
        bad = self.tmp / "replaced.zip"
        with zipfile.ZipFile(bad, "w") as z:
            for n, d in PAGES.items():
                z.writestr(tool.Utf8ZipInfo(n), d if n != "003.png" else d[:-1] + b"\x00")
        with self.assertRaisesRegex(tool.BookError, "size/CRC differ"):
            tool.verify_zip(str(bad), self.pages)

    def test_missing_entry_is_caught(self):
        bad = self.tmp / "short.zip"
        with zipfile.ZipFile(bad, "w") as z:
            for n, d in list(PAGES.items())[:3]:
                z.writestr(tool.Utf8ZipInfo(n), d)
        with self.assertRaisesRegex(tool.BookError, "3 entries, expected 4"):
            tool.verify_zip(str(bad), self.pages)

    def test_tampered_output_fails_the_book(self):
        real_write = tool.write_zip

        def tampering_write(zip_path, dest, pages):
            real_write(zip_path, dest, pages)
            data = bytearray(pathlib.Path(zip_path).read_bytes())
            data[200] ^= 0x01
            pathlib.Path(zip_path).write_bytes(bytes(data))

        with mock.patch.object(tool, "write_zip", tampering_write), \
                mock.patch.object(tool, "move_to_trash") as trash:
            status, out = run_main("--convert", "--delete-originals", self.book)
        self.assertEqual(status, 1, out)
        self.assertIn("FAILED: ", out)
        self.assertIn("verify:", out)
        self.assertFalse((self.root / "solid_ascii.zip").exists())
        self.assertTrue(self.book.exists())
        trash.assert_not_called()
        self.assertNoLeftovers()


@unittest.skipUnless(HAVE_7ZZ and HAVE_UNAR, "needs both 7zz and unar")
class DeleteOriginalsTest(ConvertTestBase):
    GOOD = ["solid_jp.cbr", "solid_ascii.rar", "UPPER.CBR", "solid_encname.cbr",
            "solid_legacy.cbr"]

    def run_with_fake_trash(self, *args):
        trashed = []

        def fake_trash(path):
            trashed.append(os.path.basename(path))
            os.rename(path, self.tmp / ("trashed-" + os.path.basename(path)))
            return None

        with mock.patch.object(tool, "move_to_trash", fake_trash):
            status, out = run_main(*args)
        return status, out, sorted(trashed)

    def assertKept(self):
        self.assertTrue((self.root / "corrupt.cbr").exists())
        for name in SKIPS:
            self.assertTrue((self.root / name).exists(), name)
        self.assertEqual((self.root / "exists.cbz").read_bytes(), b"already here")

    def test_only_verified_originals_are_trashed(self):
        status, out, trashed = self.run_with_fake_trash(
            "--convert", "--delete-originals", self.root)
        self.assertEqual(status, 1, out)  # corrupt.cbr and exists.cbr failed
        self.assertEqual(trashed, sorted(self.GOOD))
        self.assertKept()
        # a target that is not this book's conversion keeps its original
        line = self.line_for(out, "exists.cbr")
        self.assertTrue(line.startswith("FAILED: "), line)
        self.assertIn("existing target does not match", line)
        self.assertIn("originals moved to the Trash: 5", out)
        self.assertIn("already converted, verified again: 0", out)  # exists.cbz failed

    def test_delete_after_earlier_convert(self):
        status, out = run_main("--convert", self.root)
        self.assertEqual(status, 1, out)
        written = {n: (self.root / n).read_bytes() for n in EXPECTED}
        stats = {n: (self.root / n).stat().st_mtime_ns for n in EXPECTED}
        # tamper with one earlier output: its original must stay
        tampered = bytearray(written["solid_ascii.zip"])
        tampered[100] ^= 0xFF
        (self.root / "solid_ascii.zip").write_bytes(bytes(tampered))
        os.utime(self.root / "solid_ascii.zip", ns=(MTIME_NS, MTIME_NS))

        status, out, trashed = self.run_with_fake_trash(
            "--convert", "--delete-originals", self.root)
        self.assertEqual(status, 1, out)
        self.assertEqual(trashed, sorted(set(self.GOOD) - {"solid_ascii.rar"}))
        self.assertTrue((self.root / "solid_ascii.rar").exists())
        self.assertIn("existing target does not match", self.line_for(out, "solid_ascii.rar"))
        self.assertTrue(self.line_for(out, "solid_jp.cbr").startswith("verified existing: "))
        self.assertIn("already converted, verified again: 4", out)
        self.assertIn("converted: 0", out)
        self.assertKept()
        # existing targets are never rewritten
        for name in EXPECTED:
            if name != "solid_ascii.zip":
                self.assertEqual((self.root / name).read_bytes(), written[name], name)
                self.assertEqual((self.root / name).stat().st_mtime_ns, stats[name], name)
        self.assertEqual((self.root / "solid_ascii.zip").read_bytes(), bytes(tampered))
        self.assertNoLeftovers()

    def test_trash_failure_keeps_original(self):
        with mock.patch.object(tool, "move_to_trash", return_value="trash: exit 1 nope"):
            status, out = run_main("--convert", "--delete-originals", self.root / "UPPER.CBR")
        self.assertEqual(status, 1, out)
        self.assertTrue((self.root / "UPPER.CBR").exists())
        self.assertConverted("UPPER.CBZ")
        self.assertIn("original KEPT", out)
        self.assertIn("originals kept (Trash failed): 1", out)


if __name__ == "__main__":
    unittest.main(verbosity=2)
