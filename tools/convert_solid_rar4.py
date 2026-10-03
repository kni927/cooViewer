#!/usr/bin/env python3
"""Convert solid RAR4 books (.cbr/.rar) to ZIP (.cbz/.zip).

cooViewer cannot read solid RAR4 (docs/KNOWN_ISSUES.md #39). This tool
finds every solid RAR4 .cbr/.rar under the given folders -- "solid RAR4"
means exactly what tools/rar_survey.py reports -- and rewrites each one as
an uncompressed ZIP with the same page bytes:

    book.cbr -> book.cbz, book.rar -> book.zip (same folder, same base name)

By default nothing is written: the tool lists what would be converted and
what is skipped, and why. --convert performs the conversion, and
--delete-originals (with --convert) moves each original to the Trash once
its ZIP has been verified in the same run: written now, or, when the ZIP
already exists from an earlier --convert, checked against the original.

Per book, --convert:
  1. walks the RAR4 headers itself (names, sizes, CRC-32s, flags);
  2. lists and extracts the archive with an external extractor into a
     temporary folder, which is removed afterwards;
  3. checks the extracted files against both listings (count, size,
     CRC-32), writes the ZIP with ZIP_STORED (no recompression) and the
     UTF-8 name flag, in archive order, to a hidden temporary name in the
     book's folder;
  4. verifies the ZIP (entry count, names, sizes, CRC-32s against the
     archive's listing, and zipfile.testzip()), gives it the original's
     modification time and permissions, and renames it into place, never
     over an existing file.

Extractor: 7zz is preferred when it has the RAR codecs, otherwise
unar/lsar (Homebrew unar) is used. Homebrew's sevenzip is built without
them: its 7zz lists RAR archives but cannot decompress them, so it is
left out. RAR4 names stored without Unicode (old archives made on Japanese
Windows store Shift_JIS bytes) cannot be decoded by 7zz on macOS, so such
books are extracted with unar and named by decoding the header bytes with
--legacy-encoding (cp932 by default).

Runs on the Python 3 that ships with the macOS Command Line Tools
(/usr/bin/python3, 3.9); standard library only, plus the extractor.
"""

from __future__ import annotations

import argparse
import collections
import json
import os
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import unicodedata
import zipfile
import zlib

sys.dont_write_bytecode = True  # keep tools/ free of __pycache__
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rar_survey  # noqa: E402  (header detection shared with the survey)

TARGET_EXT = {".cbr": ".cbz", ".rar": ".zip"}

LHD_LARGE = 0x0100
MAX_ENTRIES = 1000000
LHD_WINDOWMASK = 0x00E0
LHD_DIRECTORY = 0x00E0
ZIP_FLAG_UTF8 = 0x0800

# Skip reasons for files that are not solid RAR4 at all: counted in the
# summary, listed one per line only with --list-all.
NOT_SOLID_RAR4 = ("RAR5", "not RAR", "not solid")

TRASH = "/usr/bin/trash"
OSASCRIPT = "/usr/bin/osascript"
CHUNK = 1 << 20

EPILOG = """\
Notes:
  Reading a Dropbox (or other cloud) "online-only" file downloads it, even
  in a dry run, because the RAR headers have to be read; use
  --skip-online-only to leave those files alone. The new .cbz/.zip files
  are written next to the originals and will sync like any other file.

  Originals are only moved to the Trash (recoverable), never deleted, and
  only when --convert and --delete-originals are both given and that book
  was verified in this run: either converted now, or -- when its .cbz/.zip
  already exists, e.g. from an earlier --convert -- extracted again and
  the existing ZIP checked against it entry by entry. An existing target
  is never modified; one that does not match is reported as failed and its
  original is kept.

Output lists only solid RAR4 books (to convert, skipped, or failed);
RAR5, non-solid RAR4 and non-RAR files are counted in the summary, and
--list-all lists them too.

Typical use:
  tools/convert_solid_rar4.py FOLDER                      # dry run
  tools/convert_solid_rar4.py --convert FOLDER            # write .cbz/.zip
  tools/convert_solid_rar4.py --convert --delete-originals FOLDER
"""


class BookError(Exception):
    """This book cannot be converted; the run continues with the next one."""


# ---------------------------------------------------------------- RAR4 headers

class RarEntry:
    """One RAR4 file header, as stored."""

    def __init__(self, raw_name, flags, size, crc):
        self.raw_name = raw_name
        self.flags = flags
        self.size = size
        self.crc = crc

    @property
    def is_dir(self):
        return self.flags & LHD_WINDOWMASK == LHD_DIRECTORY

    @property
    def encrypted(self):
        return bool(self.flags & rar_survey.LHD_PASSWORD)

    @property
    def legacy_name(self):
        """Non-ASCII name bytes without RAR's Unicode form: their encoding
        is whatever code page the archiver ran in."""
        return (not self.flags & rar_survey.LHD_UNICODE
                and any(b >= 0x80 for b in self.raw_name))

    def decoded_name(self, legacy_encoding):
        """The name as text, or None when it is in RAR's compressed
        Unicode form (OEM bytes, NUL, encoded Unicode), which only the
        extractor decodes."""
        raw = self.raw_name
        if self.flags & rar_survey.LHD_UNICODE:
            if b"\x00" in raw:
                return None
            name = raw.decode("utf-8")
        elif self.legacy_name:
            name = raw.decode(legacy_encoding)
        else:
            name = raw.decode("ascii")
        # decode first: a Shift_JIS trail byte can be 0x5C ('\')
        return name.replace("\\", "/")


def read_rar4_entries(path):
    """Every file header of a non-encrypted, single-volume RAR4 archive."""
    entries = []
    # Unbuffered: a buffered reader refills its whole buffer (st_blksize,
    # which can be large on some volumes) after every seek, and this walk
    # seeks once per block.
    with open(path, "rb", buffering=0) as f:
        size = os.fstat(f.fileno()).st_size
        read = rar_survey.read_exact
        pos = len(rar_survey.RAR4_SIG)
        f.seek(pos)
        _crc, htype, flags, hsize = struct.unpack("<HBHH", read(f, 7))
        if htype != rar_survey.RAR4_MAIN or hsize < 7:
            raise rar_survey.HeaderError("no main archive header")
        add = struct.unpack("<I", read(f, 4))[0] if flags & rar_survey.LONG_BLOCK else 0
        pos += hsize + add
        while pos + 7 <= size:
            if len(entries) >= MAX_ENTRIES:
                raise rar_survey.HeaderError("more than %d file headers" % MAX_ENTRIES)
            f.seek(pos)
            _crc, htype, flags, hsize = struct.unpack("<HBHH", read(f, 7))
            if hsize < 7 or pos + hsize > size:
                raise rar_survey.HeaderError("malformed or truncated block header")
            if htype == rar_survey.RAR4_END:
                break
            add = 0
            if htype == rar_survey.RAR4_FILE:
                body = read(f, hsize - 7)
                if len(body) < 25:
                    raise rar_survey.HeaderError("short file header")
                (pack_lo, unp_lo, _host, crc, _time, _ver, _method, name_size,
                 _attr) = struct.unpack("<IIBIIBBHI", body[:25])
                off = 25
                pack_hi = unp_hi = 0
                if flags & LHD_LARGE:
                    pack_hi, unp_hi = struct.unpack("<II", body[25:33])
                    off = 33
                raw_name = body[off:off + name_size]
                if len(raw_name) != name_size:
                    raise rar_survey.HeaderError("truncated file name")
                entries.append(RarEntry(raw_name, flags, unp_lo | unp_hi << 32, crc))
                add = pack_lo | pack_hi << 32
            elif flags & rar_survey.LONG_BLOCK:
                add = struct.unpack("<I", read(f, 4))[0]
            pos += hsize + add
    return entries


# ------------------------------------------------------------------ extractors

class Item:
    """One entry of the extractor's listing."""

    def __init__(self, path, is_dir, size, crc, encrypted=False, link=False):
        self.path = path
        self.is_dir = is_dir
        self.size = size
        self.crc = crc
        self.encrypted = encrypted
        self.link = link


def run(cmd):
    proc = subprocess.run(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE)
    out = proc.stdout.decode("utf-8", "replace")
    if proc.returncode != 0:
        err = proc.stderr.decode("utf-8", "replace").strip() or out.strip()
        lines = err.splitlines()
        raise BookError("%s failed (exit %d): %s" % (
            os.path.basename(cmd[0]), proc.returncode, lines[-1] if lines else "no output"))
    return out


class SevenZip:
    name = "7zz"
    reads_legacy_names = False

    def __init__(self, exe):
        self.exe = exe

    def list(self, path, legacy_encoding):
        out = run([self.exe, "l", "-slt", "-ba", "-sccUTF-8", "--", path])
        items = []
        for block in out.split("\n\n"):
            fields = {}
            for line in block.splitlines():
                key, sep, value = line.partition(" = ")
                if sep:
                    fields[key] = value
                elif line.endswith(" ="):
                    fields[line[:-2]] = ""
            if "Path" not in fields:
                continue
            is_dir = fields.get("Folder") == "+"
            crc = fields.get("CRC", "")
            items.append(Item(
                fields["Path"], is_dir,
                int(fields.get("Size") or 0),
                int(crc, 16) if crc else None,
                encrypted=fields.get("Encrypted") == "+",
                link=fields.get("Attributes", "").strip().startswith("l")))
        return items

    def extract(self, path, dest, legacy_encoding):
        run([self.exe, "x", "-y", "-bso0", "-bsp0", "-sccUTF-8", "-o" + dest, "--", path])


class Unar:
    name = "unar"
    reads_legacy_names = True

    def __init__(self, unar, lsar):
        self.unar = unar
        self.lsar = lsar

    def list(self, path, legacy_encoding):
        out = run([self.lsar, "-j", "-e", legacy_encoding, path])
        try:
            contents = json.loads(out)["lsarContents"]
        except (ValueError, KeyError) as exc:
            raise BookError("cannot parse lsar output: %s" % exc)
        items = []
        for e in contents:
            crc = e.get("RARCRC32")
            items.append(Item(
                e["XADFileName"], bool(e.get("XADIsDirectory")),
                int(e.get("XADFileSize") or 0), crc,
                encrypted=bool(e.get("XADIsEncrypted")),
                link=bool(e.get("XADIsLink"))))
        return items

    def extract(self, path, dest, legacy_encoding):
        run([self.unar, "-q", "-nr", "-D", "-f", "-k", "skip", "-e", legacy_encoding,
             "-o", dest, path])


def has_rar_codec(seven):
    """Whether this 7zz can decompress RAR. Homebrew's sevenzip is built
    without the RAR codecs: it lists RAR archives and extracts STORE
    entries, but fails every compressed one with "Unsupported Method"."""
    proc = subprocess.run([seven, "i"], stdin=subprocess.DEVNULL,
                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    lines = proc.stdout.decode("utf-8", "replace").splitlines()
    return any(line.split()[-1:] == ["Rar3"] for line in lines)


def find_extractors(choice):
    """Extractors to use, in order of preference, and notes on any left out."""
    found, notes = [], []
    seven = shutil.which("7zz")
    unar, lsar = shutil.which("unar"), shutil.which("lsar")
    if seven and choice in ("auto", "7zz"):
        if has_rar_codec(seven):
            found.append(SevenZip(seven))
        else:
            notes.append("%s has no RAR codec (Homebrew's sevenzip is built without "
                         "it), so it is not used" % seven)
    if unar and lsar and choice in ("auto", "unar"):
        found.append(Unar(unar, lsar))
    return found, notes


# ------------------------------------------------------------------- planning

def target_for(path):
    base, ext = os.path.splitext(path)
    new = TARGET_EXT[ext.lower()]
    return base + (new.upper() if ext.isupper() else new)


def classify(path, st, args, planned):
    """Return (None, entries) for a book to convert, or (skip reason, None).

    The dry run reads only what tools/rar_survey.py reads (the start of the
    file) and returns entries None; --convert also walks every file header,
    which reads the whole archive."""
    online_only = bool(getattr(st, "st_flags", 0) & rar_survey.SF_DATALESS)
    if online_only and args.skip_online_only:
        return "online-only (not read)", None
    try:
        rec = rar_survey.survey_file(path, st.st_size)
    except OSError as exc:
        return "unreadable: %s" % exc.strerror, None
    fmt = rec["format"]
    if fmt == "RAR5":
        return "RAR5 (cooViewer reads it)", None
    if fmt != "RAR4":
        return "not RAR (%s)" % fmt, None
    if rec["note"].startswith("error"):
        return "RAR4 header %s" % rec["note"], None
    if rec["solid"] != "yes":
        return "not solid (cooViewer reads it)", None
    if rec["header_encrypted"] == "yes":
        return "header-encrypted", None
    if rec["volume"] != "no":
        return "multi-volume", None
    if rec["note"] == "none":
        return "no files in archive", None
    if rec["first_file_encrypted"] == "yes":
        return "password-protected", None
    entries = None
    if args.convert:
        try:
            entries = read_rar4_entries(path)
        except (OSError, rar_survey.HeaderError, struct.error) as exc:
            return "RAR4 header error: %s" % exc, None
        if any(e.encrypted for e in entries):
            return "password-protected", None
    target = target_for(path)
    if target in planned or (os.path.lexists(target) and not args.delete_originals):
        return "target exists", None
    planned.add(target)
    return None, entries


# ----------------------------------------------------------------- conversion

class Utf8ZipInfo(zipfile.ZipInfo):
    """ZipInfo whose name is always written as UTF-8 with the UTF-8 flag,
    ASCII names included (zipfile sets the flag only for non-ASCII)."""

    def _encodeFilenameFlags(self):
        return self.filename.encode("utf-8"), self.flag_bits | ZIP_FLAG_UTF8


def is_macos_metadata(name):
    parts = name.split("/")
    return "__MACOSX" in parts or parts[-1] == ".DS_Store"


def nfc(name):
    return unicodedata.normalize("NFC", name).strip("/")


def file_crc(path):
    crc = 0
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(CHUNK), b""):
            crc = zlib.crc32(chunk, crc)
    return crc & 0xFFFFFFFF


def pick_extractor(entries, extractors):
    legacy = any(e.legacy_name for e in entries)
    for ex in extractors:
        if not legacy or ex.reads_legacy_names:
            return ex
    if legacy:
        raise BookError("names are stored without Unicode (legacy code page); "
                        "extracting them needs unar (brew install unar)")
    raise BookError("no extractor available")


def build_plan(entries, items, legacy_encoding):
    """Pair the RAR headers with the extractor's listing and decide every
    ZIP entry. Returns (pages, skipped): pages are (zip name, listed path,
    size, crc) in archive order; skipped are descriptions."""
    if len(items) != len(entries):
        raise BookError("extractor lists %d entries, the RAR headers have %d"
                        % (len(items), len(entries)))
    pages, skipped, seen = [], [], set()
    for entry, item in zip(entries, items):
        if entry.is_dir != item.is_dir:
            raise BookError("entry %r: directory flag differs between listings" % item.path)
        try:
            name = entry.decoded_name(legacy_encoding)
        except UnicodeDecodeError:
            raise BookError("entry %r: name is not valid %s" % (item.path, legacy_encoding))
        if name is not None and not entry.legacy_name and nfc(name) != nfc(item.path):
            raise BookError("entry %r: name differs from the RAR header (%r)" % (item.path, name))
        if entry.legacy_name:
            name = name.strip("/")
        else:
            name = item.path
        if entry.is_dir:
            skipped.append("directory entry %s" % name)
            continue
        if item.link or item.encrypted:
            raise BookError("entry %r: %s" % (name, "symbolic link" if item.link else "encrypted"))
        if item.size != entry.size or (item.crc is not None and item.crc != entry.crc):
            raise BookError("entry %r: size/CRC differ between the extractor and the RAR header"
                            % name)
        parts = name.split("/")
        if not name or name.startswith("/") or ".." in parts or "" in parts:
            raise BookError("entry %r: unsafe path" % name)
        key = nfc(name)
        if key in seen:
            raise BookError("entry %r appears twice" % name)
        seen.add(key)
        if is_macos_metadata(name):
            skipped.append("macOS metadata %s" % name)
            continue
        pages.append((name, item.path, entry.size, entry.crc))
    if not pages:
        raise BookError("no pages to convert")
    return pages, skipped


def check_extracted(dest, pages, n_files):
    """Every listed file was extracted as a regular file with the listed
    size and CRC-32, and nothing else was."""
    count = 0
    for dirpath, dirnames, filenames in os.walk(dest):
        for n in filenames + dirnames:
            p = os.path.join(dirpath, n)
            st = os.lstat(p)
            if stat.S_ISREG(st.st_mode):
                count += 1
            elif not stat.S_ISDIR(st.st_mode):
                raise BookError("extracted %r is not a regular file" % os.path.relpath(p, dest))
    if count != n_files:
        raise BookError("extracted %d files, expected %d" % (count, n_files))
    for name, listed, size, crc in pages:
        p = os.path.join(dest, listed)
        try:
            st = os.lstat(p)
        except OSError:
            raise BookError("entry %r was not extracted" % name)
        if not stat.S_ISREG(st.st_mode) or st.st_size != size:
            raise BookError("entry %r: extracted size %d, expected %d" % (name, st.st_size, size))
        if file_crc(p) != crc:
            raise BookError("entry %r: extracted CRC-32 does not match the archive" % name)


def write_zip(zip_path, dest, pages):
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_STORED) as z:
        for name, listed, _size, _crc in pages:
            disk = os.path.join(dest, listed)
            info = Utf8ZipInfo.from_file(disk, name, strict_timestamps=False)
            info.compress_type = zipfile.ZIP_STORED
            with open(disk, "rb") as s, z.open(info, "w") as d:
                shutil.copyfileobj(s, d, CHUNK)


def verify_zip(zip_path, pages):
    """Raise BookError unless the ZIP holds exactly pages, stored, with the
    archive's sizes and CRC-32s, and every entry reads back intact."""
    try:
        with zipfile.ZipFile(zip_path) as z:
            infos = z.infolist()
            if len(infos) != len(pages):
                raise BookError("verify: ZIP has %d entries, expected %d" % (len(infos), len(pages)))
            for info, (name, _listed, size, crc) in zip(infos, pages):
                if info.filename != name:
                    raise BookError("verify: entry %r, expected %r" % (info.filename, name))
                if info.compress_type != zipfile.ZIP_STORED:
                    raise BookError("verify: entry %r is compressed" % name)
                if not info.flag_bits & ZIP_FLAG_UTF8:
                    raise BookError("verify: entry %r lacks the UTF-8 flag" % name)
                if info.file_size != size or info.CRC != crc:
                    raise BookError("verify: entry %r size/CRC differ from the archive" % name)
            bad = z.testzip()
            if bad is not None:
                raise BookError("verify: entry %r fails its CRC check" % bad)
    except (zipfile.BadZipFile, OSError, EOFError) as exc:
        raise BookError("verify: %s" % exc)


def extract_checked(src, entries, extractors, legacy_encoding, dest):
    """Extract src into dest and check it; returns (pages, skipped, extractor name)."""
    extractor = pick_extractor(entries, extractors)
    items = extractor.list(src, legacy_encoding)
    pages, skipped = build_plan(entries, items, legacy_encoding)
    extractor.extract(src, dest, legacy_encoding)
    check_extracted(dest, pages, sum(1 for e in entries if not e.is_dir))
    return pages, skipped, extractor.name


def convert_book(src, st, entries, extractors, legacy_encoding, existing=False):
    """Write and verify the ZIP or, with existing, verify the ZIP already at
    the target against src. Returns (target, pages, skipped, extractor name)."""
    target = target_for(src)
    dest = tempfile.mkdtemp(prefix="convert_solid_rar4.")
    partial = None
    try:
        pages, skipped, used = extract_checked(src, entries, extractors, legacy_encoding, dest)
        if existing:
            if not stat.S_ISREG(os.lstat(target).st_mode):
                raise BookError("existing target is not a regular file")
            try:
                verify_zip(target, pages)
            except BookError as exc:
                raise BookError("existing target does not match: %s" % exc)
        else:
            folder, base = os.path.split(target)
            fd, partial = tempfile.mkstemp(dir=folder or ".", prefix="." + base + ".",
                                           suffix=".partial")
            os.close(fd)
            write_zip(partial, dest, pages)
            verify_zip(partial, pages)
            os.chmod(partial, stat.S_IMODE(st.st_mode))
            os.utime(partial, ns=(st.st_atime_ns, st.st_mtime_ns))
            if os.path.lexists(target):
                raise BookError("target appeared during conversion: %s" % target)
            os.rename(partial, target)
    finally:
        shutil.rmtree(dest, ignore_errors=True)
        if partial and os.path.lexists(partial):
            os.unlink(partial)
    return target, pages, skipped, used


def move_to_trash(path):
    """Move path to the Trash. Returns None on success, else the reason."""
    reasons = []
    if os.access(TRASH, os.X_OK):
        proc = subprocess.run([TRASH, path], stdin=subprocess.DEVNULL,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if proc.returncode == 0 and not os.path.lexists(path):
            return None
        reasons.append("trash: exit %d %s" % (
            proc.returncode, proc.stderr.decode("utf-8", "replace").strip()))
    if os.access(OSASCRIPT, os.X_OK):
        script = ['on run argv',
                  'tell application "Finder" to delete (POSIX file (item 1 of argv) as alias)',
                  'end run']
        cmd = [OSASCRIPT]
        for line in script:
            cmd += ["-e", line]
        proc = subprocess.run(cmd + [path], stdin=subprocess.DEVNULL,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if proc.returncode == 0 and not os.path.lexists(path):
            return None
        reasons.append("Finder: exit %d %s" % (
            proc.returncode, proc.stderr.decode("utf-8", "replace").strip()))
    return "; ".join(reasons) or "no way to move files to the Trash"


# ----------------------------------------------------------------------- main

def plural(n, word):
    return "%d %s%s" % (n, word, "" if n == 1 else "s")


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Convert solid RAR4 .cbr/.rar books to .cbz/.zip with identical "
                    "page bytes. Without --convert this is a dry run that writes nothing.",
        epilog=EPILOG, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("paths", nargs="+", metavar="FOLDER",
                        help="folders to walk (files are accepted too)")
    parser.add_argument("--convert", action="store_true",
                        help="write the .cbz/.zip files (default: dry run)")
    parser.add_argument("--delete-originals", action="store_true",
                        help="with --convert: move each original to the Trash once its "
                             "ZIP is verified in this run; an existing .cbz/.zip is "
                             "verified against the original instead of being skipped")
    parser.add_argument("--extractor", choices=("auto", "7zz", "unar"), default="auto",
                        help="extractor to use (default: 7zz if it has the RAR codecs, "
                             "which Homebrew's build lacks, else unar; books with legacy "
                             "non-Unicode names always need unar)")
    parser.add_argument("--legacy-encoding", default="cp932", metavar="CODEC",
                        help="code page of RAR4 names stored without Unicode "
                             "(default: cp932, Japanese Windows)")
    parser.add_argument("--skip-online-only", action="store_true",
                        help="skip cloud placeholder files without reading "
                             "(and so without downloading) them")
    parser.add_argument("--list-all", action="store_true",
                        help="also list files that are not solid RAR4 (RAR5, non-solid "
                             "RAR4, not RAR); by default they are only counted in the "
                             "summary")
    args = parser.parse_args(argv)
    if args.delete_originals and not args.convert:
        parser.error("--delete-originals needs --convert")
    try:
        "".encode(args.legacy_encoding)
    except LookupError:
        parser.error("unknown encoding: %s" % args.legacy_encoding)

    extractors = []
    if args.convert:
        extractors, notes = find_extractors(args.extractor)
        for note in notes:
            print("convert_solid_rar4: %s" % note, file=sys.stderr)
        if not extractors:
            print("convert_solid_rar4: no usable extractor; install unar "
                  "(`brew install unar`)", file=sys.stderr)
            return 2

    counters = collections.Counter()
    skipped = collections.Counter()
    failed = []
    converted = reverified = trashed = kept = 0
    planned = set()
    out = sys.stdout

    for path, st in rar_survey.iter_candidates(args.paths, counters):
        reason, entries = classify(path, st, args, planned)
        if reason:
            skipped[reason] += 1
            if args.list_all or not reason.startswith(NOT_SOLID_RAR4):
                print("skip (%s): %s" % (reason, path), file=out)
            continue
        if not args.convert:
            print("would convert: %s -> %s" % (path, os.path.basename(target_for(path))),
                  file=out)
            converted += 1
            continue
        existing = os.path.lexists(target_for(path))  # only with --delete-originals
        print("%s: %s ..." % ("verifying" if existing else "converting", path), file=out)
        out.flush()
        try:
            target, pages, dropped, used = convert_book(
                path, st, entries, extractors, args.legacy_encoding, existing)
        except KeyboardInterrupt:
            raise
        except Exception as exc:  # report it and go on with the next book
            failed.append(path)
            if not isinstance(exc, (BookError, OSError)):
                exc = "%s: %s" % (type(exc).__name__, exc)
            print("FAILED: %s: %s" % (path, exc), file=out)
            continue
        if existing:
            reverified += 1
        else:
            converted += 1
        print("%s: %s -> %s (%s, %s)" % (
            "verified existing" if existing else "converted",
            path, os.path.basename(target), plural(len(pages), "page"), used), file=out)
        for d in dropped:
            print("  left out %s" % d, file=out)
        if args.delete_originals:
            why = move_to_trash(path)
            if why is None:
                trashed += 1
                print("  original moved to the Trash", file=out)
            else:
                kept += 1
                print("  original KEPT, could not move it to the Trash: %s" % why, file=out)
        out.flush()

    print("", file=out)
    print("Summary%s" % ("" if args.convert else " (dry run, nothing written)"), file=out)
    print("  %s: %d" % ("converted" if args.convert else "would convert", converted), file=out)
    for reason in sorted(skipped):
        unlisted = not args.list_all and reason.startswith(NOT_SOLID_RAR4)
        print("  skipped, %s: %d%s" % (reason, skipped[reason],
                                       " (not listed; --list-all lists them)" if unlisted else ""),
              file=out)
    for key in ("skipped symlink", "unreadable file", "unreadable folder", "missing argument"):
        if counters[key]:
            print("  %s: %d" % (key, counters[key]), file=out)
    if args.delete_originals:
        print("  already converted, verified again: %d" % reverified, file=out)
    if args.convert:
        print("  failed: %d" % len(failed), file=out)
        for path in failed:
            print("    %s" % path, file=out)
    if args.delete_originals:
        print("  originals moved to the Trash: %d" % trashed, file=out)
        if kept:
            print("  originals kept (Trash failed): %d" % kept, file=out)
    return 1 if failed or kept or counters["missing argument"] else 0


if __name__ == "__main__":
    sys.exit(main())
