#!/usr/bin/env python3
"""Generate the tools/cbr_bench corpus (see README.md).

usage: make_corpus.py <gen_pages-binary> <out-dir>

Pages come from gen_pages (synthetic greyscale JPEG noise, nearly
incompressible like real scans). Archives, all with ASCII names p0001.jpg...:

  r4n        RAR4, non-solid, 120 x ~1.4 MB, shuffled stored order, STORE
  r4n_small  RAR4, non-solid, 2000 x ~90 KB, shuffled stored order, STORE
  r5n        RAR5, non-solid, 120 x ~1.4 MB, shuffled stored order, -m3
  r5n_small  RAR5, non-solid, 2000 x ~90 KB, shuffled stored order, -m3
  r5s        RAR5, solid,     120 x ~1.4 MB, name order (rar sorts), -m3

RAR4 is hand-written STORE by tests/fixtures/make_rar4_fixture.py's block
writers: rar 7.x cannot write RAR4. "Shuffled" is a fixed-seed permutation,
standing in for the directory order rar uses for non-solid archives, which
on APFS is not name order. Existing files are kept (delete to regenerate).
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
    if path.exists():
        return
    blocks = [rar4.RAR4_SIGNATURE, rar4.archive_header_block(False)]
    for f in files:
        blocks.append(rar4.file_header_block(f.name, f.read_bytes()))
    blocks.append(rar4.end_header_block())
    path.write_bytes(b"".join(blocks))


def write_rar5(path: pathlib.Path, files: list[pathlib.Path], solid: bool) -> None:
    if path.exists():
        return
    listfile = path.with_suffix(".list")
    listfile.write_text("".join(f.name + "\n" for f in files))
    args = ["rar", "a", "-idq", "-ma5", "-m3", "-ep1"]
    if solid:
        args.append("-s")
    subprocess.run(args + [str(path), "@" + str(listfile)], cwd=files[0].parent, check=True)
    listfile.unlink()


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    gen, out = sys.argv[1], pathlib.Path(sys.argv[2]).resolve()
    out.mkdir(parents=True, exist_ok=True)
    large = pages(gen, out, "large", 120, 1400, 2000, 0.86, 1)
    small = pages(gen, out, "small", 2000, 300, 430, 0.95, 2)
    write_rar4(out / "r4n.cbr", shuffled(large, 11))
    write_rar4(out / "r4n_small.cbr", shuffled(small, 12))
    write_rar5(out / "r5n.cbr", shuffled(large, 13), solid=False)
    write_rar5(out / "r5n_small.cbr", shuffled(small, 14), solid=False)
    write_rar5(out / "r5s.cbr", large, solid=True)
    for p in sorted(out.glob("*.cbr")):
        print(f"{p.name}: {p.stat().st_size / 1e6:.0f} MB")


if __name__ == "__main__":
    main()
