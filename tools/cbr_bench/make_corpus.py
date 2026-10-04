#!/usr/bin/env python3
"""Generate the tools/cbr_bench corpus (see README.md).

usage: make_corpus.py <gen_pages-binary> <out-dir> [name ...]

Without names, the default set is made (DEFAULT below); the large books are
made only when named. Pages come from gen_pages (synthetic greyscale JPEG
noise, nearly incompressible like real scans). Archives, all with ASCII
names p0001.jpg...:

  r4n          RAR4, non-solid, 120 x ~1.4 MB, shuffled stored order, STORE
  r4n_small    RAR4, non-solid, 2000 x ~90 KB, shuffled stored order, STORE
  r5n          RAR5, non-solid, 120 x ~1.4 MB, shuffled stored order, -m3
  r5n_small    RAR5, non-solid, 2000 x ~90 KB, shuffled stored order, -m3
  r5s          RAR5, solid,     120 x ~1.4 MB, name order (rar sorts), -m3
  r5n_ordered  RAR5, non-solid, 120 x ~1.4 MB, name order, -m3
  s7s          7z,   solid,     120 x ~1.4 MB, name order, LZMA2 -mx=5 (.cb7)
large (only when named):
  r5n_large    RAR5, non-solid, 400 x ~1.4 MB, shuffled stored order, -m3
  r5s_large    RAR5, solid,     400 x ~1.4 MB, name order, -m3
  s7s_large    7z,   solid,     400 x ~1.4 MB, name order, LZMA2 -mx=5 (.cb7)

RAR4 is hand-written STORE by tests/fixtures/make_rar4_fixture.py's block
writers: rar 7.x cannot write RAR4. "Shuffled" is a fixed-seed permutation,
standing in for the directory order rar uses for non-solid archives, which
on APFS is not name order. The first five files are unchanged from the
first version of this tool, so their numbers stay comparable. Existing files
are kept (delete to regenerate). RAR5 needs `rar`, 7z needs `7zz` on PATH.
"""

from __future__ import annotations

import pathlib
import random
import shutil
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tests" / "fixtures"))
import make_rar4_fixture as rar4  # noqa: E402

DEFAULT = ["r4n", "r4n_small", "r5n", "r5n_small", "r5s", "r5n_ordered", "s7s"]
LARGE = ["r5n_large", "r5s_large", "s7s_large"]


def pages(gen: str, out: pathlib.Path, name: str, count: int, width: int, height: int,
          quality: float, seed: int) -> list[pathlib.Path]:
    d = out / "pages" / name
    if not d.is_dir() or len(list(d.glob("*.jpg"))) != count:
        shutil.rmtree(d, ignore_errors=True)
        subprocess.run([gen, str(d), str(count), str(width), str(height), str(quality), str(seed)],
                       check=True)
    return sorted(d.glob("*.jpg"))


def shuffled(files: list[pathlib.Path], seed: int) -> list[pathlib.Path]:
    order = list(files)
    random.Random(seed).shuffle(order)
    return order


def write_rar4(path: pathlib.Path, files: list[pathlib.Path]) -> None:
    blocks = [rar4.RAR4_SIGNATURE, rar4.archive_header_block(False)]
    for f in files:
        blocks.append(rar4.file_header_block(f.name, f.read_bytes()))
    blocks.append(rar4.end_header_block())
    path.write_bytes(b"".join(blocks))


def write_listed(args: list[str], path: pathlib.Path, files: list[pathlib.Path]) -> None:
    """Run an archiver over files in the given order, through a list file."""
    tmp = path.with_name(path.name + ".tmp")
    listfile = path.with_name(path.name + ".list")
    listfile.write_text("".join(f.name + "\n" for f in files))
    tmp.unlink(missing_ok=True)
    try:
        subprocess.run(args + [str(tmp), "@" + str(listfile)], cwd=files[0].parent, check=True)
    finally:
        listfile.unlink()
    tmp.rename(path)	# only a complete archive gets the final name


def write_rar5(path: pathlib.Path, files: list[pathlib.Path], solid: bool) -> None:
    # rar adds .rar only to a name without an extension, so the .tmp name stays
    args = ["rar", "a", "-idq", "-ma5", "-m3", "-ep1"]
    if solid:
        args.append("-s")
    write_listed(args, path, files)


def write_7z(path: pathlib.Path, files: list[pathlib.Path]) -> None:
    # -t7z because the .cb7 suffix does not name a type; -ms=on: one solid
    # block (7-Zip's solid-block limits are far above these sizes)
    write_listed(["7zz", "a", "-bd", "-bso0", "-bsp0", "-t7z", "-mx=5", "-ms=on"], path, files)


def main() -> None:
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    gen, out = sys.argv[1], pathlib.Path(sys.argv[2]).resolve()
    names = sys.argv[3:] or DEFAULT
    unknown = [n for n in names if n not in DEFAULT + LARGE]
    if unknown:
        sys.exit(f"unknown corpus file(s): {' '.join(unknown)}; known: {' '.join(DEFAULT + LARGE)}")
    out.mkdir(parents=True, exist_ok=True)

    def large():
        return pages(gen, out, "large", 120, 1400, 2000, 0.86, 1)

    def small():
        return pages(gen, out, "small", 2000, 300, 430, 0.95, 2)

    def large400():
        return pages(gen, out, "large400", 400, 1400, 2000, 0.86, 3)

    makers = {
        "r4n": (".cbr", lambda p: write_rar4(p, shuffled(large(), 11))),
        "r4n_small": (".cbr", lambda p: write_rar4(p, shuffled(small(), 12))),
        "r5n": (".cbr", lambda p: write_rar5(p, shuffled(large(), 13), solid=False)),
        "r5n_small": (".cbr", lambda p: write_rar5(p, shuffled(small(), 14), solid=False)),
        "r5s": (".cbr", lambda p: write_rar5(p, large(), solid=True)),
        "r5n_ordered": (".cbr", lambda p: write_rar5(p, large(), solid=False)),
        "s7s": (".cb7", lambda p: write_7z(p, large())),
        "r5n_large": (".cbr", lambda p: write_rar5(p, shuffled(large400(), 15), solid=False)),
        "r5s_large": (".cbr", lambda p: write_rar5(p, large400(), solid=True)),
        "s7s_large": (".cb7", lambda p: write_7z(p, large400())),
    }
    for name in names:
        ext, make = makers[name]
        path = out / (name + ext)
        if path.exists():
            continue
        tool = "7zz" if ext == ".cb7" else "rar" if name.startswith("r5") else None
        if tool and not shutil.which(tool):
            sys.exit(f"{tool} is required for {name}")
        make(path)
    for name in names:
        p = out / (name + makers[name][0])
        print(f"{p.name}: {p.stat().st_size / 1e6:.0f} MB")


if __name__ == "__main__":
    main()
