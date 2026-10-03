#!/usr/bin/env python3
"""Tests for tools/rar_survey.py.

Fixtures are generated into a temporary folder and removed afterwards:
RAR4 headers are written by hand (rar 7.x can no longer create RAR4);
RAR5 archives are made with `rar` when it is installed, otherwise those
cases are skipped. The tool is run as a subprocess, as the owner runs it.

    /usr/bin/python3 tests/tools/test_rar_survey.py
"""

from __future__ import annotations

import os
import pathlib
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile
import zlib

REPO = pathlib.Path(__file__).resolve().parents[2]
TOOL = REPO / "tools" / "rar_survey.py"
SRC = REPO / "tests" / "fixtures" / "src"
RAR = shutil.which("rar")

RAR4_SIG = b"Rar!\x1a\x07\x00"


def rar4_block(htype, flags, body=b"", add=None):
    """One RAR4 block; add is the ADD_SIZE (packed data size) field."""
    if add is not None:
        flags |= 0x8000
        body = struct.pack("<I", add) + body
    rest = struct.pack("<BHH", htype, flags, 7 + len(body)) + body
    return struct.pack("<H", zlib.crc32(rest) & 0xFFFF) + rest


def rar4_file(name, data, flags=0):
    namebytes = name.encode("utf-8")
    body = struct.pack("<IBIIBBHI", len(data), 3, zlib.crc32(data), 0, 20, 0x30,
                       len(namebytes), 0o100644) + namebytes
    return rar4_block(0x74, flags, body, add=len(data)) + data


def rar4_archive(main_flags=0, files=(("001.jpg", b"page", 0),), prefix_blocks=b""):
    blocks = [RAR4_SIG, rar4_block(0x73, main_flags, b"\x00" * 6), prefix_blocks]
    for name, data, flags in files:
        blocks.append(rar4_file(name, data, flags))
    blocks.append(rar4_block(0x7B, 0))
    return b"".join(blocks)


def run_tool(*args):
    proc = subprocess.run([sys.executable, "-B", str(TOOL)] + [str(a) for a in args],
                          capture_output=True, text=True)
    lines = proc.stdout.splitlines()
    header = lines[0].split("\t")
    rows = {}
    for line in lines[1:]:
        fields = dict(zip(header, line.split("\t")))
        rows[os.path.basename(fields["path"])] = fields
    return proc, rows


def snapshot(root):
    state = {}
    for dirpath, dirnames, filenames in os.walk(root):
        for name in dirnames + filenames:
            p = os.path.join(dirpath, name)
            st = os.lstat(p)
            state[p] = (st.st_mode, st.st_size, st.st_mtime_ns)
    return state


class RarSurveyTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix="rar_survey_test.")
        root = pathlib.Path(cls.tmp) / "books"
        sub = root / "sub folder"
        sub.mkdir(parents=True)
        cls.root = root

        page = b"\xff\xd8 synthetic page \xff\xd9"
        comment = rar4_block(0x7A, 0, b"CMT-subblock", add=4) + b"note"
        fixtures = {
            "r4_plain.cbr": rar4_archive(),
            "r4_solid.cbr": rar4_archive(0x0008),
            "r4_unicode.cbr": rar4_archive(files=(("表紙.jpg", page, 0x0200),)),
            "r4_after_comment.rar": rar4_archive(prefix_blocks=comment),
            "r4_crypt_file.cbr": rar4_archive(files=(("001.jpg", page, 0x0004),)),
            "r4_vol_first.part1.rar": rar4_archive(0x0001 | 0x0100,
                                                    files=(("001.jpg", page, 0x0002),)),
            "r4_vol_later.part2.rar": rar4_archive(0x0001,
                                                    files=(("001.jpg", page, 0x0001),)),
            "r4_vol_old_first.rar": rar4_archive(0x0001, files=(("001.jpg", page, 0x0002),)),
            "r4_empty_archive.cbr": RAR4_SIG + rar4_block(0x73, 0, b"\x00" * 6)
                                    + rar4_block(0x7B, 0),
            "r4_truncated.cbr": rar4_archive()[:15],
            "empty.cbr": b"",
            "pdf_named.cbr": b"%PDF-1.4\n",
            "UPPER.CBR": rar4_archive(),
        }
        # header-encrypted RAR4: everything after the main header is opaque
        fixtures["r4_crypt_headers.cbr"] = (RAR4_SIG + rar4_block(0x73, 0x0080 | 0x0008, b"\x00" * 6)
                                           + bytes(range(256)))
        for name, data in fixtures.items():
            (root / name).write_bytes(data)
        (sub / "nested.cbr").write_bytes(rar4_archive(0x0008))
        (root / "._r4_plain.cbr").write_bytes(b"\x00\x05\x16\x07")  # AppleDouble
        (root / "notes.txt").write_bytes(b"not a book")
        with zipfile.ZipFile(root / "zip_named.cbr", "w") as z:
            z.writestr("001.jpg", page)
        os.symlink(root / "r4_solid.cbr", root / "link.cbr")
        outside = pathlib.Path(cls.tmp) / "outside"
        outside.mkdir()
        (outside / "hidden.cbr").write_bytes(rar4_archive())
        os.symlink(outside, root / "linked folder")

        cls.have_rar = RAR is not None
        if cls.have_rar:
            work = pathlib.Path(cls.tmp) / "work"
            work.mkdir()
            for src in ("001.png", "002.jpg", "003.png", "004.jpg"):
                shutil.copy(SRC / src, work / src)
            files = ["001.png", "002.jpg", "003.png", "004.jpg"]

            def make(args, out):
                subprocess.run([RAR, "a", "-idq", "-ep"] + args + [str(root / out)] + files,
                               cwd=work, check=True)

            make([], "r5_plain.cbr")
            make(["-s"], "r5_solid.cbr")
            make(["-psurvey-test"], "r5_crypt_file.cbr")
            make(["-hpsurvey-test"], "r5_crypt_headers.cbr")
            make(["-v200k"], "r5_vol.rar")
            # a comment block before the first file header
            (work / "comment.txt").write_text("survey test comment\n")
            make(["-zcomment.txt"], "r5_comment.cbr")

        cls.before = snapshot(cls.tmp)
        cls.proc, cls.rows = run_tool(root)
        cls.after = snapshot(cls.tmp)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp)

    def row(self, name):
        self.assertIn(name, self.rows, self.proc.stdout)
        return self.rows[name]

    def assertRow(self, name, **expected):
        row = self.row(name)
        for key, value in expected.items():
            self.assertEqual(row[key], value, "%s: %s" % (name, key))

    def test_exit_status(self):
        self.assertEqual(self.proc.returncode, 0, self.proc.stderr)

    def test_read_only(self):
        self.assertEqual(self.before, self.after)

    def test_rar4_categories(self):
        self.assertRow("r4_plain.cbr", format="RAR4", solid="no", volume="no",
                       header_encrypted="no", first_entry_unicode="no",
                       first_file_encrypted="no", online_only="no", note="")
        self.assertRow("r4_solid.cbr", format="RAR4", solid="yes")
        self.assertRow("nested.cbr", format="RAR4", solid="yes")
        self.assertRow("r4_unicode.cbr", first_entry_unicode="yes")
        self.assertRow("r4_after_comment.rar", first_entry_unicode="no", note="")
        self.assertRow("r4_crypt_file.cbr", first_file_encrypted="yes", header_encrypted="no")
        self.assertRow("r4_crypt_headers.cbr", header_encrypted="yes", solid="yes",
                       first_entry_unicode="unknown", first_file_encrypted="unknown")
        self.assertRow("r4_vol_first.part1.rar", volume="first")
        self.assertRow("r4_vol_later.part2.rar", volume="later")
        self.assertRow("r4_vol_old_first.rar", volume="first")
        self.assertRow("r4_empty_archive.cbr", note="none", first_entry_unicode="none")
        self.assertRow("UPPER.CBR", format="RAR4")
        self.assertTrue(self.row("r4_truncated.cbr")["note"].startswith("error:"))

    def test_not_rar(self):
        self.assertRow("zip_named.cbr", format="ZIP", solid="n/a")
        self.assertRow("empty.cbr", format="empty")
        self.assertRow("pdf_named.cbr", format="PDF")

    def test_skipped_files(self):
        for name in ("notes.txt", "._r4_plain.cbr", "link.cbr", "hidden.cbr"):
            self.assertNotIn(name, self.rows)
        self.assertIn("skipped symlink: 1", self.proc.stderr)

    def test_summary(self):
        err = self.proc.stderr
        self.assertIn("RAR4 solid: 3", err)  # r4_solid, nested, r4_crypt_headers
        self.assertIn("RAR4 header-encrypted: 1", err)
        self.assertIn("RAR4 LHD_UNICODE first entry: 1", err)
        self.assertIn("RAR4 header error: 1", err)
        self.assertIn("format: ZIP: 1", err)
        self.assertIn("=> solid RAR4 (not readable by cooViewer 1.6.x): 3", err)

    def test_file_argument(self):
        proc, rows = run_tool(self.root / "r4_solid.cbr")
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(rows["r4_solid.cbr"]["solid"], "yes")

    def test_missing_argument(self):
        proc, _rows = run_tool(self.root / "does-not-exist")
        self.assertEqual(proc.returncode, 1)
        self.assertIn("not found", proc.stderr)

    def test_rar5_categories(self):
        if not self.have_rar:
            self.skipTest("rar not installed")
        self.assertRow("r5_plain.cbr", format="RAR5", solid="no", volume="no",
                       header_encrypted="no", first_entry_unicode="n/a",
                       first_file_encrypted="no", note="")
        self.assertRow("r5_solid.cbr", solid="yes")
        self.assertRow("r5_crypt_file.cbr", first_file_encrypted="yes", header_encrypted="no")
        self.assertRow("r5_crypt_headers.cbr", header_encrypted="yes", solid="unknown",
                       volume="unknown", first_file_encrypted="unknown")
        self.assertRow("r5_comment.cbr", first_file_encrypted="no", note="")
        self.assertRow("r5_vol.part1.rar", volume="first")
        self.assertRow("r5_vol.part2.rar", volume="later")


if __name__ == "__main__":
    unittest.main(verbosity=2)
