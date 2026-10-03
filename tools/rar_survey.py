#!/usr/bin/env python3
"""Classify .cbr/.rar books by their RAR archive headers.

Walks the given folders (and accepts individual files), and for every
file named *.cbr or *.rar reads only the archive headers -- never the
compressed data -- and prints one tab-separated line per file:

    path  format  solid  volume  header_encrypted
    first_entry_unicode  first_file_encrypted  online_only  note

followed by a summary count per category on stderr, so the TSV on stdout
can be redirected to a file on its own.

Columns:
  format                RAR4 (RAR 1.5-4.x), RAR5, or what the file really
                        is when it is not RAR (ZIP, 7z, PDF, empty, ...).
  solid                 yes/no from the main archive header.
  volume                no, first, later (a continuation part), or yes
                        (a RAR4 volume whose position cannot be told).
  header_encrypted      yes when the headers themselves are encrypted
                        (rar -hp); the remaining columns are then unknown.
  first_entry_unicode   RAR4 only: whether the first file header sets
                        LHD_UNICODE (non-ASCII names in RAR's own Unicode
                        encoding). n/a for RAR5, whose names are UTF-8.
  first_file_encrypted  whether the first file header is encrypted (rar -p).
  online_only           yes when the file was a cloud placeholder
                        (SF_DATALESS) before it was read.
  note                  "none" when the archive has no file header, or the
                        reason a header could not be parsed.

The tool is read-only: it opens archives for reading, never writes, and
does not follow symbolic links (symlinked files are skipped and counted,
symlinked folders are not entered). Reading a cloud "online-only" file,
e.g. Dropbox, makes the cloud provider download it; use
--skip-online-only to list those files without reading them.

--solid-only prints lines only for solid archives (RAR4 or RAR5); the
summary still counts every file surveyed.

Header layouts follow Sources/CORarHeaderIndex.m (itself derived from
XADMaster's XADRARParser.m / XADRAR5Parser.m) and RARLAB's technote.

Runs on the Python 3 that ships with the macOS Command Line Tools
(/usr/bin/python3, 3.9); standard library only.
"""

from __future__ import annotations

import argparse
import collections
import os
import stat
import struct
import sys

EXTENSIONS = (".cbr", ".rar")

# st_flags bit for a File Provider placeholder whose data is not local
# (<sys/stat.h> SF_DATALESS); not exported by the stat module before 3.13.
SF_DATALESS = 0x40000000

RAR4_SIG = b"Rar!\x1a\x07\x00"
RAR5_SIG = b"Rar!\x1a\x07\x01\x00"

# RAR4 block types and flags
RAR4_MAIN = 0x73
RAR4_FILE = 0x74
RAR4_END = 0x7B
MHD_VOLUME = 0x0001
MHD_SOLID = 0x0008
MHD_PASSWORD = 0x0080
MHD_FIRSTVOLUME = 0x0100
LHD_SPLIT_BEFORE = 0x0001
LHD_PASSWORD = 0x0004
LHD_UNICODE = 0x0200
LONG_BLOCK = 0x8000

# RAR5 header types and flags
RAR5_MAIN = 1
RAR5_FILE = 2
RAR5_ENCRYPTION = 4
RAR5_END = 5
RAR5_HFL_EXTRA = 0x0001
RAR5_HFL_DATA = 0x0002
RAR5_MHD_VOLUME = 0x0001
RAR5_MHD_VOLNUMBER = 0x0002
RAR5_MHD_SOLID = 0x0004
RAR5_FHEXTRA_CRYPT = 0x01

# Blocks walked before giving up on finding the first file header
# (archive comments, quick-open and other service blocks may come first).
MAX_BLOCKS = 64
# Largest header accepted; RAR5 caps headers at 2 MB, RAR4 at 64 KB.
MAX_HEADER = 2 * 1024 * 1024

COLUMNS = ("path", "format", "solid", "volume", "header_encrypted",
           "first_entry_unicode", "first_file_encrypted", "online_only", "note")


class HeaderError(Exception):
    """The archive headers end early or are malformed."""


def read_exact(f, n):
    data = f.read(n)
    if len(data) != n:
        raise HeaderError("truncated header")
    return data


def read_vint(f):
    """RAR5 variable-length integer: 7 bits per byte, low group first."""
    value = 0
    shift = 0
    while True:
        byte = read_exact(f, 1)[0]
        value |= (byte & 0x7F) << shift
        if not byte & 0x80:
            return value
        shift += 7
        if shift > 63:
            raise HeaderError("malformed vint")


def yes_no(flag):
    return "yes" if flag else "no"


def new_record(fmt):
    return {
        "format": fmt,
        "solid": "n/a",
        "volume": "n/a",
        "header_encrypted": "n/a",
        "first_entry_unicode": "n/a",
        "first_file_encrypted": "n/a",
        "note": "",
    }


def sniff_other(head):
    """Name a non-RAR file by its magic bytes."""
    if not head:
        return "empty"
    if head[:4] in (b"PK\x03\x04", b"PK\x05\x06", b"PK\x07\x08"):
        return "ZIP"
    if head[:6] == b"7z\xbc\xaf\x27\x1c":
        return "7z"
    if head[:4] == b"%PDF":
        return "PDF"
    if head[:4] == b"RE~^":
        return "RAR 1.4"
    if head[:2] == b"MZ":
        return "EXE (maybe SFX)"
    return "unknown"


def survey_rar4(f, size):
    rec = new_record("RAR4")
    pos = len(RAR4_SIG)
    f.seek(pos)
    _crc, htype, flags, hsize = struct.unpack("<HBHH", read_exact(f, 7))
    if htype != RAR4_MAIN or hsize < 7:
        raise HeaderError("no main archive header")
    if pos + hsize > size:
        raise HeaderError("truncated header")
    rec["solid"] = yes_no(flags & MHD_SOLID)
    rec["header_encrypted"] = yes_no(flags & MHD_PASSWORD)
    volume = flags & MHD_VOLUME
    if not volume:
        rec["volume"] = "no"
    elif flags & MHD_FIRSTVOLUME:
        rec["volume"] = "first"
    else:
        rec["volume"] = "yes"  # refined below from the first file header
    if flags & MHD_PASSWORD:
        rec["first_entry_unicode"] = "unknown"
        rec["first_file_encrypted"] = "unknown"
        return rec
    add = struct.unpack("<I", read_exact(f, 4))[0] if flags & LONG_BLOCK else 0
    pos += hsize + add

    for _ in range(MAX_BLOCKS):
        if pos >= size:
            break  # ends without an end-of-archive block
        f.seek(pos)
        _crc, htype, flags, hsize = struct.unpack("<HBHH", read_exact(f, 7))
        if hsize < 7 or pos + hsize > size:
            raise HeaderError("malformed or truncated block header")
        if htype == RAR4_FILE:
            rec["first_entry_unicode"] = yes_no(flags & LHD_UNICODE)
            rec["first_file_encrypted"] = yes_no(flags & LHD_PASSWORD)
            if rec["volume"] == "yes":
                rec["volume"] = "later" if flags & LHD_SPLIT_BEFORE else "first"
            return rec
        if htype == RAR4_END:
            break
        add = 0
        if flags & LONG_BLOCK:
            add = struct.unpack("<I", read_exact(f, 4))[0]
        pos += hsize + add
    else:
        rec["note"] = "no file header in the first %d blocks" % MAX_BLOCKS
        rec["first_entry_unicode"] = "unknown"
        rec["first_file_encrypted"] = "unknown"
        return rec
    rec["note"] = "none"
    rec["first_entry_unicode"] = "none"
    rec["first_file_encrypted"] = "none"
    return rec


def read_rar5_block(f, pos, size):
    """Return (type, flags, header_end, extra_size, data_size, body_pos)."""
    f.seek(pos + 4)  # skip the header CRC32
    hsize = read_vint(f)
    start = f.tell()
    if hsize == 0 or hsize > MAX_HEADER or start + hsize > size:
        raise HeaderError("malformed block header")
    htype = read_vint(f)
    hflags = read_vint(f)
    extra = read_vint(f) if hflags & RAR5_HFL_EXTRA else 0
    data = read_vint(f) if hflags & RAR5_HFL_DATA else 0
    end = start + hsize
    if extra > hsize:
        raise HeaderError("malformed extra area")
    return htype, hflags, end, extra, data, f.tell()


def rar5_file_encrypted(f, header_end, extra_size):
    """True when the file header's extra area holds an encryption record.

    The extra area is the last extra_size bytes of the header, so it can
    be read without parsing the file fields in front of it."""
    pos = header_end - extra_size
    for _ in range(MAX_BLOCKS):
        if pos >= header_end:
            return False
        f.seek(pos)
        rsize = read_vint(f)
        rstart = f.tell()
        if rsize == 0 or rstart + rsize > header_end:
            raise HeaderError("malformed extra record")
        if read_vint(f) == RAR5_FHEXTRA_CRYPT:
            return True
        pos = rstart + rsize
    return False


def survey_rar5(f, size):
    rec = new_record("RAR5")
    rec["first_entry_unicode"] = "n/a"
    pos = len(RAR5_SIG)
    htype, _hflags, end, _extra, data, body = read_rar5_block(f, pos, size)
    if htype == RAR5_ENCRYPTION:
        rec["header_encrypted"] = "yes"
        for key in ("solid", "volume", "first_file_encrypted"):
            rec[key] = "unknown"
        return rec
    rec["header_encrypted"] = "no"
    if htype != RAR5_MAIN:
        raise HeaderError("no main archive header")
    f.seek(body)
    aflags = read_vint(f)
    rec["solid"] = yes_no(aflags & RAR5_MHD_SOLID)
    if not aflags & RAR5_MHD_VOLUME:
        rec["volume"] = "no"
    elif aflags & RAR5_MHD_VOLNUMBER and read_vint(f) > 0:
        rec["volume"] = "later"
    else:
        rec["volume"] = "first"
    pos = end + data

    for _ in range(MAX_BLOCKS):
        if pos >= size:
            break  # ends without an end-of-archive block
        htype, _hflags, end, extra, data, _body = read_rar5_block(f, pos, size)
        if htype == RAR5_FILE:
            rec["first_file_encrypted"] = yes_no(rar5_file_encrypted(f, end, extra))
            return rec
        if htype == RAR5_END:
            break
        if end + data <= pos:
            raise HeaderError("block does not advance")
        pos = end + data
    else:
        rec["note"] = "no file header in the first %d blocks" % MAX_BLOCKS
        rec["first_file_encrypted"] = "unknown"
        return rec
    rec["note"] = "none"
    rec["first_file_encrypted"] = "none"
    return rec


def survey_file(path, size):
    with open(path, "rb") as f:
        head = f.read(8)
        try:
            if head == RAR5_SIG:
                return survey_rar5(f, size)
            if head[:7] == RAR4_SIG:
                return survey_rar4(f, size)
        except HeaderError as exc:
            rec = new_record("RAR5" if head == RAR5_SIG else "RAR4")
            rec["note"] = "error: %s" % exc
            return rec
        return new_record(sniff_other(head))


def iter_candidates(roots, counters):
    """Yield (path, lstat) for each regular *.cbr / *.rar under roots."""
    for root in roots:
        if os.path.isfile(root):
            entries = [root]
        elif os.path.isdir(root):
            entries = None
        else:
            print("rar_survey: not found: %s" % root, file=sys.stderr)
            counters["missing argument"] += 1
            continue
        if entries is not None:
            yield from check_candidates(entries, counters)
            continue

        def onerror(exc):
            print("rar_survey: cannot list %s: %s" % (exc.filename, exc.strerror),
                  file=sys.stderr)
            counters["unreadable folder"] += 1

        for dirpath, dirnames, filenames in os.walk(root, onerror=onerror, followlinks=False):
            dirnames.sort()
            names = sorted(n for n in filenames
                           if n.lower().endswith(EXTENSIONS) and not n.startswith("._"))
            yield from check_candidates([os.path.join(dirpath, n) for n in names], counters)


def check_candidates(paths, counters):
    for path in paths:
        try:
            st = os.lstat(path)
        except OSError as exc:
            print("rar_survey: cannot stat %s: %s" % (path, exc.strerror), file=sys.stderr)
            counters["unreadable file"] += 1
            continue
        if stat.S_ISLNK(st.st_mode):
            counters["skipped symlink"] += 1
            continue
        if not stat.S_ISREG(st.st_mode):
            continue
        yield path, st


def tsv_field(value):
    return value.replace("\\", "\\\\").replace("\t", "\\t").replace("\n", "\\n").replace("\r", "\\r")


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Classify .cbr/.rar files by their RAR headers (read-only).")
    parser.add_argument("paths", nargs="+", metavar="FOLDER",
                        help="folders to walk (files are accepted too)")
    parser.add_argument("--skip-online-only", action="store_true",
                        help="list cloud placeholder files without reading "
                             "(and so without downloading) them")
    parser.add_argument("--solid-only", action="store_true",
                        help="print a TSV line only for archives whose header says "
                             "solid (RAR4 or RAR5); the summary on stderr still "
                             "counts every file surveyed. Archives whose solidity "
                             "cannot be read (RAR5 with encrypted headers) are not "
                             "printed")
    args = parser.parse_args(argv)

    counters = collections.Counter()
    categories = collections.Counter()
    out = sys.stdout
    out.write("\t".join(COLUMNS) + "\n")

    for path, st in iter_candidates(args.paths, counters):
        online_only = bool(getattr(st, "st_flags", 0) & SF_DATALESS)
        if online_only and args.skip_online_only:
            rec = new_record("not read")
            rec["note"] = "online-only, skipped"
            counters["online-only skipped"] += 1
        else:
            try:
                rec = survey_file(path, st.st_size)
            except OSError as exc:
                rec = new_record("unreadable")
                rec["note"] = "error: %s" % exc.strerror
        if online_only and not args.skip_online_only:
            counters["online-only read (downloaded)"] += 1
        rec["online_only"] = yes_no(online_only)
        if not args.solid_only or rec["solid"] == "yes":
            out.write("\t".join(tsv_field(path if c == "path" else rec[c]) for c in COLUMNS) + "\n")

        counters["files"] += 1
        fmt = rec["format"]
        categories["format: " + fmt] += 1
        if fmt in ("RAR4", "RAR5"):
            if rec["note"].startswith("error"):
                categories["%s header error" % fmt] += 1
            else:
                solidity = {"yes": "solid", "no": "non-solid"}.get(rec["solid"], "solid unknown")
                categories["%s %s" % (fmt, solidity)] += 1
                if rec["header_encrypted"] == "yes":
                    categories["%s header-encrypted" % fmt] += 1
                if rec["volume"] not in ("no", "unknown"):
                    categories["%s multi-volume (%s)" % (fmt, rec["volume"])] += 1
                if rec["first_file_encrypted"] == "yes":
                    categories["%s first file encrypted" % fmt] += 1
                if fmt == "RAR4" and rec["first_entry_unicode"] == "yes":
                    categories["RAR4 LHD_UNICODE first entry"] += 1
                if rec["note"] == "none":
                    categories["%s no file header" % fmt] += 1

    err = sys.stderr
    print("", file=err)
    print("Summary", file=err)
    print("  files surveyed: %d" % counters["files"], file=err)
    for key in sorted(categories):
        print("  %s: %d" % (key, categories[key]), file=err)
    for key in ("online-only read (downloaded)", "online-only skipped", "skipped symlink",
                "unreadable file", "unreadable folder", "missing argument"):
        if counters[key]:
            print("  %s: %d" % (key, counters[key]), file=err)
    solid4 = categories["RAR4 solid"]
    print("  => solid RAR4 (not readable by cooViewer 1.6.x): %d" % solid4, file=err)
    return 1 if counters["missing argument"] else 0


if __name__ == "__main__":
    sys.exit(main())
